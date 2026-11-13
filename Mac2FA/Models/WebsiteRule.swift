import Foundation

struct WebsiteRule: Codable, Equatable {
    let host: String
    let port: Int
    let path: String

    /// Match a login page by HTTPS host, effective port and exact path.
    /// Query parameters and fragments often vary during sign-in.
    init?(_ address: String) {
        guard let parts = URLComponents(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              parts.scheme?.lowercased() == "https",
              let host = parts.encodedHost?.lowercased(), !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.url != nil,
              (1...65535).contains(parts.port ?? 443)
        else { return nil }

        self.host = host
        port = parts.port ?? 443
        path = parts.percentEncodedPath.isEmpty ? "/" : parts.percentEncodedPath
    }

    var address: String {
        let explicitPort = port == 443 ? "" : ":\(port)"
        return "https://\(host)\(explicitPort)\(path)"
    }

    func account(in accounts: [OTPAccount]) -> OTPAccount? {
        let matches = accounts.filter { $0.websites?.contains(self) == true }
        return matches.count == 1 ? matches.first : nil
    }
}

enum CopyLink {
    static func url(for id: OTPAccount.ID) -> URL {
        URL(string: "mac2fa://copy/\(id.uuidString)")!
    }

    static func accountID(from url: URL) -> OTPAccount.ID? {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == "mac2fa", parts.host?.lowercased() == "copy",
              parts.user == nil, parts.password == nil, parts.port == nil,
              parts.query == nil, parts.fragment == nil,
              parts.percentEncodedPath.count == 37, parts.percentEncodedPath.first == "/"
        else { return nil }
        return UUID(uuidString: String(parts.percentEncodedPath.dropFirst()))
    }
}
