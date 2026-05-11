import SwiftUI

struct PasteURIView: View {
    var onDone: (Bool) -> Void
    @State private var uriText: String = ""
    @State private var drafts: [OTPAccountDraft] = []
    @State private var showingPreview = false
    @State private var errorMessage: String?
    @State private var showingError = false

    var body: some View {
        VStack {
            if !showingPreview {
                TextEditor(text: $uriText)
                    .font(.system(.body, design: .monospaced))
                    .border(Color.secondary.opacity(0.2))
                    .padding()

                Button("Parse") {
                    parseURI()
                }
                .disabled(uriText.isEmpty)
                .padding()
            } else {
                List {
                    ForEach(drafts.indices, id: \.self) { index in
                        let draft = drafts[index]
                        HStack {
                            VStack(alignment: .leading) {
                                Text(draft.issuer.isEmpty ? "Unknown" : draft.issuer)
                                    .font(.headline)
                                Text(draft.label)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if draft.type == .hotp {
                                Text("HOTP (unsupported)")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            } else {
                                Text("TOTP \(draft.digits) digits")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                HStack {
                    Button("Back") {
                        showingPreview = false
                    }
                    Button("Import All") {
                        importAll()
                    }
                    .disabled(drafts.filter { $0.type == .totp }.isEmpty)
                }
                .padding()
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
        .padding()
    }

    private func parseURI() {
        let trimmed = uriText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("otpauth-migration://") {
            do {
                drafts = try GoogleMigrationParser.parse(trimmed)
                showingPreview = true
            } catch {
                errorMessage = "Failed to parse migration URI."
                showingError = true
            }
        } else if trimmed.hasPrefix("otpauth://") {
            do {
                let draft = try OTPAuthParser.parse(trimmed)
                drafts = [draft]
                showingPreview = true
            } catch {
                errorMessage = "Failed to parse otpauth URI."
                showingError = true
            }
        } else {
            errorMessage = "Unrecognized URI format."
            showingError = true
        }
    }

    private func importAll() {
        Task {
            var imported = 0
            for draft in drafts {
                guard draft.type == .totp else { continue }
                do {
                    _ = try await AccountStore.shared.addAccount(draft: draft)
                    imported += 1
                } catch AccountStoreError.duplicateAccount {
                    // Skip duplicates silently for minimal implementation
                } catch {
                    // Skip failed imports
                }
            }
            await MainActor.run {
                onDone(imported > 0)
            }
        }
    }
}
