import CoreGraphics
@testable import TermTileKit
import TermTileCore
import Testing

@Suite("View model — tinting lifecycle")
@MainActor
struct MenuBarViewModelTintingTests {
    static func make(enabled: Bool = false, intensity: ReadyIntensity = .standard)
        -> (MenuBarViewModel, InMemorySettingsStore, FakeTintingController) {
        let store = InMemorySettingsStore()
        store.save(AppSettings(targetBundleID: "com.googlecode.iterm2", wasTrusted: true, gap: 8,
                               hotKey: .rearrange, reorderOnDrag: false, reorderStrategy: .adaptive,
                               bringToFrontOnRearrange: false,
                               tintingEnabled: enabled, readyIntensity: intensity))
        let fake = FakeTintingController()
        let vm = MenuBarViewModel(
            settings: store, loginItem: InMemoryLoginItem(), appsProvider: InMemoryTargetAppsProvider(seed: []),
            isTrustedProbe: { true }, visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800),
            epsilon: 2, makeActor: { _ in TilingActor(system: InMemoryWindowSystem()) },
            tinting: fake)
        return (vm, store, fake)
    }


    /// Waits for an async expectation rather than assuming a fixed delay is enough.
    ///
    /// The first version of these tests slept 50ms and passed in isolation, then FAILED in the
    /// full suite where the machine is busy. A sleep encodes a guess about scheduler latency; this
    /// encodes the actual condition, and still fails (rather than hangs) if it never holds.
    static func eventually(_ condition: @Sendable () async -> Bool,
                           within: Duration = .seconds(2)) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: within)
        while ContinuousClock.now < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return await condition()
    }

    @Test("tinting is off on a fresh install and nothing is started")
    func offByDefault() async throws {
        let (vm, _, fake) = Self.make()
        #expect(vm.tintingEnabled == false)
        vm.startTintingIfEnabled()
        try await Task.sleep(for: .milliseconds(200))
        #expect(await fake.starts == 0, "tinting started without the user enabling it")
        // NON-VACUOUS: prove the fake and the wiring are live in this same test, so the zero
        // above means "did not start" rather than "nothing was ever connected".
        vm.setTintingEnabled(true)
        #expect(await Self.eventually { await fake.starts == 1 },
                "the controller never started even when enabled — the zero above proved nothing")
    }

    @Test("enabling persists and starts the loop")
    func enableStarts() async {
        let (vm, store, fake) = Self.make()
        vm.setTintingEnabled(true)
        #expect(store.load().tintingEnabled == true)
        #expect(await Self.eventually { await fake.starts == 1 })
        #expect(await fake.stops == 0)
    }

    /// Disabling must STOP, not merely persist — the driver's stop is what repaints touched
    /// sessions back to normal. A persisted-but-not-stopped toggle strands the colours.
    @Test("disabling persists and stops the loop")
    func disableStops() async {
        let (vm, store, fake) = Self.make(enabled: true)
        vm.setTintingEnabled(false)
        #expect(store.load().tintingEnabled == false)
        #expect(await Self.eventually { await fake.stops == 1 })
    }

    /// A persisted preference that does not take effect on relaunch reads as broken, not as off.
    @Test("a persisted enabled preference starts at launch, with its intensity")
    func persistedPreferenceStartsAtLaunch() async {
        let (vm, _, fake) = Self.make(enabled: true, intensity: .bold)
        #expect(vm.tintingEnabled == true)
        vm.startTintingIfEnabled()
        #expect(await Self.eventually { await fake.starts == 1 })
        #expect(await fake.intensities == [.bold], "launch did not carry the saved intensity")
    }

    @Test("changing intensity persists and reaches the driver")
    func intensityForwarded() async {
        let (vm, store, fake) = Self.make(enabled: true)
        vm.setReadyIntensity(.bold)
        #expect(store.load().readyIntensity == .bold)
        #expect(await Self.eventually { await fake.intensities == [.bold] })
    }
}

@Suite("View model — tinting diagnostics")
@MainActor
struct MenuBarViewModelDiagnosticsTests {
    @Test("refresh pulls the driver's last decisions")
    func refreshPulls() async {
        let (vm, _, fake) = MenuBarViewModelTintingTests.make(enabled: true)
        await fake.seed([
            TintDecision(cwd: "termtile", tty: "/dev/ttys005", state: .ready, wrote: true,
                         hadBaseline: true),
            TintDecision(cwd: "shared", tty: nil, state: .unknown, wrote: false,
                         ambiguity: .cwdNotUnique)
        ])
        #expect(vm.tintDiagnostics.isEmpty, "diagnostics were populated before any refresh")
        await vm.refreshTintDiagnostics()
        #expect(vm.tintDiagnostics.count == 2)
        #expect(vm.tintDiagnostics.first?.untintedReason == nil, "a painted session gave a reason")
        #expect(vm.tintDiagnostics.last?.untintedReason != nil, "an unpainted session gave none")
    }

    /// With no controller injected there is nothing to ask, and the panel must stay empty rather
    /// than showing whatever it held last.
    @Test("refresh with no controller leaves diagnostics empty")
    func refreshWithoutController() async {
        let store = InMemorySettingsStore()
        let vm = MenuBarViewModel(
            settings: store, loginItem: InMemoryLoginItem(),
            appsProvider: InMemoryTargetAppsProvider(seed: []), isTrustedProbe: { true },
            visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800), epsilon: 2,
            makeActor: { _ in TilingActor(system: InMemoryWindowSystem()) })
        await vm.refreshTintDiagnostics()
        #expect(vm.tintDiagnostics.isEmpty)
    }
}
