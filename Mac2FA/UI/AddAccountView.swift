import SwiftUI

/// The ways an account can be brought into Mac2FA.
enum AddAccountMethod: String, CaseIterable, Identifiable {
    case setupKey
    case link
    case qrCode

    var id: Self { self }

    var title: String {
        switch self {
        case .setupKey: return "Setup Key"
        case .link: return "Link"
        case .qrCode: return "QR Code"
        }
    }
}

struct AddAccountView: View {
    @State private var method: AddAccountMethod = .setupKey
    /// Accounts found by a link or QR code; while non-empty, the sheet shows them for review.
    @State private var candidates: [ImportCandidate] = []

    var body: some View {
        Group {
            if candidates.isEmpty {
                VStack(spacing: 0) {
                    SheetHeader(
                        title: "Add Account",
                        message: "Codes are generated on this Mac and secrets are kept in your keychain."
                    ) {
                        Picker("Method", selection: $method) {
                            ForEach(AddAccountMethod.allCases) { method in
                                Text(method.title).tag(method)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }

                    switch method {
                    case .setupKey:
                        ManualEntryView()
                    case .link:
                        PasteURIView { candidates = $0 }
                    case .qrCode:
                        QRImageImportView { candidates = $0 }
                    }
                }
            } else {
                ImportReviewView(candidates: $candidates)
            }
        }
        .frame(width: 480, height: 540)
    }
}

/// Title, explanation and optional control at the top of a sheet.
struct SheetHeader<Accessory: View>: View {
    let title: String
    let message: String
    let accessory: Accessory

    init(title: String, message: String, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.message = message
        self.accessory = accessory()
    }

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            accessory
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 4)
    }
}

extension SheetHeader where Accessory == EmptyView {
    init(title: String, message: String) {
        self.init(title: title, message: message) { EmptyView() }
    }
}

/// Bottom button row of a sheet: an optional leading action, then Cancel and the default action.
struct SheetFooter<Leading: View, Primary: View>: View {
    let leading: Leading
    let primary: Primary

    @Environment(\.dismiss) private var dismiss

    init(@ViewBuilder leading: () -> Leading, @ViewBuilder primary: () -> Primary) {
        self.leading = leading()
        self.primary = primary()
    }

    var body: some View {
        HStack(spacing: 12) {
            leading
            Spacer()
            Button("Cancel", role: .cancel) {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            primary
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}

extension SheetFooter where Leading == EmptyView {
    init(@ViewBuilder primary: () -> Primary) {
        self.init(leading: { EmptyView() }, primary: primary)
    }
}
