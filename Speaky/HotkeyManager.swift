import AppKit
import Carbon.HIToolbox

/// Registers system-wide hotkeys via Carbon's `RegisterEventHotKey`.
///
/// Carbon is used deliberately: unlike a `CGEventTap` it needs no Input
/// Monitoring permission and it fires even when the app has no window focus.
///
/// Global hotkeys are first-come-first-served across the whole system. When
/// another app already owns a combination the registration fails, which is why
/// the status of every shortcut is reported back rather than assumed.
final class HotkeyManager {
    static let shared = HotkeyManager()

    enum Shortcut: UInt32, CaseIterable, Identifiable {
        case speak = 1
        case playPause = 2
        case back = 3
        case forward = 4

        var id: UInt32 { rawValue }

        var title: String {
            switch self {
            case .speak:     return "Read selection / stop"
            case .playPause: return "Pause / resume"
            case .back:      return "Skip back"
            case .forward:   return "Skip forward"
            }
        }

        /// ⌃⌘ by default. Command is deliberate: on layouts where Option is the
        /// dead-key modifier (Polish, German, …) an Option-based combination
        /// types a diacritic if registration ever fails, which hides the failure.
        /// A Command-modified key can never insert text.
        var fallback: KeyCombo {
            let ctrlOpt = UInt32(controlKey | cmdKey)
            switch self {
            case .speak:     return KeyCombo(keyCode: UInt32(kVK_ANSI_S), carbonModifiers: ctrlOpt)
            case .playPause: return KeyCombo(keyCode: UInt32(kVK_ANSI_P), carbonModifiers: ctrlOpt)
            case .back:      return KeyCombo(keyCode: UInt32(kVK_LeftArrow), carbonModifiers: ctrlOpt)
            case .forward:   return KeyCombo(keyCode: UInt32(kVK_RightArrow), carbonModifiers: ctrlOpt)
            }
        }
    }

    /// Shortcuts the system refused, because another app holds them.
    private(set) var conflicts: Set<Shortcut> = []

    private var refs: [EventHotKeyRef?] = []
    private var handlerRef: EventHandlerRef?
    private var actions: [UInt32: () -> Void] = [:]

    private init() {}

    @discardableResult
    func registerAll(combos: [Shortcut: KeyCombo], actions: [Shortcut: () -> Void]) -> Set<Shortcut> {
        unregisterAll()
        conflicts = []

        for (shortcut, action) in actions {
            self.actions[shortcut.rawValue] = action
        }

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let userData, let event else { return noErr }
                var id = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &id
                )
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { manager.actions[id.id]?() }
                return noErr
            },
            1,
            &spec,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )

        for shortcut in Shortcut.allCases {
            guard actions[shortcut] != nil,
                  let combo = combos[shortcut],
                  !combo.isEmpty
            else { continue }

            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: OSType(0x53504b59), id: shortcut.rawValue) // 'SPKY'
            let status = RegisterEventHotKey(
                combo.keyCode,
                combo.carbonModifiers,
                id,
                GetApplicationEventTarget(),
                0,
                &ref
            )

            if status == noErr {
                refs.append(ref)
            } else {
                conflicts.insert(shortcut)
            }
        }

        return conflicts
    }

    func unregisterAll() {
        for ref in refs where ref != nil { UnregisterEventHotKey(ref!) }
        refs.removeAll()
        if let handlerRef { RemoveEventHandler(handlerRef) }
        handlerRef = nil
        actions.removeAll()
    }
}
