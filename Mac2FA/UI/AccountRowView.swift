import SwiftUI

struct AccountRowView: View {
    let account: OTPAccount
    @State private var code: String = ""
    @State private var remaining: Int = 30
    @State private var timer: Timer? = nil
    @State private var showCopied = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(account.issuer)
                    .font(.headline)
                Text(account.label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Text(formattedCode)
                        .font(.system(.title2, design: .monospaced))
                        .fontWeight(.semibold)
                    Text("Expires in \(remaining)s")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(action: copyCode) {
                Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                    .foregroundStyle(showCopied ? .green : .primary)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            copyCode()
        }
        .overlay(alignment: .center) {
            if showCopied {
                Text("Copied to clipboard")
                    .font(.callout)
                    .fontWeight(.medium)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.green.opacity(0.5), lineWidth: 1))
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .task {
            updateCode()
            startTimer()
        }
        .onDisappear {
            timer?.invalidate()
        }
    }

    private var formattedCode: String {
        guard code.count == account.digits else { return code }
        if account.digits == 6 {
            let mid = code.index(code.startIndex, offsetBy: 3)
            return String(code[..<mid]) + " " + String(code[mid...])
        }
        return code
    }

    private func updateCode() {
        guard account.type == .totp else {
            code = "HOTP not supported"
            return
        }
        Task {
            guard let secret = await AccountStore.shared.getSecret(for: account) else {
                await MainActor.run { code = "Error" }
                return
            }
            do {
                let newCode = try TOTP.generate(
                    secret: secret,
                    time: TimeProvider.now(),
                    period: account.period,
                    algorithm: account.algorithm,
                    digits: account.digits
                )
                let newRemaining = TOTP.remainingSeconds(for: TimeProvider.now(), period: account.period)
                await MainActor.run {
                    self.code = newCode
                    self.remaining = newRemaining
                }
            } catch {
                await MainActor.run { self.code = "Error" }
            }
        }
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            updateCode()
        }
    }

    private func copyCode() {
        let cleanCode = code.replacingOccurrences(of: " ", with: "")
        Task {
            await ClipboardManager.shared.copyCode(cleanCode)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showCopied = true
                }
            }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showCopied = false
                }
            }
        }
    }
}
