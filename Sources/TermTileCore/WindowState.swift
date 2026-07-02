import CoreGraphics

/// A window the tiler tracks: its CGWindowID and last-known frame. Insertion order in
/// `WindowState.windows` is the slot order the tiling policy (#10) maps to `TileLayout`
/// columns — hence an ordered list, not a dictionary.
public struct TrackedWindow: Equatable, Sendable {
    public let id: CGWindowID
    public var frame: CGRect

    public init(id: CGWindowID, frame: CGRect) {
        self.id = id
        self.frame = frame
    }
}

/// The cached window state model (ADR-0001 rule 4 — the snapshot a Kit actor will own for
/// instant reads). Pure value: the tracked windows in slot order plus the expectation
/// ledger of in-flight AX writes. `WindowStateReducer.reduce` is the only transition.
public struct WindowState: Equatable, Sendable {
    /// Tracked windows in insertion (slot) order.
    public var windows: [TrackedWindow]
    /// Expectation ledger: AX writes awaiting their echoing move/resize notification.
    public var pending: [PendingMove]

    public init(windows: [TrackedWindow] = [], pending: [PendingMove] = []) {
        self.windows = windows
        self.pending = pending
    }

    /// Register one `PendingMove` per emitted `FrameCommand` (ADR-0001 rule 3: FrameCommands
    /// register pending expectations). The caller (#10/#11's TilingActor) calls this when it
    /// applies commands so the resulting echoes classify `.internal`. Per the `MoveClassifier`
    /// ledger contract, a single `size→pos→size` write emits SEPARATE resized/moved echoes, so
    /// the caller passes ONE command per AX write it issues — each becomes one pending here.
    public func recording(commands: [FrameCommand], expiresAtEpoch: Double) -> WindowState {
        var next = self
        next.pending.append(contentsOf: commands.map { $0.pending(expiresAtEpoch: expiresAtEpoch) })
        return next
    }
}
