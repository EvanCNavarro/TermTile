import AppKit
import MacFaceKit
import SwiftUI
import TermTileCore
import TermTileKit

/// The menu-bar popover's content — a THIN renderer over `MenuBarViewModel` (ADR-0001: the view
/// holds no logic). Every control reads observable state and routes its change back through a VM
/// method; the async toggle/picker actions are dispatched in a `Task` so the UI never blocks on an
/// AX write. The button→VM bindings here are the one hop the beat's live PROVE cannot exercise
/// without clicking (verified by code review; see docs/verification/task12c-menubar-shell.md).
struct MenuBarContent: View {
    let viewModel: MenuBarViewModel
    let updater: Updater
    let appInfo: AppInfo
    @State private var showActions = false

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.gap) {
            AppHeader(name: AppIdentity.appName,
                      version: "\(appInfo.version) (\(appInfo.build))") { overflowMenu }
            links
            Divider()   // separates identity/meta (above) from the settings + action (below)

            SectionCard("Tiling") {
                LabeledContent("Target app") {
                    Picker("", selection: Binding(
                        get: { viewModel.targetBundleID },
                        set: { id in Task { await viewModel.setTarget(id) } })) {
                        ForEach(pickerOptions) { app in Text(app.name).tag(app.bundleID) }
                    }
                    .labelsHidden()
                }
                // Gap (#17a): setGap is synchronous. Step 4 lands on the 8-pt default.
                LabeledContent("Gap") {
                    Stepper("\(Int(viewModel.gap)) pt", value: Binding(
                        get: { viewModel.gap }, set: { viewModel.setGap($0) }),
                        in: MenuBarViewModel.gapRange, step: 4)
                }
            }

            SectionCard("Drag to reorder") {
                Toggle("Reorder windows on drag", isOn: Binding(
                    get: { viewModel.reorderOnDrag },
                    set: { viewModel.setReorderOnDrag($0) }))
                // How a drag reshuffles the others (#27) — only while reorder-on-drag is on.
                if viewModel.reorderOnDrag {
                    LabeledContent("When dragged") {
                        Picker("", selection: Binding(
                            get: { viewModel.reorderStrategy },
                            set: { viewModel.setReorderStrategy($0) })) {
                            ForEach(ReorderStrategy.allCases, id: \.self) { s in
                                Text(s.displayName).tag(s)
                            }
                        }
                        .labelsHidden()
                    }
                }
                if viewModel.reorderNeedsInputMonitoring {
                    NoticeCard(title: "Input Monitoring required",
                               message: "Reorder-on-drag needs Input Monitoring to detect when you drag a window.",
                               linkLabel: "Open Input Monitoring Settings…",
                               url: viewModel.inputMonitoringSettingsURL)
                }
            }

            SectionCard("General") {
                // Global-hotkey recorder (#25b): click the field, press a combo (needs ⌥ or ⌃).
                // The "⚠" marks a persisted combo that couldn't register (taken by another app).
                LabeledContent("Shortcut") {
                    HotKeyRecorder(current: viewModel.hotKey, registered: viewModel.hotKeyRegistered) {
                        viewModel.setHotKey($0)
                    }
                    .frame(width: 120, height: 22)
                }
                Toggle("Launch at login", isOn: Binding(
                    get: { viewModel.launchAtLogin },
                    set: { viewModel.setLaunchAtLogin($0) }))
            }

            accessibilityNotice   // the blocker, right above the action it gates

            // PRIMARY ACTION — after the settings it operates on (configure, then tile). Taller than a
            // standard button (~1.5×) so it clearly reads as the hero; shortcut shown inline.
            Button {
                Task { await viewModel.rearrangeNow() }
            } label: {
                HStack {
                    Label("Rearrange now", systemImage: "rectangle.grid.2x2")
                    Spacer()
                    Text(viewModel.hotKey.displayString).foregroundStyle(Tokens.muted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Tokens.micro + 2)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!viewModel.isAccessibilityTrusted)
        }
        .padding(Tokens.pad)
        .frame(width: 280)
        .background(Tokens.panel)   // fixed-dark brand surface (shared with RememBar)
        .onAppear { viewModel.refreshTrust() }
        // MenuBarExtra(.window) keeps this view alive across opens, so `.onAppear` fires once per
        // process — a grant made later rendered a stale fix-it row. The panel becomes key on every
        // open; re-probe then (cheap, read-only).
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            viewModel.refreshTrust()
        }
    }

    // MARK: - Composition

    /// The outbound links as outlined LinkButtons (RememBar's "Learn more" treatment) — the boxed style
    /// is for clickable LINKS, distinct from the plain `···` menu items.
    private var links: some View {
        HStack(spacing: Tokens.micro + 2) {
            LinkButton("GitHub", url: appInfo.repoURL, image: Brand.github)
            LinkButton("License", url: appInfo.licenseURL, systemImage: "doc.text")
        }
    }

    /// The `···` overflow — an `IconButton` (the shared icon family; owns its own hover, lifts while
    /// `active`) opening RememBar's CUSTOM dark dropdown: a popover of plain `MenuRow`s on `Tokens.field`.
    private var overflowMenu: some View {
        IconButton(systemImage: "ellipsis", active: showActions) { showActions.toggle() }
        .popover(isPresented: $showActions, arrowEdge: .bottom) {
            VStack(spacing: 1) {
                MenuRow(title: "Check for Updates", systemImage: "arrow.triangle.2.circlepath",
                        enabled: updater.canCheckForUpdates) { showActions = false; updater.checkForUpdates() }
                MenuRow(title: "Quit TermTile", systemImage: "power") { NSApplication.shared.terminate(nil) }
                MenuRow(title: "Uninstall TermTile…", systemImage: "trash", destructive: true) {
                    showActions = false
                    // Close the popover FIRST, then run the modal on the next tick — a SwiftUI dialog
                    // anchored to the menu-bar popover fights its auto-dismiss (the wonky-window bug).
                    DispatchQueue.main.async { runUninstallFlow() }
                }
            }
            .padding(6)
            .frame(width: 210)
            .background(Tokens.field)   // RememBar's dropdown bg is darker than the panel (#0e0f11)
        }
    }

    /// Accessibility permission state → a contextual `NoticeCard` (nothing when trusted). Honest about
    /// the moved/duplicate-bundle break AND an intentional revoke (indistinguishable via AXIsProcessTrusted).
    @ViewBuilder
    private var accessibilityNotice: some View {
        switch viewModel.accessibilityState {
        case .trusted:
            EmptyView()
        case .needsFirstGrant:
            NoticeCard(title: "Accessibility access required",
                       message: "TermTile needs Accessibility permission to arrange windows.",
                       linkLabel: "Open Accessibility Settings…", url: viewModel.accessibilitySettingsURL)
        case .grantBroken:
            NoticeCard(title: "Accessibility access is off",
                       message: "If you didn't turn it off, TermTile may have moved or a duplicate copy ran. "
                       + "Remove any old TermTile entries in Accessibility settings, then re-add this one.",
                       linkLabel: "Open Accessibility Settings…", url: viewModel.accessibilitySettingsURL)
        }
    }

    /// The uninstall confirm + outcome flow, run as imperative `NSAlert`s in their OWN windows — NOT
    /// SwiftUI modals anchored to the menu-bar popover (which auto-dismisses on focus loss, orphaning
    /// the dialog and tangling it with the panel). Each modal is its own window, so nothing fights the
    /// popover. Confirmed removal always ends in `exit(0)` (a graceful quit lets cfprefsd re-flush the
    /// purged prefs — #22b), so each outcome button does its side effect, then exits.
    private func runUninstallFlow() {
        NSApplication.shared.activate(ignoringOtherApps: true)   // bring the alert frontmost (accessory app)

        let confirm = NSAlert()
        confirm.messageText = "Uninstall TermTile?"
        confirm.informativeText = "Moves TermTile and its data to the Trash. You'll still need to remove "
            + "its Accessibility permission in System Settings — that can't be revoked automatically."
        confirm.alertStyle = .warning
        confirm.addButton(withTitle: "Move to Trash")
        confirm.addButton(withTitle: "Cancel")
        guard confirm.runModal() == .alertFirstButtonReturn else { return }   // Cancel → done, panel intact

        // nil = no armed uninstaller (gallery/selftest) → safe no-op, no outcome, no exit.
        guard let outcome = viewModel.uninstall() else { return }
        let done = NSAlert()
        done.messageText = outcome.isClean ? "TermTile removed" : "TermTile mostly removed"
        done.informativeText = uninstallMessage(outcome)
        done.alertStyle = .informational
        var actions: [() -> Void] = []
        if let url = outcome.bundleURLIfManual {
            done.addButton(withTitle: "Show in Finder")
            actions.append { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }
        done.addButton(withTitle: "Open Accessibility Settings…")
        actions.append { NSWorkspace.shared.open(viewModel.accessibilitySettingsURL) }
        done.addButton(withTitle: "Quit")
        actions.append {}
        let index = done.runModal().rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        if actions.indices.contains(index) { actions[index]() }
        exit(0)
    }

    /// Compose the post-uninstall message from the outcome's structured facts (presentation only —
    /// the facts live on `UninstallOutcome`). Honest about partial removal; always ends with the
    /// Accessibility-grant reminder (the one thing uninstall can't do).
    private func uninstallMessage(_ o: Uninstaller.UninstallOutcome) -> String {
        var parts = [o.isClean
            ? "TermTile and its data were moved to the Trash."
            : "TermTile was removed, but some parts need a hand:"]
        if !o.failedData.isEmpty { parts.append("• \(o.failedData.count) item(s) couldn't be removed.") }
        if o.bundleURLIfManual != nil { parts.append("• Drag TermTile.app to the Trash yourself.") }
        parts.append("Last step: remove TermTile from System Settings → Privacy & Security → "
            + "Accessibility. It can't be revoked automatically.")
        return parts.joined(separator: "\n\n")
    }

    /// The persisted target is always selectable even when it isn't currently running (so the
    /// `Picker` has a matching tag → no "selection has no tag" runtime warning). Its label falls
    /// back to the bundle id until the app is running and the provider supplies a real name.
    private var pickerOptions: [TargetApp] {
        if viewModel.availableApps.contains(where: { $0.bundleID == viewModel.targetBundleID }) {
            return viewModel.availableApps
        }
        return [TargetApp(bundleID: viewModel.targetBundleID, name: viewModel.targetBundleID)]
            + viewModel.availableApps
    }
}
