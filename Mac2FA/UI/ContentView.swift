import SwiftUI

struct ContentView: View {
    @Binding var isAddingAccount: Bool
    @Binding var isImportingAccounts: Bool
    @Binding var isExportingAccounts: Bool
    let isShowingSheet: Bool

    @Environment(QuickAccess.self) private var quickAccess
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        AccountListView(
            isAddingAccount: $isAddingAccount,
            isImportingAccounts: $isImportingAccounts,
            isExportingAccounts: $isExportingAccounts,
            isShowingSheet: isShowingSheet
        )
            .frame(minWidth: 440, minHeight: 360)
            .onAppear {
                quickAccess.openMainWindow = { openWindow(id: "main") }
            }
    }
}
