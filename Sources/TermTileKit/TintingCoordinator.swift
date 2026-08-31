import Foundation
import TermTileCore

/// What one pass decided about one pane. The record #37f will render, and the reason a session
/// was left alone is as much a result as the colour it was painted.
public struct TintDecision: Equatable, Sendable {
    public let cwd: String
    public let tty: String?
    public let state: AgentState
    public let wrote: Bool
    /// Present only when the pane could not be joined to a session.
    public let ambiguity: AmbiguityReason?
    /// Whether a previous character count existed for this session on this pass.
    ///
    /// Splits the two very different things `.unknown` means. Without it the diagnostics cannot
    /// tell the user "seen for the first time, deciding on the next pass" apart from "running, but
    /// its state is not recognised" — and those call for opposite reactions: wait, or report a
    /// missing marker (EvanCNavarro/TermTile#6).
    public let hadBaseline: Bool

    public init(cwd: String, tty: String?, state: AgentState, wrote: Bool,
                ambiguity: AmbiguityReason? = nil, hadBaseline: Bool = false) {
        self.cwd = cwd
        self.tty = tty
        self.state = state
        self.wrote = wrote
        self.ambiguity = ambiguity
        self.hadBaseline = hadBaseline
    }

    /// Why this session was left untinted, in the user's terms — or `nil` if it was painted.
    ///
    /// Ordered by what actually stopped the paint. An unresolved JOIN outranks the state: the
    /// state may well be knowable, but there was no window to put it on, and telling the user
    /// about the state would point them at the wrong problem.
    public var untintedReason: String? {
        guard !wrote else { return nil }

        if let ambiguity {
            switch ambiguity {
            case .cwdNotUnique:
                return "Several terminals share this folder, so TermTile can't tell which window this is."
            case .noCandidate:
                return "No matching terminal session — the window may have just closed."
            case .multipleCandidates:
                return "This window holds several sessions in the same folder, which can't be told apart."
            }
        }

        if state == .unknown {
            // The two meanings of `.unknown`, which call for opposite reactions.
            return hadBaseline
                ? "Running, but TermTile doesn't recognise what it's doing."
                : "Just noticed — TermTile decides on the next check."
        }

        // A known state, a resolved window, and still no paint: the write itself failed.
        return "Couldn't write to this terminal."
    }
}

/// Runs one tinting pass across the three ports, and owns the ONLY mutable state the feature has.
///
/// STATEFUL BY NECESSITY (ADR-0006 finding 9). Ready may only be reported on a MEASURED delta, so
/// the coordinator remembers each session's previous character count. Everything else in this
/// feature is a pure function or a stateless adapter; this is where the memory lives, deliberately
/// in one place.
public actor TintingCoordinator {
    private let reader: any SessionReading
    private let probe: any TTYProbing
    private let writer: any SessionTinting
    private var readyColor: TintColor

    /// Previous character count per tty, WITH the cwd it belonged to.
    ///
    /// Keyed by tty but VALIDATED by cwd, because a tty number is recycled. Evicting ttys that
    /// vanish is not enough on its own: a session that dies and is reborn on the same tty between
    /// two polls is present at both, and comparing the new session's count against the dead one's
    /// would manufacture a delta — or worse, manufacture STILLNESS and paint a working window green.
    private var baselines: [String: (cwd: String, count: Int)] = [:]

    public init(reader: any SessionReading,
                probe: any TTYProbing,
                writer: any SessionTinting,
                readyColor: TintColor = TintPalette.ready) {
        self.reader = reader
        self.probe = probe
        self.writer = writer
        self.readyColor = readyColor
    }

    /// Change the READY shade. Takes effect on the next pass; nothing is repainted eagerly,
    /// because the next pass is at most one interval away and an eager repaint would paint a
    /// session whose state may since have changed.
    public func setReadyIntensity(_ intensity: ReadyIntensity) {
        readyColor = intensity.color
    }

    /// One pass: read panes, probe ttys, join, classify, write.
    @discardableResult
    public func pass() async -> [TintDecision] {
        let panes = await reader.visiblePanes()
        let sessions = await probe.sessions()
        let outcomes = SessionJoin.resolve(panes: panes.map(\.snapshot), sessions: sessions)

        var decisions: [TintDecision] = []
        var seenThisPass: [String: (cwd: String, count: Int)] = [:]

        for (pane, outcome) in zip(panes, outcomes) {
            switch outcome {
            case .ambiguous(let reason):
                // The STATE may well be knowable here. The TARGET is not, and painting a guessed
                // window with a correctly-read state is the worst of both.
                decisions.append(TintDecision(cwd: pane.snapshot.cwd, tty: nil, state: .unknown,
                                              wrote: false, ambiguity: reason))

            case .resolved(let tty):
                // A baseline counts only if it belonged to the SAME session — same cwd on this
                // tty. Otherwise the tty was recycled and the delta would be fiction.
                let previous = baselines[tty]
                let delta: Int? = previous.map { $0.cwd == pane.snapshot.cwd
                    ? pane.characterCount - $0.count
                    : nil } ?? nil
                seenThisPass[tty] = (pane.snapshot.cwd, pane.characterCount)

                let state = AgentStateClassifier.classify(
                    StateEvidence(tail: pane.scrollbackTail,
                                  widerTail: pane.scrollbackTail,
                                  charCountDelta: delta))
                var wrote = false
                if let colour = TintPalette.color(for: state, ready: readyColor) {
                    wrote = await writer.setBackground(colour, onTTY: tty)
                }
                decisions.append(TintDecision(cwd: pane.snapshot.cwd, tty: tty,
                                              state: state, wrote: wrote,
                                              hadBaseline: delta != nil))
            }
        }

        // Wholesale replacement is the eviction: a tty absent from this pass is gone from the map,
        // so a later session landing on that number starts with no baseline rather than a stale one.
        baselines = seenThisPass
        return decisions
    }

    /// Repaint every session this coordinator has touched back to normal.
    ///
    /// For disable and for quit. A tinted window that outlives the feature is orphaned state the
    /// user cannot explain and TermTile no longer maintains.
    public func resetAll() async {
        for tty in baselines.keys.sorted() {
            await writer.setBackground(TintPalette.normal, onTTY: tty)
        }
        baselines = [:]
    }
}
