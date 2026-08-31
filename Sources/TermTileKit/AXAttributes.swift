@preconcurrency import ApplicationServices
import Foundation

/// Shared AX attribute reads.
///
/// Promoted out of `AXWindowSystem` when `AXSessionReader` arrived (#37b): the same accessor in
/// two adapters is one invariant in two places, which is what FL-5 exists to prevent. `internal`
/// so it stays inside Kit — ADR-0001 rule 2 keeps ApplicationServices out of Core and the shell.
func copyAttr(_ el: AXUIElement, _ attr: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, attr as CFString, &value) == .success else { return nil }
    return value
}

/// A parameterized AX read — the ranged-text path `AXSessionReader` uses to pull only a tail.
func copyParamAttr(_ el: AXUIElement, _ attr: String, _ parameter: CFTypeRef) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyParameterizedAttributeValue(el, attr as CFString, parameter, &value)
        == .success else { return nil }
    return value
}
