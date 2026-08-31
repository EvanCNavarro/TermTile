import Foundation
import TermTileCore

/// The PRODUCTION `TTYProbing` adapter.
///
/// SECURITY-CRITICAL (ADR-0006 "Privacy surface", #37c). Resolving a session's window/tab/pane
/// requires reading `ITERM_SESSION_ID` out of a process ENVIRONMENT BLOCK, and an environment
/// block contains secrets — an `ANTHROPIC_API_KEY` and a `SESSION_SECRET` were exposed in plain
/// text by one unguarded read while this design was being probed.
///
/// Three rules hold that exposure down, and all three are enforced by structure rather than care:
///   1. The env read is per-PID (`ps -p <pid>`), never a machine-wide `ps -E` dump.
///   2. The block is handed straight to `EnvironmentScan`, whose return type is three `Int`s and
///      therefore cannot carry a credential.
///   3. Nothing from a block is logged, stored, or returned. There is no debug path that prints it.
public actor ProcessTTYProbe: TTYProbing {
    /// Injected so tests drive the parsing with fixed output instead of the real process table.
    /// Mirrors `PermissionRepairer.Runner`, which injects the same way but returns only a status.
    public typealias CommandRunner = @Sendable (_ executable: String, _ arguments: [String]) -> String

    private let run: CommandRunner

    public init(run: @escaping CommandRunner = ProcessTTYProbe.runCapturing) {
        self.run = run
    }

    public func sessions() async -> [TTYSessionSnapshot] {
        let table = run("/bin/ps", ["-eo", "tty=,pid=,args="])
        return ProcessTTYProbe.agentProcesses(inPSTable: table).compactMap { entry in
            // Per-PID env read, never a machine-wide dump.
            let block = run("/bin/ps", ["-p", String(entry.pid), "-Eww", "-o", "command="])
            guard let id = EnvironmentScan.sessionID(fromEnvironmentBlock: block) else { return nil }
            // `block` goes out of scope here and is never referenced again.
            let cwdOutput = run("/usr/sbin/lsof", ["-a", "-p", String(entry.pid), "-d", "cwd", "-Fn"])
            guard let cwd = ProcessTTYProbe.cwdName(inLSOFOutput: cwdOutput) else { return nil }
            return TTYSessionSnapshot(
                tty: "/dev/" + entry.tty,
                windowIndex: id.windowIndex,
                tabIndex: id.tabIndex,
                paneIndex: id.paneIndex,
                cwd: cwd
            )
        }
    }

    struct AgentProcess: Equatable {
        let tty: String
        let pid: Int
    }

    /// Agent processes that own a real terminal. Matched on the command, mirroring the tool this
    /// replaces: `claude`, and Codex under either of its two launch shapes.
    static let agentPatterns = ["claude", "codex-darwin", "bin/codex"]

    /// Parses `ps -eo tty=,pid=,args=`. Processes with no controlling terminal print `??` and are
    /// skipped — those are the hook and helper processes, which no window corresponds to.
    static func agentProcesses(inPSTable table: String) -> [AgentProcess] {
        var seen = Set<String>()
        var result: [AgentProcess] = []
        for line in table.split(separator: "\n") {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count >= 3 else { continue }
            let tty = String(fields[0])
            guard tty.hasPrefix("ttys"), let pid = Int(fields[1]) else { continue }
            let command = fields.dropFirst(2).joined(separator: " ")
            guard agentPatterns.contains(where: command.contains) else { continue }
            // One session per tty: the first agent match wins, so a subshell spawned by the agent
            // cannot displace the agent itself.
            guard seen.insert(tty).inserted else { continue }
            result.append(AgentProcess(tty: tty, pid: pid))
        }
        return result
    }

    /// Parses `lsof -Fn` field output: one `n`-prefixed line carrying the path.
    static func cwdName(inLSOFOutput output: String) -> String? {
        for line in output.split(separator: "\n") where line.hasPrefix("n") {
            let path = line.dropFirst()
            let name = (String(path) as NSString).lastPathComponent
            if !name.isEmpty, name != "/" { return name }
        }
        return nil
    }

    /// Captures stdout. Returns "" on any failure, which drops the session from the result —
    /// fail-closed, since a session we cannot identify must not be tinted.
    public static let runCapturing: CommandRunner = { executable, arguments in
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return ""
        }
        // Read BEFORE waiting: a process whose output exceeds the pipe buffer blocks on write
        // while we block on exit, and neither side moves.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
