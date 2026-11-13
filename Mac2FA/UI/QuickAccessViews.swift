import ServiceManagement
import SwiftUI

struct LockButton: View {
    @Environment(QuickAccess.self) private var access

    var body: some View {
        if access.lock.requiresAuthentication {
            Button {
                if access.lock.isLocked {
                    Task { await access.unlock() }
                } else {
                    access.lockNow()
                }
            } label: {
                Label(access.lock.isLocked ? "Unlock Mac2FA" : "Lock Mac2FA",
                      systemImage: access.lock.isLocked ? "lock.fill" : "lock.open")
            }
            .disabled(access.lock.isAuthenticating)
        }
    }
}

struct CopyRequestButtons: View {
    @Environment(QuickAccess.self) private var access

    var body: some View {
        if let request = access.linkRequest,
           let account = access.model.accounts.first(where: { $0.id == request.accountID }) {
            HStack {
                Text("Link requests a code for \(account.displayName).")
                Spacer()
                Button("Dismiss") { access.dismissLink() }
                copyButton(request)
            }
            .padding(10)
        }
        if let request = access.websiteSuggestion,
           let website = request.website,
           let account = access.model.accounts.first(where: { $0.id == request.accountID }) {
            HStack {
                VStack(alignment: .leading) {
                    Text(account.displayName)
                    Text(website.address)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                copyButton(request)
            }
            .padding(10)
        }
    }

    private func copyButton(_ request: QuickAccess.CopyRequest) -> some View {
        Button(access.lock.isLocked ? "Unlock and Copy" : "Copy Code") {
            Task { await access.confirm(request) }
        }
        .disabled(access.lock.isAuthenticating)
    }
}

struct QuickAccessMenu: View {
    @Environment(QuickAccess.self) private var access
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CopyRequestButtons()
            if let error = access.lock.error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            if access.model.accounts.isEmpty {
                Text("No accounts yet.").foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(access.model.accounts) { account in
                            Button {
                                Task { await access.copy(account) }
                            } label: {
                                HStack {
                                    Text(account.displayName)
                                    Spacer()
                                    if access.lock.isLocked {
                                        Image(systemName: "lock")
                                    } else {
                                        TimelineView(.periodic(from: .now, by: 1)) { context in
                                            Text(access.model.code(for: account, at: context.date)?.formatted ?? "—")
                                                .monospacedDigit()
                                        }
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("Copy code for \(account.displayName)")
                        }
                    }
                    .padding(2)
                }
                .frame(maxHeight: 240)
            }
            Divider()
            HStack {
                Button("Open Mac2FA") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                LockButton()
                Spacer()
                SettingsLink { Image(systemName: "gear") }
                    .help("Settings")
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(12)
        .frame(width: 350)
    }
}

struct QuickAccessSettings: View {
    @Environment(QuickAccess.self) private var access
    @State private var loginStatus = SMAppService.mainApp.status
    @State private var loginError: String?

    var body: some View {
        @Bindable var access = access
        TabView {
            Form {
                Section("App Lock") {
                    Toggle("Require Touch ID or Mac password", isOn: Binding(
                        get: { access.lock.requiresAuthentication },
                        set: { required in Task { await access.setAuthenticationRequired(required) } }
                    ))
                    .disabled(access.lock.isAuthenticating)
                    if let error = access.lock.error {
                        Text(error).foregroundStyle(.red)
                    }
                }
                Section("Shortcuts") {
                    Toggle("Enable global copy shortcut (⌥⌘C)", isOn: $access.shortcutEnabled)
                    Text("Copies the last account used, or the first account if you haven't copied a code.")
                        .foregroundStyle(.secondary)
                    if access.shortcutUnavailable {
                        Text("The shortcut could not be registered. Check for a conflicting shortcut.")
                            .foregroundStyle(.red)
                    }
                    Toggle("Open at Login", isOn: Binding(
                        get: { loginStatus == .enabled || loginStatus == .requiresApproval },
                        set: { enabled in setLaunchAtLogin(enabled) }
                    ))
                    if loginStatus == .requiresApproval {
                        Button("Open Login Items Settings") { SMAppService.openSystemSettingsLoginItems() }
                    }
                    if let loginError { Text(loginError).foregroundStyle(.red) }
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("General", systemImage: "gear") }

            Form {
                Section("Website Suggestions") {
                    Toggle("Suggest accounts for matching browser tabs", isOn: $access.websitesEnabled)
                    Text("Enter one HTTPS login URL per line. Mac2FA reads the active tab in supported browsers with Automation permission. Copy the suggested code from the menu bar or main window.")
                        .foregroundStyle(.secondary)
                    if access.browserPermissionDenied {
                        Text("Allow Mac2FA to control your browser in System Settings → Privacy & Security → Automation.")
                            .foregroundStyle(.secondary)
                    }
                }
                Section("Copy Links") {
                    Toggle("Allow links to request a code", isOn: $access.linksEnabled)
                    Text("Mac2FA asks before copying a code from a link.")
                        .foregroundStyle(.secondary)
                }
                ForEach(access.model.accounts) { account in
                    AccountQuickAccessSettings(account: account)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Websites & Links", systemImage: "link") }

            ProximitySettings(status: access.proximity)
                .tabItem { Label("Proximity", systemImage: "antenna.radiowaves.left.and.right") }
        }
        .frame(width: 560, height: 480)
        .onAppear { loginStatus = SMAppService.mainApp.status }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        loginError = nil
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            loginError = error.localizedDescription
        }
        loginStatus = SMAppService.mainApp.status
    }
}

private struct AccountQuickAccessSettings: View {
    let account: OTPAccount
    @Environment(QuickAccess.self) private var access
    @State private var addresses = ""
    @State private var error: String?
    @State private var isSaving = false

    private var savedAddresses: String {
        (account.websites ?? []).map(\.address).joined(separator: "\n")
    }

    var body: some View {
        Section(account.displayName) {
            TextField("Login URLs", text: $addresses, prompt: Text("https://example.com/login"), axis: .vertical)
                .lineLimit(1...4)
            HStack {
                Button("Save Websites") { Task { await save() } }
                    .disabled(isSaving || addresses == savedAddresses)
                Button("Copy Account Link") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(CopyLink.url(for: account.id).absoluteString, forType: .string)
                }
                .disabled(!access.linksEnabled)
            }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .onAppear { addresses = savedAddresses }
    }

    private func save() async {
        error = nil
        isSaving = true
        defer { isSaving = false }
        let input = addresses
        let lines = input.split { $0.isNewline }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let parsed = lines.compactMap(WebsiteRule.init)
        guard parsed.count == lines.count else {
            error = "Each website needs a valid HTTPS URL."
            return
        }
        var rules: [WebsiteRule] = []
        for rule in parsed where !rules.contains(rule) { rules.append(rule) }
        do {
            try await AccountStore.shared.setWebsites(rules, for: account.id)
            await access.model.reload()
            if addresses == input { addresses = rules.map(\.address).joined(separator: "\n") }
        } catch AccountStoreError.websiteAlreadyAssigned {
            error = "That login URL is already assigned to another account."
        } catch {
            self.error = "Couldn’t save the login URLs."
        }
    }
}

private struct ProximitySettings: View {
    @Bindable var status: ProximityStatus
    @State private var devices: [ProximityStatus.Device] = []

    var body: some View {
        Form {
            Section {
                Picker("Signal", selection: $status.signal) {
                    ForEach(ProximityStatus.Signal.allCases, id: \.self) { signal in
                        Text(signal.rawValue).tag(signal)
                    }
                }
                switch status.signal {
                case .bluetooth:
                    Picker("Paired Device", selection: $status.deviceID) {
                        Text("Choose a device").tag("")
                        if !status.deviceID.isEmpty, !devices.contains(where: { $0.id == status.deviceID }) {
                            Text("Previously selected device").tag(status.deviceID)
                        }
                        ForEach(devices) { device in
                            Text("\(device.name) (\(device.id.suffix(5)))").tag(device.id)
                        }
                    }
                    Button("Refresh Devices") { devices = status.pairedDevices() }
                case .network:
                    TextField("Device IPv4 Address", text: $status.address, prompt: Text("192.168.1.20"))
                }
                Button(status.isChecking ? "Checking…" : "Check Status") { Task { await status.check() } }
                    .disabled(status.isChecking)
                if let message = status.message { Text(message) }
            } footer: {
                Text("Proximity shows connection status. Unlock Mac2FA with Touch ID or your Mac password.")
            }
        }
        .formStyle(.grouped)
        .onChange(of: status.signal) { status.resetMessage() }
        .onChange(of: status.deviceID) { status.resetMessage() }
        .onChange(of: status.address) { status.resetMessage() }
    }
}
