import SwiftUI

struct AccountListView: View {
    @Binding var isAddingAccount: Bool

    @State private var model = AccountsModel()
    @State private var searchText = ""
    @State private var selection: OTPAccount.ID?
    @State private var accountPendingDeletion: OTPAccount?

    private var visibleAccounts: [OTPAccount] {
        model.filteredAccounts(matching: searchText)
    }

    var body: some View {
        NavigationStack {
            List(selection: $selection) {
                ForEach(visibleAccounts) { account in
                    AccountRowView(account: account, model: model)
                }
            }
            .listStyle(.inset)
            .contextMenu(forSelectionType: OTPAccount.ID.self) { ids in
                if let account = firstAccount(in: ids) {
                    Button("Copy Code") {
                        model.copyCode(for: account)
                    }
                    Divider()
                    Button("Delete", role: .destructive) {
                        accountPendingDeletion = account
                    }
                }
            } primaryAction: { ids in
                // Double-click or Return copies, like opening an item elsewhere on macOS.
                if let account = firstAccount(in: ids) {
                    model.copyCode(for: account)
                }
            }
            .onCopyCommand {
                guard let account = selectedAccount else { return [] }
                return model.itemProvidersForCopy(of: account)
            }
            .onDeleteCommand {
                accountPendingDeletion = selectedAccount
            }
            .overlay {
                emptyState
            }
            .searchable(text: $searchText, placement: .toolbar, prompt: "Search")
            .navigationTitle("Mac2FA")
            .navigationSubtitle(subtitle)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isAddingAccount = true
                    } label: {
                        Label("Add Account", systemImage: "plus")
                    }
                    .help("Add Account")
                }
            }
        }
        .sheet(isPresented: $isAddingAccount, onDismiss: {
            Task { await model.reload() }
        }) {
            AddAccountView()
        }
        .confirmationDialog(
            deletionTitle,
            isPresented: Binding(
                get: { accountPendingDeletion != nil },
                set: { if !$0 { accountPendingDeletion = nil } }
            ),
            presenting: accountPendingDeletion
        ) { account in
            Button("Delete", role: .destructive) {
                delete(account)
            }
            Button("Cancel", role: .cancel) {
                accountPendingDeletion = nil
            }
        } message: { _ in
            Text("Its secret is removed from your keychain. This doesn't turn off two-factor authentication for the service, so make sure you can still sign in another way.")
        }
        .task {
            await model.reload()
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if model.hasLoaded && model.accounts.isEmpty {
            ContentUnavailableView {
                Label("No Accounts", systemImage: "lock.shield")
            } description: {
                Text("Add an account with its setup key, an otpauth link, or a QR code exported from Google Authenticator.")
            } actions: {
                Button("Add Account…") {
                    isAddingAccount = true
                }
            }
        } else if visibleAccounts.isEmpty && !searchText.isEmpty {
            ContentUnavailableView.search(text: searchText)
        }
    }

    private var subtitle: String {
        guard model.hasLoaded else { return "" }
        return model.accounts.count == 1 ? "1 account" : "\(model.accounts.count) accounts"
    }

    private var selectedAccount: OTPAccount? {
        model.accounts.first { $0.id == selection }
    }

    private var deletionTitle: String {
        guard let account = accountPendingDeletion else { return "Delete account?" }
        return "Delete “\(displayName(for: account))”?"
    }

    private func firstAccount(in ids: Set<OTPAccount.ID>) -> OTPAccount? {
        guard let id = ids.first else { return nil }
        return model.accounts.first { $0.id == id }
    }

    private func displayName(for account: OTPAccount) -> String {
        if !account.issuer.isEmpty && !account.label.isEmpty {
            return "\(account.issuer) (\(account.label))"
        }
        return account.issuer.isEmpty ? account.label : account.issuer
    }

    private func delete(_ account: OTPAccount) {
        accountPendingDeletion = nil
        if selection == account.id {
            selection = nil
        }
        Task { await model.delete(account) }
    }
}
