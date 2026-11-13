import SwiftUI

struct ContentView: View {
    @Binding var isAddingAccount: Bool
    @Environment(QuickAccess.self) private var quickAccess
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        AccountListView(isAddingAccount: $isAddingAccount)
            .frame(minWidth: 440, minHeight: 360)
            .onAppear {
                quickAccess.openMainWindow = { openWindow(id: "main") }
            }
    }
}
