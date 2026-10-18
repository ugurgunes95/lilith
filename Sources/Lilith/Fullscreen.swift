import AppKit
import Carbon

// MARK: Full screen at launch (formerly the MacFS app)

/// Puts a newly launched app's windows into native full screen, once. Leaving full screen sticks until the next launch.
/// Needs Accessibility. Exceptions are bundle ids in the "fullscreenSkip" default.
enum Fullscreen {
    static var skip: [String] {
        get { UserDefaults.standard.stringArray(forKey: "fullscreenSkip") ?? ["com.apple.finder"] }
        set { UserDefaults.standard.set(newValue, forKey: "fullscreenSkip") }
    }

    static func start() {
        importMacFS()
        if UserDefaults.standard.bool(forKey: "fullscreen") { askForAccess() }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { note in
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication { apply(app) }
        }
    }

    static func askForAccess() {
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
    }

    static func toggle(_ id: String) {
        if skip.contains(id) { skip.removeAll { $0 == id } } else { skip.append(id) }
    }

    /// Apps create their windows a moment after launching: retry every 0.3s for about 5s.
    static func apply(_ app: NSRunningApplication, attempt: Int = 0) {
        // Menu bar utilities and background helpers (no Dock icon) have no windows to fill the screen.
        guard UserDefaults.standard.bool(forKey: "fullscreen"), AXIsProcessTrusted(), app.activationPolicy == .regular,
              !app.isTerminated, let id = app.bundleIdentifier, !skip.contains(id) else { return }
        let windows = standardWindows(AXUIElementCreateApplication(app.processIdentifier))
        if windows.isEmpty {
            if attempt < 16 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { apply(app, attempt: attempt + 1) } }
            return
        }
        let done = windows.filter { AXUIElementSetAttributeValue($0, "AXFullScreen" as CFString, kCFBooleanTrue) == .success }
        // Some apps ignore the attribute but honor the menu shortcut ⌃⌘F.
        if done.isEmpty, app.isActive {
            let source = CGEventSource(stateID: .hidSystemState)
            for down in [true, false] {
                let e = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_F), keyDown: down)
                e?.flags = [.maskControl, .maskCommand]
                e?.postToPid(app.processIdentifier)
            }
        }
    }

    static func standardWindows(_ app: AXUIElement) -> [AXUIElement] {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return [] }
        return windows.filter { window in
            var subrole: AnyObject?
            AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subrole)
            return subrole as? String == kAXStandardWindowSubrole
        }
    }

    /// One-time: carry over MacFS's skip list and on/off state (MacFS defaulted to on).
    static func importMacFS() {
        let dir = NSHomeDirectory() + "/Library/Application Support/MacFS/"
        guard UserDefaults.standard.object(forKey: "fullscreenSkip") == nil,
              let list = try? String(contentsOfFile: dir + "skip.txt", encoding: .utf8) else { return }
        skip = list.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let settings = (try? String(contentsOfFile: dir + "settings.txt", encoding: .utf8)) ?? ""
        UserDefaults.standard.set(!settings.contains("fullscreen=0"), forKey: "fullscreen")
    }
}

func appName(_ id: String) -> String {
    NSWorkspace.shared.urlForApplication(withBundleIdentifier: id).map {
        var name = FileManager.default.displayName(atPath: $0.path)
        if name.hasSuffix(".app") { name.removeLast(4) }
        return name
    } ?? id
}
