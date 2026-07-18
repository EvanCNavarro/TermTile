import Foundation
import Testing

@Suite("MenuBarContent accessibility")
struct MenuBarContentAccessibilityTests {
    private static func repoRoot() -> URL {
        var dir = URL(filePath: #filePath).deletingLastPathComponent()
        while dir.path != "/" {
            if FileManager.default.fileExists(atPath: dir.appending(path: "Package.swift").path) {
                return dir
            }
            dir = dir.deletingLastPathComponent()
        }
        fatalError("could not locate Package.swift above \(#filePath)")
    }

    @Test("bring-forward toggle gives assistive tech Rearrange context")
    func bringForwardToggleHasContextualAccessibilityHint() {
        let menuURL = Self.repoRoot().appending(path: "Sources/TermTile/MenuBarContent.swift")
        let source = (try? String(contentsOf: menuURL, encoding: .utf8)) ?? ""
        guard let toggleStart = source.range(of: "Toggle(\"Bring app forward\""),
              let shortcutStart = source.range(of: "LabeledContent(\"Shortcut\"") else {
            Issue.record("MenuBarContent.swift must render the bring-forward toggle before Shortcut")
            return
        }

        let toggleBlock = String(source[toggleStart.lowerBound..<shortcutStart.lowerBound])
        #expect(toggleBlock.contains(
            ".accessibilityHint(\"Brings the selected target app forward after Rearrange now runs.\")"
        ))
    }

    @Test("Rearrange section surfaces failed app-focus attempts")
    func rearrangeSectionReadsForegroundWarningMessage() {
        let menuURL = Self.repoRoot().appending(path: "Sources/TermTile/MenuBarContent.swift")
        let source = (try? String(contentsOf: menuURL, encoding: .utf8)) ?? ""
        guard let sectionStart = source.range(of: "SectionCard(\"Rearrange\""),
              let dragStart = source.range(of: "SectionCard(\"Drag\"") else {
            Issue.record("MenuBarContent.swift must keep a Rearrange section before Drag")
            return
        }

        let rearrangeBlock = String(source[sectionStart.lowerBound..<dragStart.lowerBound])
        #expect(rearrangeBlock.contains("viewModel.foregroundWarningMessage"))
        #expect(rearrangeBlock.contains("exclamationmark.triangle.fill"))
    }

    @Test("Target owns the app picker; Rearrange owns command modifiers")
    func targetAndRearrangeSectionsKeepScalableGrouping() {
        let menuURL = Self.repoRoot().appending(path: "Sources/TermTile/MenuBarContent.swift")
        let source = (try? String(contentsOf: menuURL, encoding: .utf8)) ?? ""
        guard let targetStart = source.range(of: "SectionCard(\"Target\""),
              let rearrangeStart = source.range(of: "SectionCard(\"Rearrange\""),
              let dragStart = source.range(of: "SectionCard(\"Drag\"") else {
            Issue.record("MenuBarContent.swift must keep Target, Rearrange, and Drag sections in order")
            return
        }

        let targetBlock = String(source[targetStart.lowerBound..<rearrangeStart.lowerBound])
        let rearrangeBlock = String(source[rearrangeStart.lowerBound..<dragStart.lowerBound])

        #expect(targetBlock.contains("LabeledContent(\"Target app\""))
        #expect(!targetBlock.contains("LabeledContent(\"Gap\""))
        #expect(rearrangeBlock.contains("LabeledContent(\"Gap\""))
        #expect(rearrangeBlock.contains("Toggle(\"Bring app forward\""))
        #expect(rearrangeBlock.contains("LabeledContent(\"Shortcut\""))
    }

    @Test("update availability is the single overflow attention source")
    func updateAvailabilityIsSingleOverflowAttentionSource() {
        let menuURL = Self.repoRoot().appending(path: "Sources/TermTile/MenuBarContent.swift")
        let source = (try? String(contentsOf: menuURL, encoding: .utf8)) ?? ""

        #expect(source.contains("attention: updater.availability.hasAvailableUpdate"),
                "the update overflow action should derive attention from Updater availability")
        #expect(!source.contains("attention: true"),
                "overflow attention must not be hardcoded")
    }

    @Test("update overflow action carries TermTile-owned attention accessibility semantics")
    func updateOverflowActionCarriesAttentionAccessibilitySemantics() {
        let menuURL = Self.repoRoot().appending(path: "Sources/TermTile/MenuBarContent.swift")
        let source = (try? String(contentsOf: menuURL, encoding: .utf8)) ?? ""
        guard let updatesStart = source.range(of: "MenuAction(title: \"Check for Updates\""),
              let quitStart = source.range(of: "MenuAction(title: \"Quit TermTile\"") else {
            Issue.record("MenuBarContent.swift must render Check for Updates before Quit TermTile")
            return
        }

        let updateAction = String(source[updatesStart.lowerBound..<quitStart.lowerBound])
        #expect(updateAction.contains("enabled: updater.canOpenUpdateCheck"),
                "the update action should stay actionable after a passive probe finds an update")
        #expect(updateAction.contains("attention: updater.availability.hasAvailableUpdate"),
                "the update action should remain the single availability-derived attention source")
        #expect(updateAction.contains("attentionAccessibilityHint: \"Update available\""),
                "TermTile should supply update-specific semantics through MacFaceKit's generic hook")
    }
}
