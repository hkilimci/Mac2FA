import SwiftUI

struct ManualEntryView: View {
    var onDone: (Bool) -> Void
    @State private var issuer: String = ""
    @State private var label: String = ""
    @State private var secret: String = ""
    @State private var algorithm: OTPAlgorithm = .sha1
    @State private var digits: Int = 6
    @State private var period: Int = 30
    @State private var errorMessage: String?
    @State private var showingError = false

    var body: some View {
        Form {
            Section {
                TextField("Issuer", text: $issuer)
                TextField("Account Label", text: $label)
                TextField("Secret (Base32)", text: $secret)
                    .textFieldStyle(.roundedBorder)
                Picker("Algorithm", selection: $algorithm) {
                    ForEach(OTPAlgorithm.allCases, id: \.self) { algo in
                        Text(algo.rawValue.uppercased()).tag(algo)
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

            Section {
                Button("Save Account") {
                    saveAccount()
                }
                .disabled(issuer.isEmpty || label.isEmpty || secret.isEmpty)
            }
        }
        .formStyle(.grouped)
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
        .padding()
    }

    private func saveAccount() {
        do {
            let secretData = try Base32.decode(secret)
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
            Task {
                do {
                    _ = try await AccountStore.shared.addAccount(draft: draft)
                    await MainActor.run { onDone(true) }
                } catch AccountStoreError.duplicateAccount {
                    await MainActor.run {
                        errorMessage = "An account with this issuer and label already exists."
                        showingError = true
                    }
                } catch {
                    await MainActor.run {
                        errorMessage = error.localizedDescription
                        showingError = true
                    }
                }
            }
        } catch Base32Error.invalidCharacter {
            errorMessage = "Secret contains invalid characters."
            showingError = true
        } catch {
            errorMessage = "Invalid secret."
            showingError = true
        }
    }
}
