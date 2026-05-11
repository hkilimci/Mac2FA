import XCTest
@testable import Mac2FA

final class GoogleMigrationParserTests: XCTestCase {
    func testDecodeValidMigration() throws {
        // This is a base64-encoded minimal protobuf migration payload with one TOTP account
        // Constructed manually for testing
        let payload = createMinimalMigrationPayload()
        let base64 = payload.base64EncodedString()
        let uri = "otpauth-migration://offline?data=\(base64)"

        let drafts = try GoogleMigrationParser.parse(uri)
        XCTAssertEqual(drafts.count, 1)
        XCTAssertEqual(drafts[0].type, .totp)
        XCTAssertEqual(drafts[0].digits, 6)
        XCTAssertEqual(drafts[0].algorithm, .sha1)
    }

    func testMultipleAccounts() throws {
        let payload = createMigrationPayloadWithTwoAccounts()
        let base64 = payload.base64EncodedString()
        let uri = "otpauth-migration://offline?data=\(base64)"

        let drafts = try GoogleMigrationParser.parse(uri)
        XCTAssertEqual(drafts.count, 2)
    }

    func testSkipsUnknownLengthDelimitedTopLevelField() throws {
        var payload = Data()
        payload.append(0x12) // field 2, wire type 2
        payload.append(0x01)
        payload.append(0xFF)
        payload.append(createMinimalMigrationPayload())

        let base64 = payload.base64EncodedString()
        let uri = "otpauth-migration://offline?data=\(base64)"

        let drafts = try GoogleMigrationParser.parse(uri)
        XCTAssertEqual(drafts.count, 1)
        XCTAssertEqual(drafts[0].label, "Test")
    }

    func testTruncatedLengthDelimitedFieldThrowsInvalidProtobuf() {
        let payload = Data([0x0A, 0x05, 0x01])
        let base64 = payload.base64EncodedString()
        let uri = "otpauth-migration://offline?data=\(base64)"

        XCTAssertThrowsError(try GoogleMigrationParser.parse(uri)) { error in
            guard case GoogleMigrationParserError.invalidProtobuf = error else {
                return XCTFail("Expected invalidProtobuf, got \(error)")
            }
        }
    }

    private func createMinimalMigrationPayload() -> Data {
        var data = Data()
        // OtpParameters (field 1, wire type 2)
        let params = createOtpParameters(secret: Data([0x01, 0x02, 0x03]), name: "Test", issuer: "TestIssuer")
        data.append(0x0A) // field 1, wire type 2
        data.append(UInt8(params.count))
        data.append(params)
        return data
    }

    private func createMigrationPayloadWithTwoAccounts() -> Data {
        var data = Data()
        let params1 = createOtpParameters(secret: Data([0x01]), name: "User1", issuer: "Issuer1")
        data.append(0x0A)
        data.append(UInt8(params1.count))
        data.append(params1)

        let params2 = createOtpParameters(secret: Data([0x02]), name: "User2", issuer: "Issuer2")
        data.append(0x0A)
        data.append(UInt8(params2.count))
        data.append(params2)
        return data
    }

    private func createOtpParameters(secret: Data, name: String, issuer: String) -> Data {
        var data = Data()
        // secret (field 1, wire type 2)
        data.append(0x0A)
        data.append(UInt8(secret.count))
        data.append(secret)
        // name (field 2, wire type 2)
        let nameData = Data(name.utf8)
        data.append(0x12)
        data.append(UInt8(nameData.count))
        data.append(nameData)
        // issuer (field 3, wire type 2)
        let issuerData = Data(issuer.utf8)
        data.append(0x1A)
        data.append(UInt8(issuerData.count))
        data.append(issuerData)
        return data
    }
}
