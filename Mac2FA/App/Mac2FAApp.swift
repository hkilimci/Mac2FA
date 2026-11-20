import SwiftUI

@main
struct Mac2FAApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var quickAccess = QuickAccess.shared
    @State private var isAddingAccount = false
    @State private var isCheckingForUpdates = false
    @State private var isExportingAccounts = false
    @State private var isImportingAccounts = false

    private var isShowingSheet: Bool {
        isAddingAccount || isCheckingForUpdates || isExportingAccounts || isImportingAccounts
    }

    var body: some Scene {
        // A single window: there is one list of accounts, so File > New Window wouldn't mean anything.
        Window("Mac2FA", id: "main") {
            ContentView(
                isAddingAccount: $isAddingAccount,
                isImportingAccounts: $isImportingAccounts,
                isExportingAccounts: $isExportingAccounts,
                isShowingSheet: isShowingSheet
            )
                .environment(quickAccess)
                .sheet(isPresented: $isCheckingForUpdates) {
                    UpdateCheckView()
                }
                .sheet(isPresented: $isExportingAccounts) {
                    ExportAccountsView(lock: quickAccess.lock)
                }
                .sheet(isPresented: $isImportingAccounts, onDismiss: {
                    Task { await quickAccess.model.reload() }
                }) {
                    ImportAccountsView(lock: quickAccess.lock)
                }
        }
        .defaultSize(width: 560, height: 620)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    isCheckingForUpdates = true
                }
                .disabled(isShowingSheet)
            }
            CommandGroup(replacing: .newItem) {
                Button("New Account…") {
                    isAddingAccount = true
                }
                .keyboardShortcut("n")
                .disabled(isShowingSheet)

                Divider()

                Button("Import Accounts…") {
                    quickAccess.openMainWindow?()
                    isImportingAccounts = true
                }
                .disabled(isShowingSheet || quickAccess.lock.isLocked)

                Button("Export Accounts…") {
                    quickAccess.openMainWindow?()
                    isExportingAccounts = true
                }
                .disabled(isShowingSheet || quickAccess.lock.isLocked || quickAccess.model.accounts.isEmpty)
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
