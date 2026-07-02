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
import TermTileCore  // spike-06: exercise the REAL MoveClassifier live (no inline copy)
import TermTileKit   // #19a livecheck: drive the REAL AXWindowSystem adapter live (no inline copy)

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

// Spike 06 mode: drag-end / self-move tagging. Places a spike window at a known frame,
// arms an app-level AXObserver, records a PendingMove expectation, drives ONE programmatic
// move, and — GATED on a real AXWindowMoved firing for that window (audit B1: a ledger-only
// verdict is spoofable; the moved-event fire is the gate, not a data line) — runs the REAL
// TermTileCore.MoveClassifier three ways on the SAME observed frame: vs the recorded
// expectation (→internal), vs an empty ledger (→external), vs a +100-shifted ledger
// (→external). Exit 0 iff moved fired AND position actually changed AND all three verdicts
// hold. Findings: docs/research/spikes/06-drag-end-detection.md
nonisolated(unsafe) var dragMovedWindows: Set<CGWindowID> = []  // set on the run-loop thread only

func dragprobe(bundleID: String, windowID: CGWindowID) {
    setvbuf(stdout, nil, _IOLBF, 0)  // spike-05 F4: line-buffer for tail-ability
    guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
    else { print("dragprobe: \(bundleID) not running"); exit(1) }
    let appEl = AXUIElementCreateApplication(app.processIdentifier)
    let windows = (copyAttr(appEl, kAXWindowsAttribute).1 as? [AXUIElement]) ?? []
    guard let win = windows.first(where: { w in
        var id = CGWindowID(0)
        return _AXUIElementGetWindow(w, &id) == .success && id == windowID
    }) else { print("dragprobe: window \(windowID) not found in kAXWindows"); exit(1) }

    func readFrame() -> CGRect {
        var pos = CGPoint.zero, size = CGSize.zero
        if let pv = copyAttr(win, kAXPositionAttribute).1, CFGetTypeID(pv) == AXValueGetTypeID() {
            _ = AXValueGetValue(pv as! AXValue, .cgPoint, &pos)
        }
        if let sv = copyAttr(win, kAXSizeAttribute).1, CFGetTypeID(sv) == AXValueGetTypeID() {
            _ = AXValueGetValue(sv as! AXValue, .cgSize, &size)
        }
        return CGRect(origin: pos, size: size)
    }
    func writeAttr(_ attr: String, _ v: AXValue) -> AXError {
        AXUIElementSetAttributeValue(win, attr as CFString, v)
    }
    func posValue(_ p: CGPoint) -> AXValue { var q = p; return AXValueCreate(.cgPoint, &q)! }
    func sizeValue(_ s: CGSize) -> AXValue { var t = s; return AXValueCreate(.cgSize, &t)! }

    // AXEnhancedUserInterface off during writes (spike-04 F2 / research :58-59).
    // NOTE: restore is INLINE before the single terminal exit() — NOT `defer`. AXProbe
    // terminates via exit(), which SKIPS Swift defer (spike-07 R1, verified: /tmp/deferexit
    // never printed DEFER-RAN). A `defer` here silently left iTerm2's enhanced-UI OFF after
    // every dragprobe run. Enforced by .engine/checks/axprobe-no-defer.sh.
    let euiWasOn = (copyAttr(appEl, "AXEnhancedUserInterface").1 as? Bool) == true
    if euiWasOn { _ = AXUIElementSetAttributeValue(appEl, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse) }
    func restoreEUI() {
        if euiWasOn { _ = AXUIElementSetAttributeValue(appEl, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue) }
    }

    // Setup (events NOT gated): place at a known on-screen base so the measured +80 move
    // can't clamp off-screen. size→pos→size (spike-04 ordering).
    let base = CGRect(x: 200, y: 200, width: 800, height: 600)
    _ = writeAttr(kAXSizeAttribute, sizeValue(base.size))
    _ = writeAttr(kAXPositionAttribute, posValue(base.origin))
    _ = writeAttr(kAXSizeAttribute, sizeValue(base.size))
    usleep(200_000)  // settle before we start measuring
    let preMove = readFrame()
    print("dragprobe: placed base, preMove=\(rectStr(preMove))")

    // Arm the observer AFTER placement so only the measured move is observed.
    var obs: AXObserver?
    guard AXObserverCreate(app.processIdentifier, { _, element, notification, _ in
        let name = notification as String
        guard name == "AXWindowMoved" || name == "AXWindowResized" else { return }
        var wid = CGWindowID(0)
        _ = _AXUIElementGetWindow(element, &wid)
        print("event: name=\(name) id=\(wid) epochUs=\(nowEpochUs())")
        dragMovedWindows.insert(wid)
    }, &obs) == .success, let observer = obs
    else { print("dragprobe: AXObserverCreate failed"); exit(1) }
    for n in ["AXWindowMoved", "AXWindowResized"] {
        _ = AXObserverAddNotification(observer, appEl, n as CFString, nil)
    }
    CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)

    // Record the expectation from the SAME readback path (audit SF4: size from live read,
    // only position changes → no clamp risk), then drive the move.
    let targetPos = CGPoint(x: preMove.origin.x + 80, y: preMove.origin.y + 80)
    guard targetPos != preMove.origin else { print("dragprobe: target == current, no move"); exit(1) }
    let expected = CGRect(origin: targetPos, size: preMove.size)
    let nowEpoch = Date().timeIntervalSince1970
    let pending = [PendingMove(windowID: windowID, expectedFrame: expected, expiresAtEpoch: nowEpoch + 2.0)]
    print("dragprobe: expect=\(rectStr(expected)) armed epochUs=\(nowEpochUs())")
    _ = writeAttr(kAXPositionAttribute, posValue(targetPos))

    // Pump until the real AXWindowMoved for our window fires, or deadline (audit B1 gate).
    let deadline = Date().addingTimeInterval(2.0)
    while Date() < deadline && !dragMovedWindows.contains(windowID) {
        _ = CFRunLoopRunInMode(.defaultMode, 0.1, false)
    }
    let movedFired = dragMovedWindows.contains(windowID)
    usleep(100_000)
    let observed = readFrame()
    let posChanged = observed.origin != preMove.origin
    let eps: CGFloat = 1.0
    let vInternal = MoveClassifier.classify(windowID: windowID, observedFrame: observed,
        nowEpoch: nowEpoch, pending: pending, epsilon: eps)
    let vEmpty = MoveClassifier.classify(windowID: windowID, observedFrame: observed,
        nowEpoch: nowEpoch, pending: [], epsilon: eps)
    let shifted = [PendingMove(windowID: windowID,
        expectedFrame: expected.offsetBy(dx: 100, dy: 100), expiresAtEpoch: nowEpoch + 2.0)]
    let vShifted = MoveClassifier.classify(windowID: windowID, observedFrame: observed,
        nowEpoch: nowEpoch, pending: shifted, epsilon: eps)

    print("dragprobe: movedFired=\(movedFired) posChanged=\(posChanged) observed=\(rectStr(observed))")
    print("dragprobe: verdict vsExpected=\(vInternal) vsEmpty=\(vEmpty) vsShifted+100=\(vShifted)")
    let pass = movedFired && posChanged
        && vInternal == .internal && vEmpty == .external && vShifted == .external
    print("dragprobe: PASS=\(pass)")
    restoreEUI()  // inline restore before exit() (see restoreEUI note above)
    exit(pass ? 0 : 1)
}

func rectStr(_ r: CGRect) -> String {
    "(\(Int(r.origin.x)),\(Int(r.origin.y)) \(Int(r.width))x\(Int(r.height)))"
}

// Spike 06 mode: mouse-up feasibility for the drag-END signal. Uses the NON-prompting
// CGPreflightListenEventAccess() (audit N12: CGRequestListenEventAccess would raise a TCC
// dialog on Bobby's unattended screen — declined) as the reported signal, and only
// attempts a listen-only CGEventTap for leftMouseUp if input monitoring is ALREADY
// granted. Either outcome is a finding for #12's permission UX; does not gate #6 DONE.
func mouseprobe(seconds: Int) {
    setvbuf(stdout, nil, _IOLBF, 0)
    let granted = CGPreflightListenEventAccess()
    print("mouseprobe: inputMonitoringPreflight=\(granted)")
    guard granted else {
        print("mouseprobe: not granted — menu-bar app will need Input Monitoring for a "
            + "global mouse-up CGEventTap (finding for #12). No prompt raised (preflight only).")
        exit(0)
    }
    let mask = CGEventMask(1 << CGEventType.leftMouseUp.rawValue)
    guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
        options: .listenOnly, eventsOfInterest: mask,
        callback: { _, _, event, _ in
            print("mouseprobe: leftMouseUp observed epochUs=\(nowEpochUs())")
            return Unmanaged.passUnretained(event)
        }, userInfo: nil)
    else { print("mouseprobe: CGEvent.tapCreate returned nil despite preflight=true"); exit(0) }
    CGEvent.tapEnable(tap: tap, enable: true)
    let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
    print("mouseprobe: listen-only leftMouseUp tap installed+enabled from bg process; "
        + "watching \(seconds)s (reception during unattended run may be 0 — that is expected)")
    let deadline = Date().addingTimeInterval(Double(seconds))
    while Date() < deadline { _ = CFRunLoopRunInMode(.defaultMode, deadline.timeIntervalSinceNow, false) }
    print("mouseprobe: done epochUs=\(nowEpochUs())")
    exit(0)
}

// #19a mode: LIVE grid-snap PROVE of the REAL TermTileKit.AXWindowSystem adapter (FL-1).
// Creates its OWN throwaway iTerm2 windows (NEVER touches Bobby's existing windows — the adapter's
// writeFrame is driven on the throwaway ids only, not a global activate()), computes a real grid
// via AXGeometry (origin-screen flip) + TileLayout, snaps the throwaways with the REAL adapter,
// asserts via adapter.readFrame that they landed, screencaptures the grid, then closes the
// throwaways tolerantly (already-gone = success, TRAP-8; addressed by `window id N`, TRAP-6).
// events() is NOT exercised here — the AXObserver bridge + new-window snap is #19b.
// Exit 0 iff every throwaway write returned success AND its readback origin snapped within EPS.
func runOsascript(_ script: String) -> String? {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    p.arguments = ["-e", script]
    let out = Pipe(), err = Pipe()
    p.standardOutput = out; p.standardError = err
    do { try p.run() } catch { print("livecheck: osascript launch failed: \(error)"); return nil }
    p.waitUntilExit()
    let data = out.fileHandleForReading.readDataToEndOfFile()
    let s = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    if p.terminationStatus != 0 {
        let e = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        print("livecheck: osascript rc=\(p.terminationStatus) err=\(e.trimmingCharacters(in: .whitespacesAndNewlines))")
    }
    return s
}

/// The adapter-driving CORE of the PROVE (steps 1,3,4,5): given already-created throwaway window
/// `ids`, build the REAL `AXWindowSystem`, compute a real `TileLayout` grid on the origin screen's
/// AX visibleFrame, snap each id with the REAL `adapter.writeFrame`, assert the snap via
/// `adapter.readFrame`, and screencapture the result. Uses NO AppleEvents (the caller owns window
/// create/close), so it runs under only Accessibility trust (terminal-attributed, spike-02/04).
/// Returns `true` iff every write succeeded AND its readback origin snapped within EPS.
func stderrLog(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }

/// The origin screen's AX visibleFrame — read `NSScreen` (a `@MainActor` type) HERE, on the
/// main-actor top-level context, so the async snap work never hops back to a main thread that is
/// parked in `sem.wait()` (that deadlock cost a full live diagnosis, TRAP-14). Points, origin
/// screen (never `.main` — audit Axis 3). Returns `.null` if there is no screen.
@MainActor func originAXVisibleFrame() -> CGRect {
    guard let screen = NSScreen.screens.first else { return .null }
    let axVisible = AXGeometry.axFrame(fromCocoa: screen.visibleFrame, displayHeight: screen.frame.height)
    print("livecheck: originScreen H=\(Int(screen.frame.height)) "
        + "cocoaVisible=\(rectStr(screen.visibleFrame)) → axVisible=\(rectStr(axVisible))")
    return axVisible
}

func snapWindows(bundleID: String, ids: [CGWindowID], axVisible: CGRect, outPNG: String) async -> Bool {
    let eps: CGFloat = 2.0            // spike-04: non-clamped readbacks are integer-exact
    let gap: CGFloat = 12
    guard axVisible != .null else { print("livecheck: no screen"); return false }

    // (3) The REAL adapter + a real TileLayout grid for `ids.count` windows.
    let adapter = AXWindowSystem(bundleID: bundleID)
    let targets = TileLayout.frames(count: ids.count, visibleFrame: axVisible, gap: gap)

    // Opportunistic enumerate findings (audit Axis 6: log, no deep treatment — cross-Space/
    // fullscreen completeness is #19b). Includes Bobby's windows READ-ONLY; none are moved.
    stderrLog("stage: adapter.tileableWindows()")
    let enumerated = await adapter.tileableWindows()
    print("livecheck: adapter enumerated \(enumerated.count) tileable iTerm2 window(s); "
        + "throwaways present=\(ids.allSatisfy { id in enumerated.contains { $0.id == id } })")

    // (4) Snap each throwaway with the REAL adapter.writeFrame; assert via adapter.readFrame.
    var allSnapped = true
    for (k, id) in ids.enumerated() {
        let target = targets[k]
        stderrLog("stage: writeFrame id=\(id) (\(k + 1)/\(ids.count))")
        let ok = await adapter.writeFrame(id, to: target)
        usleep(120_000)  // spike-04: settle < 50ms; generous
        stderrLog("stage: readFrame id=\(id)")
        let back = await adapter.readFrame(id) ?? .null
        let dOrigin = max(abs(back.origin.x - target.origin.x), abs(back.origin.y - target.origin.y))
        let dSize = max(abs(back.width - target.width), abs(back.height - target.height))
        let snapped = ok && dOrigin <= eps       // origin is tiling-critical; size may cell-quantize
        allSnapped = allSnapped && snapped
        print("livecheck: id=\(id) write=\(ok) target=\(rectStr(target)) readback=\(rectStr(back)) "
            + "dOrigin=\(Int(dOrigin)) dSize=\(Int(dSize)) snapped=\(snapped)")
    }

    // (5) Screencapture the rendered grid (FL-9 / MEMORY: screencapture = rendered-reality proof).
    stderrLog("stage: screencapture → \(outPNG)")
    usleep(300_000)
    let cap = Process()
    cap.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    cap.arguments = ["-x", outPNG]
    try? cap.run(); cap.waitUntilExit()
    print("livecheck: screencapture rc=\(cap.terminationStatus) → \(outPNG)")
    return allSnapped
}

func livecheck(bundleID: String, count: Int, axVisible: CGRect, outPNG: String) async {
    setvbuf(stdout, nil, _IOLBF, 0)  // spike-05 F4: line-buffer for tail-ability

    // (2) Create N throwaway iTerm2 windows; iTerm2's AppleScript window id == CGWindowID (spike-03).
    var ids: [CGWindowID] = []
    for i in 0..<count {
        guard let out = runOsascript(
            "tell application \"iTerm2\" to return id of (create window with default profile)"),
            let raw = UInt32(out) else {
            print("livecheck: window \(i) create failed (out=nil/non-numeric)"); break
        }
        ids.append(CGWindowID(raw))
    }
    print("livecheck: created throwaway ids=\(ids.map(String.init).joined(separator: ","))")
    guard ids.count == count else {
        print("livecheck: FAIL — created \(ids.count)/\(count) windows")
        for id in ids { _ = runOsascript("tell application \"iTerm2\" to close (window id \(id))") }
        exit(1)
    }
    usleep(400_000)  // settle: let the new windows register in kAXWindows

    let allSnapped = await snapWindows(bundleID: bundleID, ids: ids, axVisible: axVisible, outPNG: outPNG)

    // (6) Close throwaways — SEPARATE from evidence (TRAP-9), tolerate already-gone (TRAP-8).
    for id in ids {
        _ = runOsascript("tell application \"iTerm2\" to close (window id \(id))")
    }
    print("livecheck: closed throwaways; PASS=\(allSnapped)")
    exit(allSnapped ? 0 : 1)
}

/// Consent-free variant: the CALLER (a shell with AppleEvents consent) creates + closes the
/// throwaway windows and passes their ids here; AXProbe drives ONLY the AX write path, so a
/// freshly-rebuilt ad-hoc AXProbe (new cdhash → AppleEvents consent reset, spike-02) can still
/// prove the live grid snap without a blocking Automation-consent dialog. Same real adapter,
/// same screencapture, same PASS criterion as `livecheck`.
func livecheckIDs(bundleID: String, ids: [CGWindowID], axVisible: CGRect, outPNG: String) async {
    setvbuf(stdout, nil, _IOLBF, 0)
    print("livecheck-ids: driving \(ids.count) pre-created ids="
        + "\(ids.map(String.init).joined(separator: ","))")
    let allSnapped = await snapWindows(bundleID: bundleID, ids: ids, axVisible: axVisible, outPNG: outPNG)
    print("livecheck-ids: PASS=\(allSnapped)")
    exit(allSnapped ? 0 : 1)
}

// Spike #7 mode: macOS Sequoia native-tiling interference / suppression surface. Exercises
// the REAL TermTileCore.NativeTilingSettings resolver against the REAL com.apple.WindowManager
// preference domain — (1) enumerates the 4 tiling toggles' live state, (2) proves the GLOBAL
// suppression surface is programmatically controllable via a write→readback→restore round-trip
// on ALL FOUR keys, one at a time. Uses CFPreferences at (currentUser, anyHost) — the exact
// scope `defaults`/`defaults write` touch (spike-07 R5), NOT CopyAppValue (which merges
// NSGlobalDomain + both host layers). Restore is INLINE + atexit, NEVER defer (R1). Findings:
// docs/research/spikes/07-native-tiling-interference.md
nonisolated(unsafe) let tileDomain = "com.apple.WindowManager" as CFString  // immutable, shared-safe
// Armed with the in-flight key's prior value ONLY during its round-trip window, so an
// unexpected exit() restores exactly the one key we mutated (belt to the inline restore, R1b).
nonisolated(unsafe) var tileRestore: [(key: CFString, prior: Bool?)] = []

func tileRead(_ key: CFString) -> Bool? {
    guard let v = CFPreferencesCopyValue(key, tileDomain,
        kCFPreferencesCurrentUser, kCFPreferencesAnyHost) else { return nil }
    if CFGetTypeID(v) == CFBooleanGetTypeID() { return CFBooleanGetValue((v as! CFBoolean)) }
    return (v as? NSNumber)?.boolValue  // defensive: a non-CFBoolean stored value
}
func tileWrite(_ key: CFString, _ value: Bool?) {
    // nil deletes the key (restores "absent"); a Bool writes the CFBoolean.
    let v: CFPropertyList? = value.map { $0 ? kCFBooleanTrue : kCFBooleanFalse }
    CFPreferencesSetValue(key, v, tileDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    CFPreferencesSynchronize(tileDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
}
func tileRestoreAll() { for e in tileRestore { tileWrite(e.key, e.prior) } }

func tilecheck() {
    setvbuf(stdout, nil, _IOLBF, 0)  // spike-05 F4: line-buffer for tail-ability
    // Manual-recovery hint BEFORE any mutation (R1c): a SIGKILL runs neither the inline
    // restore nor atexit, so a human needs the recovery command up front.
    print("tilecheck: SAFETY — the 4 tiling keys are ABSENT (OS default) on this Mac; if this "
        + "probe is hard-killed mid-round-trip, restore a stuck key with e.g. "
        + "`defaults delete com.apple.WindowManager EnableTilingByEdgeDrag`")
    print("tilecheck: macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")

    // (1) Enumerate live state via the REAL TermTileCore resolver.
    var storedMap: [NativeTilingToggle: Bool?] = [:]
    for t in NativeTilingToggle.allCases {
        let stored = tileRead(t.rawValue as CFString)
        storedMap[t] = stored
        let resolved = NativeTilingSettings.isEnabled(t, storedValue: stored)
        print("tilecheck: \(t.rawValue) stored=\(stored.map(String.init) ?? "absent") "
            + "resolved=\(resolved) isAutoSnapPath=\(NativeTilingToggle.autoSnapPaths.contains(t))")
    }
    let anyActive = NativeTilingSettings.anyAutoSnapPathActive(storedMap)
    print("tilecheck: anyAutoSnapPathActive=\(anyActive) (REAL com.apple.WindowManager read)")

    // (2) Round-trip ALL FOUR keys ONE AT A TIME (min blast radius, R3).
    atexit { tileRestoreAll() }  // belt-and-suspenders to the inline restore (R1b)
    var allOK = true
    for t in NativeTilingToggle.allCases {
        let key = t.rawValue as CFString
        let prior = tileRead(key)
        tileRestore = [(key, prior)]           // arm atexit for THIS key's window
        tileWrite(key, false)                  // suppress
        let afterSet = tileRead(key)
        tileWrite(key, prior)                  // restore (inline; nil deletes)
        let afterRestore = tileRead(key)
        tileRestore = []                       // window closed — nothing left to restore
        let setOK = (afterSet == false)
        let restoreOK = (afterRestore == prior)
        allOK = allOK && setOK && restoreOK
        print("tilecheck: roundtrip \(t.rawValue) prior=\(prior.map(String.init) ?? "absent") "
            + "afterSetFalse=\(afterSet.map(String.init) ?? "absent") "
            + "afterRestore=\(afterRestore.map(String.init) ?? "absent") "
            + "setOK=\(setOK) restoreOK=\(restoreOK)")
    }
    // PASS iff every key round-tripped (writable + restored) AND the live read showed the
    // expected all-default-on auto-snap state (Q2: suppression surface is controllable).
    print("tilecheck: PASS=\(allOK && anyActive)")
    exit(allOK && anyActive ? 0 : 1)
}

if CommandLine.arguments.count >= 2, CommandLine.arguments[1] == "tilecheck" {
    tilecheck()
}

// livecheck <bundle-id> [count] [outPNG] — #19a LIVE grid-snap PROVE. Dispatched via a
// semaphore-blocked `Task.detached`: top-level main.swift code runs on the @MainActor, so a plain
// `Task {}` INHERITS main-actor isolation and enqueues onto the main thread — which is then parked
// in `sem.wait()` → deadlock (TRAP-14). `Task.detached` runs on the global executor instead. The
// origin screen (a @MainActor NSScreen read) is resolved HERE, before the wait, and passed in so
// the detached work never hops back to the blocked main thread. livecheck calls exit() itself.
if CommandLine.arguments.count >= 3, CommandLine.arguments[1] == "livecheck" {
    let n = CommandLine.arguments.count >= 4 ? (Int(CommandLine.arguments[3]) ?? 4) : 4
    let png = CommandLine.arguments.count >= 5
        ? CommandLine.arguments[4] : "docs/verification/task19a-grid.png"
    let axVisible = originAXVisibleFrame()
    let sem = DispatchSemaphore(value: 0)
    Task.detached {
        await livecheck(bundleID: CommandLine.arguments[2], count: n, axVisible: axVisible, outPNG: png)
        sem.signal()
    }
    sem.wait()
}

// livecheck-ids <bundle-id> <outPNG> <id1> [id2 …] — #19a consent-free LIVE PROVE. The caller
// (a shell holding AppleEvents consent) creates+closes the throwaway windows; AXProbe drives only
// the AX write path, so a rebuilt ad-hoc binary (AppleEvents consent reset, spike-02) still proves
// the live snap. Same `Task.detached` + pre-resolved axVisible model as livecheck (TRAP-14).
if CommandLine.arguments.count >= 5, CommandLine.arguments[1] == "livecheck-ids" {
    let ids: [CGWindowID] = CommandLine.arguments[4...].compactMap { UInt32($0) }
    let axVisible = originAXVisibleFrame()
    let sem = DispatchSemaphore(value: 0)
    Task.detached {
        await livecheckIDs(bundleID: CommandLine.arguments[2], ids: ids,
                           axVisible: axVisible, outPNG: CommandLine.arguments[3])
        sem.signal()
    }
    sem.wait()
}

if CommandLine.arguments.count >= 4, CommandLine.arguments[1] == "dragprobe",
   let winID = UInt32(CommandLine.arguments[3]) {
    dragprobe(bundleID: CommandLine.arguments[2], windowID: CGWindowID(winID))
}

if CommandLine.arguments.count >= 2, CommandLine.arguments[1] == "mouseprobe" {
    mouseprobe(seconds: CommandLine.arguments.count >= 3 ? (Int(CommandLine.arguments[2]) ?? 2) : 2)
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

