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

    var body: some View {
        // The SHARED identity card (icon · name · version · made-with · ··· · GitHub/License · separator);
        // TermTile supplies the content below the separator — its settings + hero.
        AppIdentityCard(
            name: AppIdentity.appName,
            version: appInfo.displayVersion,
            subtitle: "A minimalist menu-bar tiler that keeps your terminal windows in a tidy, even grid.",
            actions: overflowActions,
            links: identityLinks
        ) {
            SectionCard("Target") {
                LabeledContent("Target app") {
                    Picker("", selection: Binding(
                        get: { viewModel.targetBundleID },
                        set: { id in Task { await viewModel.setTarget(id) } })) {
                        ForEach(pickerOptions) { app in Text(app.name).tag(app.bundleID) }
                    }
                    .labelsHidden()
                }
            }

            SectionCard("Rearrange") {
                // Gap (#17a): setGap is synchronous. Step 4 lands on the 8-pt default.
                LabeledContent("Gap") {
                    Stepper("\(Int(viewModel.gap)) pt", value: Binding(
                        get: { viewModel.gap }, set: { viewModel.setGap($0) }),
                        in: MenuBarViewModel.gapRange, step: 4)
                }
                Toggle("Bring app forward", isOn: Binding(
                    get: { viewModel.bringToFrontOnRearrange },
                    set: { viewModel.setBringToFrontOnRearrange($0) }))
                .accessibilityHint("Brings the selected target app forward after Rearrange now runs.")
                if let message = viewModel.foregroundWarningMessage {
                    Label {
                        Text(message)
                            .font(Tokens.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .foregroundStyle(Tokens.warning)
                    .accessibilityLabel("App focus")
                    .accessibilityValue(message)
                }
                // Global-hotkey recorder (#25b): click the field, press a combo (needs ⌥ or ⌃).
                // The "⚠" marks a persisted combo that couldn't register (taken by another app).
                LabeledContent("Shortcut") {
                    HotKeyRecorder(current: viewModel.hotKey, registered: viewModel.hotKeyRegistered) {
                        viewModel.setHotKey($0)
                    }
                    .frame(width: 120, height: 22)
                }
            }

            SectionCard("Drag") {
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
                               message: "Reorder-on-drag needs Input Monitoring to detect when you drag a window. "
                               + "If it already looks enabled, repair the stale entry and approve TermTile again.",
                               linkLabel: "Open Input Monitoring Settings…",
                               url: viewModel.inputMonitoringSettingsURL)
                    repairButton("Repair Input Monitoring", systemImage: "arrow.clockwise") {
                        viewModel.repairInputMonitoringPermission()
                        NSWorkspace.shared.open(viewModel.inputMonitoringSettingsURL)
                    }
                }
            }

            SectionCard("General") {
                Toggle("Launch at login", isOn: Binding(
                    get: { viewModel.launchAtLogin },
                    set: { viewModel.setLaunchAtLogin($0) }))
            }

            accessibilityNotice   // the blocker, right above the action it gates

            // PRIMARY ACTION — after the settings it operates on (configure, then tile). The shared
            // branded hero; shortcut shown inline; disabled until Accessibility is granted.
            PrimaryButton("Rearrange now", systemImage: "rectangle.grid.2x2",
                          trailing: viewModel.hotKey.displayString,
                          enabled: viewModel.isAccessibilityTrusted) {
                Task { await viewModel.rearrangeNow() }
            }
        }
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

    /// Package-safe identity links. MacFaceKit's `.github` convenience uses a SwiftPM resource bundle
    /// for the brand mark; signed `.app` bundles cannot carry that generated bundle at the app root.
    private var identityLinks: [IdentityLink] {
        [
            IdentityLink.link("GitHub", AppIdentity.repoURL, systemImage: "globe"),
            IdentityLink.license(AppIdentity.licenseURL)
        ]
    }

    /// The `···` overflow actions fed to the identity card. Uninstall defers to the next tick (the
    /// popover closes first — the menu-bar-dialog wonky-window fix).
    private var overflowActions: [MenuAction] {
        [
            MenuAction(title: "Check for Updates", systemImage: "arrow.triangle.2.circlepath",
                       enabled: updater.canCheckForUpdates,
                       attention: updater.availability.hasAvailableUpdate) { updater.checkForUpdates() },
            MenuAction(title: "Quit TermTile", systemImage: "power") { NSApplication.shared.terminate(nil) },
            MenuAction(title: "Uninstall TermTile…", systemImage: "trash", destructive: true) {
                DispatchQueue.main.async { runUninstallFlow() }
            }
        ]
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
                       message: "TermTile needs Accessibility permission to arrange windows. "
                       + "If it already looks enabled, repair the stale entry and approve TermTile again.",
                       linkLabel: "Open Accessibility Settings…", url: viewModel.accessibilitySettingsURL)
            repairAccessibilityButton
        case .grantBroken:
            NoticeCard(title: "Accessibility access is off",
                       message: "If it already looks enabled, macOS is holding a stale grant from an older copy. "
                       + "Repair it, then approve TermTile again.",
                       linkLabel: "Open Accessibility Settings…", url: viewModel.accessibilitySettingsURL)
            repairAccessibilityButton
        }
    }

    private var repairAccessibilityButton: some View {
        repairButton("Repair Accessibility", systemImage: "arrow.clockwise") {
            viewModel.repairAccessibilityPermission()
            NSWorkspace.shared.open(viewModel.accessibilitySettingsURL)
        }
    }

    private func repairButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    /// The uninstall confirm + outcome flow, run as imperative `NSAlert`s in their OWN windows — NOT
    /// SwiftUI modals anchored to the menu-bar popover (which auto-dismisses on focus loss, orphaning
    /// the dialog and tangling it with the panel). Each modal is its own window, so nothing fights the
    /// popover. Confirmed removal always ends in `exit(0)` (a graceful quit lets cfprefsd re-flush the
    /// purged prefs — #22b), so each outcome button does its side effect, then exits.
    private func runUninstallFlow() {
        NSApplication.shared.activate()   // bring the alert frontmost (accessory app)

        let confirm = NSAlert()
        confirm.messageText = "Uninstall TermTile?"
        confirm.informativeText = "Moves TermTile and its data to the Trash, deregisters launch at login, "
            + "and resets TermTile's Accessibility and Input Monitoring entries."
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
        if !outcome.failedPermissionRepairReports.isEmpty {
            done.addButton(withTitle: "Open Privacy Settings…")
            let privacyURL = URL(string: "x-apple.systempreferences:com.apple.preference.security")!
            actions.append { NSWorkspace.shared.open(privacyURL) }
        }
        done.addButton(withTitle: "Quit")
        actions.append {}
        let index = done.runModal().rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        if actions.indices.contains(index) { actions[index]() }
        exit(0)
    }

    /// Compose the post-uninstall message from the outcome's structured facts (presentation only —
    /// the facts live on `UninstallOutcome`). Honest about partial removal and privacy-reset
    /// failures without duplicating TCC service mapping in the UI.
    private func uninstallMessage(_ o: Uninstaller.UninstallOutcome) -> String {
        var parts = [o.isClean
            ? "TermTile and its data were moved to the Trash."
            : "Uninstall is incomplete; some parts need a hand:"]
        if !o.loginItem.isOK { parts.append("• Launch at login could not be deregistered.") }
        if !o.failedData.isEmpty { parts.append("• \(o.failedData.count) item(s) couldn't be removed.") }
        if o.bundleURLIfManual != nil { parts.append("• Drag TermTile.app to the Trash yourself.") }
        if o.permissionRepairSucceeded {
            parts.append("TermTile's Accessibility and Input Monitoring entries were reset.")
        } else if !o.permissionRepairAttempted {
            parts.append("TermTile's privacy entries were not changed in this build context.")
        } else {
            let labels = o.failedPermissionRepairReports.map(\.scope.label).joined(separator: ", ")
            parts.append("• Privacy reset failed for: \(labels). Remove TermTile manually in "
                + "System Settings → Privacy & Security.")
        }
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
