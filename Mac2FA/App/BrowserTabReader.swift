import AppKit

@MainActor
final class BrowserTabReader {
    enum Result {
        case mac2FA
        case page(WebsiteRule)
        case permissionDenied
        case unavailable
    }

    private static let chromium = ["com.google.Chrome", "com.brave.Browser", "com.microsoft.edgemac",
                                   "company.thebrowser.Browser", "com.vivaldi.Vivaldi"]
    private static let safari = ["com.apple.Safari", "com.apple.SafariTechnologyPreview"]
    private var scripts: [String: NSAppleScript] = [:]

    func readFrontTab() -> Result {
        guard let app = NSWorkspace.shared.frontmostApplication, let bundleID = app.bundleIdentifier else {
            return .unavailable
        }
        if app.processIdentifier == ProcessInfo.processInfo.processIdentifier { return .mac2FA }

        let tab: String
        if Self.safari.contains(bundleID) {
            tab = "current tab"
        } else if Self.chromium.contains(bundleID) {
            tab = "active tab"
        } else {
            return .unavailable
        }

        let script = scripts[bundleID] ?? NSAppleScript(source: """
            with timeout of 1 second
                tell application id "\(bundleID)" to get URL of \(tab) of front window
            end timeout
            """)
        scripts[bundleID] = script
        var error: NSDictionary?
        let result = script?.executeAndReturnError(&error)
        if (error?[NSAppleScript.errorNumber] as? Int) == -1743 { return .permissionDenied }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier,
              let url = result?.stringValue, let page = WebsiteRule(url)
        else { return .unavailable }
        return .page(page)
    }
}
