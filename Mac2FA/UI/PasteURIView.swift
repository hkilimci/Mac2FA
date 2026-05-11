import SwiftUI

struct PasteURIView: View {
    var onDone: (Bool) -> Void
    @State private var uriText: String = ""
    @State private var drafts: [OTPAccountDraft] = []
    @State private var selectedIndices: Set<Int> = []
    @State private var showingPreview = false
    @State private var errorMessage: String?
    @State private var showingError = false

    private var selectableIndices: [Int] {
        drafts.indices.filter { drafts[$0].type == .totp }
    }

    private var allSelectableSelected: Bool {
        !selectableIndices.isEmpty && selectableIndices.allSatisfy { selectedIndices.contains($0) }
    }

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
                HStack {
                    Button(allSelectableSelected ? "Deselect All" : "Select All") {
                        if allSelectableSelected {
                            selectedIndices.removeAll()
                        } else {
                            selectedIndices = Set(selectableIndices)
                        }
                    }
                    .disabled(selectableIndices.isEmpty)
                    Spacer()
                    Text("\(selectedIndices.count) selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)

                List {
                    ForEach(drafts.indices, id: \.self) { index in
                        let draft = drafts[index]
                        HStack {
                            Toggle("", isOn: Binding(
                                get: { selectedIndices.contains(index) },
                                set: { isOn in
                                    if isOn {
                                        selectedIndices.insert(index)
                                    } else {
                                        selectedIndices.remove(index)
                                    }
                                }
                            ))
                            .labelsHidden()
                            .disabled(draft.type != .totp)
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
                    Button("Import Selected (\(selectedIndices.count))") {
                        importSelected()
                    }
                    .disabled(selectedIndices.isEmpty)
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
                let parsed = try GoogleMigrationParser.parse(trimmed)
                drafts = parsed
                selectedIndices = Set(parsed.indices.filter { parsed[$0].type == .totp })
                showingPreview = true
            } catch {
                errorMessage = "Failed to parse migration URI."
                showingError = true
            }
        } else if trimmed.hasPrefix("otpauth://") {
            do {
                let draft = try OTPAuthParser.parse(trimmed)
                drafts = [draft]
                selectedIndices = draft.type == .totp ? [0] : []
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

    private func importSelected() {
        let selected = selectedIndices.sorted().compactMap { drafts.indices.contains($0) ? drafts[$0] : nil }
        Task {
            var imported = 0
            for draft in selected {
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
