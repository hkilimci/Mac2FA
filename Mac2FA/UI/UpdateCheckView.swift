import SwiftUI

struct UpdateCheckView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var isChecking = true
    @State private var result: UpdateCheckResult?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: iconName)
                    .font(.system(size: 28))
                    .foregroundStyle(iconColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
            }

            if case .updateAvailable(_, _, _, let notes) = result, let notes, !notes.isEmpty {
                Divider()
                Text("Release Notes").font(.subheadline).bold()
                ScrollView {
                    Text(notes)
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 180)
            }

            HStack {
                Button("Recheck") { Task { await runCheck() } }
                    .disabled(isChecking)
                Spacer()
                if case .updateAvailable(_, _, let url, _) = result {
                    Button("Download") { openURL(url) }
                        .keyboardShortcut(.defaultAction)
                }
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 460)
        .task { await runCheck() }
    }

    private var iconName: String {
        if isChecking { return "arrow.triangle.2.circlepath" }
        if errorMessage != nil { return "exclamationmark.triangle.fill" }
        switch result {
        case .updateAvailable: return "arrow.down.circle.fill"
        case .upToDate: return "checkmark.circle.fill"
        case .none: return "questionmark.circle"
        }
    }

    private var iconColor: Color {
        if errorMessage != nil { return .orange }
        switch result {
        case .updateAvailable: return .accentColor
        case .upToDate: return .green
        default: return .secondary
        }
    }

    private var title: String {
        if isChecking { return "Checking for updates…" }
        if errorMessage != nil { return "Update check failed" }
        switch result {
        case .updateAvailable(_, let latest, _, _): return "Version \(latest) is available"
        case .upToDate: return "You're up to date"
        case .none: return "Check for Updates"
        }
    }

    private var subtitle: String {
        if let errorMessage { return errorMessage }
        let current = UpdateChecker.currentVersion
        switch result {
        case .updateAvailable(let cur, _, _, _): return "Installed: \(cur)"
        case .upToDate: return "Installed: \(current)"
        case .none: return "Installed: \(current)"
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
