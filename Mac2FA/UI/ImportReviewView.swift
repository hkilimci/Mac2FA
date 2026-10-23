import SwiftUI

/// Lists the accounts found in a link or QR code so the user can pick which to import.
struct ImportReviewView: View {
    @Binding var candidates: [ImportCandidate]

    @Environment(\.dismiss) private var dismiss
    @State private var isImporting = false
    @State private var summary: ImportSummary?

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Choose Accounts to Import", message: foundMessage)

            List {
                ForEach($candidates) { $candidate in
                    ImportCandidateRow(candidate: $candidate)
                }
            }
            .listStyle(.bordered)
            .padding(.horizontal, 20)
            .padding(.top, 12)

            HStack {
                Toggle("Select All", sources: supportedCandidates, isOn: \.isSelected)
                    .disabled(supportedCandidates.isEmpty)
                Spacer()
                Text("\(selectedDrafts.count) of \(supportedCandidates.count) selected")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)

            SheetFooter {
                Button("Back") {
                    candidates = []
                }
            } primary: {
                Button(importTitle, action: importSelected)
                    .disabled(selectedDrafts.isEmpty || isImporting)
            }
        }
        .alert(
            summary.map { summaryTitle($0) } ?? "",
            isPresented: Binding(
                get: { summary != nil },
                set: { if !$0 { summary = nil } }
            ),
            presenting: summary
        ) { _ in
            Button("OK") {
                dismiss()
            }
        } message: { summary in
            Text(summaryMessage(summary))
        }
    }

    private var supportedCandidates: [Binding<ImportCandidate>] {
        $candidates.filter { $0.wrappedValue.isSupported }
    }

    private var selectedDrafts: [OTPAccountDraft] {
        candidates.filter { $0.isSelected && $0.isSupported }.map(\.draft)
    }

    private var foundMessage: String {
        candidates.count == 1 ? "1 account was found." : "\(candidates.count) accounts were found."
    }

    private var importTitle: String {
        switch selectedDrafts.count {
        case 0, 1: return "Import"
        default: return "Import \(selectedDrafts.count) Accounts"
        }
    }

    private func importSelected() {
        let drafts = selectedDrafts
        isImporting = true
        Task { @MainActor in
            let result = await AccountStore.shared.importDrafts(drafts)
            isImporting = false
            if result.skipped == 0 {
                dismiss()
            } else {
                summary = result
            }
        }
    }

    private func summaryTitle(_ summary: ImportSummary) -> String {
        switch summary.imported {
        case 0: return "No Accounts Imported"
        case 1: return "1 Account Imported"
        default: return "\(summary.imported) Accounts Imported"
        }
    }

    private func summaryMessage(_ summary: ImportSummary) -> String {
        var lines: [String] = []
        if summary.duplicates > 0 {
            lines.append(summary.duplicates == 1
                ? "1 account was skipped because it's already in Mac2FA."
                : "\(summary.duplicates) accounts were skipped because they're already in Mac2FA.")
        }
        if summary.failed > 0 {
            lines.append(summary.failed == 1
                ? "1 account couldn't be added because its settings aren't supported."
                : "\(summary.failed) accounts couldn't be added because their settings aren't supported.")
        }
        return lines.joined(separator: " ")
    }
}

private struct ImportCandidateRow: View {
    @Binding var candidate: ImportCandidate

    var body: some View {
        HStack(spacing: 10) {
            Toggle(isOn: $candidate.isSelected) {
                HStack(spacing: 10) {
                    AccountMonogram(name: candidate.title, size: 24)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(candidate.title)
                            .lineLimit(1)
                        if !candidate.subtitle.isEmpty {
                            Text(candidate.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
            }
            .disabled(!candidate.isSupported)

            Spacer(minLength: 8)

            if candidate.isSupported {
                Text(candidate.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(candidate.detail)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .help("Mac2FA supports time-based (TOTP) codes only. Counter-based (HOTP) codes can't be imported.")
            }
        }
        .padding(.vertical, 3)
    }
}
