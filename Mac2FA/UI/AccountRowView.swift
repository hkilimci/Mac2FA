import SwiftUI

struct AccountRowView: View {
    let account: OTPAccount
    @State private var code: String = ""
    @State private var remaining: Int = 30
    @State private var timer: Timer? = nil
    @State private var showCopied = false

    private let codeColor = Color(red: 0.13, green: 0.31, blue: 0.49)

    var body: some View {
        HStack(spacing: 14) {
            MonogramTile(issuer: account.issuer)

            VStack(alignment: .leading, spacing: 2) {
                Text(account.issuer)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(account.label)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Text(formattedCode)
                .font(.system(size: 22, weight: .regular, design: .monospaced))
                .foregroundStyle(codeColor)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()

            CountdownRing(remaining: remaining, period: account.period, tint: codeColor)
                .frame(width: 26, height: 26)

            Button(action: copyCode) {
                Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(showCopied ? .green : .secondary)
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .contentShape(Rectangle())
        .onTapGesture { copyCode() }
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
        if account.digits == 8 {
            let mid = code.index(code.startIndex, offsetBy: 4)
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
            Task { @MainActor in
                updateCode()
            }
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

private struct MonogramTile: View {
    let issuer: String

    var body: some View {
        let color = MonogramPalette.color(for: issuer)
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(color.opacity(0.18))
            .frame(width: 40, height: 40)
            .overlay(
                Text(initial)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(color)
            )
    }

    private var initial: String {
        guard let first = issuer.trimmingCharacters(in: .whitespaces).first else { return "?" }
        return String(first)
    }
}

private struct CountdownRing: View {
    let remaining: Int
    let period: Int
    let tint: Color

    var body: some View {
        let progress = period > 0 ? Double(remaining) / Double(period) : 0
        ZStack {
            Circle()
                .stroke(tint.opacity(0.18), lineWidth: 2)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.5), value: remaining)
            Text("\(remaining)")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
        }
    }
}

private enum MonogramPalette {
    private static let colors: [Color] = [
        Color(red: 0.36, green: 0.65, blue: 0.86), // blue
        Color(red: 0.62, green: 0.49, blue: 0.86), // purple
        Color(red: 0.40, green: 0.76, blue: 0.55), // green
        Color(red: 0.95, green: 0.66, blue: 0.36), // orange
        Color(red: 0.93, green: 0.45, blue: 0.62), // pink
        Color(red: 0.36, green: 0.74, blue: 0.78), // teal
        Color(red: 0.86, green: 0.55, blue: 0.36), // amber
        Color(red: 0.55, green: 0.62, blue: 0.86), // indigo
    ]

    static func color(for issuer: String) -> Color {
        let key = issuer.trimmingCharacters(in: .whitespaces).lowercased()
        guard !key.isEmpty else { return colors[0] }
        var hash: UInt64 = 1469598103934665603
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        return colors[Int(hash % UInt64(colors.count))]
    }
}
