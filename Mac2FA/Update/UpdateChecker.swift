import Foundation

struct GitHubRelease: Decodable {
    let tagName: String
    let name: String?
    let htmlUrl: String
    let body: String?
    let prerelease: Bool
    let draft: Bool

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case htmlUrl = "html_url"
        case body
        case prerelease
        case draft
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

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid response from GitHub."
        case .httpStatus(let code): return "GitHub returned HTTP \(code)."
        case .noReleases: return "No published releases found."
        case .invalidURL: return "Release URL was malformed."
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
        let current = Self.currentVersion
        let latest = Self.normalize(release.tagName)
        guard let url = URL(string: release.htmlUrl) else {
            throw UpdateCheckError.invalidURL
        }
        if Self.compare(current, latest) == .orderedAscending {
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
