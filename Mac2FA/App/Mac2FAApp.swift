import SwiftUI

@main
struct Mac2FAApp: App {
    @State private var isAddingAccount = false
    @State private var isCheckingForUpdates = false

    var body: some Scene {
        // A single window: there is one list of accounts, so File > New Window wouldn't mean anything.
        Window("Mac2FA", id: "main") {
            ContentView(isAddingAccount: $isAddingAccount)
                .sheet(isPresented: $isCheckingForUpdates) {
                    UpdateCheckView()
                }
        }
        .defaultSize(width: 560, height: 620)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    isCheckingForUpdates = true
                }
                // A window shows one sheet at a time.
                .disabled(isAddingAccount)
            }
            CommandGroup(replacing: .newItem) {
                Button("New Account…") {
                    isAddingAccount = true
                }
                .keyboardShortcut("n")
                .disabled(isCheckingForUpdates)
            }
        }
    }
}
