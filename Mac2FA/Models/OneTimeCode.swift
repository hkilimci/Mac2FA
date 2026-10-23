import Foundation

/// A TOTP code as it stands at one instant: the digits to show and how long they stay valid.
struct OneTimeCode: Equatable {
    let value: String
    let period: Int
    let secondsRemaining: Int

    init(value: String, period: Int, at date: Date) {
        self.value = value
        self.period = period
        self.secondsRemaining = TOTP.remainingSeconds(for: date, period: period)
    }

    /// Digits split into two groups for easier reading, e.g. "123 456" or "1234 5678".
    var formatted: String {
        guard value.count >= 6 else { return value }
        let mid = value.index(value.startIndex, offsetBy: value.count / 2)
        return String(value[..<mid]) + " " + String(value[mid...])
    }

    /// Code spoken digit by digit, so VoiceOver doesn't read it as one large number.
    var spoken: String {
        value.map(String.init).joined(separator: " ")
    }

    /// Share of the period left once the current second has elapsed, from 1 down to 0.
    var fractionRemaining: Double {
        guard period > 0 else { return 0 }
        return Double(max(secondsRemaining - 1, 0)) / Double(period)
    }

    /// The code is about to roll over, so it may expire before the user finishes typing it.
    var isExpiring: Bool {
        secondsRemaining <= 5
    }
}
