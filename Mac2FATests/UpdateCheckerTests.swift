import XCTest
@testable import Mac2FA

final class UpdateCheckerTests: XCTestCase {
    func testDownloadsDMGInsteadOfZIPOrReleasePage() throws {
        let release = try makeRelease(assets: [
            ["name": "Mac2FA.zip", "browser_download_url": "https://github.com/hkilimci/Mac2FA/releases/download/v1.0.2/Mac2FA.zip"],
            ["name": "Mac2FA.dmg", "browser_download_url": dmgURL],
        ])
        XCTAssertEqual(try UpdateChecker.result(for: release, currentVersion: "1.0.1"),
                       .updateAvailable(current: "1.0.1", latest: "1.0.2", url: URL(string: dmgURL)!, notes: "Release notes"))
    }

    func testZIPOnlyReleaseHasNoDMG() throws {
        let release = try makeRelease(assets: [
            ["name": "Mac2FA.zip", "browser_download_url": "https://github.com/hkilimci/Mac2FA/releases/download/v1.0.2/Mac2FA.zip"],
        ])
        XCTAssertThrowsError(try UpdateChecker.result(for: release, currentVersion: "1.0.1")) {
            guard case UpdateCheckError.noDMG = $0 else { return XCTFail("Expected a missing DMG error, got \($0)") }
        }
    }

    func testReleaseWithoutAssetsHasNoDMG() throws {
        let release = try makeRelease()
        XCTAssertThrowsError(try UpdateChecker.result(for: release, currentVersion: "1.0.1")) {
            guard case UpdateCheckError.noDMG = $0 else { return XCTFail("Expected a missing DMG error, got \($0)") }
        }
    }

    func testRejectsUnsafeOrNonDMGDownloadURLs() throws {
        for downloadURL in ["not a URL", "file:///tmp/Mac2FA.dmg", "http://example.com/Mac2FA.dmg", "https://example.com/Mac2FA.zip"] {
            let release = try makeRelease(assets: [["name": "Mac2FA.dmg", "browser_download_url": downloadURL]])
            XCTAssertThrowsError(try UpdateChecker.result(for: release, currentVersion: "1.0.1")) {
                guard case UpdateCheckError.invalidURL = $0 else { return XCTFail("Expected an invalid URL error, got \($0)") }
            }
        }
    }

    func testDMGExtensionIsCaseInsensitive() throws {
        let url = "https://github.com/hkilimci/Mac2FA/releases/download/v1.0.2/Mac2FA.DMG"
        let release = try makeRelease(assets: [["name": "Mac2FA.DMG", "browser_download_url": url]])
        XCTAssertEqual(try UpdateChecker.result(for: release, currentVersion: "1.0.1"),
                       .updateAvailable(current: "1.0.1", latest: "1.0.2", url: URL(string: url)!, notes: "Release notes"))
    }

    func testCurrentAndNewerVersionsDoNotRequireAnAsset() throws {
        let release = try makeRelease()
        for current in ["1.0.2", "1.0.3"] {
            XCTAssertEqual(try UpdateChecker.result(for: release, currentVersion: current), .upToDate(current: current))
        }
    }

    func testIgnoresDraftAndPrerelease() throws {
        for flag in ["draft", "prerelease"] {
            let release = try makeRelease(flags: [flag: true])
            XCTAssertThrowsError(try UpdateChecker.result(for: release, currentVersion: "1.0.1")) {
                guard case UpdateCheckError.noReleases = $0 else { return XCTFail("Expected no published release, got \($0)") }
            }
        }
    }

    func testComparesVersionsNumerically() {
        XCTAssertEqual(UpdateChecker.compare("1.0.9", "1.0.10"), .orderedAscending)
        XCTAssertEqual(UpdateChecker.compare("1.0", "1.0.0"), .orderedSame)
        XCTAssertEqual(UpdateChecker.normalize(" v1.0.2\n"), "1.0.2")
    }

    private let dmgURL = "https://github.com/hkilimci/Mac2FA/releases/download/v1.0.2/Mac2FA.dmg"

    private func makeRelease(assets: [[String: String]] = [], flags: [String: Bool] = [:]) throws -> GitHubRelease {
        let payload: [String: Any] = [
            "tag_name": "v1.0.2",
            "name": "Mac2FA 1.0.2",
            "html_url": "https://github.com/hkilimci/Mac2FA/releases/tag/v1.0.2",
            "body": "Release notes",
            "draft": flags["draft"] ?? false,
            "prerelease": flags["prerelease"] ?? false,
            "assets": assets,
        ]
        return try JSONDecoder().decode(GitHubRelease.self, from: JSONSerialization.data(withJSONObject: payload))
    }
}
