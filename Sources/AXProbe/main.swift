// Spike 02+03 probe. Default mode (spike 02): prints whether THIS process is
// trusted for Accessibility — shell-exec (TCC attributes to the terminal) vs a
// micro .app bundle launched via `open` (attributes to itself). Findings:
// docs/research/spikes/02-accessibility-tcc.md
// `enumerate <bundle-id>` mode (spike 03): AXUIElementCreateApplication →
// kAXWindows per-window dump + CGWindowList id-join. Findings:
// docs/research/spikes/03-iterm2-window-enumeration.md
// Throwaway-quality by design (backlog Phase A contract).
@preconcurrency import ApplicationServices
import AppKit
import Foundation

// The one private call the architecture allows itself (research doc :27-28,
// AeroSpace/Rectangle precedent): AXUIElement → CGWindowID.
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ el: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

func copyAttr(_ el: AXUIElement, _ attr: String) -> (AXError, CFTypeRef?) {
    var value: CFTypeRef?
    let err = AXUIElementCopyAttributeValue(el, attr as CFString, &value)
    return (err, value)
}

func enumerate(bundleID: String) {
    guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
    else { print("enumerate: \(bundleID) not running"); exit(1) }
    let pid = app.processIdentifier
    let (winsErr, winsRef) = copyAttr(AXUIElementCreateApplication(pid), kAXWindowsAttribute)
    let windows = (winsRef as? [AXUIElement]) ?? []
    print("pid=\(pid) kAXWindows err=\(winsErr.rawValue) count=\(windows.count)")

    for (i, win) in windows.enumerated() {
        var windowID = CGWindowID(0)
        let idErr = _AXUIElementGetWindow(win, &windowID)
        let title = copyAttr(win, kAXTitleAttribute).1 as? String ?? "<nil>"
        let role = copyAttr(win, kAXRoleAttribute).1 as? String ?? "<nil>"
        let subrole = copyAttr(win, kAXSubroleAttribute).1 as? String ?? "<nil>"
        let minimized = copyAttr(win, kAXMinimizedAttribute).1 as? Bool
        let fullscreen = copyAttr(win, "AXFullScreen").1 as? Bool
        var pos = CGPoint.zero
        if let pv = copyAttr(win, kAXPositionAttribute).1, CFGetTypeID(pv) == AXValueGetTypeID() {
            _ = AXValueGetValue(pv as! AXValue, .cgPoint, &pos)
        }
        var size = CGSize.zero
        if let sv = copyAttr(win, kAXSizeAttribute).1, CFGetTypeID(sv) == AXValueGetTypeID() {
            _ = AXValueGetValue(sv as! AXValue, .cgSize, &size)
        }
        let minStr = minimized.map(String.init) ?? "<err>"
        let fsStr = fullscreen.map(String.init) ?? "<err>"
        print("[\(i)] id=\(windowID) idErr=\(idErr.rawValue) role=\(role) subrole=\(subrole) "
            + "min=\(minStr) fs=\(fsStr) frame=(\(Int(pos.x)),\(Int(pos.y)) "
            + "\(Int(size.width))x\(Int(size.height))) tileable="
            // Inlined WindowFiltering.isTileable (AXProbe can't import an executable target).
            + "\(subrole == "AXStandardWindow" && minimized == false && fullscreen == false) "
            + "title=\(title)")
    }

    // Cross-check: JOIN BY WINDOW NUMBER, never count equality (stoke-plan-3 F6:
    // CG optionAll includes phantom layer-0 windows + panels AX never reports).
    let axIDs = Set(windows.compactMap { win -> CGWindowID? in
        var windowID = CGWindowID(0)
        return _AXUIElementGetWindow(win, &windowID) == .success ? windowID : nil
    })
    let cgAll = (CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? [])
        .filter { ($0[kCGWindowOwnerPID as String] as? Int) == Int(pid) }
    let cgIDs = Set(cgAll.compactMap { $0[kCGWindowNumber as String] as? Int }.map(CGWindowID.init))
    print("cg: pid-windows=\(cgAll.count) ax-ids-in-cg=\(axIDs.intersection(cgIDs).count)/\(axIDs.count)")
}

if CommandLine.arguments.count >= 3, CommandLine.arguments[1] == "enumerate" {
    enumerate(bundleID: CommandLine.arguments[2])
    exit(0)
}

let key: CFString = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
// --prompt exercises the grant-dialog path; guarded because even prompting:false
// registers a denied TCC row when run from a bundle (spike finding — see note).
let prompting = CommandLine.arguments.contains("--prompt")
let trusted = AXIsProcessTrustedWithOptions([key: prompting] as CFDictionary)

let report = "trusted=\(trusted) prompting=\(prompting) pid=\(ProcessInfo.processInfo.processIdentifier) "
    + "path=\(CommandLine.arguments[0]) bundleID=\(Bundle.main.bundleIdentifier ?? "none")"

// `open` drops the caller's env, so the launcher passes AXPROBE_OUT via `open --env`.
if let outPath = ProcessInfo.processInfo.environment["AXPROBE_OUT"] {
    try? (report + "\n").write(toFile: outPath, atomically: true, encoding: .utf8)
}
print(report)

