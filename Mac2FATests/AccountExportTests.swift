import CommonCrypto
import CryptoKit
import XCTest
@testable import Mac2FA

final class AccountExportTests: XCTestCase {
    private let secret = Data("12345".utf8)

    func testEmptyPasswordExportsAllAccountsAsReadableJSON() throws {
        let entries = [
            makeEntry(issuer: "Example", label: "alice@example.com", algorithm: .sha256),
            makeEntry(issuer: "Other", label: "bob@example.com", algorithm: .sha512)
        ]
        let data = try AccountExport.encode(entries, password: "")
        let payload = try JSONDecoder().decode(Plaintext.self, from: data)
        let backup = try AccountExport.decode(data)

        XCTAssertEqual(payload.format, "Mac2FA")
        XCTAssertEqual(payload.version, 1)
        XCTAssertFalse(backup.requiresPassword)
        XCTAssertEqual(try backup.entries(password: ""), entries)
        XCTAssertEqual(payload.accounts.map(\.issuer), ["Example", "Other"])
        XCTAssertEqual(payload.accounts.map(\.label), ["alice@example.com", "bob@example.com"])
        XCTAssertEqual(payload.accounts.map(\.algorithm), [.sha256, .sha512])
        for account in payload.accounts {
            XCTAssertEqual(account.secret, "GEZDGNBV")
            XCTAssertEqual(try Base32.decode(account.secret), secret)
            XCTAssertEqual(account.digits, 8)
            XCTAssertEqual(account.period, 60)
            XCTAssertEqual(account.type, .totp)
            XCTAssertEqual(account.websites, [WebsiteRule("https://example.com/login")!])
        }
    }

    func testPasswordProtectedExportRoundTripsAndRejectsWrongPassword() throws {
        let entries = [makeEntry(issuer: "Example", label: "alice@example.com", algorithm: .sha1)]
        let password = " şifre 🔑 "
        let plaintext = try AccountExport.encode(entries, password: "")
        let encrypted = try AccountExport.encode(entries, password: password)
        let envelope = try JSONDecoder().decode(Encrypted.self, from: encrypted)
        let backup = try AccountExport.decode(encrypted)

        XCTAssertEqual(envelope.format, "Mac2FA")
        XCTAssertEqual(envelope.version, 1)
        XCTAssertEqual(envelope.encryption, "AES-256-GCM")
        XCTAssertEqual(envelope.kdf, "PBKDF2-HMAC-SHA256")
        XCTAssertEqual(envelope.iterations, 600_000)
        XCTAssertEqual(envelope.salt.count, 16)
        XCTAssertEqual(envelope.sealedData.count, 12 + plaintext.count + 16)
        XCTAssertFalse(String(decoding: encrypted, as: UTF8.self).contains("alice@example.com"))
        XCTAssertFalse(String(decoding: encrypted, as: UTF8.self).contains("GEZDGNBV"))
        XCTAssertTrue(backup.requiresPassword)
        XCTAssertEqual(try backup.entries(password: password), entries)
        XCTAssertThrowsError(try backup.entries(password: "")) { error in
            XCTAssertEqual(error as? AccountImportError, .passwordRequired)
        }
        XCTAssertThrowsError(try backup.entries(password: "wrong password")) { error in
            XCTAssertEqual(error as? AccountImportError, .authenticationFailed)
        }

        let box = try AES.GCM.SealedBox(combined: envelope.sealedData)
        let key = deriveKey(password, envelope: envelope)
        let wrongKey = deriveKey("wrong password", envelope: envelope)
        XCTAssertEqual(try AES.GCM.open(box, using: key), plaintext)
        XCTAssertThrowsError(try AES.GCM.open(box, using: wrongKey))

        var tamperedData = envelope.sealedData
        tamperedData[12] ^= 1
        let tamperedBox = try AES.GCM.SealedBox(combined: tamperedData)
        XCTAssertThrowsError(try AES.GCM.open(tamperedBox, using: key))
        var tampered = try XCTUnwrap(JSONSerialization.jsonObject(with: encrypted) as? [String: Any])
        tampered["sealedData"] = tamperedData.base64EncodedString()
        let modified = try AccountExport.decode(JSONSerialization.data(withJSONObject: tampered))
        XCTAssertThrowsError(try modified.entries(password: password)) { error in
            XCTAssertEqual(error as? AccountImportError, .authenticationFailed)
        }
    }

    func testRejectsInvalidFilesAndUnsupportedVersions() throws {
        let invalidFiles = [
            ("{}", AccountImportError.invalidBackup),
            (#"{"format":"Mac2FA","version":2}"#, .unsupportedFormat),
            (#"{"format":"Mac2FA","version":1,"accounts":[]}"#, .invalidBackup),
            (#"{"format":"Mac2FA","version":1,"encryption":"unknown"}"#, .unsupportedFormat)
        ]
        for (json, expectedError) in invalidFiles {
            XCTAssertThrowsError(try AccountExport.decode(Data(json.utf8))) { error in
                XCTAssertEqual(error as? AccountImportError, expectedError)
            }
        }
    }

    func testExportReplacesExistingFileWithOwnerOnlyPermissions() throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? fileManager.removeItem(at: directory) }
        let url = directory.appendingPathComponent("accounts.json")
        try Data("old file".utf8).write(to: url)
        try fileManager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)

        let export = try AccountExport.encode([], password: "")
        try AccountExport.write(export, to: url)

        XCTAssertEqual(try Data(contentsOf: url), export)
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        XCTAssertEqual(attributes[.posixPermissions] as? Int, 0o600)
    }

    private func makeEntry(issuer: String, label: String, algorithm: OTPAlgorithm) -> AccountExport.Entry {
        let account = OTPAccount(
            id: UUID(), issuer: issuer, label: label, secretIdentifier: "local-keychain-id",
            algorithm: algorithm, digits: 8, period: 60, type: .totp, counter: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            websites: [WebsiteRule("https://example.com/login")!]
        )
        return AccountExport.Entry(account: account, secret: secret)
    }

    private func deriveKey(_ password: String, envelope: Encrypted) -> SymmetricKey {
        let salt = Array(envelope.salt)
        let length = 32
        var key = [UInt8](repeating: 0, count: length)
        let status = password.withCString { bytes in
            CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2), bytes, password.utf8.count, salt, salt.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), envelope.iterations, &key, length
            )
        }
        XCTAssertEqual(status, Int32(kCCSuccess))
        return SymmetricKey(data: key)
    }

    private struct Plaintext: Decodable {
        struct Entry: Decodable {
            let issuer: String
            let label: String
            let secret: String
            let algorithm: OTPAlgorithm
            let digits: Int
            let period: Int
            let type: OTPType
            let websites: [WebsiteRule]
        }
        let format: String
        let version: Int
        let accounts: [Entry]
    }

    private struct Encrypted: Decodable {
        let format: String
        let version: Int
        let encryption: String
        let kdf: String
        let iterations: UInt32
        let salt: Data
        let sealedData: Data
    }
}
