import Foundation
import Observation

/// The saved accounts as the main window sees them, plus the secrets needed to show their codes.
@MainActor
@Observable
final class AccountsModel {
    private(set) var accounts: [OTPAccount] = []
    private(set) var hasLoaded = false
    /// The account whose code was just copied, so its row can confirm it.
    private(set) var recentlyCopiedID: OTPAccount.ID?

    /// Secrets keyed by keychain identifier, read once instead of on every tick.
    private var secrets: [String: Data] = [:]
    @ObservationIgnored private var copyFeedbackTask: Task<Void, Never>?

    func filteredAccounts(matching query: String) -> [OTPAccount] {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return accounts }
        return accounts.filter {
            $0.issuer.localizedCaseInsensitiveContains(query) ||
            $0.label.localizedCaseInsensitiveContains(query)
        }
    }

    func reload() async {
        let loaded = await AccountStore.shared.getAllAccounts()
        var loadedSecrets: [String: Data] = [:]
        for account in loaded {
            if let secret = secrets[account.secretIdentifier] {
                loadedSecrets[account.secretIdentifier] = secret
            } else if let secret = await AccountStore.shared.getSecret(for: account) {
                loadedSecrets[account.secretIdentifier] = secret
            }
        }
        secrets = loadedSecrets
        accounts = loaded
        hasLoaded = true
    }

    func code(for account: OTPAccount, at date: Date) -> OneTimeCode? {
        guard account.type == .totp, let secret = secrets[account.secretIdentifier] else { return nil }
        guard let value = try? TOTP.generate(
            secret: secret,
            time: date,
            period: account.period,
            algorithm: account.algorithm,
            digits: account.digits
        ) else { return nil }
        return OneTimeCode(value: value, period: account.period, at: date)
    }

    func copyCode(for account: OTPAccount) {
        guard let code = self.code(for: account, at: TimeProvider.now()) else { return }
        Task { await ClipboardManager.shared.copyCode(code.value) }
        confirmCopy(of: account)
    }

    /// Supplies the code to the system Copy command (⌘C), which writes the pasteboard itself.
    func itemProvidersForCopy(of account: OTPAccount) -> [NSItemProvider] {
        guard let code = self.code(for: account, at: TimeProvider.now()) else { return [] }
        Task { await ClipboardManager.shared.scheduleClear(of: code.value) }
        confirmCopy(of: account)
        return [NSItemProvider(object: code.value as NSString)]
    }

    func delete(_ account: OTPAccount) async {
        try? await AccountStore.shared.deleteAccount(id: account.id)
        await reload()
    }

    private func confirmCopy(of account: OTPAccount) {
        recentlyCopiedID = account.id
        copyFeedbackTask?.cancel()
        copyFeedbackTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            recentlyCopiedID = nil
        }
    }
}
