import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(sessionLeft),
                           name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(sessionReturned),
                           name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(displaySlept),
                           name: NSWorkspace.screensDidSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(displayWoke),
                           name: NSWorkspace.screensDidWakeNotification, object: nil)
        center.addObserver(self, selector: #selector(systemSlept),
                           name: NSWorkspace.willSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(systemWoke),
                           name: NSWorkspace.didWakeNotification, object: nil)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        QuickAccess.shared.start()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        Task {
            for url in urls { await QuickAccess.shared.receiveLink(url) }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        QuickAccess.shared.lockNow()
    }

    @objc private func sessionLeft(_ notification: Notification) {
        QuickAccess.shared.setSessionActive(false)
    }

    @objc private func sessionReturned(_ notification: Notification) {
        QuickAccess.shared.setSessionActive(true)
    }

    @objc private func displaySlept(_ notification: Notification) {
        QuickAccess.shared.setDisplayAwake(false)
    }

    @objc private func displayWoke(_ notification: Notification) {
        QuickAccess.shared.setDisplayAwake(true)
    }

    @objc private func systemSlept(_ notification: Notification) {
        QuickAccess.shared.setSystemAwake(false)
    }

    @objc private func systemWoke(_ notification: Notification) {
        QuickAccess.shared.setSystemAwake(true)
    }
}
