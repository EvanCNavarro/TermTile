import AppKit
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
    @State private var confirmingUninstall = false
    @State private var uninstallOutcome: Uninstaller.UninstallOutcome?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AppIdentity.appName).font(.headline)

            Button {
                Task { await viewModel.rearrangeNow() }
            } label: {
                Label("Rearrange now", systemImage: "rectangle.grid.2x2")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.isAccessibilityTrusted)

            Picker("Target app", selection: Binding(
                get: { viewModel.targetBundleID },
                set: { id in Task { await viewModel.setTarget(id) } })) {
                ForEach(pickerOptions) { app in
                    Text(app.name).tag(app.bundleID)
                }
            }

            Toggle("Launch at login", isOn: Binding(
                get: { viewModel.launchAtLogin },
                set: { viewModel.setLaunchAtLogin($0) }))

            if !viewModel.isAccessibilityTrusted {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Accessibility access required").font(.subheadline).bold()
                    Text("TermTile needs Accessibility permission to arrange windows.")
                        .font(.caption).foregroundStyle(.secondary)
                    Link("Open Accessibility Settings…", destination: viewModel.accessibilitySettingsURL)
                }
            }

            Divider()
            Button("Check for Updates…") { updater.checkForUpdates() }
                .disabled(!updater.canCheckForUpdates)

            // About — version + links, single-sourced from AppInfo (nothing hardcoded here).
            HStack(spacing: 8) {
                Text("v\(appInfo.version)").foregroundStyle(.secondary)
                Spacer()
                Link("GitHub", destination: appInfo.repoURL)
                Text("·").foregroundStyle(.tertiary)
                Link("License", destination: appInfo.licenseURL)
            }
            .font(.caption)

            Button("Uninstall TermTile…", role: .destructive) { confirmingUninstall = true }
            Button("Quit TermTile") { NSApplication.shared.terminate(nil) }
        }
        .padding(12)
        .frame(width: 280)
        .onAppear { viewModel.refreshTrust() }
        // Destructive — an explicit confirm so uninstall is never a one-click accident.
        .confirmationDialog("Uninstall TermTile?", isPresented: $confirmingUninstall, titleVisibility: .visible) {
            Button("Move to Trash", role: .destructive) { uninstallOutcome = viewModel.uninstall() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Moves TermTile and its data to the Trash. You'll still need to remove its "
                + "Accessibility permission in System Settings — that can't be revoked automatically.")
        }
        // Outcome + the one thing uninstall can't do (revoke the TCC grant). EVERY action exits with
        // exit(0), NOT NSApp.terminate — a graceful quit (or leaving the app running) would let
        // cfprefsd re-flush the purged prefs domain. So the terminal state after uninstall is always
        // process exit; each button does its side effect, then exits.
        .alert(uninstallTitle, isPresented: Binding(
            get: { uninstallOutcome != nil },
            set: { if !$0 { uninstallOutcome = nil } }
        ), presenting: uninstallOutcome) { outcome in
            if let url = outcome.bundleURLIfManual {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]); exit(0) }
            }
            Button("Open Accessibility Settings…") {
                NSWorkspace.shared.open(viewModel.accessibilitySettingsURL); exit(0)
            }
            Button("Quit") { exit(0) }
        } message: { outcome in
            Text(uninstallMessage(outcome))
        }
        // MenuBarExtra(.window) keeps this view alive across opens, so `.onAppear` fires once per
        // process — a grant made later rendered a stale fix-it row. The panel becomes key on every
        // open; re-probe then (cheap, read-only).
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            viewModel.refreshTrust()
        }
    }

    /// Honest title — never claims a clean removal on a partial one.
    private var uninstallTitle: String {
        (uninstallOutcome?.isClean ?? true) ? "TermTile removed" : "TermTile mostly removed"
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
