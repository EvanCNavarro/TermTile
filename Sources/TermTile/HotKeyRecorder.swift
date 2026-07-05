import AppKit
import Carbon.HIToolbox
import MacFaceKit
import SwiftUI
import TermTileKit

/// A click-to-record shortcut field (#25b). SwiftUI has no native one, so this is a self-contained
/// focusable `NSView` that DRAWS itself and grabs first-responder on its OWN `mouseDown` — the
/// reliable pattern (an earlier SwiftUI-Button + `.background` recorder failed because the Button
/// kept keyboard focus, so the capture view never became first responder in the menu popover).
/// ⌘-combos arrive via `performKeyEquivalent` (grabbed before the main menu); other combos via
/// `keyDown`. Esc cancels; key-repeat is ignored; only a bindable combo (needs ⌥ or ⌃) is reported.
struct HotKeyRecorder: NSViewRepresentable {
    let current: HotKeyConfig
    let registered: Bool
    let onCapture: (HotKeyConfig) -> Void

    func makeNSView(context: Context) -> HotKeyRecorderView {
        let view = HotKeyRecorderView()
        view.onCapture = onCapture
        view.update(current: current, registered: registered)
        return view
    }

    func updateNSView(_ view: HotKeyRecorderView, context: Context) {
        view.onCapture = onCapture
        view.update(current: current, registered: registered)
    }
}

final class HotKeyRecorderView: NSView {
    var onCapture: ((HotKeyConfig) -> Void)?
    private var current = HotKeyConfig.rearrange
    private var registered = true
    private var recording = false

    /// Refresh the displayed combo from the model — but never while actively recording (don't stomp
    /// the "Press keys…" prompt).
    func update(current: HotKeyConfig, registered: Bool) {
        guard !recording else { return }
        self.current = current
        self.registered = registered
        needsDisplay = true
    }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 120, height: 22) }

    override func draw(_ dirtyRect: NSRect) {
        let box = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: box, xRadius: 5, yRadius: 5)
        // Dark, distinct field (Tokens.nsField) so the recorder reads as a separate input on the
        // dark panel — not the near-panel-colored system control background.
        (recording ? Tokens.nsAccent.withAlphaComponent(0.18) : Tokens.nsField).setFill()
        path.fill()
        (recording ? Tokens.nsAccent : Tokens.nsLine).setStroke()
        path.stroke()

        let text = recording ? "Press keys…"
            : (registered ? current.displayString : "\(current.displayString) ⚠")
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: recording ? Tokens.nsAccent : Tokens.nsText,
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        (text as NSString).draw(at: NSPoint(x: (bounds.width - size.width) / 2,
                                            y: (bounds.height - size.height) / 2), withAttributes: attrs)
    }

    // The click that starts recording ALSO focuses this view (same gesture) — the key to reliable
    // capture in a popover, vs a separate button toggling state then hoping focus transfers.
    override func mouseDown(with event: NSEvent) {
        recording.toggle()
        window?.makeFirstResponder(recording ? self : nil)
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if !handle(event) { super.keyDown(with: event) }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        handle(event)
    }

    // Losing focus (click away / popover dismiss) ends recording cleanly.
    override func resignFirstResponder() -> Bool {
        recording = false
        needsDisplay = true
        return true
    }

    /// Returns true if consumed. Esc cancels; key-repeat dropped; a valid combo is captured, ends
    /// recording, and is reported; an invalid combo (no ⌥/⌃) beeps and keeps recording.
    private func handle(_ event: NSEvent) -> Bool {
        guard recording else { return false }
        if event.isARepeat { return true }
        if event.keyCode == UInt16(kVK_Escape) {
            recording = false
            window?.makeFirstResponder(nil)
            needsDisplay = true
            return true
        }
        let config = HotKeyConfig(keyCode: UInt32(event.keyCode),
                                  modifiers: HotKeyConfig.carbonModifiers(from: event.modifierFlags))
        guard config.isValid else { NSSound.beep(); return true }   // needs ⌥ or ⌃ — reject, stay
        recording = false
        current = config
        window?.makeFirstResponder(nil)
        needsDisplay = true
        onCapture?(config)
        return true
    }
}
