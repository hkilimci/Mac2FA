import Foundation

enum AccountStoreError: Error {
    case invalidAccountType
    case invalidDigits
    case invalidPeriod
    case invalidAlgorithm
    case failedToGenerateCode
    case duplicateAccount
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
        try data.write(to: fileURL)
    }

    func getAllAccounts() -> [OTPAccount] {
        loadAccountsIfNeeded()
        return accounts
    }

    func addAccount(draft: OTPAccountDraft) async throws -> OTPAccount {
        loadAccountsIfNeeded()

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
            updatedAt: Date()
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

    func getSecret(for account: OTPAccount) -> Data? {
        return try? KeychainStore.retrieve(identifier: account.secretIdentifier)
    }
}
