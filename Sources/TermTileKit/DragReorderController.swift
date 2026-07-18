import CoreGraphics
import Foundation
import TermTileCore

/// The concrete drag-reorder controller (#26) — thin `@MainActor` glue over the proven `DragMonitor`
/// (#14b). `start()` builds + installs the mouse tap wired to the injected drag-op closures (the VM's
/// `resolveDraggedWindow`/`reorderDroppedWindow`, which hit the current actor); `stop()` tears it
/// down. `@MainActor` so the tap's `CFRunLoop` add/remove always run on the main loop (skeptic S2).
/// The live tap behaviour is proven by #14b + the end-to-end human drag test; this file is glue.
@MainActor
public final class DragReorderController: DragReorderControlling {
    private let resolveWindow: @Sendable (CGPoint) async -> TrackedWindow?
    private let currentFrame: @Sendable (CGWindowID) async -> CGRect?
    private let onDrop: @Sendable (CGWindowID) async -> Void
    private var monitor: DragMonitor?

    public init(resolveWindow: @escaping @Sendable (CGPoint) async -> TrackedWindow?,
                currentFrame: @escaping @Sendable (CGWindowID) async -> CGRect?,
                onDrop: @escaping @Sendable (CGWindowID) async -> Void) {
        self.resolveWindow = resolveWindow
        self.currentFrame = currentFrame
        self.onDrop = onDrop
    }

    /// Non-prompting Input-Monitoring preflight (the tap can't run without it).
    public var inputMonitoringGranted: Bool { DragMonitor.inputMonitoringGranted }
    public func requestInputMonitoring() { DragMonitor.requestInputMonitoring() }
    public var isRunning: Bool { monitor != nil }

    /// Install the tap (idempotent). Returns false if it couldn't start (Input Monitoring absent) —
    /// the VM treats that as "not running" and surfaces the fix-it row (#26 S3), never a half-run.
    @discardableResult
    public func start() -> Bool {
        guard monitor == nil else { return true }
        let newMonitor = DragMonitor(
            resolveWindow: resolveWindow,
            currentFrame: currentFrame,
            onDragEnd: onDrop
        )
        guard newMonitor.start() else { return false }
        monitor = newMonitor
        return true
    }

    public func stop() {
        monitor?.stop()
        monitor = nil
    }

    deinit { monitor?.stop() }
}
