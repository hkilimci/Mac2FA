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
            let (fieldNumber, wireType, nextIndex) = try decodeTag(data, from: index)
            index = nextIndex

            if fieldNumber == 1 && wireType == 2 {
                let (parametersData, newIndex) = try readLengthDelimited(data, from: index)
                accounts.append(try parseOtpParameters(parametersData))
                index = newIndex
            } else {
                index = try skipField(wireType: wireType, data: data, from: index)
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
            let (fieldNumber, wireType, nextIndex) = try decodeTag(data, from: index)
            index = nextIndex

            switch (fieldNumber, wireType) {
            case (1, 2):
                let (fieldData, newIndex) = try readLengthDelimited(data, from: index)
                secret = fieldData
                index = newIndex
            case (2, 2):
                let (fieldData, newIndex) = try readLengthDelimited(data, from: index)
                if let str = String(data: fieldData, encoding: .utf8) {
                    name = str
                }
                index = newIndex
            case (3, 2):
                let (fieldData, newIndex) = try readLengthDelimited(data, from: index)
                if let str = String(data: fieldData, encoding: .utf8) {
                    issuer = str
                }
                index = newIndex
            case (4, 0):
                let (value, newIndex) = decodeVarint(data, from: index)
                guard let value else { throw GoogleMigrationParserError.invalidProtobuf }
                guard let intValue = Int(exactly: value) else { throw GoogleMigrationParserError.invalidProtobuf }
                index = newIndex
                algorithm = mapAlgorithm(intValue)
            case (5, 0):
                let (value, newIndex) = decodeVarint(data, from: index)
                guard let value else { throw GoogleMigrationParserError.invalidProtobuf }
                guard let intValue = Int(exactly: value) else { throw GoogleMigrationParserError.invalidProtobuf }
                index = newIndex
                digits = mapDigits(intValue)
            case (6, 0):
                let (value, newIndex) = decodeVarint(data, from: index)
                guard let value else { throw GoogleMigrationParserError.invalidProtobuf }
                guard let intValue = Int(exactly: value) else { throw GoogleMigrationParserError.invalidProtobuf }
                index = newIndex
                type = mapType(intValue)
            case (7, 0):
                let (value, newIndex) = decodeVarint(data, from: index)
                guard let value else { throw GoogleMigrationParserError.invalidProtobuf }
                index = newIndex
                counter = value
            default:
                index = try skipField(wireType: wireType, data: data, from: index)
            }
        }

        guard !secret.isEmpty else {
            throw GoogleMigrationParserError.invalidProtobuf
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

    private static func decodeTag(_ data: Data, from startIndex: Data.Index) throws -> (fieldNumber: Int, wireType: UInt8, nextIndex: Data.Index) {
        let (tag, nextIndex) = decodeVarint(data, from: startIndex)
        guard let tag, tag != 0 else {
            throw GoogleMigrationParserError.invalidProtobuf
        }
        guard let fieldNumber = Int(exactly: tag >> 3) else {
            throw GoogleMigrationParserError.invalidProtobuf
        }
        return (fieldNumber, UInt8(tag & 0x07), nextIndex)
    }

    private static func readLengthDelimited(_ data: Data, from startIndex: Data.Index) throws -> (Data, Data.Index) {
        let (length, valueIndex) = decodeVarint(data, from: startIndex)
        guard let length else {
            throw GoogleMigrationParserError.invalidProtobuf
        }
        guard length <= UInt64(data.distance(from: valueIndex, to: data.endIndex)) else {
            throw GoogleMigrationParserError.invalidProtobuf
        }
        let endIndex = data.index(valueIndex, offsetBy: Int(length))
        return (Data(data[valueIndex..<endIndex]), endIndex)
    }

    private static func advanceIndex(_ data: Data, from startIndex: Data.Index, by count: Int) throws -> Data.Index {
        guard count <= data.distance(from: startIndex, to: data.endIndex) else {
            throw GoogleMigrationParserError.invalidProtobuf
        }
        return data.index(startIndex, offsetBy: count)
    }

    private static func skipField(wireType: UInt8, data: Data, from startIndex: Data.Index) throws -> Data.Index {
        switch wireType {
        case 0:
            let (value, newIndex) = decodeVarint(data, from: startIndex)
            guard value != nil else {
                throw GoogleMigrationParserError.invalidProtobuf
            }
            return newIndex
        case 2:
            let (_, newIndex) = try readLengthDelimited(data, from: startIndex)
            return newIndex
        case 5:
            return try advanceIndex(data, from: startIndex, by: 4)
        case 1:
            return try advanceIndex(data, from: startIndex, by: 8)
        default:
            throw GoogleMigrationParserError.invalidProtobuf
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
