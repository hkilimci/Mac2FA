import Foundation
import CryptoKit

enum HOTPError: Error {
    case invalidDigits
    case invalidSecret
}

struct HOTP {
    static func generate(secret: Data, counter: UInt64, algorithm: OTPAlgorithm, digits: Int) throws -> String {
        guard digits == 6 || digits == 7 || digits == 8 else {
            throw HOTPError.invalidDigits
        }
        guard !secret.isEmpty else {
            throw HOTPError.invalidSecret
        }

        var counterBigEndian = counter.bigEndian
        let counterData = Data(bytes: &counterBigEndian, count: MemoryLayout<UInt64>.size)

        let hash: Data
        switch algorithm {
        case .sha1:
            hash = Data(HMAC<Insecure.SHA1>.authenticationCode(for: counterData, using: .init(data: secret)))
        case .sha256:
            hash = Data(HMAC<SHA256>.authenticationCode(for: counterData, using: .init(data: secret)))
        case .sha512:
            hash = Data(HMAC<SHA512>.authenticationCode(for: counterData, using: .init(data: secret)))
        }

        let otp = dynamicTruncation(hash: hash)
        let code = otp % UInt32(pow(10.0, Double(digits)))
        return String(format: "%0\(digits)d", code)
    }

    private static func dynamicTruncation(hash: Data) -> UInt32 {
        let offset = Int(hash[hash.count - 1] & 0x0F)
        let truncated = hash.subdata(in: offset..<offset + 4)
        var number = truncated.withUnsafeBytes { $0.load(as: UInt32.self) }
        number = UInt32(bigEndian: number)
        number = number & 0x7FFF_FFFF
        return number
    }
}
