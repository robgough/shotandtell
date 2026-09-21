import AppKit
import Carbon.HIToolbox

/// A single system-wide hotkey, registered through Carbon.
///
/// Carbon, in 2026, on purpose: `RegisterEventHotKey` goes through the window
/// server, so it works inside the App Sandbox and needs no Accessibility grant.
/// The modern-looking alternatives don't — `CGEvent.tapCreate` and
/// `NSEvent.addGlobalMonitorForEvents` both require Accessibility, which the Mac
/// App Store won't have. The API is still un-deprecated in the macOS 27 SDK.
@MainActor
final class GlobalHotkey {
    static let shared = GlobalHotkey()

    var onFire: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private static let signature: OSType = 0x53_6E_54_6C // 'SnTl'

    private init() {}

    enum Failure: LocalizedError {
        case alreadyTaken
        case registrationFailed(OSStatus)

        var errorDescription: String? {
            switch self {
            case .alreadyTaken:
                "Another app is already using that shortcut."
            case let .registrationFailed(status):
                "macOS refused that shortcut (error \(status))."
            }
        }
    }

    /// `keyCode` is a virtual key code; `modifiers` are AppKit's flags, which
    /// are translated to Carbon's here rather than at every call site.
    func register(keyCode: UInt32, modifiers: NSEvent.ModifierFlags) throws {
        unregister()
        installHandlerIfNeeded()

        let id = EventHotKeyID(signature: Self.signature, id: 1)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            Self.carbonModifiers(from: modifiers),
            id,
            GetApplicationEventTarget(),
            0,
            &ref
        )

        guard status == noErr, let ref else {
            // eventHotKeyExistsErr means somebody else owns it. That's a thing
            // to tell the user about, not a thing to swallow — a shortcut that
            // silently does nothing is worse than no shortcut.
            throw status == OSStatus(eventHotKeyExistsErr) ? Failure.alreadyTaken : Failure.registrationFailed(status)
        }
        hotKeyRef = ref
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    fileprivate func fire() {
        onFire?()
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), hotkeyEventHandler, 1, &type, nil, &eventHandler)
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        return carbon
    }
}

/// The Carbon callback. A free function because it's passed to C as a bare
/// pointer, and `nonisolated` because C has never heard of actors.
private nonisolated func hotkeyEventHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    var id = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &id
    )
    guard status == noErr else { return status }

    Task { @MainActor in
        GlobalHotkey.shared.fire()
    }
    return noErr
}
