import Carbon

@MainActor
final class GlobalCopyShortcut {
    private var handler: EventHandlerRef?
    private var hotKey: EventHotKeyRef?
    private var action: (() -> Void)?

    func register(action: @escaping () -> Void) -> Bool {
        guard hotKey == nil else { return true }
        let target = GetApplicationEventTarget()
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let signature: OSType = 0x4D324641 // M2FA
        let status = InstallEventHandler(target, { _, event, data in
            guard let event, let data else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                    EventParamType(typeEventHotKeyID), nil,
                                    MemoryLayout<EventHotKeyID>.size, nil, &id) == noErr,
                  id.signature == 0x4D324641, id.id == 1
            else { return OSStatus(eventNotHandledErr) }
            let shortcut = Unmanaged<GlobalCopyShortcut>.fromOpaque(data).takeUnretainedValue()
            MainActor.assumeIsolated { shortcut.action?() }
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else { return false }
        guard RegisterEventHotKey(UInt32(kVK_ANSI_C), UInt32(cmdKey | optionKey),
                                  EventHotKeyID(signature: signature, id: 1),
                                  target, 0, &hotKey) == noErr else {
            unregister()
            return false
        }
        self.action = action
        return true
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil
        handler = nil
        action = nil
    }
}
