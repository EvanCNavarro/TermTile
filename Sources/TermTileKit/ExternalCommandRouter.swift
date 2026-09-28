import Foundation
import TermTileCore

/// The imperative side of `termtile://…` (zio re-tiles after it opens or closes a session window). URLs pass the
/// Core allowlist (`ExternalCommand`); anything else is dropped. A burst of requests collapses to one running
/// rearrange plus at most one trailing rearrange: the trailing run sees every window opened during the first,
/// and N requests never walk the windows N times.
public actor ExternalCommandRouter {
    private let rearrange: @Sendable () async -> Void
    private var isRunning = false
    private var isPending = false

    public init(rearrange: @escaping @Sendable () async -> Void) {
        self.rearrange = rearrange
    }

    /// True when the URL was an allowlisted command (it runs now, or once the current run ends).
    @discardableResult
    public func receive(_ url: URL) -> Bool {
        guard let command = ExternalCommand(url: url) else { return false }
        switch command {
        case .rearrange: requestRearrange()
        }
        return true
    }

    private func requestRearrange() {
        guard !isRunning else {
            isPending = true
            return
        }
        isRunning = true
        Task { await drain() }
    }

    private func drain() async {
        repeat {
            isPending = false
            await rearrange()
        } while isPending
        isRunning = false
    }
}
