import AppKit
import Carbon.HIToolbox

/// A recorded keyboard shortcut.
nonisolated struct KeyCombo: Equatable, Codable, Sendable {
    var keyCode: UInt32
    /// `NSEvent.ModifierFlags` raw value, already reduced to the device
    /// independent flags — the raw event also carries things like "which shift
    /// key", which would make two identical-looking shortcuts unequal.
    var modifierRawValue: UInt

    var modifiers: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierRawValue)
    }

    init(keyCode: UInt32, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifierRawValue = modifiers.intersection(.deviceIndependentFlagsMask).rawValue
    }

    /// ⌃⇧S and so on, in the order macOS writes them in menus.
    var displayString: String {
        var result = ""
        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option) { result += "⌥" }
        if modifiers.contains(.shift) { result += "⇧" }
        if modifiers.contains(.command) { result += "⌘" }
        return result + Self.name(for: keyCode)
    }

    /// At least one of ⌘ ⌃ ⌥ — a bare key, or Shift plus a key, would swallow
    /// ordinary typing everywhere on the system.
    var isUsable: Bool {
        !modifiers.intersection([.command, .control, .option]).isEmpty
    }

    static let `default` = KeyCombo(keyCode: UInt32(kVK_ANSI_S), modifiers: [.control, .shift])

    /// The printable name of a virtual key code.
    ///
    /// Letters and digits are read from the *current* keyboard layout, so a
    /// French user recording the key next to Tab sees the letter that key
    /// actually types. The named keys are a fixed table because they have no
    /// printable character at all.
    static func name(for keyCode: UInt32) -> String {
        if let named = namedKeys[Int(keyCode)] { return named }

        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else {
            return "Key \(keyCode)"
        }

        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: 4)
        var length = 0

        let status = data.withUnsafeBytes { buffer -> OSStatus in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
                return OSStatus(paramErr)
            }
            return UCKeyTranslate(
                layout,
                UInt16(keyCode),
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                characters.count,
                &length,
                &characters
            )
        }

        guard status == noErr, length > 0 else { return "Key \(keyCode)" }
        return String(utf16CodeUnits: characters, count: length).uppercased()
    }

    private static let namedKeys: [Int: String] = [
        kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "Space", kVK_Delete: "⌫",
        kVK_ForwardDelete: "⌦", kVK_Escape: "⎋", kVK_Home: "↖", kVK_End: "↘",
        kVK_PageUp: "⇞", kVK_PageDown: "⇟", kVK_LeftArrow: "←", kVK_RightArrow: "→",
        kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5",
        kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10",
        kVK_F11: "F11", kVK_F12: "F12",
    ]
}
