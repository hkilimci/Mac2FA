import Foundation

struct OTPAccountDraft: Equatable {
    var issuer: String
    var label: String
    var secretData: Data
    var algorithm: OTPAlgorithm
    var digits: Int
    var period: Int
    var type: OTPType
    var counter: UInt64?
}

enum OTPAuthParserError: Error {
    case invalidURL
    case invalidScheme
    case invalidType
    case missingSecret
    case invalidBase32Secret
    case invalidDigits
    case invalidPeriod
    case invalidAlgorithm
}

struct OTPAuthParser {
    static func parse(_ urlString: String) throws -> OTPAccountDraft {
        guard let url = URL(string: urlString), let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw OTPAuthParserError.invalidURL
        }

        guard components.scheme == "otpauth" else {
            throw OTPAuthParserError.invalidScheme
        }

        let path = components.path
        let typeString = url.host?.lowercased() ?? ""
        guard let type = OTPType(rawValue: typeString) else {
            throw OTPAuthParserError.invalidType
        }

        let queryItems = components.queryItems ?? []
        var params: [String: String] = [:]
        for item in queryItems {
            params[item.name.lowercased()] = item.value
        }

        guard let secretString = params["secret"] else {
            throw OTPAuthParserError.missingSecret
        }

        let secretData: Data
        do {
            secretData = try Base32.decode(secretString)
        } catch {
            throw OTPAuthParserError.invalidBase32Secret
        }

        var issuer = params["issuer"] ?? ""
        var label = path

        if label.hasPrefix("/") {
            label.removeFirst()
        }

        let decodedLabel = label.removingPercentEncoding ?? label
        label = decodedLabel

        if let colonIndex = label.firstIndex(of: ":") {
            let labelIssuer = String(label[..<colonIndex])
            let accountLabel = String(label[label.index(after: colonIndex)...])
            if issuer.isEmpty {
                issuer = labelIssuer
            }
            label = accountLabel
        }

        issuer = issuer.trimmingCharacters(in: .whitespacesAndNewlines)
        label = label.trimmingCharacters(in: .whitespacesAndNewlines)

        var algorithm: OTPAlgorithm = .sha1
        if let algoString = params["algorithm"]?.lowercased() {
            switch algoString {
            case "sha1": algorithm = .sha1
            case "sha256": algorithm = .sha256
            case "sha512": algorithm = .sha512
            default: throw OTPAuthParserError.invalidAlgorithm
            }
        }

        var digits = 6
        if let digitsString = params["digits"], let d = Int(digitsString) {
            guard d == 6 || d == 7 || d == 8 else {
                throw OTPAuthParserError.invalidDigits
            }
            digits = d
        }

        var period = 30
        if let periodString = params["period"], let p = Int(periodString) {
            guard p > 0 else {
                throw OTPAuthParserError.invalidPeriod
            }
            period = p
        }

        var counter: UInt64?
        if let counterString = params["counter"], let c = UInt64(counterString) {
            counter = c
        }

        return OTPAccountDraft(
            issuer: issuer,
            label: label,
            secretData: secretData,
            algorithm: algorithm,
            digits: digits,
            period: period,
            type: type,
            counter: counter
        )
    }
}
