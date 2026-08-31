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
    /// EvanCNavarro/TermTile#20 — the shutdown race.
    ///
    /// The loop is `await coordinator.pass()` then `await self.countPass()`. If `cancel()` lands
    /// during the pass, that pass runs to completion and `countPass` then queues on the DRIVER
    /// actor behind `stop()` — landing AFTER `stop()` returns. The driver reports itself stopped
    /// while its counter is still moving.
    ///
    /// This can only be seen with a pass IN FLIGHT, which is why it needs a slow reader: a fake
    /// that returns instantly never leaves a window for the cancel to land in.
    @Test("no pass lands after stop() returns")
    func noLateCountAfterStop() async throws {
        let pane = ObservedPane(snapshot: AXPaneSnapshot(windowBadge: 6, cwd: "termtile"),
                                scrollbackTail: "❯", characterCount: 100)
        let session = TTYSessionSnapshot(tty: "/dev/ttys005", windowIndex: 5, tabIndex: 0,
                                         paneIndex: 0, cwd: "termtile")
        let reader = SlowSessionReader(panes: [pane], delay: .milliseconds(200))
        let driver = TintingDriver(
            coordinator: TintingCoordinator(reader: reader,
                                            probe: InMemoryTTYProbe(sessions: [session]),
                                            writer: RecordingTinter()),
            interval: .milliseconds(10))
        await driver.start()
        // Cancel while a pass is genuinely in flight, not before one starts.
        #expect(await Self.eventually { await reader.entered >= 1 },
                "no pass ever started, so cancelling mid-pass proves nothing")
        await driver.stop()

        let atStop = await driver.completedPasses
        #expect(!(await driver.isRunning))
        // Longer than the slow pass, so a late continuation has every chance to land.
        try await Task.sleep(for: .milliseconds(400))
        let later = await driver.completedPasses
        #expect(later == atStop,
                "completedPasses moved from \(atStop) to \(later) AFTER stop() returned")
    }

    /// WEAKENED 2026-08-31, and named for what it still proves rather than what it used to.
    ///
    /// It was `after stop(), the LAST write is normal`, and it CAUGHT reset-before-cancel: the
    /// blocked marker painted a distinct colour (amber) WITHOUT needing a baseline, so a pass
    /// resuming after the reset repainted over it visibly. That marker was retracted — it was
    /// Claude Code's task label, not a state (EvanCNavarro/TermTile#6).
    ///
    /// With the remaining vocabulary the ordering is UNTESTABLE here, and this was measured rather
    /// than assumed: re-planting reset-before-cancel now PASSES twice over. Working paints
    /// `normal`, indistinguishable from the reset; and ready needs a baseline that `resetAll()`
    /// has already cleared by the time the in-flight pass reads it, so that pass classifies
    /// `.unknown` and writes nothing at all.
    ///
    /// So this asserts only the weaker, still-true property: a stop leaves the session at normal.
    /// Restoring the ordering guard DEPENDS on a verified marker that paints a distinct colour
    /// without a baseline — tracked on EvanCNavarro/TermTile#6.
    @Test("after stop(), the session is left at normal")
    func stopLeavesSessionAtNormal() async {
        let pane = ObservedPane(snapshot: AXPaneSnapshot(windowBadge: 6, cwd: "termtile"),
                                scrollbackTail: "❯ steady", characterCount: 100)
        let session = TTYSessionSnapshot(tty: "/dev/ttys005", windowIndex: 5, tabIndex: 0,
                                         paneIndex: 0, cwd: "termtile")
        let reader = SlowSessionReader(panes: [pane], delay: .milliseconds(200))
        let tinter = RecordingTinter()
        let driver = TintingDriver(
            coordinator: TintingCoordinator(reader: reader,
                                            probe: InMemoryTTYProbe(sessions: [session]),
                                            writer: tinter),
            interval: .milliseconds(10))
        await driver.start()
        #expect(await Self.eventually { await tinter.writtenHexes.contains(TintPalette.ready.hex) },
                "the pass never painted, so a reset proves nothing")
        await driver.stop()

        let writes = await tinter.writtenHexes
        #expect(writes.contains(TintPalette.ready.hex))
        #expect(writes.last == TintPalette.normal.hex,
                "last write was \(writes.last ?? "none") — the session was not left at normal")
    }

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

@Suite("Tinting driver — diagnostics retention")
struct TintingDriverDiagnosticsTests {
    static func rig() -> (TintingDriver, RecordingTinter) {
        let pane = ObservedPane(snapshot: AXPaneSnapshot(windowBadge: 6, cwd: "termtile"),
                                scrollbackTail: "• Working (3s · esc to interrupt)",
                                characterCount: 100)
        let session = TTYSessionSnapshot(tty: "/dev/ttys005", windowIndex: 5, tabIndex: 0,
                                         paneIndex: 0, cwd: "termtile")
        let tinter = RecordingTinter()
        return (TintingDriver(coordinator: TintingCoordinator(
            reader: InMemorySessionReader(panes: [pane]),
            probe: InMemoryTTYProbe(sessions: [session]),
            writer: tinter), interval: .milliseconds(20)), tinter)
    }

    @Test("a pass records its decisions")
    func passRecords() async {
        let (driver, _) = Self.rig()
        #expect(await driver.lastDecisions().isEmpty, "decisions existed before any pass")
        await driver.start()
        #expect(await TintingDriverTests.eventually { await !driver.lastDecisions().isEmpty })
        let decisions = await driver.lastDecisions()
        #expect(decisions.count == 1)
        #expect(decisions.first?.state == .working)
        await driver.stop()
    }

    /// Stale diagnostics after a disable would describe a world the feature is no longer watching.
    @Test("stopping clears the decisions")
    func stopClears() async {
        let (driver, _) = Self.rig()
        await driver.start()
        #expect(await TintingDriverTests.eventually { await !driver.lastDecisions().isEmpty })
        await driver.stop()
        #expect(await driver.lastDecisions().isEmpty, "diagnostics survived a stop")
    }
}
