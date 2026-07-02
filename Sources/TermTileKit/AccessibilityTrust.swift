// @preconcurrency: the SDK imports kAXTrustedCheckOptionPrompt as a mutable global
// (`public var … : Unmanaged<CFString>`), which Swift 6 strict concurrency rejects
// on plain import (verified in stoke-plan-2 audit, F1).
@preconcurrency import ApplicationServices
import Foundation

/// Accessibility (TCC) trust detection for the AX APIs the tiler depends on.
enum AccessibilityTrust {
    /// Deep link to the exact System Settings pane where the user grants trust.
    static let settingsDeepLink = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    /// Whether this process (or its TCC responsible process, e.g. the launching
    /// terminal) is trusted for Accessibility. `prompting: true` asks the system
    /// to show the grant dialog when untrusted — and even `false` registers a
    /// denied TCC entry when called from a bundled .app, so callers must treat
    /// any call as observable by TCC (spike 02 finding).
    static func isTrusted(prompting: Bool) -> Bool {
        let key: CFString = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
        return AXIsProcessTrustedWithOptions([key: prompting] as CFDictionary)
    }
}
