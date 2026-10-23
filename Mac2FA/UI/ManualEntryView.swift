import SwiftUI

struct ManualEntryView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var issuer = ""
    @State private var label = ""
    @State private var secret = ""
    @State private var algorithm: OTPAlgorithm = .sha1
    @State private var digits = 6
    @State private var period = 30
    @State private var showsAdvanced = false
    @State private var isSaving = false
    @State private var failure: SaveFailure?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Issuer", text: $issuer, prompt: Text("Example Inc."))
                    TextField("Account", text: $label, prompt: Text("name@example.com"))
                }

                Section {
                    TextField(text: $secret, prompt: Text("JBSW Y3DP EHPK 3PXP")) {
                        Text("Setup Key")
                            .font(.body)
                    }
                    .font(.body.monospaced())
                    .autocorrectionDisabled()
                } footer: {
                    if let secretProblem {
                        Label(secretProblem, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    } else {
                        Text("The setup key is shown next to the QR code when you turn on two-factor authentication.")
                    }
                }

                Section {
                    DisclosureGroup("Advanced", isExpanded: $showsAdvanced) {
                        Picker("Algorithm", selection: $algorithm) {
                            ForEach(OTPAlgorithm.allCases, id: \.self) { algorithm in
                                Text(algorithm.displayName).tag(algorithm)
                            }
                        }
                        Picker("Digits", selection: $digits) {
                            Text("6").tag(6)
                            Text("7").tag(7)
                            Text("8").tag(8)
                        }
                        Picker("Period", selection: $period) {
                            Text("30 seconds").tag(30)
                            Text("60 seconds").tag(60)
                        }
                    }
                } footer: {
                    Text("Change these only if the service asks you to. Most use SHA-1, 6 digits and 30 seconds.")
                }
            }
            .formStyle(.grouped)

            SheetFooter {
                Button("Add Account", action: save)
                    .disabled(!canSave)
            }
        }
        .alert(
            failure?.title ?? "",
            isPresented: Binding(
                get: { failure != nil },
                set: { if !$0 { failure = nil } }
            ),
            presenting: failure
        ) { _ in
            Button("OK") {}
        } message: { failure in
            Text(failure.message)
        }
    }

    private var normalizedSecret: String {
        secret.filter { !$0.isWhitespace }
    }

    /// Explains what's wrong with the setup key as the user types, instead of after they press Add.
    private var secretProblem: String? {
        guard !normalizedSecret.isEmpty else { return nil }
        guard let data = try? Base32.decode(normalizedSecret), !data.isEmpty else {
            return "A setup key only contains the letters A–Z and the digits 2–7."
        }
        return nil
    }

    private var canSave: Bool {
        !issuer.trimmingCharacters(in: .whitespaces).isEmpty &&
        !label.trimmingCharacters(in: .whitespaces).isEmpty &&
        !normalizedSecret.isEmpty &&
        secretProblem == nil &&
        !isSaving
    }

    private func save() {
        guard canSave, let secretData = try? Base32.decode(normalizedSecret) else { return }
        let draft = OTPAccountDraft(
            issuer: issuer.trimmingCharacters(in: .whitespaces),
            label: label.trimmingCharacters(in: .whitespaces),
            secretData: secretData,
            algorithm: algorithm,
            digits: digits,
            period: period,
            type: .totp,
            counter: nil
        )
        isSaving = true
        Task { @MainActor in
            do {
                _ = try await AccountStore.shared.addAccount(draft: draft)
                dismiss()
            } catch AccountStoreError.duplicateAccount {
                failure = SaveFailure(
                    title: "Account Already Added",
                    message: "Mac2FA already has an account for \(draft.issuer) (\(draft.label))."
                )
            } catch {
                failure = SaveFailure(
                    title: "Couldn't Add Account",
                    message: "Check that the setup key and options match what the service shows."
                )
            }
            isSaving = false
        }
    }
}

private struct SaveFailure {
    let title: String
    let message: String
}

private extension OTPAlgorithm {
    var displayName: String {
        switch self {
        case .sha1: return "SHA-1"
        case .sha256: return "SHA-256"
        case .sha512: return "SHA-512"
        }
    }
}
