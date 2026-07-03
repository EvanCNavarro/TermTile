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

            Toggle("Tiling enabled", isOn: Binding(
                get: { viewModel.isEnabled },
                set: { on in Task { await viewModel.setEnabled(on) } }))

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
            Button("Quit TermTile") { NSApplication.shared.terminate(nil) }
        }
        .padding(12)
        .frame(width: 280)
        .onAppear { viewModel.refreshTrust() }
        // MenuBarExtra(.window) keeps this view alive across opens, so `.onAppear` fires once per
        // process — a grant made later rendered a stale fix-it row. The panel becomes key on every
        // open; re-probe then (cheap, read-only).
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            viewModel.refreshTrust()
        }
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
