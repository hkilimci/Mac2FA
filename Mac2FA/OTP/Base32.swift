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

    static func encode(_ data: Data) -> String {
        let symbols = Array(alphabet.utf8)
        var result: [UInt8] = []
        var buffer: UInt16 = 0
        var bits = 0

        for byte in data {
            buffer = (buffer << 8) | UInt16(byte)
            bits += 8
            while bits >= 5 {
                bits -= 5
                result.append(symbols[Int((buffer >> bits) & 31)])
            }
        }
        if bits > 0 {
            result.append(symbols[Int((buffer << (5 - bits)) & 31)])
        }
        return String(decoding: result, as: UTF8.self)
    }

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
