import SwiftUI

struct AddAccountView: View {
    var onDone: (Bool) -> Void
    @State private var selectedTab = 0

    var body: some View {
        NavigationStack {
            VStack {
                Picker("Method", selection: $selectedTab) {
                    Text("Manual").tag(0)
                    Text("Paste URI").tag(1)
                    Text("QR Image").tag(2)
                }
                .pickerStyle(.segmented)
                .padding()

                switch selectedTab {
                case 0:
                    ManualEntryView { success in
                        onDone(success)
                    }
                case 1:
                    PasteURIView { success in
                        onDone(success)
                    }
                case 2:
                    QRImageImportView { success in
                        onDone(success)
                    }
                default:
                    EmptyView()
                }
            }
            .navigationTitle("Add Account")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onDone(false)
                    }
                }
            }
        }
        .frame(minWidth: 400, minHeight: 400)
    }
}
