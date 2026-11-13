import XCTest
@testable import Mac2FA

final class QuickAccessTests: XCTestCase {
    func testWebsiteRuleMatchesExactHTTPSOriginAndPath() throws {
        let rule = try XCTUnwrap(WebsiteRule("https://Example.com/sign-in"))
        XCTAssertEqual(rule, WebsiteRule("https://example.com:443/sign-in?next=%2Fhome#form"))
        XCTAssertNil(WebsiteRule("http://example.com/sign-in"))
        XCTAssertNil(WebsiteRule("https://name:password@example.com/sign-in"))
        XCTAssertNotEqual(rule, WebsiteRule("https://sub.example.com/sign-in"))
        XCTAssertNotEqual(rule, WebsiteRule("https://example.com:8443/sign-in"))
        XCTAssertNotEqual(rule, WebsiteRule("https://example.com/sign-in/other"))
        XCTAssertNotEqual(rule, WebsiteRule("https://example.com/sign-in-fake"))
    }

    func testCopyLinksUseOnlyAnExactAccountID() throws {
        let first = UUID()
        let second = UUID()
        XCTAssertEqual(CopyLink.accountID(from: CopyLink.url(for: first)), first)
        XCTAssertEqual(CopyLink.accountID(from: CopyLink.url(for: second)), second)
        for input in [
            "mac2fa://copy", "mac2fa://copy/github", "mac2fa://unlock",
            "https://copy/\(first)", "mac2fa://copy/\(first)/extra",
            "mac2fa://copy/\(first)?account=\(second)", "mac2fa://copy/\(first)#other",
            "mac2fa://user@copy/\(first)", "mac2fa://copy:443/\(first)"
        ] {
            XCTAssertNil(CopyLink.accountID(from: try XCTUnwrap(URL(string: input))), input)
        }
    }

    func testWebsiteSuggestionRequiresOneMatchingAccount() throws {
        let workPage = try XCTUnwrap(WebsiteRule("https://example.com/work"))
        let personalPage = try XCTUnwrap(WebsiteRule("https://example.com/personal"))
        let work = account(label: "Work", website: workPage)
        var personal = account(label: "Personal", website: personalPage)
        XCTAssertEqual(workPage.account(in: [personal, work])?.id, work.id)
        XCTAssertEqual(personalPage.account(in: [work, personal])?.id, personal.id)
        personal.websites = [workPage]
        XCTAssertNil(workPage.account(in: [work, personal]))
    }

    func testExistingAccountDecodesWithoutWebsiteRules() throws {
        let id = UUID()
        let json = """
        {
          "id": "\(id)", "issuer": "GitHub", "label": "Work",
          "secretIdentifier": "keychain-item", "algorithm": "sha1", "digits": 6,
          "period": 30, "type": "totp", "createdAt": 0, "updatedAt": 0
        }
        """
        let account = try JSONDecoder().decode(OTPAccount.self, from: Data(json.utf8))
        XCTAssertEqual(account.id, id)
        XCTAssertEqual(account.secretIdentifier, "keychain-item")
        XCTAssertNil(account.websites)
    }

    private func account(label: String, website: WebsiteRule) -> OTPAccount {
        OTPAccount(id: UUID(), issuer: "Example", label: label, secretIdentifier: "test",
                   algorithm: .sha1, digits: 6, period: 30, type: .totp,
                   createdAt: .now, updatedAt: .now, websites: [website])
    }
}
