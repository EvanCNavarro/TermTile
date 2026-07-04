/// How a dragged window's drop reshuffles the OTHER tiled windows (#27). All three are pure
/// permutations of the window→slot assignment (see `TileEngine.reorderCommands`); the user picks one
/// in the menu. They differ meaningfully only at 3+ columns and on cross-row drags.
public enum ReorderStrategy: String, Equatable, Sendable, CaseIterable {
    /// The dragged window trades places with the one it lands on; nobody else moves. Most intuitive
    /// for a grid ("horizontal drag → horizontal displacement"); the default.
    case swap
    /// 1D remove+insert in COLUMN-MAJOR slot order — the original behaviour; a cross-column drag can
    /// ripple a window diagonally (column bottom → next column top).
    case columnShift
    /// 1D remove+insert in ROW-MAJOR slot order — a horizontal drag shifts within the row and leaves
    /// the other row in place ("the bottom row stays the bottom row").
    case rowShift

    /// The menu Picker label.
    public var displayName: String {
        switch self {
        case .swap: return "Swap"
        case .columnShift: return "Shift by column"
        case .rowShift: return "Shift by row"
        }
    }
}
