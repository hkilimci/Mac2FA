import Foundation

struct GitHubRelease: Decodable {
    let tagName: String
    let name: String?
    let body: String?
    let prerelease: Bool
    let draft: Bool
    let assets: [Asset]

    struct Asset: Decodable {
        let name: String
        let browserDownloadUrl: String

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadUrl = "browser_download_url"
        }
    }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case prerelease
        case draft
        case assets
    }
}

enum UpdateCheckResult: Equatable {
    case upToDate(current: String)
    case updateAvailable(current: String, latest: String, url: URL, notes: String?)
}

enum UpdateCheckError: LocalizedError {
    case invalidResponse
    case httpStatus(Int)
    case noReleases
    case invalidURL
    case noDMG

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid response from GitHub."
        case .httpStatus(let code): return "GitHub returned HTTP \(code)."
        case .noReleases: return "No published releases found."
        case .invalidURL: return "The DMG download URL was malformed."
        case .noDMG: return "The latest release does not have a DMG download. Please try again later."
        }
    }
}

struct UpdateChecker {
    static let repoOwner = "hkilimci"
    static let repoName = "Mac2FA"

    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    static var currentVersion: String {
        let info = Bundle.main.infoDictionary
        return (info?["CFBundleShortVersionString"] as? String) ?? "0.0.0"
    }

    func check() async throws -> UpdateCheckResult {
        let release = try await fetchLatestRelease()
        return try Self.result(for: release, currentVersion: Self.currentVersion)
    }

    static func result(for release: GitHubRelease, currentVersion current: String) throws -> UpdateCheckResult {
        guard !release.draft, !release.prerelease else { throw UpdateCheckError.noReleases }
        let latest = Self.normalize(release.tagName)
        if Self.compare(current, latest) == .orderedAscending {
            guard let asset = release.assets.first(where: { $0.name.lowercased().hasSuffix(".dmg") }) else {
                throw UpdateCheckError.noDMG
            }
            guard let url = URL(string: asset.browserDownloadUrl),
                  url.scheme == "https", url.host != nil,
                  url.pathExtension.lowercased() == "dmg" else {
                throw UpdateCheckError.invalidURL
            }
            return .updateAvailable(current: current, latest: latest, url: url, notes: release.body)
        }
        return .upToDate(current: current)
    }

    private func fetchLatestRelease() async throws -> GitHubRelease {
        let urlString = "https://api.github.com/repos/\(Self.repoOwner)/\(Self.repoName)/releases/latest"
        guard let url = URL(string: urlString) else { throw UpdateCheckError.invalidURL }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Mac2FA-UpdateCheck", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UpdateCheckError.invalidResponse }
        if http.statusCode == 404 { throw UpdateCheckError.noReleases }
        guard (200..<300).contains(http.statusCode) else {
            throw UpdateCheckError.httpStatus(http.statusCode)
        }
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    static func normalize(_ tag: String) -> String {
        var t = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("v") || t.hasPrefix("V") { t.removeFirst() }
        return t
    }

    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let a = parts(lhs)
        let b = parts(rhs)
        let n = max(a.count, b.count)
        for i in 0..<n {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x < y { return .orderedAscending }
            if x > y { return .orderedDescending }
        }
        return .orderedSame
    }

    private static func parts(_ s: String) -> [Int] {
        let core = s.split(separator: "-").first.map(String.init) ?? s
        return core.split(separator: ".").map { Int($0) ?? 0 }
    }
}
