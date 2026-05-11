import Foundation

enum TOTPError: Error {
    case invalidPeriod
}

struct TOTP {
    static func generate(secret: Data, time: Date = Date(), period: Int = 30, algorithm: OTPAlgorithm = .sha1, digits: Int = 6) throws -> String {
        guard period > 0 else {
            throw TOTPError.invalidPeriod
        }
        let counter = UInt64(floor(time.timeIntervalSince1970 / Double(period)))
        return try HOTP.generate(secret: secret, counter: counter, algorithm: algorithm, digits: digits)
    }

    static func remainingSeconds(for time: Date = Date(), period: Int = 30) -> Int {
        let epoch = Int(time.timeIntervalSince1970)
        return period - (epoch % period)
    }
}
