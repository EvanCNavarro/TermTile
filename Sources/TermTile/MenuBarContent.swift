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
        VStack(alignment: .leading, spacing: 16) {
            header

            section("Tiling") {
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

            section("Drag to reorder") {
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
                    noticeCard("Input Monitoring required",
                               "Reorder-on-drag needs Input Monitoring to detect when you drag a window.",
                               link: "Open Input Monitoring Settings…",
                               url: viewModel.inputMonitoringSettingsURL)
                }
            }

            section("General") {
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

            // PRIMARY ACTION — after the settings it operates on (configure, then tile). Prominent,
            // full-width, with its keyboard shortcut shown inline (menu-item convention).
            Button {
                Task { await viewModel.rearrangeNow() }
            } label: {
                HStack {
                    Label("Rearrange now", systemImage: "rectangle.grid.2x2")
                    Spacer()
                    Text(viewModel.hotKey.displayString).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!viewModel.isAccessibilityTrusted)

            footer
        }
        .padding(14)
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

    // MARK: - Sections

    /// Identity header — app icon + name + version, the RememBar-popover shape. Anchors the panel and
    /// frees the footer of the version string.
    private var header: some View {
        HStack(spacing: 11) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable().frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(AppIdentity.appName).font(.headline)
                Text("Version \(appInfo.version)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    /// A labeled settings group: a small uppercase section header over a soft rounded card holding its
    /// rows (macOS System-Settings grouping — the card is the proximity cue that makes each group read
    /// as one intentional unit). The fill is `.primary`-derived so it adapts to light/dark.
    @ViewBuilder
    private func section<Content: View>(_ title: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary).textCase(.uppercase).kerning(0.5)
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
        }
    }

    /// The utility footer — muted text actions (borderless, so they read as links, not buttons
    /// competing with the settings cards), visually separated by a divider.
    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            HStack {
                Button("Check for Updates…") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
                Spacer()
                Link("GitHub", destination: appInfo.repoURL)
                Text("·").foregroundStyle(.tertiary)
                Link("License", destination: appInfo.licenseURL)
            }
            HStack {
                Button("Uninstall…", role: .destructive) { confirmingUninstall = true }
                    .foregroundStyle(.red)
                Spacer()
                Button("Quit TermTile") { NSApplication.shared.terminate(nil) }
            }
        }
        .font(.callout)
        .buttonStyle(.borderless)
    }

    /// Accessibility permission state → a contextual notice (nothing when trusted). Honest about the
    /// moved/duplicate-bundle break AND an intentional revoke (indistinguishable via AXIsProcessTrusted).
    @ViewBuilder
    private var accessibilityNotice: some View {
        switch viewModel.accessibilityState {
        case .trusted:
            EmptyView()
        case .needsFirstGrant:
            noticeCard("Accessibility access required",
                       "TermTile needs Accessibility permission to arrange windows.")
        case .grantBroken:
            noticeCard("Accessibility access is off",
                       "If you didn't turn it off, TermTile may have moved or a duplicate copy ran. "
                       + "Remove any old TermTile entries in Accessibility settings, then re-add this one.")
        }
    }

    /// A permission notice — a tinted card (icon + title + body + deep-link), reused for Accessibility
    /// (#23) and Input Monitoring (#26). Reads as an alert, not another form row.
    private func noticeCard(_ title: String, _ body: String,
                            link: String = "Open Accessibility Settings…",
                            url: URL? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold)).foregroundStyle(.orange)
            Text(body).font(.caption).foregroundStyle(.secondary)
            Link(link, destination: url ?? viewModel.accessibilitySettingsURL).font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
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
