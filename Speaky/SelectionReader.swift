import AppKit
import ApplicationServices
import Carbon.HIToolbox

enum SelectionError: LocalizedError {
    case notTrusted
    case secureInput(app: String)
    case empty

    var errorDescription: String? {
        switch self {
        case .notTrusted:
            return "Włącz Speaky w Ustawieniach → Prywatność → Dostępność."
        case .secureInput(let app):
            return "\(app) ma włączone Secure Keyboard Entry — odłącza przechwytywanie klawiszy."
        case .empty:
            return "Nie znaleziono zaznaczonego tekstu."
        }
    }
}

/// Grabs the text the user has selected in whatever app is frontmost.
///
/// Three tiers, tried in order, because no single mechanism covers every app:
///
/// 1. `AXSelectedText` — clean and instant, but many apps do not implement it.
///    iTerm2 is one: its scripting dictionary exposes only the whole visible
///    screen, and its accessibility layer reports no selection either.
/// 2. A synthetic ⌘C — works wherever copying works, but some apps ignore
///    events injected at the session tap.
/// 3. Pressing the app's own Edit ▸ Copy menu item over Accessibility — no
///    synthetic keyboard involved at all, which is what finally reaches the
///    stubborn cases.
enum SelectionReader {

    /// True once the user has granted Accessibility permission.
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt pointing at Privacy & Security → Accessibility.
    @discardableResult
    static func requestTrust() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    /// True while some app has Secure Keyboard Entry on. macOS then refuses
    /// both synthetic key events and other apps' global hotkeys.
    static var isSecureInputEnabled: Bool { IsSecureEventInputEnabled() }

    /// The app to read from — not necessarily the frontmost one, since opening
    /// Speaky's own menu makes Speaky frontmost.
    static var frontmostApp: NSRunningApplication? {
        FrontmostAppTracker.shared.captureTarget
    }

    static var frontmostAppName: String {
        frontmostApp?.localizedName ?? "Aplikacja na wierzchu"
    }

    static func currentSelection() throws -> String {
        CaptureLog.session("capture")
        CaptureLog.write("trusted=\(isTrusted) secureInput=\(isSecureInputEnabled)")
        guard isTrusted else { throw SelectionError.notTrusted }

        CaptureLog.write("frontmost=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?") lastExternal=\(FrontmostAppTracker.shared.lastExternalApp?.localizedName ?? "?")")

        // Invoked from the menu, Speaky holds focus. Hand it back first,
        // otherwise every tier below inspects Speaky instead of the target.
        let restored = FrontmostAppTracker.shared.restoreFocusIfNeeded()
        CaptureLog.write("restoreFocus=\(restored) target=\(frontmostAppName)")

        let axText = viaAccessibility()
        CaptureLog.write("tier1 AXSelectedText len=\(axText?.count ?? -1)")
        if let axText, !axText.isEmpty { return axText }

        // Only worth reporting once Accessibility has come up empty: apps that
        // answer over AX are unaffected by secure input.
        if isSecureInputEnabled { throw SelectionError.secureInput(app: frontmostAppName) }

        // Menu first, keystroke second. Pressing the app's own Copy item cannot
        // be misread as anything else, whereas a synthesized ⌘C is at the mercy
        // of whatever modifiers happen to be held down.
        let menuText = viaCopy(using: .menuItem)
        CaptureLog.write("tier2 menuCopy len=\(menuText?.count ?? -1)")
        if let menuText, !menuText.isEmpty { return menuText }

        let keyText = viaCopy(using: .keystroke)
        CaptureLog.write("tier3 syntheticCmdC len=\(keyText?.count ?? -1)")
        if let keyText, !keyText.isEmpty { return keyText }

        // Last resort: the app copied on selection and never told anyone.
        let watched = PasteboardMonitor.shared.selection(from: frontmostApp)
        CaptureLog.write("tier4 copyOnSelect len=\(watched?.count ?? -1) source=\(PasteboardMonitor.shared.lastSourceBundleID ?? "?")")
        if let watched, !watched.isEmpty { return watched }

        CaptureLog.write("RESULT empty")
        throw SelectionError.empty
    }

    // MARK: - Tier 1: AXSelectedText

    private static func viaAccessibility() -> String? {
        let system = AXUIElementCreateSystemWide()

        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              CFGetTypeID(focused) == AXUIElementGetTypeID()
        else { return nil }

        let element = unsafeBitCast(focused, to: AXUIElement.self)

        var selected: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selected) == .success,
              let text = selected as? String
        else { return nil }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Tiers 2 & 3: copy, then read the pasteboard

    private enum CopyMethod {
        case keystroke
        case menuItem
    }

    private static func viaCopy(using method: CopyMethod) -> String? {
        let pasteboard = NSPasteboard.general
        let saved = pasteboard.string(forType: .string)

        // Speaky is about to write to the pasteboard twice; neither write is a
        // user copy and the monitor must not record them.
        PasteboardMonitor.shared.isSuppressed = true
        defer {
            PasteboardMonitor.shared.resync()
            PasteboardMonitor.shared.isSuppressed = false
        }

        // A sentinel, not `changeCount`, decides whether the copy landed.
        //
        // iTerm2 copies to the pasteboard on selection by default, so by the
        // time the hotkey fires the selected text is already there. A ⌘C then
        // writes identical content and the change counter may not move at all,
        // which reads exactly like "nothing was selected". Overwriting the
        // pasteboard first makes any successful copy visibly different.
        let sentinel = "speaky-\(UUID().uuidString)"
        pasteboard.clearContents()
        pasteboard.setString(sentinel, forType: .string)

        switch method {
        case .keystroke:
            postCommandC()
        case .menuItem:
            let pressed = pressCopyMenuItem()
            CaptureLog.write("  menu Copy pressed=\(pressed)")
            if !pressed {
                restore(saved, to: pasteboard)
                return nil
            }
        }

        // Poll rather than sleep flat, so the common case stays fast.
        let deadline = Date().addingTimeInterval(0.5)
        var result: String?
        while Date() < deadline {
            if let current = pasteboard.string(forType: .string), current != sentinel {
                result = current.trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }

        restore(saved, to: pasteboard)
        return (result?.isEmpty == false) ? result : nil
    }

    private static func restore(_ saved: String?, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        if let saved { pasteboard.setString(saved, forType: .string) }
    }

    /// Waits for the user to let go of the hotkey.
    ///
    /// Events posted to the HID tap are merged with the real hardware modifier
    /// state. Fire a ⌘C while ⌃⌘ is still physically held and the target app
    /// receives ⌃⌘C — in a terminal that is Control-C, which sends SIGINT and
    /// clears the selection being read.
    private static func waitForModifierRelease(timeout: TimeInterval = 1.0) -> Bool {
        let watched: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            let flags = CGEventSource.flagsState(.combinedSessionState)
            if flags.intersection(watched).isEmpty { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        return false
    }

    private static func postCommandC() {
        let released = waitForModifierRelease()
        CaptureLog.write("  modifiers released=\(released) flags=\(CGEventSource.flagsState(.combinedSessionState).rawValue)")
        guard released else { return }

        let source = CGEventSource(stateID: .combinedSessionState)
        source?.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitLocalKeyboardEvents],
            state: .eventSuppressionStateSuppressionInterval
        )

        let cKey = CGKeyCode(kVK_ANSI_C)
        let down = CGEvent(keyboardEventSource: source, virtualKey: cKey, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: cKey, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand

        // The HID tap sits below the session tap, so apps that filter injected
        // session events still see this one.
        down?.post(tap: .cghidEventTap)
        usleep(20_000)
        up?.post(tap: .cghidEventTap)
    }

    // MARK: - Menu traversal

    /// Finds and presses the frontmost app's Copy command in its own menu bar.
    private static func pressCopyMenuItem() -> Bool {
        guard let pid = frontmostApp?.processIdentifier else {
            CaptureLog.write("  no target app for menu press")
            return false
        }
        let app = AXUIElementCreateApplication(pid)

        var menuBar: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute as CFString, &menuBar) == .success,
              CFGetTypeID(menuBar) == AXUIElementGetTypeID()
        else { return false }

        guard let item = findCopyItem(in: unsafeBitCast(menuBar, to: AXUIElement.self), depth: 0)
        else { return false }

        return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
    }

    /// Depth-limited search for the menu item bound to ⌘C. Matching on the
    /// command character rather than the title keeps this working regardless of
    /// the app's localization.
    private static func findCopyItem(in element: AXUIElement, depth: Int) -> AXUIElement? {
        guard depth < 4 else { return nil }

        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
              let items = children as? [AXUIElement]
        else { return nil }

        for item in items {
            var cmdChar: CFTypeRef?
            var modifiers: CFTypeRef?
            AXUIElementCopyAttributeValue(item, kAXMenuItemCmdCharAttribute as CFString, &cmdChar)
            AXUIElementCopyAttributeValue(item, kAXMenuItemCmdModifiersAttribute as CFString, &modifiers)

            // Modifier mask 0 means plain Command — ⌘C and nothing else.
            if let character = cmdChar as? String,
               character.uppercased() == "C",
               (modifiers as? Int) == 0 {
                // Deliberately not filtered on kAXEnabledAttribute: AppKit
                // validates menu items when the menu is opened, so an item read
                // without opening it can report a stale `false`. A press on a
                // genuinely disabled item is harmless and simply fails.
                CaptureLog.write("  found Copy enabled=\(String(describing: axBool(item, kAXEnabledAttribute as String)))")
                return item
            }

            if let found = findCopyItem(in: item, depth: depth + 1) { return found }
        }
        return nil
    }

    private static func axBool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
        else { return nil }
        return value as? Bool
    }
}
