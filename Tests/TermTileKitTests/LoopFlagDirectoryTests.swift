import Foundation
@testable import TermTileKit
import TermTileCore
import Testing

/// The flag reader for EvanCNavarro/TermTile#51. Every case runs against a real temporary
/// directory — the thing under test is filesystem behaviour, so a fake filesystem would be
/// testing the fake.
@Suite("Loop flag directory")
struct LoopFlagDirectoryTests {
    /// A fresh directory per test, removed afterwards.
    static func withTempDir(_ body: (URL) async throws -> Void) async rethrows {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("tt-loop-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try await body(dir)
    }

    static func write(_ dir: URL, tty: String, pid: Int32) {
        try? "\(pid)\n".write(to: dir.appendingPathComponent(tty), atomically: true, encoding: .utf8)
    }

    @Test("a flag whose process is alive reports its tty")
    func liveFlagReports() async {
        await Self.withTempDir { dir in
            Self.write(dir, tty: "ttys003", pid: 4242)
            let reader = LoopFlagDirectory(directory: dir, isAlive: { $0 == 4242 })
            #expect(await reader.loopingTTYs() == ["/dev/ttys003"])
        }
    }

    /// THE SAFETY TEST. A loop that was killed leaves its flag behind; without the pid guard the
    /// window stays purple forever, which is the `waiting-on-a-person` failure shape — a durable
    /// marker outliving the state it describes.
    @Test("a flag whose process is dead is ignored AND reaped")
    func deadFlagIgnoredAndReaped() async {
        await Self.withTempDir { dir in
            Self.write(dir, tty: "ttys004", pid: 9999)
            let reader = LoopFlagDirectory(directory: dir, isAlive: { _ in false })
            #expect(await reader.loopingTTYs().isEmpty, "a dead pid still reported a loop")
            #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("ttys004").path),
                    "the stale flag was left on disk to lie again on the next pass")
        }
    }

    /// Mixed, because a reader that returned everything or nothing would pass both tests above.
    @Test("live and dead flags are separated in the same pass")
    func mixedFlags() async {
        await Self.withTempDir { dir in
            Self.write(dir, tty: "ttys000", pid: 11)
            Self.write(dir, tty: "ttys001", pid: 22)
            Self.write(dir, tty: "ttys002", pid: 33)
            let reader = LoopFlagDirectory(directory: dir, isAlive: { $0 == 11 || $0 == 33 })
            let live = await reader.loopingTTYs()
            #expect(live == ["/dev/ttys000", "/dev/ttys002"], "got \(live)")
        }
    }

    /// The filename is a device path this app will later WRITE escape bytes to, so it gets the
    /// same validation `OSCColorWriter` applies before opening one.
    @Test("a filename that is not a tty is ignored")
    func rejectsNonTTYNames() async {
        await Self.withTempDir { dir in
            for bad in ["passwd", "ttysABC", "..", "ttys", "ttys1x"] {
                Self.write(dir, tty: bad, pid: 1)
            }
            let reader = LoopFlagDirectory(directory: dir, isAlive: { _ in true })
            #expect(await reader.loopingTTYs().isEmpty, "accepted a non-tty filename")
        }
    }

    @Test("an unreadable or empty flag is ignored, not treated as a loop")
    func malformedFlagIgnored() async {
        await Self.withTempDir { dir in
            try? "".write(to: dir.appendingPathComponent("ttys005"), atomically: true, encoding: .utf8)
            try? "not-a-pid".write(to: dir.appendingPathComponent("ttys006"), atomically: true, encoding: .utf8)
            let reader = LoopFlagDirectory(directory: dir, isAlive: { _ in true })
            #expect(await reader.loopingTTYs().isEmpty)
        }
    }

    /// A missing directory is the NORMAL case — nobody has ever run a loop — and must be quiet.
    @Test("a missing directory reports no loops rather than failing")
    func missingDirectoryIsQuiet() async {
        let nowhere = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("tt-loop-absent-\(UUID().uuidString)", isDirectory: true)
        let reader = LoopFlagDirectory(directory: nowhere, isAlive: { _ in true })
        #expect(await reader.loopingTTYs().isEmpty)
    }

    @Test("the default reader reports nothing, so nothing loops by accident")
    func defaultIsInert() async {
        #expect(await NoLoopFlags().loopingTTYs().isEmpty)
    }
}
