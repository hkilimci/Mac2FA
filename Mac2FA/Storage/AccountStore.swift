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

        if accounts.contains(where: { $0.issuer == account.issuer && $0.label == account.label }) {
            throw AccountStoreError.duplicateAccount
        }

        accounts.append(account)
        try saveAccounts()
        return account
    }

    func replaceAccount(draft: OTPAccountDraft, existingId: UUID) async throws -> OTPAccount {
        guard draft.type == .totp else {
            throw AccountStoreError.invalidAccountType
        }
        guard draft.digits == 6 || draft.digits == 7 || draft.digits == 8 else {
            throw AccountStoreError.invalidDigits
        }
        guard draft.period > 0 else {
            throw AccountStoreError.invalidPeriod
        }

        let code = try TOTP.generate(secret: draft.secretData, algorithm: draft.algorithm, digits: draft.digits)
        guard code.count == draft.digits else {
            throw AccountStoreError.failedToGenerateCode
        }

        guard let existingIndex = accounts.firstIndex(where: { $0.id == existingId }) else {
            throw AccountStoreError.duplicateAccount
        }

        let existing = accounts[existingIndex]
        try KeychainStore.delete(identifier: existing.secretIdentifier)
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
        try saveAccounts()
        return account
    }

    func deleteAccount(id: UUID) throws {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { return }
        let account = accounts[index]
        try? KeychainStore.delete(identifier: account.secretIdentifier)
        accounts.remove(at: index)
        try saveAccounts()
    }

    func getSecret(for account: OTPAccount) -> Data? {
        return try? KeychainStore.retrieve(identifier: account.secretIdentifier)
    }
}
