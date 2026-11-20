import SwiftUI
import UniformTypeIdentifiers

struct ExportAccountsView: View {
    let lock: AppLock

    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var confirmation = ""
    @State private var problem: String?
    @State private var savePanel: NSSavePanel?
    @State private var exportTask: Task<Void, Never>?

    private var passwordsMatch: Bool {
        password.utf8.elementsEqual(confirmation.utf8)
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                title: "Export Accounts",
                message: "Save a copy of all accounts and their setup keys."
            )

            VStack(alignment: .leading, spacing: 8) {
                SecureField("Password (optional)", text: $password)
                if !password.isEmpty {
                    SecureField("Confirm Password", text: $confirmation)
                }
                Group {
                    if password.isEmpty {
                        Label("Without a password, anyone who can open the file can read your setup keys.",
                              systemImage: "exclamationmark.triangle")
                    } else if !confirmation.isEmpty && !passwordsMatch {
                        Text("The passwords don’t match.")
                            .foregroundStyle(.red)
                    } else {
                        Text("Keep this password to open the encrypted export.")
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .textFieldStyle(.roundedBorder)
            .disabled(exportTask != nil)
            .padding(24)
            .onChange(of: password) {
                if password.isEmpty { confirmation = "" }
            }

            if let problem {
                Text(problem)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 24)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SheetFooter {
                if exportTask != nil {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Exporting accounts")
                }
            } primary: {
                Button("Export…") {
                    let exportPassword = password
                    exportTask = Task { await export(password: exportPassword) }
                }
                .disabled(exportTask != nil || (!password.isEmpty && !passwordsMatch) || lock.isLocked)
            }
        }
        .frame(width: 420)
        .onChange(of: lock.isLocked) {
            if lock.isLocked {
                cancelExport()
                dismiss()
            }
        }
        .onDisappear(perform: cancelExport)
    }

    private func export(password: String) async {
        defer { exportTask = nil }
        guard !Task.isCancelled, !lock.isLocked else { return }
        problem = nil

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.showsTagField = false
        panel.nameFieldStringValue = password.isEmpty ? "Mac2FA Accounts.json" : "Mac2FA Accounts (Encrypted).json"
        savePanel = panel
        let response = await panel.begin()
        savePanel = nil

        guard !Task.isCancelled, !lock.isLocked else { return }
        guard response != .abort else {
            problem = "Mac2FA couldn’t open the save dialog."
            return
        }
        guard response == .OK, let url = panel.url else { return }

        do {
            let data = try await AccountStore.shared.exportAccounts(password: password)
            guard !Task.isCancelled, !lock.isLocked else { return }
            try AccountExport.write(data, to: url)
            dismiss()
        } catch {
            guard !Task.isCancelled, !lock.isLocked else { return }
            problem = error.localizedDescription
        }
    }

    private func cancelExport() {
        exportTask?.cancel()
        savePanel?.cancel(nil)
    }
}
