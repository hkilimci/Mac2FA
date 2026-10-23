import AppKit

actor ClipboardManager {
    static let shared = ClipboardManager()

    private var lastCopiedCode: String?

    func copyCode(_ code: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(code, forType: .string)
        scheduleClear(of: code)
    }

    /// Clears `code` from the pasteboard after 30 seconds unless something else was copied since.
    /// Called directly when the system Copy command (⌘C) has already written the pasteboard.
    func scheduleClear(of code: String) {
        lastCopiedCode = code

        Task {
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            clearIfUnchanged(code: code)
        }
    }

    private func clearIfUnchanged(code: String) {
        let pasteboard = NSPasteboard.general
        guard let current = pasteboard.string(forType: .string), current == code else {
            return
        }
        if lastCopiedCode == code {
            pasteboard.clearContents()
            lastCopiedCode = nil
        }
    }
}
