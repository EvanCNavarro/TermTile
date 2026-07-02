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

// Spike 04 mode: write ONE window's frame (size→position→size, research doc :56-59)
// and report per-op AXError + latency, readback settle, and match-vs-request as DATA.
// Exit 0 iff all writes returned .success AND readback is STABLE (two consecutive
// identical reads) — a min-size clamp probe correctly reads back ≠ request (audit F5).
// Findings: docs/research/spikes/04-frame-writes.md
func setFrame(bundleID: String, windowID: CGWindowID, target: CGRect) {
    guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
    else { print("setframe: \(bundleID) not running"); exit(1) }
    let appEl = AXUIElementCreateApplication(app.processIdentifier)
    let windows = (copyAttr(appEl, kAXWindowsAttribute).1 as? [AXUIElement]) ?? []
    guard let win = windows.first(where: { win in
        var id = CGWindowID(0)
        return _AXUIElementGetWindow(win, &id) == .success && id == windowID
    }) else { print("setframe: window \(windowID) not found in kAXWindows"); exit(1) }

    // AXEnhancedUserInterface: app-level, CFBoolean, present on iTerm2 (audit F2);
    // -25205 = attribute unsupported. Disable before writes, restore after (research :58-59).
    let euiAttr = "AXEnhancedUserInterface"
    let (euiErr, euiVal) = copyAttr(appEl, euiAttr)
    let euiWasOn = (euiVal as? Bool) == true
    print("eui: err=\(euiErr.rawValue) value=\(euiVal as? Bool ?? false)")
    if euiWasOn {
        let off = AXUIElementSetAttributeValue(appEl, euiAttr as CFString, kCFBooleanFalse)
        print("eui: disabled err=\(off.rawValue)")
    }

    var settablePos = DarwinBoolean(false)  // NOT Bool (audit F9)
    var settableSize = DarwinBoolean(false)
    let spErr = AXUIElementIsAttributeSettable(win, kAXPositionAttribute as CFString, &settablePos)
    let ssErr = AXUIElementIsAttributeSettable(win, kAXSizeAttribute as CFString, &settableSize)
    print("settable: pos=\(settablePos) err=\(spErr.rawValue) size=\(settableSize) err=\(ssErr.rawValue)")

    func readFrame() -> CGRect {
        var pos = CGPoint.zero
        var size = CGSize.zero
        if let pv = copyAttr(win, kAXPositionAttribute).1, CFGetTypeID(pv) == AXValueGetTypeID() {
            _ = AXValueGetValue(pv as! AXValue, .cgPoint, &pos)
        }
        if let sv = copyAttr(win, kAXSizeAttribute).1, CFGetTypeID(sv) == AXValueGetTypeID() {
            _ = AXValueGetValue(sv as! AXValue, .cgSize, &size)
        }
        return CGRect(origin: pos, size: size)
    }
    let before = readFrame()
    print("before: frame=\(Int(before.origin.x)),\(Int(before.origin.y)) "
        + "\(Int(before.width))x\(Int(before.height))")

    let clock = ContinuousClock()
    var targetSize = target.size
    var targetPos = target.origin
    var allOK = true
    func timedWrite(_ label: String, _ attr: String, _ value: AXValue) {
        let start = clock.now
        let err = AXUIElementSetAttributeValue(win, attr as CFString, value)
        let micros = (clock.now - start) / .microseconds(1)
        allOK = allOK && err == .success
        print("write: \(label) err=\(err.rawValue) us=\(Int(micros))")
    }
    guard let sizeVal = AXValueCreate(.cgSize, &targetSize),
          let posVal = AXValueCreate(.cgPoint, &targetPos)
    else { print("setframe: AXValueCreate failed"); exit(1) }
    timedWrite("size1", kAXSizeAttribute, sizeVal)
    timedWrite("pos", kAXPositionAttribute, posVal)
    timedWrite("size2", kAXSizeAttribute, sizeVal)

    // Settle: poll until two consecutive identical reads (max 500ms). Match verdict
    // vs request is printed as data — comparator inlined from the tested
    // Sources/TermTile/FrameMath.swift (AXProbe can't import an executable target).
    let settleStart = clock.now
    var prev = readFrame()
    var stable = false
    for _ in 0..<10 {
        usleep(50_000)
        let cur = readFrame()
        if cur == prev { stable = true; break }
        prev = cur
    }
    let settleMs = (clock.now - settleStart) / .milliseconds(1)
    let eps: CGFloat = 1.0
    let matches = abs(prev.origin.x - target.origin.x) <= eps
        && abs(prev.origin.y - target.origin.y) <= eps
        && abs(prev.width - target.width) <= eps
        && abs(prev.height - target.height) <= eps
    print("after: frame=\(Int(prev.origin.x)),\(Int(prev.origin.y)) "
        + "\(Int(prev.width))x\(Int(prev.height)) stable=\(stable) settleMs=\(Int(settleMs)) "
        + "matchesRequest=\(matches) request=\(Int(target.origin.x)),\(Int(target.origin.y)) "
        + "\(Int(target.width))x\(Int(target.height))")

    if euiWasOn {
        let on = AXUIElementSetAttributeValue(appEl, euiAttr as CFString, kCFBooleanTrue)
        print("eui: restored err=\(on.rawValue)")
    }
    exit(allOK && stable ? 0 : 1)
}

if CommandLine.arguments.count >= 3, CommandLine.arguments[1] == "enumerate" {
    enumerate(bundleID: CommandLine.arguments[2])
    exit(0)
}

if CommandLine.arguments.count >= 8, CommandLine.arguments[1] == "setframe",
   let winID = UInt32(CommandLine.arguments[3]),
   let x = Double(CommandLine.arguments[4]), let y = Double(CommandLine.arguments[5]),
   let w = Double(CommandLine.arguments[6]), let h = Double(CommandLine.arguments[7]) {
    setFrame(bundleID: CommandLine.arguments[2], windowID: CGWindowID(winID),
             target: CGRect(x: x, y: y, width: w, height: h))
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

