import Foundation

enum Base32Error: Error {
    case invalidCharacter
    case invalidLength
}

struct Base32 {
    private static let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
    private static let decodingTable: [Character: UInt8] = {
        var table: [Character: UInt8] = [:]
        for (i, c) in alphabet.enumerated() {
            table[c] = UInt8(i)
        }
        return table
    }()

    static func decode(_ string: String) throws -> Data {
        let cleaned = string
            .uppercased()
            .filter { $0 != " " && $0 != "-" }
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))

        guard !cleaned.isEmpty else {
            return Data()
        }

        var bits = 0
        var value = 0
        var result: [UInt8] = []

        for char in cleaned {
            guard let index = decodingTable[char] else {
                throw Base32Error.invalidCharacter
            }
            value = (value << 5) | Int(index)
            bits += 5
            if bits >= 8 {
                bits -= 8
                result.append(UInt8((value >> bits) & 0xFF))
            }
        }

        return Data(result)
    }
}
