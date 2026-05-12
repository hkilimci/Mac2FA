import SwiftUI

struct AccountListView: View {
    @State private var accounts: [OTPAccount] = []
    @State private var searchText: String = ""
    @State private var showingAddSheet = false
    @State private var timer: Timer? = nil
    @State private var accountPendingDeletion: OTPAccount?

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
                        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .contextMenu {
                            Button(role: .destructive) {
                                accountPendingDeletion = account
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
                .onDelete(perform: deleteAccount)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
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
        .confirmationDialog(
            confirmationTitle,
            isPresented: Binding(
                get: { accountPendingDeletion != nil },
                set: { if !$0 { accountPendingDeletion = nil } }
            ),
            presenting: accountPendingDeletion
        ) { account in
            Button("Delete", role: .destructive) {
                confirmDelete(account)
            }
            Button("Cancel", role: .cancel) {
                accountPendingDeletion = nil
            }
        } message: { account in
            Text("This will permanently remove \(displayName(for: account)) and its secret from the keychain.")
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

    private var confirmationTitle: String {
        if let account = accountPendingDeletion {
            return "Delete \(displayName(for: account))?"
        }
        return "Delete account?"
    }

    private func displayName(for account: OTPAccount) -> String {
        if !account.issuer.isEmpty && !account.label.isEmpty {
            return "\(account.issuer) (\(account.label))"
        }
        return account.issuer.isEmpty ? account.label : account.issuer
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

    private func confirmDelete(_ account: OTPAccount) {
        accountPendingDeletion = nil
        Task {
            try? await AccountStore.shared.deleteAccount(id: account.id)
            await loadAccounts()
        }
    }
}
