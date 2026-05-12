import SwiftUI

@main
struct Mac2FAApp: App {
    @State private var showingUpdateCheck = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .sheet(isPresented: $showingUpdateCheck) {
                    UpdateCheckView()
                }
        }
        .windowStyle(.automatic)
        .defaultSize(width: 600, height: 500)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    showingUpdateCheck = true
                }
            }
        }
    }
}
