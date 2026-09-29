import Foundation

extension MenuBarViewModel {
    /// Record that the user was sent to Settings to allow TermTile (TRAP-23). If TermTile is STILL untrusted after
    /// that, the entry Settings shows is stale (another build under this bundle ID), so `accessibilityState` turns
    /// to `.grantBroken` and the notice offers the reset. Per launch only: never saved, so a fresh start begins at
    /// the plain first-grant prompt.
    public func noteAccessibilitySettingsOpened() {
        sentToAccessibilitySettings = true
    }
}
