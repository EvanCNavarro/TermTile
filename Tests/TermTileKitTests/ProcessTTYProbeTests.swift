@testable import TermTileKit
import TermTileCore
import Testing

@Suite("Process tty probe — parsing and assembly, driven by fixed output")
struct ProcessTTYProbeTests {
    /// Shape taken from real `ps -eo tty=,pid=,args=` output on this Mac.
    static let psTable = """
        ?? 369 /bin/zsh -c source /Users/evancnavarro/.claude/shell-snapshot
        ?? 2305 /bin/bash /private/tmp/claude-501/some-hook
        ttys000 3966 claude --dangerously-skip-permissions
        ttys000 4011 /bin/zsh -c claude helper subshell
        ttys001 8690 node /Users/evancnavarro/.local/share/mise/installs/codex-darwin
        ttys002 3028 claude --dangerously-skip-permissions
        ttys004 5555 -zsh
        """

    @Test("only agent processes on a real tty are returned")
    func selectsAgentsWithTTY() {
        let found = ProcessTTYProbe.agentProcesses(inPSTable: Self.psTable)
        #expect(found.count == 3)
        #expect(found == [
            .init(tty: "ttys000", pid: 3966),
            .init(tty: "ttys001", pid: 8690),
            .init(tty: "ttys002", pid: 3028)
        ])
    }

    /// `??` is a process with no controlling terminal — the hooks and helpers. No window
    /// corresponds to them, and including one would invent a session.
    @Test("processes with no controlling terminal are skipped")
    func skipsNoTTY() {
        let found = ProcessTTYProbe.agentProcesses(inPSTable: Self.psTable)
        #expect(!found.contains { $0.pid == 369 || $0.pid == 2305 })
    }

    /// A plain login shell is not an agent session.
    @Test("a non-agent shell is not a session")
    func skipsPlainShell() {
        let found = ProcessTTYProbe.agentProcesses(inPSTable: Self.psTable)
        #expect(!found.contains { $0.tty == "ttys004" })
    }

    /// The agent spawns subshells on its own tty; the first match must win so a helper cannot
    /// displace the agent and hand back the wrong pid.
    @Test("one session per tty — a subshell cannot displace the agent")
    func oneSessionPerTTY() {
        let found = ProcessTTYProbe.agentProcesses(inPSTable: Self.psTable)
        #expect(found.filter { $0.tty == "ttys000" }.count == 1)
        #expect(found.first { $0.tty == "ttys000" }?.pid == 3966)
    }

    @Test("empty ps output yields no sessions")
    func emptyTable() {
        #expect(ProcessTTYProbe.agentProcesses(inPSTable: "").isEmpty)
    }

    @Test("lsof field output yields the cwd name")
    func lsofParse() {
        let out = "p3966\nfcwd\nn/Users/evancnavarro/Developer/termtile\n"
        #expect(ProcessTTYProbe.cwdName(inLSOFOutput: out) == "termtile")
    }

    @Test("lsof output without an n-line yields nil")
    func lsofNoPath() {
        #expect(ProcessTTYProbe.cwdName(inLSOFOutput: "p3966\nfcwd\n") == nil)
        #expect(ProcessTTYProbe.cwdName(inLSOFOutput: "") == nil)
    }

    /// End to end through the actor with a scripted runner: ps -> env -> lsof -> snapshot.
    @Test("assembles snapshots from ps, env and lsof")
    func assembles() async {
        let probe = ProcessTTYProbe { executable, arguments in
            if arguments.contains("-eo") { return "ttys005 86501 claude\n" }
            if executable.hasSuffix("lsof") { return "n/Users/evancnavarro/Developer/termtile\n" }
            return "claude ITERM_SESSION_ID=w5t0p0:ABC-DEF SECRET=nope\n"
        }
        let sessions = await probe.sessions()
        #expect(sessions.count == 1)
        #expect(sessions.first == TTYSessionSnapshot(
            tty: "/dev/ttys005", windowIndex: 5, tabIndex: 0, paneIndex: 0, cwd: "termtile"))
    }

    /// Fail-closed: a session whose identity cannot be established is DROPPED, never guessed at.
    @Test("a session with no ITERM_SESSION_ID is dropped, not invented")
    func dropsUnidentifiable() async {
        let probe = ProcessTTYProbe { executable, arguments in
            if arguments.contains("-eo") { return "ttys005 86501 claude\n" }
            if executable.hasSuffix("lsof") { return "n/Users/evancnavarro/Developer/termtile\n" }
            return "claude TERM=xterm PWD=/tmp\n"
        }
        #expect(await probe.sessions().isEmpty)
    }

    @Test("a session with no resolvable cwd is dropped")
    func dropsNoCwd() async {
        let probe = ProcessTTYProbe { executable, arguments in
            if arguments.contains("-eo") { return "ttys005 86501 claude\n" }
            if executable.hasSuffix("lsof") { return "" }
            return "claude ITERM_SESSION_ID=w5t0p0:ABC\n"
        }
        #expect(await probe.sessions().isEmpty)
    }

    /// The env read must be scoped to ONE pid. A machine-wide `ps -E` would pull every process's
    /// environment on this Mac into memory to answer a question about six terminals.
    @Test("the environment read is per-PID, never a machine-wide dump")
    func envReadIsScoped() async {
        actor Recorder {
            var calls: [[String]] = []
            func record(_ a: [String]) { calls.append(a) }
        }
        let recorder = Recorder()
        let probe = ProcessTTYProbe { executable, arguments in
            Task { await recorder.record(arguments) }
            if arguments.contains("-eo") { return "ttys005 86501 claude\n" }
            if executable.hasSuffix("lsof") { return "n/Users/x/Developer/termtile\n" }
            return "claude ITERM_SESSION_ID=w5t0p0:ABC\n"
        }
        _ = await probe.sessions()
        try? await Task.sleep(nanoseconds: 50_000_000)
        let calls = await recorder.calls
        let envCalls = calls.filter { $0.contains("-Eww") }
        #expect(!envCalls.isEmpty, "no environment read happened at all")
        for call in envCalls {
            #expect(call.contains("-p"), "environment read was not scoped to a pid: \(call)")
            #expect(!call.contains("-e"), "environment read used a machine-wide -e dump: \(call)")
        }
    }
}
