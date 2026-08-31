@testable import TermTileKit
import TermTileCore
import Testing

@Suite("Tinting driver — the schedule")
struct TintingDriverTests {
    static func rig() -> (TintingDriver, RecordingTinter) {
        let pane = ObservedPane(snapshot: AXPaneSnapshot(windowBadge: 6, cwd: "termtile"),
                                scrollbackTail: "⧉  waiting-on-a-person", characterCount: 100)
        let session = TTYSessionSnapshot(tty: "/dev/ttys005", windowIndex: 5, tabIndex: 0,
                                        paneIndex: 0, cwd: "termtile")
        let tinter = RecordingTinter()
        let coordinator = TintingCoordinator(reader: InMemorySessionReader(panes: [pane]),
                                             probe: InMemoryTTYProbe(sessions: [session]),
                                             writer: tinter)
        return (TintingDriver(coordinator: coordinator, interval: .milliseconds(20)), tinter)
    }

    @Test("starting drives passes")
    func startsPassing() async throws {
        let (driver, tinter) = Self.rig()
        await driver.start()
        #expect(await driver.isRunning)
        try await Task.sleep(for: .milliseconds(120))
        let passes = await driver.completedPasses
        #expect(passes >= 2, "the loop ran \(passes) times")
        #expect(!(await tinter.writes.isEmpty))
        await driver.stop()
    }

    /// Two loops would double the poll rate and race each other's baselines. Asserted on the
    /// number of loops CREATED rather than on passes-per-wall-clock: the timing form measures
    /// machine speed as much as the guard, and its margin was one flaky run from useless.
    @Test("starting twice does not spawn a second loop")
    func startIsIdempotent() async {
        let (driver, _) = Self.rig()
        await driver.start()
        await driver.start()
        await driver.start()
        #expect(await driver.loopsStarted == 1)
        await driver.stop()
    }

    /// The other half: after a stop, start MUST create a new loop — an over-eager guard that
    /// never restarts would pass the test above and leave the feature dead after one toggle.
    @Test("start after stop creates a fresh loop")
    func restartAfterStopWorks() async {
        let (driver, _) = Self.rig()
        await driver.start()
        await driver.stop()
        await driver.start()
        #expect(await driver.loopsStarted == 2)
        #expect(await driver.isRunning)
        await driver.stop()
    }

    @Test("stopping halts the loop")
    func stopHalts() async throws {
        let (driver, _) = Self.rig()
        await driver.start()
        try await Task.sleep(for: .milliseconds(60))
        await driver.stop()
        #expect(!(await driver.isRunning))
        let after = await driver.completedPasses
        try await Task.sleep(for: .milliseconds(80))
        #expect(await driver.completedPasses == after, "the loop kept running after stop()")
    }

    /// THE ORPHAN GUARD. Disabling the feature must leave no window wearing a colour TermTile is
    /// no longer maintaining.
    @Test("stopping repaints touched sessions back to normal")
    func stopResets() async throws {
        let (driver, tinter) = Self.rig()
        await driver.start()
        try await Task.sleep(for: .milliseconds(60))
        await tinter.clear()
        await driver.stop()
        #expect(await tinter.writtenHexes == [TintPalette.normal.hex],
                "stop() did not reset the session to normal")
    }
}
