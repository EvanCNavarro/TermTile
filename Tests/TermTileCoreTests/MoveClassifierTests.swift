import CoreGraphics
import Testing
@testable import TermTileCore

/// Self-move tagging (task #6): the classifier must tag the tiler's own AX-write echoes
/// `.internal` (ignore) and genuine user drags `.external` (act). Red-first oracle: the
/// `.internal`-expecting cases fail when the match branch is inverted (see invert-check).
@Suite("MoveClassifier")
struct MoveClassifierTests {
    static let win: CGWindowID = 4242
    static let other: CGWindowID = 9999
    static let now = 1_000.0
    static let frame = CGRect(x: 200, y: 200, width: 800, height: 600)
    static let eps: CGFloat = 1.0

    /// A live (non-expired) pending move: deadline strictly after `now`.
    static func live(_ id: CGWindowID, _ f: CGRect) -> PendingMove {
        PendingMove(windowID: id, expectedFrame: f, expiresAtEpoch: now + 5)
    }

    @Test("our own write echoing the expected frame → internal")
    func matchInternal() {
        let origin = MoveClassifier.classify(
            windowID: Self.win, observedFrame: Self.frame, nowEpoch: Self.now,
            pending: [Self.live(Self.win, Self.frame)], epsilon: Self.eps)
        #expect(origin == .internal)
    }

    @Test("no pending at all → external (user drag)")
    func emptyLedgerExternal() {
        let origin = MoveClassifier.classify(
            windowID: Self.win, observedFrame: Self.frame, nowEpoch: Self.now,
            pending: [], epsilon: Self.eps)
        #expect(origin == .external)
    }

    @Test("window ended somewhere we did not ask (beyond epsilon) → external")
    func mismatchExternal() {
        let landedElsewhere = CGRect(x: 340, y: 200, width: 800, height: 600)
        let origin = MoveClassifier.classify(
            windowID: Self.win, observedFrame: landedElsewhere, nowEpoch: Self.now,
            pending: [Self.live(Self.win, Self.frame)], epsilon: Self.eps)
        #expect(origin == .external)
    }

    @Test("a matching but EXPIRED expectation must not mask a later real drag → external")
    func expiredExternal() {
        let stale = PendingMove(windowID: Self.win, expectedFrame: Self.frame,
                                expiresAtEpoch: Self.now - 1)  // deadline already passed
        let origin = MoveClassifier.classify(
            windowID: Self.win, observedFrame: Self.frame, nowEpoch: Self.now,
            pending: [stale], epsilon: Self.eps)
        #expect(origin == .external)
    }

    @Test("deadline exactly equal to now still counts as live (inclusive) → internal")
    func deadlineInclusiveInternal() {
        let boundary = PendingMove(windowID: Self.win, expectedFrame: Self.frame,
                                   expiresAtEpoch: Self.now)  // expiresAtEpoch == nowEpoch
        let origin = MoveClassifier.classify(
            windowID: Self.win, observedFrame: Self.frame, nowEpoch: Self.now,
            pending: [boundary], epsilon: Self.eps)
        #expect(origin == .internal)
    }

    @Test("a pending for a DIFFERENT window that matches the frame → external (id-scoped)")
    func wrongWindowExternal() {
        let origin = MoveClassifier.classify(
            windowID: Self.win, observedFrame: Self.frame, nowEpoch: Self.now,
            pending: [Self.live(Self.other, Self.frame)], epsilon: Self.eps)
        #expect(origin == .external)
    }

    // Ledger order must not matter: the matching pending is found regardless of position.
    @Test("multiple pending, exactly one matches → internal", arguments: [0, 1, 2])
    func multiplePendingInternal(matchIndex: Int) {
        var ledger = [
            Self.live(Self.other, CGRect(x: 0, y: 0, width: 10, height: 10)),
            Self.live(Self.win, CGRect(x: 900, y: 900, width: 400, height: 300)),
            Self.live(Self.other, Self.frame),
        ]
        ledger[matchIndex] = Self.live(Self.win, Self.frame)  // the one true match
        let origin = MoveClassifier.classify(
            windowID: Self.win, observedFrame: Self.frame, nowEpoch: Self.now,
            pending: ledger, epsilon: Self.eps)
        #expect(origin == .internal)
    }

    @Test("per-component drift of exactly epsilon still matches (inclusive) → internal")
    func epsilonBoundaryInternal() {
        let drifted = CGRect(x: 201, y: 200, width: 800, height: 600)  // +1 == epsilon
        let origin = MoveClassifier.classify(
            windowID: Self.win, observedFrame: drifted, nowEpoch: Self.now,
            pending: [Self.live(Self.win, Self.frame)], epsilon: Self.eps)
        #expect(origin == .internal)
    }

    // B2 (audit): a size→pos→size batch fires a SEPARATE resized echo carrying the
    // intermediate (newSize, oldPos) frame. Against ONLY the final-frame expectation it
    // reads external — the exact feedback-loop failure. Documents WHY the caller must
    // record a per-write expectation.
    @Test("intermediate resized echo vs only the final-frame expectation → external (failure mode)")
    func intermediateVsFinalOnlyExternal() {
        let oldPos = Self.frame.origin
        let newSize = CGSize(width: 500, height: 400)
        let finalFrame = CGRect(origin: CGPoint(x: 400, y: 350), size: newSize)
        let intermediate = CGRect(origin: oldPos, size: newSize)  // resized, not yet moved
        let origin = MoveClassifier.classify(
            windowID: Self.win, observedFrame: intermediate, nowEpoch: Self.now,
            pending: [Self.live(Self.win, finalFrame)], epsilon: Self.eps)
        #expect(origin == .external)
    }

    // B2 fix: recording ONE pending per AX write (intermediate AND final) makes both
    // echoes classify internal.
    @Test("intermediate resized echo vs per-write ledger (intermediate + final) → internal (fix)")
    func intermediateVsPerWriteLedgerInternal() {
        let oldPos = Self.frame.origin
        let newSize = CGSize(width: 500, height: 400)
        let intermediate = CGRect(origin: oldPos, size: newSize)
        let finalFrame = CGRect(origin: CGPoint(x: 400, y: 350), size: newSize)
        let ledger = [Self.live(Self.win, intermediate), Self.live(Self.win, finalFrame)]
        let origin = MoveClassifier.classify(
            windowID: Self.win, observedFrame: intermediate, nowEpoch: Self.now,
            pending: ledger, epsilon: Self.eps)
        #expect(origin == .internal)
    }

    // SF7 (audit): two pendings for the SAME window, one expired + one live, both frame-match.
    @Test("same-window pendings — one expired one live, observed matches → internal (live wins)")
    func sameWindowLiveWinsInternal() {
        let expired = PendingMove(windowID: Self.win, expectedFrame: Self.frame,
                                  expiresAtEpoch: Self.now - 10)
        let ledger = [expired, Self.live(Self.win, Self.frame)]
        let origin = MoveClassifier.classify(
            windowID: Self.win, observedFrame: Self.frame, nowEpoch: Self.now,
            pending: ledger, epsilon: Self.eps)
        #expect(origin == .internal)
    }

    // SF7 (audit): observed matches ONLY an expired same-window pending → external.
    @Test("same-window match exists but only on an expired pending → external")
    func sameWindowOnlyExpiredExternal() {
        let expired = PendingMove(windowID: Self.win, expectedFrame: Self.frame,
                                  expiresAtEpoch: Self.now - 10)
        let liveElsewhere = Self.live(Self.win, CGRect(x: 900, y: 900, width: 400, height: 300))
        let origin = MoveClassifier.classify(
            windowID: Self.win, observedFrame: Self.frame, nowEpoch: Self.now,
            pending: [expired, liveElsewhere], epsilon: Self.eps)
        #expect(origin == .external)
    }
}
