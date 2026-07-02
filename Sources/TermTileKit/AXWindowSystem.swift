@preconcurrency import ApplicationServices
import AppKit
import CoreGraphics
import Foundation
import TermTileCore

/// The PRODUCTION `WindowSystem` adapter (ADR-0001 rule 2 — the ONLY code importing
/// ApplicationServices for control). #19a delivers the WRITE PATH: enumerate the target app's
/// tileable windows, read a window's frame, and write a window to a target frame using the
/// proven size→position→size + `AXEnhancedUserInterface`-off workaround (spike-04). Promoted
/// from the throwaway `AXProbe` (`enumerate`/`setFrame`) into tested Kit code.
///
/// `events()` is a FINISHED-empty stub here — the AXObserver→AsyncStream bridge (with its
/// run-loop-thread-confined `WindowIDMap` for the -25201 destroy-id problem and the
/// `@convention(c)` continuation bridge) is genuinely-new concurrency-sensitive code split to
/// **#19b**; `TilingActor.run()`'s `for await` over a finished stream simply returns.
///
/// An `actor` so it satisfies the `Sendable` port and serializes AX writes; each call resolves
/// the running app fresh, so app launch/quit between calls is handled without stale handles.
public actor AXWindowSystem: WindowSystem {
    private let bundleID: String

    public init(bundleID: String) {
        self.bundleID = bundleID
    }

    /// The target app's AX element, or `nil` if it is not currently running.
    private func appElement() -> AXUIElement? {
        guard let app = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID).first else { return nil }
        return AXUIElementCreateApplication(app.processIdentifier)
    }

    public func tileableWindows() async -> [TrackedWindow] {
        guard let appEl = appElement() else { return [] }
        let windows = (copyAttr(appEl, kAXWindowsAttribute) as? [AXUIElement]) ?? []
        return windows.compactMap { win -> TrackedWindow? in
            guard let id = windowID(of: win) else { return nil }   // unresolved id → skip
            let subrole = copyAttr(win, kAXSubroleAttribute) as? String
            let minimized = copyAttr(win, kAXMinimizedAttribute) as? Bool
            let fullscreen = copyAttr(win, "AXFullScreen") as? Bool
            guard WindowFiltering.isTileable(subrole: subrole,
                                             isMinimized: minimized,
                                             isFullscreen: fullscreen) else { return nil }
            return TrackedWindow(id: id, frame: frame(of: win))
        }
    }

    public func readFrame(_ id: CGWindowID) async -> CGRect? {
        guard let win = windowElement(id) else { return nil }
        return frame(of: win)
    }

    /// Move + resize `id` to `target` via the size→position→size decomposition (spike-04 /
    /// Rectangle: guards against cross-display size clamping). `AXEnhancedUserInterface` is
    /// disabled around the writes and restored via `defer` — this is a normally-returning actor
    /// method, so `defer` DOES run on every path (unlike AXProbe's `exit()`, TRAP-12); the
    /// no-defer check guards only AXProbe. Returns `true` iff all three writes returned
    /// `.success`. A `.success` write can still be silently size-clamped (iTerm2 73×67, spike-04
    /// — err=0 even when clamped); detecting that is the CALLER's readback concern (livecheck
    /// asserts snap via `readFrame`), not encoded here — no clamp compensation (YAGNI, post-#19).
    public func writeFrame(_ id: CGWindowID, to target: CGRect) async -> Bool {
        guard let appEl = appElement(), let win = windowElement(id) else { return false }

        let euiWasOn = (copyAttr(appEl, kAXEnhancedUserInterface) as? Bool) == true
        if euiWasOn { setBool(appEl, kAXEnhancedUserInterface, false) }
        defer { if euiWasOn { setBool(appEl, kAXEnhancedUserInterface, true) } }

        var size = target.size
        var origin = target.origin
        guard let sizeVal = AXValueCreate(.cgSize, &size),
              let posVal = AXValueCreate(.cgPoint, &origin) else { return false }

        let s1 = AXUIElementSetAttributeValue(win, kAXSizeAttribute as CFString, sizeVal)
        let p = AXUIElementSetAttributeValue(win, kAXPositionAttribute as CFString, posVal)
        let s2 = AXUIElementSetAttributeValue(win, kAXSizeAttribute as CFString, sizeVal)
        return s1 == .success && p == .success && s2 == .success
    }

    /// #19b — the REAL AXObserver→AsyncStream bridge (ADR-0001 rule 4; the ONLY place AX callbacks
    /// live). `nonisolated` because a `@convention(c)` callback can't capture `self`: the bridge
    /// state (continuation + `WindowIDMap` + the retained `AXObserver`) is module-global, written
    /// ONLY on the run-loop (main) thread — single-writer, the proven spike-05/06 shape.
    ///
    /// The source is added to `CFRunLoopGetMain()` in `CFRunLoopCommonModes` (NOT `GetCurrent()` —
    /// this runs on the actor executor, a pool thread whose loop never pumps; NOT `.defaultMode`
    /// only — NSApp switches to eventTracking/modal during menu & drag). Production (MenuBarExtra,
    /// #12) pumps main via NSApp; the AXProbe `livecheck-events` PROVE PUMPS main (never `sem.wait`,
    /// TRAP-14). A not-running target returns a finished-empty stream — no observer, no hang.
    public nonisolated func events() -> AsyncStream<WindowEvent> {
        // Resolve the pid WITHOUT touching actor-isolated state (`appElement()` is isolated;
        // `bundleID` is an immutable `let` → nonisolated-readable). Not running → finished-empty.
        guard let app = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID).first else {
            return AsyncStream { $0.finish() }
        }
        let pid = app.processIdentifier

        return AsyncStream { continuation in
            teardownEventObserver()                 // clean re-arm (single production adapter)
            var observer: AXObserver?
            guard AXObserverCreate(pid, axEventCallback, &observer) == .success,
                  let obs = observer else { continuation.finish(); return }

            // Publish bridge state BEFORE adding the source — no callback can fire until then, so
            // the callback thread never observes a nil continuation / stale observer (WCGW8).
            gEventContinuation = continuation
            gWindowIDMap = WindowIDMap()            // create-seed only this beat (F3 → #12)
            gEventObserver = obs                    // RETAIN — AddSource retains the source, not the
                                                    // observer; without this ARC frees it → 0 events.

            let appEl = AXUIElementCreateApplication(pid)
            for name in ["AXWindowCreated", "AXWindowMoved", "AXWindowResized", "AXUIElementDestroyed"] {
                _ = AXObserverAddNotification(obs, appEl, name as CFString, nil)   // spike-05: app-level fires all 4
            }
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .commonModes)

            // Teardown on cancel/finish: remove the source + release the observer (no leak, safe re-arm).
            continuation.onTermination = { _ in teardownEventObserver() }
        }
    }

    // MARK: - AX helpers (promoted from AXProbe)

    /// The window element in the target app whose CGWindowID equals `id`, or `nil`.
    private func windowElement(_ id: CGWindowID) -> AXUIElement? {
        guard let appEl = appElement() else { return nil }
        let windows = (copyAttr(appEl, kAXWindowsAttribute) as? [AXUIElement]) ?? []
        return windows.first { windowID(of: $0) == id }
    }
}

/// The one private call the architecture allows itself (ADR / research :27-28,
/// AeroSpace/Rectangle precedent): AXUIElement → CGWindowID. A bodyless external-symbol import
/// (like `extern`); `internal` to Kit, distinct from AXProbe's file-private copy — no clash.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ el: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

private let kAXEnhancedUserInterface = "AXEnhancedUserInterface"

// MARK: - #19b AXObserver→AsyncStream bridge (module-global; a @convention(c) callback can't
// capture self). ALL three are written ONLY on the run-loop (main) thread — single-writer, the
// proven spike-05/06 shape. `gEventObserver` is the mandatory strong ref (CFRunLoopAddSource
// retains the SOURCE, not the observer — without this the observer deallocs and no events fire).

private nonisolated(unsafe) var gEventContinuation: AsyncStream<WindowEvent>.Continuation?
private nonisolated(unsafe) var gWindowIDMap = WindowIDMap()
private nonisolated(unsafe) var gEventObserver: AXObserver?

/// Remove the source + release the observer + reset the bridge state. Called on stream
/// termination and on re-arm. Removing a source from main's run loop off-thread is legal.
private func teardownEventObserver() {
    if let obs = gEventObserver {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .commonModes)
    }
    gEventObserver = nil
    gEventContinuation = nil
    gWindowIDMap = WindowIDMap()
}

/// The no-capture `@convention(c)` AX callback (spike-05: a closure literal with no captures
/// converts to `AXObserverCallback`; the observer arrives as param 1 for on-the-fly re-registration).
/// Maps the notification → `WindowEventKind`, resolves the CGWindowID (alive: direct
/// `_AXUIElementGetWindow` + create-seed the map; destroy: `consumeDestroy` since the AX id is
/// -25201/0 then, spike-05), reads a NON-nil frame for frame-bearing kinds (A5 — else reduce
/// no-ops), and yields the `WindowEvent`. Unknown/deduped destroy → dropped (no phantom removal).
private let axEventCallback: AXObserverCallback = { observer, element, notification, _ in
    guard let kind = WindowEventKind(axNotification: notification as String) else { return }
    let hash = CFHash(element)                       // UInt, stable dead-or-alive (spike-05)
    let resolvedID: CGWindowID?
    let windowFrame: CGRect?
    switch kind {
    case .created, .moved, .resized:
        guard let id = windowID(of: element) else { return }   // alive → resolvable
        resolvedID = id
        windowFrame = frame(of: element)             // A5: non-nil frame so reduce can retile
        if kind == .created {
            gWindowIDMap.record(hash: hash, id: id)
            // Belt (spike-05 (b)): also register destroyed on the new window; -25209 dup is benign.
            _ = AXObserverAddNotification(observer, element, "AXUIElementDestroyed" as CFString, nil)
        }
    case .destroyed:
        resolvedID = gWindowIDMap.consumeDestroy(hash: hash)   // -25201 → resolve via the map (once)
        windowFrame = nil
    }
    guard let id = resolvedID else { return }        // unknown / duplicate destroy → drop
    gEventContinuation?.yield(WindowEvent(windowID: id, kind: kind, frame: windowFrame))
}

private func copyAttr(_ el: AXUIElement, _ attr: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, attr as CFString, &value) == .success else { return nil }
    return value
}

private func setBool(_ el: AXUIElement, _ attr: String, _ value: Bool) {
    AXUIElementSetAttributeValue(el, attr as CFString, value ? kCFBooleanTrue : kCFBooleanFalse)
}

private func windowID(of win: AXUIElement) -> CGWindowID? {
    var id = CGWindowID(0)
    return _AXUIElementGetWindow(win, &id) == .success ? id : nil
}

private func frame(of win: AXUIElement) -> CGRect {
    var pos = CGPoint.zero, size = CGSize.zero
    if let pv = copyAttr(win, kAXPositionAttribute), CFGetTypeID(pv) == AXValueGetTypeID() {
        _ = AXValueGetValue(pv as! AXValue, .cgPoint, &pos)
    }
    if let sv = copyAttr(win, kAXSizeAttribute), CFGetTypeID(sv) == AXValueGetTypeID() {
        _ = AXValueGetValue(sv as! AXValue, .cgSize, &size)
    }
    return CGRect(origin: pos, size: size)
}
