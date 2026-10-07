import AppKit
import Carbon
import ServiceManagement

if CommandLine.arguments.contains("--selftest") {
    selftest()
    exit(0)
}

let defaults = UserDefaults.standard
defaults.register(defaults: ["calc": true, "system": true, "clipboard": true])

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let panel = Panel()
Clipboard.start()

// ponytail: preset list, no free-form recorder. Add a key-capture recorder if presets aren't enough.
let shortcuts: [(name: String, key: Int, mods: Int)] = [
    ("⌥ Space", kVK_Space, optionKey),
    ("⌃ Space", kVK_Space, controlKey),
    ("⌘ Space (disable Spotlight's first)", kVK_Space, cmdKey),
    ("⌥⌘ Space", kVK_Space, cmdKey | optionKey),
    ("⇧⌘ Space", kVK_Space, cmdKey | shiftKey),
]

// Carbon hotkey: global, needs no Accessibility permission.
var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
    MainActor.assumeIsolated { panel.toggle() }
    return noErr
}, 1, &spec, nil, nil)
var hotKey: EventHotKeyRef?

func registerHotKey(_ i: Int) -> Bool {
    if let hotKey { UnregisterEventHotKey(hotKey) }
    hotKey = nil
    let s = shortcuts[shortcuts.indices.contains(i) ? i : 0]
    return RegisterEventHotKey(UInt32(s.key), UInt32(s.mods), EventHotKeyID(signature: OSType(0x4C4E4348), id: 1),
                               GetApplicationEventTarget(), 0, &hotKey) == noErr
}
_ = registerHotKey(defaults.integer(forKey: "shortcut"))

final class StatusMenu: NSObject, NSMenuDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    override init() {
        super.init()
        item.button?.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Lilith")
        item.menu = NSMenu()
        item.menu?.delegate = self
    }

    // Rebuilt on every open so checkmarks always reflect current state.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        add(menu, "Open Lilith", #selector(open))
        let sub = NSMenu()
        for (i, s) in shortcuts.enumerated() {
            add(sub, s.name, #selector(setShortcut), tag: i).state = i == defaults.integer(forKey: "shortcut") ? .on : .off
        }
        menu.addItem(withTitle: "Shortcut", action: nil, keyEquivalent: "").submenu = sub
        menu.addItem(.separator())
        for (title, key) in [("Calculator", "calc"), ("System Commands", "system"), ("Clipboard History", "clipboard")] {
            let m = add(menu, title, #selector(toggleSetting))
            m.representedObject = key
            m.state = defaults.bool(forKey: key) ? .on : .off
        }
        add(menu, "Clear Clipboard History", #selector(clearClipboard))
        menu.addItem(.separator())
        add(menu, "Launch at Login", #selector(toggleLogin)).state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(withTitle: "Quit Lilith", action: #selector(NSApplication.terminate), keyEquivalent: "q")
    }

    @discardableResult
    func add(_ menu: NSMenu, _ title: String, _ action: Selector, tag: Int = 0) -> NSMenuItem {
        let m = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
        m.target = self
        m.tag = tag
        return m
    }

    @objc func open() { if !Lilith.panel.isVisible { Lilith.panel.toggle() } }  // NSObject has its own `panel`

    @objc func setShortcut(_ m: NSMenuItem) {
        if registerHotKey(m.tag) { return defaults.set(m.tag, forKey: "shortcut") }
        NSSound.beep()  // taken by another app; restore the old one
        _ = registerHotKey(defaults.integer(forKey: "shortcut"))
    }

    @objc func toggleSetting(_ m: NSMenuItem) {
        let key = m.representedObject as! String
        defaults.set(!defaults.bool(forKey: key), forKey: key)
        if key == "clipboard" { Clipboard.history.removeAll() }
    }

    @objc func clearClipboard() { Clipboard.history.removeAll() }

    @objc func toggleLogin() {
        let s = SMAppService.mainApp
        do { try s.status == .enabled ? s.unregister() : s.register() } catch { NSSound.beep() }
    }
}
let statusMenu = StatusMenu()

app.run()
