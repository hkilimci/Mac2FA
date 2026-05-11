import XCTest
@testable import Mac2FA

final class Base32Tests: XCTestCase {
    func testUppercase() throws {
        let decoded = try Base32.decode("JBSWY3DPEHPK3PXP")
        XCTAssertEqual(decoded, Data([0x48, 0x65, 0x6c, 0x6c, 0x6f, 0x21, 0xde, 0xad, 0xbe, 0xef]))
    }

    func testLowercase() throws {
        let decoded = try Base32.decode("jbswy3dpehpk3pxp")
        XCTAssertEqual(decoded, Data([0x48, 0x65, 0x6c, 0x6c, 0x6f, 0x21, 0xde, 0xad, 0xbe, 0xef]))
    }

    func testWithSpaces() throws {
        let decoded = try Base32.decode("JBSW Y3DP EHPK 3PXP")
        XCTAssertEqual(decoded, Data([0x48, 0x65, 0x6c, 0x6c, 0x6f, 0x21, 0xde, 0xad, 0xbe, 0xef]))
    }

    func testWithHyphens() throws {
        let decoded = try Base32.decode("JBSW-Y3DP-EHPK-3PXP")
        XCTAssertEqual(decoded, Data([0x48, 0x65, 0x6c, 0x6c, 0x6f, 0x21, 0xde, 0xad, 0xbe, 0xef]))
    }

    func testWithPadding() throws {
        let decoded = try Base32.decode("JBSWY3DPEHPK3PXP=")
        XCTAssertEqual(decoded, Data([0x48, 0x65, 0x6c, 0x6c, 0x6f, 0x21, 0xde, 0xad, 0xbe, 0xef]))
    }

    func testInvalidCharacters() {
        XCTAssertThrowsError(try Base32.decode("JBSWY3DPEHPK3PX1"))
    }
}
