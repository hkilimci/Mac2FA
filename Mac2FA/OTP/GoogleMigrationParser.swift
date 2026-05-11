import Foundation

enum GoogleMigrationParserError: Error {
    case invalidURL
    case invalidScheme
    case missingData
    case invalidBase64
    case invalidProtobuf
}

struct GoogleMigrationParser {
    static func parse(_ urlString: String) throws -> [OTPAccountDraft] {
        guard let url = URL(string: urlString), let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw GoogleMigrationParserError.invalidURL
        }

        guard components.scheme == "otpauth-migration" else {
            throw GoogleMigrationParserError.invalidScheme
        }

        let queryItems = components.queryItems ?? []
        guard let dataString = queryItems.first(where: { $0.name == "data" })?.value,
              let data = Data(base64Encoded: dataString) else {
            throw GoogleMigrationParserError.missingData
        }

        return try parseProtobuf(data)
    }

    private static func parseProtobuf(_ data: Data) throws -> [OTPAccountDraft] {
        var accounts: [OTPAccountDraft] = []
        var index = data.startIndex

        while index < data.endIndex {
            let tag = data[index]
            index = data.index(after: index)
            let fieldNumber = Int(tag >> 3)
            let wireType = tag & 0x07

            if fieldNumber == 1 && wireType == 2 {
                let (length, newIndex) = decodeVarint(data, from: index)
                index = newIndex
                guard let lengthValue = length else { break }
                let endIndex = data.index(index, offsetBy: Int(lengthValue))
                let parametersData = data[index..<endIndex]
                if let account = try? parseOtpParameters(parametersData) {
                    accounts.append(account)
                }
                index = endIndex
            } else {
                let (value, newIndex) = decodeVarint(data, from: index)
                index = newIndex
                if value == nil { break }
            }
        }

        return accounts
    }

    private static func parseOtpParameters(_ data: Data) throws -> OTPAccountDraft {
        var secret: Data = Data()
        var name: String = ""
        var issuer: String = ""
        var algorithm: OTPAlgorithm = .sha1
        var digits: Int = 6
        var type: OTPType = .totp
        var counter: UInt64 = 0

        var index = data.startIndex
        while index < data.endIndex {
            let tag = data[index]
            index = data.index(after: index)
            let fieldNumber = Int(tag >> 3)
            let wireType = tag & 0x07

            switch (fieldNumber, wireType) {
            case (1, 2):
                let (length, newIndex) = decodeVarint(data, from: index)
                index = newIndex
                guard let lengthValue = length else { break }
                let endIndex = data.index(index, offsetBy: Int(lengthValue))
                secret = Data(data[index..<endIndex])
                index = endIndex
            case (2, 2):
                let (length, newIndex) = decodeVarint(data, from: index)
                index = newIndex
                guard let lengthValue = length else { break }
                let endIndex = data.index(index, offsetBy: Int(lengthValue))
                if let str = String(data: data[index..<endIndex], encoding: .utf8) {
                    name = str
                }
                index = endIndex
            case (3, 2):
                let (length, newIndex) = decodeVarint(data, from: index)
                index = newIndex
                guard let lengthValue = length else { break }
                let endIndex = data.index(index, offsetBy: Int(lengthValue))
                if let str = String(data: data[index..<endIndex], encoding: .utf8) {
                    issuer = str
                }
                index = endIndex
            case (4, 0):
                let (value, newIndex) = decodeVarint(data, from: index)
                index = newIndex
                algorithm = mapAlgorithm(Int(value ?? 0))
            case (5, 0):
                let (value, newIndex) = decodeVarint(data, from: index)
                index = newIndex
                digits = mapDigits(Int(value ?? 0))
            case (6, 0):
                let (value, newIndex) = decodeVarint(data, from: index)
                index = newIndex
                type = mapType(Int(value ?? 0))
            case (7, 0):
                let (value, newIndex) = decodeVarint(data, from: index)
                index = newIndex
                counter = value ?? 0
            default:
                let (_, newIndex) = skipField(wireType: wireType, data: data, from: index)
                index = newIndex
            }
        }

        let label: String
        if name.contains(":") && issuer.isEmpty {
            let parts = name.split(separator: ":", maxSplits: 1)
            issuer = String(parts[0])
            label = String(parts[1])
        } else {
            label = name
        }

        return OTPAccountDraft(
            issuer: issuer,
            label: label,
            secretData: secret,
            algorithm: algorithm,
            digits: digits,
            period: 30,
            type: type,
            counter: type == .hotp ? counter : nil
        )
    }

    private static func decodeVarint(_ data: Data, from startIndex: Data.Index) -> (UInt64?, Data.Index) {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        var index = startIndex

        while index < data.endIndex {
            let byte = data[index]
            index = data.index(after: index)
            result |= UInt64(byte & 0x7F) << shift
            if (byte & 0x80) == 0 {
                return (result, index)
            }
            shift += 7
            if shift >= 64 {
                return (nil, index)
            }
        }
        return (nil, index)
    }

    private static func skipField(wireType: UInt8, data: Data, from startIndex: Data.Index) -> (Data?, Data.Index) {
        var index = startIndex
        switch wireType {
        case 0:
            let (_, newIndex) = decodeVarint(data, from: index)
            return (nil, newIndex)
        case 2:
            let (length, newIndex) = decodeVarint(data, from: index)
            index = newIndex
            guard let lengthValue = length else { return (nil, index) }
            let endIndex = data.index(index, offsetBy: Int(lengthValue))
            return (data[index..<endIndex], endIndex)
        case 5:
            let endIndex = data.index(index, offsetBy: 4)
            return (data[index..<endIndex], endIndex)
        case 1:
            let endIndex = data.index(index, offsetBy: 8)
            return (data[index..<endIndex], endIndex)
        default:
            return (nil, index)
        }
    }

    private static func mapAlgorithm(_ value: Int) -> OTPAlgorithm {
        switch value {
        case 1: return .sha1
        case 2: return .sha256
        case 3: return .sha512
        default: return .sha1
        }
    }

    private static func mapDigits(_ value: Int) -> Int {
        switch value {
        case 1: return 6
        case 2: return 8
        default: return 6
        }
    }

    private static func mapType(_ value: Int) -> OTPType {
        switch value {
        case 1: return .hotp
        case 2: return .totp
        default: return .totp
        }
    }
}
