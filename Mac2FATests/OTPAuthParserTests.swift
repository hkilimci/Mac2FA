import XCTest
@testable import Mac2FA

final class OTPAuthParserTests: XCTestCase {
    func testStandardTOTP() throws {
        let uri = "otpauth://totp/GitHub:harun@example.com?secret=JBSWY3DPEHPK3PXP&issuer=GitHub"
        let draft = try OTPAuthParser.parse(uri)
        XCTAssertEqual(draft.issuer, "GitHub")
        XCTAssertEqual(draft.label, "harun@example.com")
        XCTAssertEqual(draft.type, .totp)
        XCTAssertEqual(draft.algorithm, .sha1)
        XCTAssertEqual(draft.digits, 6)
        XCTAssertEqual(draft.period, 30)
    }

    func testIssuerInLabel() throws {
        let uri = "otpauth://totp/harun@example.com?secret=JBSWY3DPEHPK3PXP"
        let draft = try OTPAuthParser.parse(uri)
        XCTAssertEqual(draft.issuer, "")
        XCTAssertEqual(draft.label, "harun@example.com")
    }

    func testIssuerPrefixInLabel() throws {
        let uri = "otpauth://totp/Google:harun@example.com?secret=JBSWY3DPEHPK3PXP"
        let draft = try OTPAuthParser.parse(uri)
        XCTAssertEqual(draft.issuer, "Google")
        XCTAssertEqual(draft.label, "harun@example.com")
    }

    func testSHA256() throws {
        let uri = "otpauth://totp/Test?secret=JBSWY3DPEHPK3PXP&algorithm=SHA256"
        let draft = try OTPAuthParser.parse(uri)
        XCTAssertEqual(draft.algorithm, .sha256)
    }

    func testEightDigits() throws {
        let uri = "otpauth://totp/Test?secret=JBSWY3DPEHPK3PXP&digits=8"
        let draft = try OTPAuthParser.parse(uri)
        XCTAssertEqual(draft.digits, 8)
    }

    func testHOTP() throws {
        let uri = "otpauth://hotp/Test:user?secret=JBSWY3DPEHPK3PXP&issuer=Test&counter=0"
        let draft = try OTPAuthParser.parse(uri)
        XCTAssertEqual(draft.type, .hotp)
        XCTAssertEqual(draft.counter, 0)
    }

    func testMissingSecret() {
        let uri = "otpauth://totp/Test"
        XCTAssertThrowsError(try OTPAuthParser.parse(uri))
    }
}
