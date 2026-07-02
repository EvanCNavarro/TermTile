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
        // epochUs stamped in-process at write time: shell-side stamps carry ~40-120ms
        // spawn overhead that swamps AX latencies (spike-05 audit F5).
        let epochUs = Int(Date().timeIntervalSince1970 * 1_000_000)
        let start = clock.now
        let err = AXUIElementSetAttributeValue(win, attr as CFString, value)
        let micros = (clock.now - start) / .microseconds(1)
        allOK = allOK && err == .success
        print("write: \(label) err=\(err.rawValue) us=\(Int(micros)) epochUs=\(epochUs)")
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

// Spike 05 mode: per-pid AXObserver — register app-level window notifications +
// per-window destroyed, then pump the run loop for N seconds printing one line per
// event. Which registration actually reports destruction (app-level vs per-window)
// is DATA observed at fire time — app-level registration accepts silently (audit F2).
// Exit 0 iff the app-level created/moved/resized registrations returned .success.
// Findings: docs/research/spikes/05-axobserver-events.md
func nowEpochUs() -> Int { Int(Date().timeIntervalSince1970 * 1_000_000) }

// skipPerWindow (--no-perwin) suppresses per-window + on-the-fly destroyed
// registration, isolating whether APP-level AXUIElementDestroyed fires for window
// destruction at all — fire/no-fire is the only way to answer that (audit F2).
func observe(bundleID: String, seconds: Int, skipPerWindow: Bool) {
    // Line-buffer stdout: when redirected to a file, Swift print() is FULLY buffered
    // and an abnormal exit destroys the whole event log (audit F4, verified).
    setvbuf(stdout, nil, _IOLBF, 0)
    guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
    else { print("observe: \(bundleID) not running"); exit(1) }
    let pid = app.processIdentifier

    var obs: AXObserver?
    // No-capture closure → @convention(c); the observer arrives as the callback's own
    // first parameter, so re-registration needs no globals/refcon (audit F1 shape).
    let createErr = AXObserverCreate(pid, { observer, element, notification, _ in
        let name = notification as String
        var windowID = CGWindowID(0)
        let idErr = _AXUIElementGetWindow(element, &windowID)
        // Inlined WindowEventKind mapping — pointer: Sources/TermTile/WindowEvent.swift
        // (executable targets can't import executables, spike-04 audit F4 precedent).
        let kind: String
        switch name {
        case "AXWindowCreated": kind = "created"
        case "AXWindowMoved": kind = "moved"
        case "AXWindowResized": kind = "resized"
        case "AXUIElementDestroyed": kind = "destroyed"
        default: kind = "unmapped"
        }
        // CFHash correlates create↔destroy even if id resolution fails on the dead
        // element (audit F11/W3).
        print("event: epochUs=\(nowEpochUs()) name=\(name) kind=\(kind) id=\(windowID) "
            + "idErr=\(idErr.rawValue) hash=\(CFHash(element))")
        if name == "AXWindowCreated", !CommandLine.arguments.contains("--no-perwin") {
            // Register destroyed on the new window on-the-fly; -25209
            // (already registered) is benign (audit F3).
            let err = AXObserverAddNotification(
                observer, element, "AXUIElementDestroyed" as CFString, nil)
            print("event: destroyed-on-new hash=\(CFHash(element)) err=\(err.rawValue)")
        }
    }, &obs)
    guard createErr == .success, let observer = obs
    else { print("observe: AXObserverCreate err=\(createErr.rawValue)"); exit(1) }

    let appEl = AXUIElementCreateApplication(pid)
    var registrationsOK = true
    for name in ["AXWindowCreated", "AXWindowMoved", "AXWindowResized", "AXUIElementDestroyed"] {
        let err = AXObserverAddNotification(observer, appEl, name as CFString, nil)
        print("register: app-level \(name) err=\(err.rawValue)")
        // App-level destroyed acceptance/fire behavior is the (b) finding, not a
        // pass/fail criterion (audit F2).
        if name != "AXUIElementDestroyed" { registrationsOK = registrationsOK && err == .success }
    }
    if skipPerWindow {
        print("register: per-window destroyed SKIPPED (--no-perwin)")
    } else {
        let windows = (copyAttr(appEl, kAXWindowsAttribute).1 as? [AXUIElement]) ?? []
        var perWindowOK = 0
        for win in windows {
            var windowID = CGWindowID(0)
            _ = _AXUIElementGetWindow(win, &windowID)
            let err = AXObserverAddNotification(observer, win, "AXUIElementDestroyed" as CFString, nil)
            if err == .success { perWindowOK += 1 }
            else { print("register: per-window destroyed id=\(windowID) err=\(err.rawValue)") }
        }
        print("register: per-window destroyed ok=\(perWindowOK)/\(windows.count)")
    }

    CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
    print("observe: pid=\(pid) armed epochUs=\(nowEpochUs()) deadline=\(seconds)s")
    let deadline = Date().addingTimeInterval(Double(seconds))
    while Date() < deadline {
        // rc=3 kCFRunLoopRunTimedOut is the expected deadline exit (audit F9).
        _ = CFRunLoopRunInMode(.defaultMode, deadline.timeIntervalSinceNow, false)
    }
    print("observe: done epochUs=\(nowEpochUs())")
    exit(registrationsOK ? 0 : 1)
}

if CommandLine.arguments.count >= 4, CommandLine.arguments[1] == "observe",
   let seconds = Int(CommandLine.arguments[3]) {
    observe(bundleID: CommandLine.arguments[2], seconds: seconds,
            skipPerWindow: CommandLine.arguments.contains("--no-perwin"))
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

