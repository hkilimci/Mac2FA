import AppKit
import Observation

@MainActor
@Observable
final class QuickAccess {
    struct CopyRequest: Equatable {
        let accountID: OTPAccount.ID
        let website: WebsiteRule?
        let expiresAt: Date
    }

    static let shared = QuickAccess()
    let model = AccountsModel(lock: AppLock())
    let proximity = ProximityStatus()
    var lock: AppLock { model.lock }

    private(set) var linkRequest: CopyRequest?
    private(set) var websiteSuggestion: CopyRequest?
    private(set) var browserPermissionDenied = false
    private(set) var shortcutUnavailable = false

    var linksEnabled = UserDefaults.standard.bool(forKey: "copyLinksEnabled") {
        didSet {
            UserDefaults.standard.set(linksEnabled, forKey: "copyLinksEnabled")
            if !linksEnabled { linkRequest = nil }
        }
    }
    var websitesEnabled = UserDefaults.standard.bool(forKey: "websiteSuggestionsEnabled") {
        didSet {
            UserDefaults.standard.set(websitesEnabled, forKey: "websiteSuggestionsEnabled")
            if !websitesEnabled {
                websiteSuggestion = nil
                browserPermissionDenied = false
            }
        }
    }
    var shortcutEnabled = UserDefaults.standard.bool(forKey: "globalCopyShortcutEnabled") {
        didSet {
            UserDefaults.standard.set(shortcutEnabled, forKey: "globalCopyShortcutEnabled")
            updateShortcut()
        }
    }

    @ObservationIgnored var openMainWindow: (() -> Void)?
    @ObservationIgnored private let shortcut = GlobalCopyShortcut()
    @ObservationIgnored private let browser = BrowserTabReader()
    @ObservationIgnored private var linkExpiry: Task<Void, Never>?
    @ObservationIgnored private var browserTask: Task<Void, Never>?
    @ObservationIgnored private var isSessionActive = true
    @ObservationIgnored private var isDisplayAwake = true
    @ObservationIgnored private var isSystemAwake = true

    var accountForShortcut: OTPAccount? {
        model.accounts.first { $0.id == model.lastCopiedID } ?? model.accounts.first
    }

    func start() {
        guard browserTask == nil else { return }
        Task { await model.reload() }
        updateShortcut()
        browserTask = Task {
            while !Task.isCancelled {
                refreshWebsiteSuggestion()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func unlock() async {
        guard lock.sessionAvailable else { return }
        await lock.unlock()
        if !lock.isLocked { await model.reload() }
    }

    func setAuthenticationRequired(_ required: Bool) async {
        guard lock.sessionAvailable else { return }
        await lock.setAuthenticationRequired(required)
        if lock.isLocked {
            clearProtectedState()
        } else {
            await model.reload()
        }
    }

    func lockNow() {
        lock.lock()
        clearProtectedState()
    }

    func setSessionActive(_ active: Bool) {
        isSessionActive = active
        refreshSession()
    }

    func setDisplayAwake(_ awake: Bool) {
        isDisplayAwake = awake
        refreshSession()
    }

    func setSystemAwake(_ awake: Bool) {
        isSystemAwake = awake
        refreshSession()
    }

    func copy(_ account: OTPAccount) async {
        guard lock.sessionAvailable else { return }
        if lock.isLocked {
            NSApp.activate(ignoringOtherApps: true)
            await unlock()
        }
        guard !lock.isLocked,
              let current = model.accounts.first(where: { $0.id == account.id })
        else { return }
        model.copyCode(for: current)
    }

    func copyFromShortcut() {
        guard let account = accountForShortcut else { return }
        Task { await copy(account) }
    }

    func receiveLink(_ url: URL) async {
        guard linksEnabled, lock.sessionAvailable,
              linkRequest == nil, let id = CopyLink.accountID(from: url)
        else { return }
        if !model.hasLoaded { await model.reload() }
        guard linksEnabled, lock.sessionAvailable, linkRequest == nil,
              model.accounts.contains(where: { $0.id == id })
        else { return }

        linkRequest = CopyRequest(accountID: id, website: nil, expiresAt: .now.addingTimeInterval(30))
        linkExpiry?.cancel()
        linkExpiry = Task {
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { return }
            linkRequest = nil
        }
        openMainWindow?()
        NSApp.activate(ignoringOtherApps: true)
    }

    func dismissLink() {
        linkRequest = nil
        linkExpiry?.cancel()
    }

    func confirm(_ request: CopyRequest) async {
        if request.website != nil {
            guard request == websiteSuggestion else { return }
            websiteSuggestion = nil
        } else {
            guard request == linkRequest else { return }
            dismissLink()
        }

        guard lock.sessionAvailable, account(for: request) != nil else { return }
        if lock.isLocked {
            NSApp.activate(ignoringOtherApps: true)
            await unlock()
        }
        guard !lock.isLocked, let account = account(for: request) else { return }
        model.copyCode(for: account)
    }

    private func account(for request: CopyRequest) -> OTPAccount? {
        guard request.expiresAt > .now else { return nil }
        if let website = request.website {
            guard websitesEnabled, let account = website.account(in: model.accounts),
                  account.id == request.accountID else { return nil }
            return account
        }
        guard linksEnabled else { return nil }
        return model.accounts.first { $0.id == request.accountID }
    }

    private func clearProtectedState() {
        model.clearSecrets()
        ClipboardManager.shared.clearIfUnchanged()
        dismissLink()
        websiteSuggestion = nil
    }

    private func refreshSession() {
        lock.setSessionAvailable(isSessionActive && isDisplayAwake && isSystemAwake)
        if !lock.sessionAvailable {
            clearProtectedState()
        } else if !lock.isLocked {
            Task { await model.reload() }
        }
    }

    private func updateShortcut() {
        if shortcutEnabled {
            shortcutUnavailable = !shortcut.register { [weak self] in self?.copyFromShortcut() }
        } else {
            shortcut.unregister()
            shortcutUnavailable = false
        }
    }

    private func refreshWebsiteSuggestion() {
        guard websitesEnabled, lock.sessionAvailable,
              model.accounts.contains(where: { $0.websites?.isEmpty == false })
        else {
            websiteSuggestion = nil
            return
        }
        switch browser.readFrontTab() {
        case .page(let website):
            browserPermissionDenied = false
            guard let account = website.account(in: model.accounts) else {
                websiteSuggestion = nil
                return
            }
            let id = account.id
            if let existing = websiteSuggestion, existing.accountID == id, existing.website == website,
               existing.expiresAt.timeIntervalSinceNow > 10 { return }
            websiteSuggestion = CopyRequest(accountID: id, website: website, expiresAt: .now.addingTimeInterval(30))
        case .mac2FA:
            if let request = websiteSuggestion, account(for: request) == nil {
                websiteSuggestion = nil
            }
        case .permissionDenied:
            browserPermissionDenied = true
            websiteSuggestion = nil
        case .unavailable:
            websiteSuggestion = nil
        }
    }
}
