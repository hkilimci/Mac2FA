import SwiftUI

@main
struct Mac2FAApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var quickAccess = QuickAccess.shared
    @State private var isAddingAccount = false
    @State private var isCheckingForUpdates = false

    var body: some Scene {
        // A single window: there is one list of accounts, so File > New Window wouldn't mean anything.
        Window("Mac2FA", id: "main") {
            ContentView(isAddingAccount: $isAddingAccount)
                .environment(quickAccess)
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
            CommandMenu("Security") {
                if quickAccess.lock.isLocked {
                    Button("Unlock Mac2FA…") { Task { await quickAccess.unlock() } }
                } else if quickAccess.lock.requiresAuthentication {
                    Button("Lock Mac2FA") { quickAccess.lockNow() }
                        .keyboardShortcut("l", modifiers: [.command, .control])
                }
            }
        }

        Settings {
            QuickAccessSettings()
                .environment(quickAccess)
        }

        MenuBarExtra("Mac2FA", systemImage: quickAccess.lock.isLocked ? "lock.fill" : "lock.open") {
            QuickAccessMenu()
                .environment(quickAccess)
        }
        .menuBarExtraStyle(.window)
    }
}
