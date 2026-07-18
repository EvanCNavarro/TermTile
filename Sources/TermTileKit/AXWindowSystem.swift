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
        let apps = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID)
            .map(AXRunningApplication.init)
        guard let app = TargetRunningApplicationResolver.preferred(
            bundleID: bundleID,
            in: apps,
            bundleIdentifier: \.bundleIdentifier,
            isRegular: \.isRegular
        ) else {
            return nil
        }
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

    // MARK: - AX helpers (promoted from AXProbe)

    /// The window element in the target app whose CGWindowID equals `id`, or `nil`.
    private func windowElement(_ id: CGWindowID) -> AXUIElement? {
        guard let appEl = appElement() else { return nil }
        let windows = (copyAttr(appEl, kAXWindowsAttribute) as? [AXUIElement]) ?? []
        return windows.first { windowID(of: $0) == id }
    }
}

private struct AXRunningApplication {
    let app: NSRunningApplication

    var bundleIdentifier: String? { app.bundleIdentifier }
    var isRegular: Bool { app.activationPolicy == .regular }
    var processIdentifier: pid_t { app.processIdentifier }
}

/// The one private call the architecture allows itself (ADR / research :27-28,
/// AeroSpace/Rectangle precedent): AXUIElement → CGWindowID. A bodyless external-symbol import
/// (like `extern`); `internal` to Kit, distinct from AXProbe's file-private copy — no clash.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ el: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

private let kAXEnhancedUserInterface = "AXEnhancedUserInterface"

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
        // swiftlint:disable:next force_cast - CFTypeID checked above; AXValueGetValue needs AXValue (AX idiom)
        _ = AXValueGetValue(pv as! AXValue, .cgPoint, &pos)
    }
    if let sv = copyAttr(win, kAXSizeAttribute), CFGetTypeID(sv) == AXValueGetTypeID() {
        // swiftlint:disable:next force_cast - CFTypeID checked above; AXValueGetValue needs AXValue (AX idiom)
        _ = AXValueGetValue(sv as! AXValue, .cgSize, &size)
    }
    return CGRect(origin: pos, size: size)
}
