import AppKit
import SwiftUI
import TermTileCore

/// Keeps the menu panel's WINDOW the height of its content, undoing `MenuBarExtra(.window)`'s
/// high-water-mark behaviour (EvanCNavarro/TermTile#44).
///
/// **The defect, measured 2026-09-24 on the signed build** by driving the Session-tint toggle, which
/// changes the panel's content height without changing anything else:
///
///     tint ON   window=280x823  content span=762  bands 30 / 31
///     tint OFF  window=280x823  content span=682  bands 70 / 70
///
/// The content lost 80 pt, the window kept 823, and the difference showed as transparent bands above
/// and below. It survived closing and reopening the panel. On the report that prompted this the gap
/// was 125 pt each side; a freshly launched app sizes correctly, which is why it looks fine until the
/// panel has once seen a taller state.
///
/// **Why no layout modifier can fix it.** The extra height is OUTSIDE the SwiftUI view: the bands
/// measure `alpha 0` — transparent window, not window material behind a too-small background. SwiftUI
/// is never offered the space, so 0.3.1's `maxHeight: .infinity` frame had no effect. Only the WINDOW
/// can give it back.
///
/// **Why the height has to come from SwiftUI.** 0.3.2 asked AppKit (`contentView.fittingSize`) and
/// was INERT for a reason its own guard hid: every view in the panel's tree, `MenuBarExtraHostingView`
/// included, reports `fittingSize == .zero` and `intrinsicContentSize == (-1, -1)` — measured by
/// walking the live tree — so `guard fitting.height > 1` returned early on every open. A `.background`
/// is offered the size of the view it decorates, so the `GeometryReader` below reads the content's
/// natural height. That works even in the bug state, because the symptom is content being CENTRED in
/// an oversized window rather than stretched to fill it.
///
/// **Why it listens to two things.** Content can shrink while the panel is OPEN — toggling Session
/// tint off drops its diagnostics rows — so a resize hung off `didBecomeKey` alone would miss it; and
/// the window is only reachable from that notification, so the observer is still needed to find it.
///
/// The decision itself is `PanelSizing.shrinkTarget`, which is pure and tested: this only ever
/// SHRINKS, so it cannot fight SwiftUI's sizing on the way up, and an unmeasured height is ignored
/// rather than treated as "resize to nothing".
struct PanelHeightSync: ViewModifier {
    @State private var measuredContentHeight: Double = 0
    @State private var panelWindow: NSWindow?

    func body(content: Content) -> some View {
        content
            .background(GeometryReader { proxy in
                Color.clear
                    .onAppear { measuredContentHeight = proxy.size.height }
                    .onChange(of: proxy.size.height) { _, height in measuredContentHeight = height }
            })
            .onChange(of: measuredContentHeight) { _, _ in shrinkToFitContent() }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
                panelWindow = note.object as? NSWindow
                shrinkToFitContent()
            }
    }

    @MainActor
    private func shrinkToFitContent() {
        guard let window = panelWindow,
              let target = PanelSizing.shrinkTarget(currentHeight: window.frame.height,
                                                    measuredContentHeight: measuredContentHeight)
        else { return }
        window.setContentSize(NSSize(width: window.frame.width, height: target))
    }
}

extension View {
    /// Applies `PanelHeightSync` — see that type for why the menu panel needs it.
    func syncsPanelHeightToContent() -> some View { modifier(PanelHeightSync()) }
}
