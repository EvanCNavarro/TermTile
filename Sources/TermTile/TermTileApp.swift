import SwiftUI

@main
struct TermTileApp: App {
    var body: some Scene {
        MenuBarExtra(AppIdentity.appName) {
            Text("\(AppIdentity.appName) — skeleton")
        }
    }
}
