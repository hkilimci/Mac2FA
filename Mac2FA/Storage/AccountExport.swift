import CommonCrypto
import CryptoKit
import Foundation
import Security

enum AccountExport {
    private static let format = "Mac2FA"
    private static let version = 1
    private static let encryption = "AES-256-GCM"
    private static let kdf = "PBKDF2-HMAC-SHA256"
    private static let iterations: UInt32 = 600_000

    struct Entry: Codable, Equatable, Sendable {
        let id: UUID
        let issuer: String
        let label: String
        let secret: String
        let algorithm: OTPAlgorithm
        let digits: Int
        let period: Int
        let type: OTPType
        let counter: UInt64?
        let createdAt: Date
        let updatedAt: Date
        let websites: [WebsiteRule]?

        init(account: OTPAccount, secret: Data) {
            id = account.id
            issuer = account.issuer
            label = account.label
            self.secret = Base32.encode(secret)
            algorithm = account.algorithm
            digits = account.digits
            period = account.period
            type = account.type
            counter = account.counter
            createdAt = account.createdAt
            updatedAt = account.updatedAt
            websites = account.websites
        }

        func draft() throws -> OTPAccountDraft {
            let data = try Base32.decode(secret)
            return OTPAccountDraft(
                issuer: issuer, label: label, secretData: data, algorithm: algorithm,
                digits: digits, period: period, type: type, counter: counter
            )
        }
    }

    private struct Header: Decodable {
        let format: String
        let version: Int
        let encryption: String?
    }

    private struct Payload: Codable {
        let format: String
        let version: Int
        let accounts: [Entry]
    }

    struct EncryptedPayload: Codable, Sendable {
        let format: String
        let version: Int
        let encryption: String
        let kdf: String
        let iterations: UInt32
        let salt: Data
        let sealedData: Data
    }

    enum Backup: Sendable {
        case plaintext([Entry])
        case encrypted(EncryptedPayload)

        var requiresPassword: Bool {
            if case .encrypted = self { return true }
            return false
        }

        func entries(password: String) throws -> [Entry] {
            switch self {
            case .plaintext(let entries):
                return entries
            case .encrypted(let payload):
                guard !password.isEmpty else { throw AccountImportError.passwordRequired }
                let key = try deriveKey(password: password, salt: Array(payload.salt))
                let box = try AES.GCM.SealedBox(combined: payload.sealedData)
                guard let plaintext = try? AES.GCM.open(box, using: key) else {
                    throw AccountImportError.authenticationFailed
                }
                return try decodePlaintext(plaintext)
            }
        }
    }

    static func encode(_ accounts: [Entry], password: String) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let plaintext = try encoder.encode(Payload(format: format, version: version, accounts: accounts))
        guard !password.isEmpty else { return plaintext }

        var salt = [UInt8](repeating: 0, count: 16)
        let randomStatus = salt.withUnsafeMutableBufferPointer {
            SecRandomCopyBytes(kSecRandomDefault, $0.count, $0.baseAddress!)
        }
        guard randomStatus == errSecSuccess else { throw AccountExportError.encryptionFailed }

        let key = try deriveKey(password: password, salt: salt)
        guard let sealedData = try AES.GCM.seal(plaintext, using: key).combined else {
            throw AccountExportError.encryptionFailed
        }
        return try encoder.encode(EncryptedPayload(
            format: format, version: version, encryption: encryption, kdf: kdf,
            iterations: iterations, salt: Data(salt), sealedData: sealedData
        ))
    }

    static func decode(_ data: Data) throws -> Backup {
        let header = try decodeJSON(Header.self, from: data)
        try validateHeader(format: header.format, version: header.version)
        guard let cipher = header.encryption else { return .plaintext(try decodePlaintext(data)) }
        guard cipher == encryption else { throw AccountImportError.unsupportedFormat }
        let payload = try decodeJSON(EncryptedPayload.self, from: data)
        guard payload.kdf == kdf, payload.iterations == iterations else {
            throw AccountImportError.unsupportedFormat
        }
        guard payload.salt.count == 16, payload.sealedData.count >= 28 else {
            throw AccountImportError.invalidBackup
        }
        return .encrypted(payload)
    }

    private static func decodePlaintext(_ data: Data) throws -> [Entry] {
        let payload = try decodeJSON(Payload.self, from: data)
        try validateHeader(format: payload.format, version: payload.version)
        guard !payload.accounts.isEmpty else { throw AccountImportError.invalidBackup }
        return payload.accounts
    }

    private static func decodeJSON<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw AccountImportError.invalidBackup
        }
    }

    private static func validateHeader(format: String, version: Int) throws {
        guard format == Self.format else { throw AccountImportError.invalidBackup }
        guard version == Self.version else { throw AccountImportError.unsupportedFormat }
    }

    private static func deriveKey(password: String, salt: [UInt8]) throws -> SymmetricKey {
        var key = [UInt8](repeating: 0, count: 32)
        let keyLength = key.count
        let passwordLength = password.utf8.count
        let derivationStatus = password.withCString { bytes in
            CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2), bytes, passwordLength, salt, salt.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), iterations, &key, keyLength
            )
        }
        guard derivationStatus == kCCSuccess else { throw AccountExportError.encryptionFailed }
        return SymmetricKey(data: key)
    }

    static func write(_ data: Data, to url: URL) throws {
        let file = FileWrapper(regularFileWithContents: data)
        file.fileAttributes = [
            FileAttributeKey.type.rawValue: FileAttributeType.typeRegular.rawValue,
            FileAttributeKey.posixPermissions.rawValue: 0o600
        ]
        try file.write(to: url, options: .atomic, originalContentsURL: nil)
    }
}

enum AccountImportError: LocalizedError, Equatable {
    case invalidBackup
    case unsupportedFormat
    case passwordRequired
    case authenticationFailed
    case invalidAccount(String)
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .invalidBackup:
            return "This file isn’t a valid Mac2FA export."
        case .unsupportedFormat:
            return "This Mac2FA export uses an unsupported format."
        case .passwordRequired:
            return "Enter the password used to encrypt this file."
        case .authenticationFailed:
            return "The password is incorrect or the file is damaged."
        case .invalidAccount(let name):
            return "“\(name)” has invalid or unsupported account settings."
        case .saveFailed:
            return "Mac2FA couldn’t save the imported accounts."
        }
    }
}

enum AccountExportError: LocalizedError {
    case noAccounts
    case unavailableSecret(String)
    case encryptionFailed

    var errorDescription: String? {
        switch self {
        case .noAccounts:
            return "There are no accounts to export."
        case .unavailableSecret(let account):
            return "Mac2FA couldn’t read the setup key for “\(account)” from your keychain."
        case .encryptionFailed:
            return "Mac2FA couldn’t encrypt the export."
        }
    }
}
