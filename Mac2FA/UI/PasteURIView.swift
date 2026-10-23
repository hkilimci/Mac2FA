import SwiftUI

struct PasteURIView: View {
    /// Called with the accounts found in the pasted links.
    let onFound: ([ImportCandidate]) -> Void

    @State private var text = ""
    @State private var problem: String?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextEditor(text: $text)
                        .font(.body.monospaced())
                        .autocorrectionDisabled()
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 150)
                        .accessibilityLabel("Links")
                } footer: {
                    if let problem {
                        Label(problem, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    } else {
                        Text("Paste an otpauth:// link, or an otpauth-migration:// link exported from Google Authenticator. Put each link on its own line.")
                    }
                }
            }
            .formStyle(.grouped)
            .onChange(of: text) {
                problem = nil
            }

            SheetFooter {
                Button("Continue", action: parse)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func parse() {
        do {
            let drafts = try OTPPayload.drafts(fromLines: text)
            guard !drafts.isEmpty else {
                problem = "No accounts were found in this link."
                return
            }
            onFound(drafts.map(ImportCandidate.init(draft:)))
        } catch {
            problem = "This isn't a valid otpauth:// or otpauth-migration:// link."
        }
    }
}
