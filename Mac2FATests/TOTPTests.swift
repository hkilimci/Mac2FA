import XCTest
@testable import Mac2FA

final class TOTPTests: XCTestCase {
    // RFC 6238 Appendix B test vectors
    func testRFC6238_SHA1() throws {
        let secret = Data("12345678901234567890".utf8)
        let testCases: [(time: UInt64, expected: String)] = [
            (59, "287082"),
            (1111111109, "081804"),
            (1111111111, "050471"),
            (1234567890, "005924"),
            (2000000000, "279037"),
        ]

        for (time, expected) in testCases {
            let date = Date(timeIntervalSince1970: Double(time))
            let code = try TOTP.generate(secret: secret, time: date, period: 30, algorithm: .sha1, digits: 6)
            XCTAssertEqual(code, expected, "Failed for time \(time)")
        }
    }

    func testRFC6238_SHA256() throws {
        let secret = Data("12345678901234567890123456789012".utf8)
        let testCases: [(time: UInt64, expected: String)] = [
            (59, "119246"),
            (1111111109, "084774"),
            (1111111111, "062674"),
            (1234567890, "819424"),
            (2000000000, "698825"),
        ]

        for (time, expected) in testCases {
            let date = Date(timeIntervalSince1970: Double(time))
            let code = try TOTP.generate(secret: secret, time: date, period: 30, algorithm: .sha256, digits: 6)
            XCTAssertEqual(code, expected, "Failed for time \(time)")
        }
    }

    func testRFC6238_SHA512() throws {
        let secret = Data("1234567890123456789012345678901234567890123456789012345678901234".utf8)
        let testCases: [(time: UInt64, expected: String)] = [
            (59, "693936"),
            (1111111109, "091201"),
            (1111111111, "943326"),
            (1234567890, "441116"),
            (2000000000, "618901"),
        ]

        for (time, expected) in testCases {
            let date = Date(timeIntervalSince1970: Double(time))
            let code = try TOTP.generate(secret: secret, time: date, period: 30, algorithm: .sha512, digits: 6)
            XCTAssertEqual(code, expected, "Failed for time \(time)")
        }
    }

    func testEightDigits() throws {
        let secret = Data("12345678901234567890".utf8)
        let date = Date(timeIntervalSince1970: 59)
        let code = try TOTP.generate(secret: secret, time: date, period: 30, algorithm: .sha1, digits: 8)
        XCTAssertEqual(code, "94287082")
    }
}
