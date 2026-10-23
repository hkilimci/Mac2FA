import SwiftUI

struct AccountRowView: View {
    let account: OTPAccount
    let model: AccountsModel

    var body: some View {
        HStack(spacing: 12) {
            AccountMonogram(name: account.issuer.isEmpty ? account.label : account.issuer)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 12)

            // Ticks on whole seconds so codes roll over exactly on their TOTP boundary.
            TimelineView(.periodic(from: .currentSecond, by: 1)) { context in
                CodeButton(
                    code: model.code(for: account, at: context.date),
                    isCopied: model.recentlyCopiedID == account.id
                ) {
                    model.copyCode(for: account)
                }
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Copy Code") {
            model.copyCode(for: account)
        }
    }

    private var title: String {
        if !account.issuer.isEmpty { return account.issuer }
        return account.label.isEmpty ? "Unnamed Account" : account.label
    }

    private var subtitle: String {
        account.issuer.isEmpty ? "" : account.label
    }
}

/// The current code and its countdown; clicking it copies the code.
private struct CodeButton: View {
    let code: OneTimeCode?
    let isCopied: Bool
    let copy: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: copy) {
            HStack(spacing: 10) {
                Text(code?.formatted ?? "––– –––")
                    .font(.system(.title2, design: .rounded, weight: .semibold).monospacedDigit())
                    .foregroundStyle(codeColor)
                    .contentTransition(.numericText())
                    .animation(.default, value: code?.value)

                ZStack {
                    if isCopied {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 17))
                            .foregroundStyle(.green)
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        CountdownRing(
                            fraction: code?.fractionRemaining ?? 0,
                            tint: code?.isExpiring == true ? .red : .accentColor
                        )
                        .transition(.opacity)
                    }
                }
                .frame(width: 18, height: 18)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(.quaternary)
                    .opacity(isHovering ? 1 : 0)
            }
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(code == nil)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .animation(.spring(duration: 0.3), value: isCopied)
        .help("Copy Code")
        .accessibilityLabel(Text(isCopied ? "Code copied" : "Code"))
        .accessibilityValue(spokenValue)
    }

    private var codeColor: Color {
        if isCopied { return .green }
        if code?.isExpiring == true { return .red }
        return .primary
    }

    private var spokenValue: String {
        guard let code else { return "Unavailable" }
        return "\(code.spoken), expires in \(code.secondsRemaining) seconds"
    }
}

/// Drains as the code's period runs out, the same ring as in the app icon.
private struct CountdownRing: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.2), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: fraction)
        }
        .padding(1.25)
    }
}

/// A colored tile with the account's initial, in the style of macOS app icons.
struct AccountMonogram: View {
    let name: String
    var size: CGFloat = 32

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
            .fill(color.gradient)
            .frame(width: size, height: size)
            .overlay {
                Text(initial)
                    .font(.system(size: size * 0.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }

    private var initial: String {
        guard let first = name.trimmingCharacters(in: .whitespaces).first else { return "?" }
        return String(first).uppercased()
    }

    private var color: Color {
        let palette: [Color] = [.blue, .indigo, .purple, .pink, .red, .orange, .green, .teal, .brown, .gray]
        let key = name.trimmingCharacters(in: .whitespaces).lowercased()
        guard !key.isEmpty else { return .gray }
        // FNV-1a, so each issuer keeps the same color across launches.
        var hash: UInt64 = 1469598103934665603
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        return palette[Int(hash % UInt64(palette.count))]
    }
}

private extension Date {
    /// Now, truncated to the whole second.
    static var currentSecond: Date {
        Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
    }
}
