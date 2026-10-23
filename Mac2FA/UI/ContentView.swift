import SwiftUI

struct ContentView: View {
    @Binding var isAddingAccount: Bool

    var body: some View {
        AccountListView(isAddingAccount: $isAddingAccount)
            .frame(minWidth: 440, minHeight: 360)
    }
}
