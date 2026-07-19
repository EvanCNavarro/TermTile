import ApplicationServices
import CoreGraphics
import Foundation
import TermTileCore

/// Production drag-reorder wiring (#14b) — the global left-button `CGEventTap` that turns a real
/// window drag into a `TilingActor` reorder. It is the caller the spike-06 mouse-up recommendation
/// and `TilingActor.handleDragEnd` (which had ZERO callers) were always waiting for.
///
/// Two skeptic-mandated invariants shape it:
///  - **Identity at mouse-DOWN (B1):** the dragged id is resolved when the button goes down — while
///    the windows are still on their grid slots (NON-overlapping), so the cursor unambiguously
///    picks one window. Resolving at mouse-UP is unsound: the dragged window overlaps its drop
///    target, and `state.windows` order is not z-order.
///  - **Click/text selection ≠ window drag (B2):** `onDragEnd` fires ONLY when the pointer travelled
///    past `travelThreshold` AND the down window's frame actually changed. A plain click, terminal
///    text selection, or screenshot-region drag inside a managed window is ignored, so those gestures
///    never snap a maximized/focused window back to the grid.
///
/// The `CGEventTap` plumbing is a live-only surface (like `AXWindowSystem`) — it cannot run without
/// Input Monitoring + a real event stream, so it is proven live by AXProbe `dragcheck` (a
/// self-posted synthetic drag). The decision logic (`handleDown`/`handleUp`) is a testable seam,
/// callable without a tap.
public final class DragMonitor: @unchecked Sendable {
    public typealias ResolveWindow = @Sendable (CGPoint) async -> TrackedWindow?
    public typealias CurrentFrame = @Sendable (CGWindowID) async -> CGRect?
    public typealias DragEnd = @Sendable (CGWindowID) async -> Void

    private let resolveWindow: ResolveWindow
    private let currentFrame: CurrentFrame
    private let onDragEnd: DragEnd
    private let travelThreshold: CGFloat
    private let frameChangeEpsilon: CGFloat

    private let lock = NSLock()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var downPoint: CGPoint?
    private var downResolve: Task<TrackedWindow?, Never>?

    /// - Parameters:
    ///   - travelThreshold: minimum pointer travel (points) between down and up to count as a drag.
    ///   - frameChangeEpsilon: frame-delta tolerance before the gesture counts as a window move.
    ///   - resolveWindow: maps the mouse-DOWN point to the dragged window snapshot (the actor's
    ///     `trackedWindow(atFresh:)` in production).
    ///   - currentFrame: reads the candidate window's frame at mouse-UP.
    ///   - onDragEnd: the drag-end action (the actor's `handleDragEnd(_:)` in production).
    public init(travelThreshold: CGFloat = 6,
                frameChangeEpsilon: CGFloat = 2,
                resolveWindow: @escaping ResolveWindow,
                currentFrame: @escaping CurrentFrame,
                onDragEnd: @escaping DragEnd) {
        self.travelThreshold = travelThreshold
        self.frameChangeEpsilon = frameChangeEpsilon
        self.resolveWindow = resolveWindow
        self.currentFrame = currentFrame
        self.onDragEnd = onDragEnd
    }

    /// Non-prompting Input Monitoring preflight (spike-06). `false` → `start()` will return `false`.
    public static var inputMonitoringGranted: Bool { CGPreflightListenEventAccess() }

    /// PROMPTING Input Monitoring request — shows the system prompt AND registers the app in the
    /// Privacy > Input Monitoring pane (which the non-prompting preflight never does, so the app would
    /// otherwise never appear there to be approved). Safe to call repeatedly: macOS prompts once, then
    /// just returns the decided status.
    public static func requestInputMonitoring() { _ = CGRequestListenEventAccess() }

    /// Install the left-down/left-up tap on the CURRENT run loop. Returns `false` if the tap could
    /// not be created (Input Monitoring not granted). The caller pumps the run loop so the callback
    /// fires (production: NSApp; AXProbe `dragcheck`: `CFRunLoopRunInMode`).
    @discardableResult
    public func start() -> Bool {
        let mask = CGEventMask((1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.leftMouseUp.rawValue))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        guard let newTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
            eventsOfInterest: mask, callback: dragTapCallback, userInfo: selfPtr) else { return false }
        let newSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), newSource, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        lock.withLock { tap = newTap; source = newSource }
        return true
    }

    /// Remove the tap from the current run loop and reset drag state (safe to call if never started).
    public func stop() {
        lock.withLock {
            if let source { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes) }
            if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
            tap = nil; source = nil; downPoint = nil; downResolve = nil
        }
    }

    // MARK: - Decision seam (run-loop thread; unit-tested without a tap)

    /// Mouse-DOWN: remember the point and START resolving the dragged id NOW (B1 — before the drag
    /// moves the window off this point). A new down supersedes any un-consumed prior down.
    func handleDown(at point: CGPoint) {
        lock.withLock {
            downPoint = point
            downResolve = Task { await self.resolveWindow(point) }
        }
    }

    /// Mouse-UP: if the pointer travelled past the threshold since the matching down (B2), await the
    /// id resolved at down, verify that the window moved without materially resizing, and fire
    /// `onDragEnd`. Returns the fired id (`nil` = click, no matching down, down over no window,
    /// vanished window, resized/zoomed window, or pointer drag inside an unchanged window). Consumes the
    /// pending down either way.
    @discardableResult
    func handleUp(at point: CGPoint) async -> CGWindowID? {
        let pending: (point: CGPoint, resolve: Task<TrackedWindow?, Never>)? = lock.withLock {
            defer { downPoint = nil; downResolve = nil }
            guard let downPoint, let downResolve else { return nil }
            return (downPoint, downResolve)
        }
        guard let pending else { return nil }
        guard hypot(point.x - pending.point.x, point.y - pending.point.y) > travelThreshold else {
            pending.resolve.cancel(); return nil                    // click → ignore (B2)
        }
        guard let window = await pending.resolve.value else { return nil }   // down over no window
        guard let currentFrame = await currentFrame(window.id) else { return nil }
        guard sizeApproximatelyEqual(window.frame.size, currentFrame.size, epsilon: frameChangeEpsilon) else {
            return nil
        }
        guard !FrameMath.approximatelyEqual(
            window.frame,
            currentFrame,
            epsilon: frameChangeEpsilon
        ) else { return nil }
        await onDragEnd(window.id)
        return window.id
    }

    /// Re-enable the tap after the system disables it (timeout / user input). Called from the callback.
    fileprivate func reEnable() {
        lock.withLock { if let tap { CGEvent.tapEnable(tap: tap, enable: true) } }
    }

    private func sizeApproximatelyEqual(_ a: CGSize, _ b: CGSize, epsilon: CGFloat) -> Bool {
        abs(a.width - b.width) <= epsilon && abs(a.height - b.height) <= epsilon
    }
}

/// The no-capture `@convention(c)` tap callback. `self` arrives via `userInfo` (an unretained
/// `DragMonitor` pointer set in `start()`), so no module-global state is needed. Listen-only: the
/// event is always passed through unmodified.
private let dragTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let monitor = Unmanaged<DragMonitor>.fromOpaque(userInfo).takeUnretainedValue()
    switch type {
    case .leftMouseDown:
        monitor.handleDown(at: event.location)
    case .leftMouseUp:
        let loc = event.location
        Task { await monitor.handleUp(at: loc) }
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        monitor.reEnable()
    default:
        break
    }
    return Unmanaged.passUnretained(event)
}
