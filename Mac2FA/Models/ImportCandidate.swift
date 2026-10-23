import Foundation

/// An account found in a link or QR code, waiting for the user to decide whether to import it.
struct ImportCandidate: Identifiable {
    let id = UUID()
    let draft: OTPAccountDraft
    var isSelected: Bool

    init(draft: OTPAccountDraft) {
        self.draft = draft
        self.isSelected = draft.type == .totp
    }

    /// Only time-based codes can be stored; counter-based (HOTP) entries are shown but not imported.
    var isSupported: Bool {
        draft.type == .totp
    }

    var title: String {
        if !draft.issuer.isEmpty { return draft.issuer }
        return draft.label.isEmpty ? "Unknown" : draft.label
    }

    var subtitle: String {
        draft.issuer.isEmpty ? "" : draft.label
    }

    var detail: String {
        isSupported ? "\(draft.digits) digits · \(draft.period)s" : "Not Supported"
    }
}

enum OTPPayloadError: Error {
    case unrecognizedFormat
}

/// Text carried by an authenticator link or QR code.
enum OTPPayload {
    /// Accounts encoded by an `otpauth://` link or a Google Authenticator `otpauth-migration://` link.
    static func drafts(from payload: String) throws -> [OTPAccountDraft] {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("otpauth-migration://") {
            return try GoogleMigrationParser.parse(trimmed)
        }
        if trimmed.hasPrefix("otpauth://") {
            return [try OTPAuthParser.parse(trimmed)]
        }
        throw OTPPayloadError.unrecognizedFormat
    }

    /// Accounts from text that may hold several links, one per line.
    static func drafts(fromLines text: String) throws -> [OTPAccountDraft] {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { throw OTPPayloadError.unrecognizedFormat }
        return try lines.flatMap { try drafts(from: $0) }
    }
}
