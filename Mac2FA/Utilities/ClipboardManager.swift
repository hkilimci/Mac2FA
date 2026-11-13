import AppKit

@MainActor
final class ClipboardManager {
    static let shared = ClipboardManager()

    private var changeCount: Int?
    private var clearTask: Task<Void, Never>?

    func copyCode(_ code: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if pasteboard.setString(code, forType: .string) {
            scheduleClear(changeCount: pasteboard.changeCount)
        }
    }

    private func scheduleClear(changeCount: Int) {
        clearTask?.cancel()
        self.changeCount = changeCount
        clearTask = Task {
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { return }
            clearIfUnchanged()
        }
    }

    func clearIfUnchanged() {
        clearTask?.cancel()
        clearTask = nil
        let pasteboard = NSPasteboard.general
        if pasteboard.changeCount == changeCount {
            pasteboard.clearContents()
        }
        changeCount = nil
    }
}
