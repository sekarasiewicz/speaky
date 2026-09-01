import AppKit
import Carbon.HIToolbox

/// A hotkey, stored in Carbon's units because that is what `RegisterEventHotKey`
/// takes. Cocoa modifier flags are converted at the edges.
struct KeyCombo: Codable, Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32

    static let empty = KeyCombo(keyCode: 0, carbonModifiers: 0)

    var isEmpty: Bool { carbonModifiers == 0 && keyCode == 0 }

    init(keyCode: UInt32, carbonModifiers: UInt32) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
    }

    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.option)  { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.shift)   { carbon |= UInt32(shiftKey) }

        // A bare key would swallow normal typing system-wide.
        guard carbon != 0 else { return nil }

        self.keyCode = UInt32(event.keyCode)
        self.carbonModifiers = carbon
    }

    /// Option without Command is risky on layouts where Option composes
    /// diacritics: if the global registration ever fails, the keystroke falls
    /// through and quietly types a character instead of doing nothing.
    var isDeadKeyRisk: Bool {
        carbonModifiers & UInt32(optionKey) != 0 && carbonModifiers & UInt32(cmdKey) == 0
    }

    /// Menu-style rendering, e.g. `⌃⌘S`.
    var display: String {
        guard !isEmpty else { return "—" }
        var out = ""
        if carbonModifiers & UInt32(controlKey) != 0 { out += "⌃" }
        if carbonModifiers & UInt32(optionKey)  != 0 { out += "⌥" }
        if carbonModifiers & UInt32(shiftKey)   != 0 { out += "⇧" }
        if carbonModifiers & UInt32(cmdKey)     != 0 { out += "⌘" }
        out += Self.keyName(keyCode)
        return out
    }

    private static let specialKeys: [Int: String] = [
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Space: "Space", kVK_Return: "↩", kVK_Escape: "⎋", kVK_Delete: "⌫",
        kVK_Tab: "⇥", kVK_ForwardDelete: "⌦", kVK_Home: "↖", kVK_End: "↘",
        kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5",
        kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10",
        kVK_F11: "F11", kVK_F12: "F12",
    ]

    /// Resolves the printed character through the active keyboard layout, so a
    /// non-US layout shows the key the user actually pressed.
    static func keyName(_ keyCode: UInt32) -> String {
        if let special = specialKeys[Int(keyCode)] { return special }

        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return "?" }

        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        var deadKeys: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)

        let status = data.withUnsafeBytes { raw -> OSStatus in
            let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress!
            return UCKeyTranslate(
                layout,
                UInt16(keyCode),
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                UInt32(kUCKeyTranslateNoDeadKeysBit),
                &deadKeys,
                chars.count,
                &length,
                &chars
            )
        }

        guard status == noErr, length > 0 else { return "?" }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }
}
