import Foundation

/// When the menu panel's window should be resized back onto its content, and to what.
///
/// `MenuBarExtra(.window)` keeps a HIGH-WATER MARK: the window grows to the tallest content it has
/// ever shown and never gives the height back, so shorter content is centred in an oversized window
/// with transparent bands above and below (EvanCNavarro/TermTile#44).
///
/// The decision is pure so it can be tested without a window. Every guard here exists because the
/// wrong answer is worse than no answer: growing would fight SwiftUI's own sizing, and treating an
/// absent measurement as a height would resize the panel to nothing.
public enum PanelSizing {
    /// The height to resize the panel to, or `nil` to leave it alone.
    ///
    /// - Parameters:
    ///   - currentHeight: the window's height now.
    ///   - measuredContentHeight: what the SwiftUI content reported it needs; `0` when unmeasured.
    public static func shrinkTarget(currentHeight: Double, measuredContentHeight: Double) -> Double? {
        guard measuredContentHeight > 0 else { return nil }
        guard currentHeight - measuredContentHeight > 1 else { return nil }
        return measuredContentHeight
    }
}
