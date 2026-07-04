import Foundation

/// The live drag-reorder monitor as a port (#26) — the imperative-shell surface the VM starts/stops
/// based on the opt-in setting + Accessibility trust + Input-Monitoring grant. Faked in tests so the
/// start/stop LIFECYCLE is unit-provable without the real CGEventTap. The concrete adapter
/// (`DragReorderController`) wraps a `DragMonitor` wired to the actor's on-demand drag path.
///
/// `@MainActor` — the underlying `DragMonitor` adds/removes its tap source on the MAIN run loop
/// (skeptic S2: `CFRunLoopGetCurrent()` is thread-fragile; pinning to main keeps start/stop on the
/// same loop). The VM is `@MainActor`, so this composes.
@MainActor
public protocol DragReorderControlling {
    /// Whether Input Monitoring is granted — read non-prompting; the monitor can't run without it.
    var inputMonitoringGranted: Bool { get }
    /// Whether the monitor is currently watching (so the VM can reflect real state, not intent).
    var isRunning: Bool { get }
    /// Start watching for drags. Idempotent; returns false if it couldn't start (permission absent).
    @discardableResult func start() -> Bool
    /// Stop watching. Idempotent, safe if never started.
    func stop()
}
