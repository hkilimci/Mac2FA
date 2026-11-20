import SwiftUI
import UniformTypeIdentifiers

struct ImportAccountsView: View {
    let lock: AppLock

    @Environment(\.dismiss) private var dismiss
    @State private var isChoosingFile = false
    @State private var work: Task<Void, Never>?
    @State private var backup: AccountExport.Backup?
    @State private var filename = ""
    @State private var password = ""
    @State private var problem: String?
    @State private var summary: ImportSummary?

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                title: "Import Accounts",
                message: "Restore accounts from a Mac2FA export. Existing accounts are kept."
            )

            VStack(alignment: .leading, spacing: 8) {
                if backup != nil {
                    Label(filename, systemImage: "doc")
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if backup?.requiresPassword == true {
                    SecureField("Export Password", text: $password)
                        .textFieldStyle(.roundedBorder)
                        .disabled(work != nil)
                }
                if let problem {
                    Text(problem)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)

            SheetFooter {
                if work != nil {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Reading or importing accounts")
                } else if backup != nil {
                    Button("Choose Another File…") { isChoosingFile = true }
                }
            } primary: {
                if let backup {
                    Button("Import") { startImport(backup) }
                        .disabled(work != nil || lock.isLocked || (backup.requiresPassword && password.isEmpty))
                } else {
                    Button("Choose File…") { isChoosingFile = true }
                        .disabled(work != nil || lock.isLocked)
                }
            }
        }
        .frame(width: 440)
        .fileImporter(isPresented: $isChoosingFile, allowedContentTypes: [.json]) { selection in
            switch selection {
            case .success(let url):
                loadFile(url)
            case .failure:
                problem = "Mac2FA couldn’t open the selected file."
            }
        }
        .alert("Account Import", isPresented: Binding(
            get: { summary != nil },
            set: { if !$0 { summary = nil } }
        ), presenting: summary) { _ in
            Button("Done") { dismiss() }
        } message: { result in
            Text(summaryMessage(result))
        }
        .onChange(of: lock.isLocked) {
            if lock.isLocked {
                work?.cancel()
                dismiss()
            }
        }
        .onDisappear { work?.cancel() }
    }

    private func loadFile(_ url: URL) {
        guard !lock.isLocked, work == nil else { return }
        backup = nil
        password = ""
        problem = nil

        work = Task {
            defer { work = nil }
            do {
                let decoded = try await Task.detached {
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    let data = try Data(contentsOf: url, options: .mappedIfSafe)
                    return try AccountExport.decode(data)
                }.value
                guard !Task.isCancelled, !lock.isLocked else { return }
                filename = url.lastPathComponent
                backup = decoded
            } catch {
                guard !Task.isCancelled, !lock.isLocked else { return }
                problem = (error as? AccountImportError)?.localizedDescription
                    ?? "Mac2FA couldn’t read the selected file."
            }
        }
    }

    private func startImport(_ backup: AccountExport.Backup) {
        guard !lock.isLocked, work == nil else { return }
        let enteredPassword = password
        problem = nil

        work = Task {
            defer { work = nil }
            do {
                let entries = try await Task.detached {
                    try backup.entries(password: enteredPassword)
                }.value
                guard !Task.isCancelled, !lock.isLocked else { return }
                let result = try await AccountStore.shared.importBackup(entries)
                guard !Task.isCancelled, !lock.isLocked else { return }
                password = ""
                summary = result
            } catch {
                guard !Task.isCancelled, !lock.isLocked else { return }
                problem = (error as? AccountImportError)?.localizedDescription
                    ?? "Mac2FA couldn’t import the selected file."
            }
        }
    }

    private func summaryMessage(_ result: ImportSummary) -> String {
        var lines = [result.imported == 1 ? "1 account imported." : "\(result.imported) accounts imported."]
        if result.duplicates > 0 {
            lines.append(result.duplicates == 1
                ? "1 existing account skipped."
                : "\(result.duplicates) existing accounts skipped.")
        }
        if result.skippedWebsites > 0 {
            lines.append(result.skippedWebsites == 1
                ? "1 conflicting or invalid website assignment skipped."
                : "\(result.skippedWebsites) conflicting or invalid website assignments skipped.")
        }
        return lines.joined(separator: " ")
    }
}
