import LocalAuthentication
import Observation

@MainActor
@Observable
final class AppLock {
    private static let preference = "requireDeviceAuthentication"

    private(set) var requiresAuthentication =
        UserDefaults.standard.object(forKey: preference) as? Bool ?? true
    private(set) var isUnlocked = false
    private(set) var isAuthenticating = false
    private(set) var error: String?
    private(set) var sessionAvailable = true
    @ObservationIgnored private var context: LAContext?

    var isLocked: Bool { !sessionAvailable || (requiresAuthentication && !isUnlocked) }

    func unlock() async {
        guard sessionAvailable, isLocked else { return }
        await authenticate(reason: "Unlock Mac2FA to show your verification codes.") {
            self.isUnlocked = true
        }
    }

    func setAuthenticationRequired(_ required: Bool) async {
        guard sessionAvailable, required != requiresAuthentication else { return }
        if required {
            saveAuthenticationPreference(true)
        } else {
            await authenticate(reason: "Allow Mac2FA to show codes without unlocking.") {
                self.saveAuthenticationPreference(false)
            }
        }
    }

    private func saveAuthenticationPreference(_ required: Bool) {
        requiresAuthentication = required
        UserDefaults.standard.set(required, forKey: Self.preference)
        isUnlocked = false
    }

    func lock() {
        isUnlocked = false
        context?.invalidate()
        context = nil
        error = nil
    }

    func setSessionAvailable(_ available: Bool) {
        sessionAvailable = available
        if !available { lock() }
    }

    private func authenticate(reason: String, onSuccess: () -> Void) async {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        error = nil
        let attempt = LAContext()
        context = attempt
        defer {
            context = nil
            isAuthenticating = false
        }

        do {
            let accepted = try await attempt.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            if context === attempt && accepted { onSuccess() }
        } catch {
            if context === attempt, (error as? LAError)?.code != .userCancel {
                self.error = error.localizedDescription
            }
        }
    }
}
