import AppKit
import SwiftUI

struct UpdateCheckView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var isChecking = true
    @State private var result: UpdateCheckResult?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.headline)
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if isChecking {
                        ProgressView()
                            .progressViewStyle(.linear)
                            .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if case .updateAvailable(_, _, _, let notes) = result, let notes, !notes.isEmpty {
                GroupBox {
                    ScrollView {
                        Text(notes)
                            .font(.callout)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(4)
                    }
                    .frame(maxHeight: 180)
                } label: {
                    Text("Release Notes")
                }
            }

            HStack(spacing: 12) {
                if errorMessage != nil {
                    Button("Try Again") {
                        Task { await runCheck() }
                    }
                }
                Spacer()
                buttons
            }
        }
        .padding(20)
        .frame(width: 440)
        .task { await runCheck() }
    }

    @ViewBuilder
    private var buttons: some View {
        if case .updateAvailable(_, _, let url, _) = result {
            Button("Not Now") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Download") {
                openURL(url)
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        } else {
            Button(isChecking ? "Cancel" : "OK") { dismiss() }
                .keyboardShortcut(isChecking ? KeyboardShortcut.cancelAction : KeyboardShortcut.defaultAction)
        }
    }

    private var title: String {
        if isChecking { return "Checking for Updates…" }
        if errorMessage != nil { return "Couldn't Check for Updates" }
        switch result {
        case .updateAvailable(_, let latest, _, _): return "Mac2FA \(latest) Is Available"
        case .upToDate: return "Mac2FA Is Up to Date"
        case .none: return "Check for Updates"
        }
    }

    private var message: String {
        if let errorMessage { return errorMessage }
        let current = UpdateChecker.currentVersion
        switch result {
        case .updateAvailable(let installed, _, _, _): return "You have version \(installed). Download the new version from GitHub."
        case .upToDate: return "Version \(current) is the latest version."
        case .none: return "You have version \(current)."
        }
    }

    private func runCheck() async {
        isChecking = true
        errorMessage = nil
        result = nil
        do {
            result = try await UpdateChecker().check()
        } catch {
            errorMessage = error.localizedDescription
        }
        isChecking = false
    }
}
