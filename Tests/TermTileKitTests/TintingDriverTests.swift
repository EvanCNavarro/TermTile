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


    /// Waits for a condition rather than assuming a fixed delay is enough.
    ///
    /// A fixed sleep encodes a guess about machine speed. That guess FAILED on CI: `starting
    /// drives passes` slept 120ms and asserted >= 2 passes, and the runner managed 1
    /// (EvanCNavarro/TermTile#18). Polling encodes the condition instead, and still fails rather
    /// than hangs if it never holds.
    static func eventually(_ condition: @Sendable () async -> Bool,
                           within: Duration = .seconds(3)) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: within)
        while ContinuousClock.now < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return await condition()
    }

    @Test("starting drives passes")
    func startsPassing() async {
        let (driver, tinter) = Self.rig()
        await driver.start()
        #expect(await driver.isRunning)
        let reachedTwo = await Self.eventually { await driver.completedPasses >= 2 }
        let observed = await driver.completedPasses
        #expect(reachedTwo, "the loop completed \(observed) passes")
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

    /// A NEGATIVE cannot be polled for, so it is made non-vacuous instead: the loop is first
    /// PROVEN to be running, so "the count stopped moving" cannot be confused with "nothing ever
    /// started". `isRunning` is asserted too, because that half is deterministic.
    @Test("stopping halts the loop")
    func stopHalts() async throws {
        let (driver, _) = Self.rig()
        await driver.start()
        #expect(await Self.eventually { await driver.completedPasses >= 1 },
                "the loop never ran, so halting it proves nothing")
        await driver.stop()
        #expect(!(await driver.isRunning))
        let after = await driver.completedPasses
        // Several intervals' worth at the rig's 20ms tick.
        try await Task.sleep(for: .milliseconds(150))
        #expect(await driver.completedPasses == after, "the loop kept running after stop()")
    }

    /// THE ORPHAN GUARD. Disabling the feature must leave no window wearing a colour TermTile is
    /// no longer maintaining.
    @Test("stopping repaints touched sessions back to normal")
    func stopResets() async {
        let (driver, tinter) = Self.rig()
        await driver.start()
        #expect(await Self.eventually { await driver.completedPasses >= 1 })
        await tinter.clear()
        await driver.stop()
        #expect(await tinter.writtenHexes == [TintPalette.normal.hex],
                "stop() did not reset the session to normal")
    }
}
