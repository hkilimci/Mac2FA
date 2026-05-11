import SwiftUI

struct AccountListView: View {
    @State private var accounts: [OTPAccount] = []
    @State private var searchText: String = ""
    @State private var showingAddSheet = false
    @State private var timer: Timer? = nil

    var filteredAccounts: [OTPAccount] {
        if searchText.isEmpty { return accounts }
        return accounts.filter {
            $0.issuer.localizedCaseInsensitiveContains(searchText) ||
            $0.label.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredAccounts) { account in
                    AccountRowView(account: account)
                }
                .onDelete(perform: deleteAccount)
            }
            .searchable(text: $searchText, placement: .toolbar)
            .navigationTitle("Mac2FA")
        .toolbar {
            ToolbarItem {
                Button(action: { showingAddSheet = true }) {
                    Label("Add Account", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddAccountView { _ in
                showingAddSheet = false
                Task { await loadAccounts() }
            }
        }
        .task {
            await loadAccounts()
            startTimer()
        }
        .onDisappear {
            timer?.invalidate()
        }
        }
    }

    private func loadAccounts() async {
        accounts = await AccountStore.shared.getAllAccounts()
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                accounts = await AccountStore.shared.getAllAccounts()
            }
        }
    }

    private func deleteAccount(at offsets: IndexSet) {
        for index in offsets {
            let account = filteredAccounts[index]
            Task {
                try? await AccountStore.shared.deleteAccount(id: account.id)
                await loadAccounts()
            }
        }
    }
}
