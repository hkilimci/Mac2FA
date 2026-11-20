import Foundation

enum AccountStoreError: Error {
    case invalidAccountType
    case invalidDigits
    case invalidPeriod
    case invalidAlgorithm
    case failedToGenerateCode
    case duplicateAccount
    case accountNotFound
    case websiteAlreadyAssigned
}

actor AccountStore {
    static let shared = AccountStore()

    private var accounts: [OTPAccount] = []
    private var isLoaded = false
    private let fileURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("Mac2FA", isDirectory: true)
        try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)
        self.fileURL = appFolder.appendingPathComponent("accounts.json")
    }

    private func loadAccountsIfNeeded() {
        guard !isLoaded else { return }
        isLoaded = true
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else {
            return
        }
        accounts = (try? JSONDecoder().decode([OTPAccount].self, from: data)) ?? []
    }

    private func saveAccounts() throws {
        let data = try JSONEncoder().encode(accounts)
        try data.write(to: fileURL, options: .atomic)
    }

    func getAllAccounts() -> [OTPAccount] {
        loadAccountsIfNeeded()
        return accounts
    }

    func exportAccounts(password: String) throws -> Data {
        loadAccountsIfNeeded()
        guard !accounts.isEmpty else { throw AccountExportError.noAccounts }

        let entries = try accounts.map { account in
            try Task.checkCancellation()
            guard let secret = getSecret(for: account), !secret.isEmpty else {
                throw AccountExportError.unavailableSecret(account.displayName)
            }
            return AccountExport.Entry(account: account, secret: secret)
        }
        return try AccountExport.encode(entries, password: password)
    }

    func addAccount(draft: OTPAccountDraft) async throws -> OTPAccount {
        loadAccountsIfNeeded()
        try validate(draft)

        if accounts.contains(where: { $0.issuer == draft.issuer && $0.label == draft.label }) {
            throw AccountStoreError.duplicateAccount
        }

        let secretIdentifier = UUID().uuidString
        try KeychainStore.save(secret: draft.secretData, identifier: secretIdentifier)

        let account = OTPAccount(
            id: UUID(),
            issuer: draft.issuer,
            label: draft.label,
            secretIdentifier: secretIdentifier,
            algorithm: draft.algorithm,
            digits: draft.digits,
            period: draft.period,
            type: draft.type,
            counter: draft.counter,
            createdAt: Date(),
            updatedAt: Date()
        )

        accounts.append(account)
        do {
            try saveAccounts()
        } catch {
            accounts.removeAll { $0.id == account.id }
            try? KeychainStore.delete(identifier: secretIdentifier)
            throw error
        }
        return account
    }

    func replaceAccount(draft: OTPAccountDraft, existingId: UUID) async throws -> OTPAccount {
        loadAccountsIfNeeded()
        try validate(draft)

        guard let existingIndex = accounts.firstIndex(where: { $0.id == existingId }) else {
            throw AccountStoreError.duplicateAccount
        }

        let existing = accounts[existingIndex]
        let secretIdentifier = UUID().uuidString
        try KeychainStore.save(secret: draft.secretData, identifier: secretIdentifier)

        let account = OTPAccount(
            id: existingId,
            issuer: draft.issuer,
            label: draft.label,
            secretIdentifier: secretIdentifier,
            algorithm: draft.algorithm,
            digits: draft.digits,
            period: draft.period,
            type: draft.type,
            counter: draft.counter,
            createdAt: existing.createdAt,
            updatedAt: Date(),
            websites: existing.websites
        )

        accounts[existingIndex] = account
        do {
            try saveAccounts()
        } catch {
            accounts[existingIndex] = existing
            try? KeychainStore.delete(identifier: secretIdentifier)
            throw error
        }
        try? KeychainStore.delete(identifier: existing.secretIdentifier)
        return account
    }

    func deleteAccount(id: UUID) throws {
        loadAccountsIfNeeded()

        guard let index = accounts.firstIndex(where: { $0.id == id }) else { return }
        let account = accounts[index]
        accounts.remove(at: index)
        do {
            try saveAccounts()
        } catch {
            accounts.insert(account, at: index)
            throw error
        }
        try? KeychainStore.delete(identifier: account.secretIdentifier)
    }

    func setWebsites(_ websites: [WebsiteRule], for id: OTPAccount.ID) throws {
        loadAccountsIfNeeded()
        guard let index = accounts.firstIndex(where: { $0.id == id }) else {
            throw AccountStoreError.accountNotFound
        }
        guard !accounts.contains(where: { account in
            account.id != id && (account.websites ?? []).contains(where: websites.contains)
        }) else { throw AccountStoreError.websiteAlreadyAssigned }

        let previous = accounts[index]
        accounts[index].websites = websites.isEmpty ? nil : websites
        accounts[index].updatedAt = Date()
        do {
            try saveAccounts()
        } catch {
            accounts[index] = previous
            throw error
        }
    }

    func getSecret(for account: OTPAccount) -> Data? {
        return try? KeychainStore.retrieve(identifier: account.secretIdentifier)
    }

    func importBackup(_ entries: [AccountExport.Entry]) throws -> ImportSummary {
        loadAccountsIfNeeded()
        var summary = ImportSummary()
        var ids = Set(accounts.map(\.id))
        var names = Set(accounts.map { [$0.issuer, $0.label] })
        var assignedWebsites = Set(accounts.flatMap { $0.websites ?? [] })
        var pending: [(account: OTPAccount, secret: Data)] = []

        for entry in entries {
            try Task.checkCancellation()
            let name = [entry.issuer, entry.label]
            guard !ids.contains(entry.id), !names.contains(name) else {
                summary.duplicates += 1
                continue
            }

            let draft: OTPAccountDraft
            do {
                draft = try entry.draft()
                try validate(draft)
            } catch {
                let name = entry.issuer.isEmpty ? entry.label : entry.issuer
                throw AccountImportError.invalidAccount(name.isEmpty ? "Unnamed Account" : name)
            }

            let websites = (entry.websites ?? []).filter { rule in
                guard WebsiteRule(rule.address) == rule, assignedWebsites.insert(rule).inserted else {
                    summary.skippedWebsites += 1
                    return false
                }
                return true
            }
            let account = OTPAccount(
                id: entry.id, issuer: entry.issuer, label: entry.label, secretIdentifier: UUID().uuidString,
                algorithm: entry.algorithm, digits: entry.digits, period: entry.period, type: entry.type,
                counter: entry.counter, createdAt: entry.createdAt, updatedAt: entry.updatedAt,
                websites: websites.isEmpty ? nil : websites
            )
            pending.append((account, draft.secretData))
            ids.insert(entry.id)
            names.insert(name)
        }

        guard !pending.isEmpty else { return summary }
        var stored: [OTPAccount] = []
        do {
            for (account, secret) in pending {
                try Task.checkCancellation()
                try KeychainStore.save(secret: secret, identifier: account.secretIdentifier)
                stored.append(account)
            }
            try Task.checkCancellation()
            accounts.append(contentsOf: stored)
            do {
                try saveAccounts()
            } catch {
                accounts.removeLast(stored.count)
                throw error
            }
        } catch {
            for account in stored {
                try? KeychainStore.delete(identifier: account.secretIdentifier)
            }
            if error is CancellationError { throw error }
            throw AccountImportError.saveFailed
        }
        summary.imported = stored.count
        return summary
    }

    private func validate(_ draft: OTPAccountDraft) throws {
        guard draft.type == .totp else {
            throw AccountStoreError.invalidAccountType
        }
        guard draft.digits == 6 || draft.digits == 7 || draft.digits == 8 else {
            throw AccountStoreError.invalidDigits
        }
        guard draft.period > 0 else {
            throw AccountStoreError.invalidPeriod
        }
        guard draft.algorithm == .sha1 || draft.algorithm == .sha256 || draft.algorithm == .sha512 else {
            throw AccountStoreError.invalidAlgorithm
        }
        let code = try TOTP.generate(secret: draft.secretData, algorithm: draft.algorithm, digits: draft.digits)
        guard code.count == draft.digits else {
            throw AccountStoreError.failedToGenerateCode
        }
    }

    func importDrafts(_ drafts: [OTPAccountDraft]) async -> ImportSummary {
        var summary = ImportSummary()
        for draft in drafts {
            do {
                _ = try await addAccount(draft: draft)
                summary.imported += 1
            } catch AccountStoreError.duplicateAccount {
                summary.duplicates += 1
            } catch {
                summary.failed += 1
            }
        }
        return summary
    }
}

struct ImportSummary {
    var imported = 0
    var duplicates = 0
    var failed = 0
    var skippedWebsites = 0

    var skipped: Int { duplicates + failed }
}
