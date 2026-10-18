import AppKit
import Carbon
import ServiceManagement

if CommandLine.arguments.contains("--selftest") {
    selftest()
    exit(0)
}

let defaults = UserDefaults.standard
defaults.register(defaults: ["calc": true, "convert": true, "system": true, "clipboard": true, "files": true, "fullscreen": false])

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let panel = Panel()
Clipboard.start()
Rates.refreshIfStale()
Fullscreen.start()

// ponytail: preset list, no free-form recorder. Add a key-capture recorder if presets aren't enough.
let launcherShortcuts: [(name: String, key: Int, mods: Int)] = [
    ("⌥ Space", kVK_Space, optionKey),
    ("⌃ Space", kVK_Space, controlKey),
    ("⌘ Space (disable Spotlight's first)", kVK_Space, cmdKey),
    ("⌥⌘ Space", kVK_Space, cmdKey | optionKey),
    ("⇧⌘ Space", kVK_Space, cmdKey | shiftKey),
]
let clipboardShortcuts: [(name: String, key: Int, mods: Int)] = [
    ("⇧⌘V", kVK_ANSI_V, cmdKey | shiftKey),
    ("⌃⌥V", kVK_ANSI_V, controlKey | optionKey),
    ("⌥⌘V", kVK_ANSI_V, cmdKey | optionKey),
    ("⌃⌘V", kVK_ANSI_V, cmdKey | controlKey),
]
// Index = hotkey id: 0 launcher, 1 clipboard.
let hotKeyPresets = [("shortcut", launcherShortcuts), ("clipboardShortcut", clipboardShortcuts)]

// Carbon hotkey: global, needs no Accessibility permission.
var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
    var hk = EventHotKeyID()
    GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                      nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
    MainActor.assumeIsolated { hk.id == 1 ? panel.toggle(query: "cb ") : panel.toggle() }
    return noErr
}, 1, &spec, nil, nil)
var hotKeys: [EventHotKeyRef?] = [nil, nil]

func registerHotKey(_ id: Int, _ i: Int) -> Bool {
    if let h = hotKeys[id] { UnregisterEventHotKey(h) }
    hotKeys[id] = nil
    if id == 1 && !defaults.bool(forKey: "clipboard") { return true }
    let presets = hotKeyPresets[id].1
    let s = presets[presets.indices.contains(i) ? i : 0]
    return RegisterEventHotKey(UInt32(s.key), UInt32(s.mods), EventHotKeyID(signature: OSType(0x4C4E4348), id: UInt32(id)),
                               GetApplicationEventTarget(), 0, &hotKeys[id]) == noErr
}
for (id, preset) in hotKeyPresets.enumerated() { _ = registerHotKey(id, defaults.integer(forKey: preset.0)) }

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
        for (id, (title, (key, presets))) in zip(["Launcher Shortcut", "Clipboard Shortcut"], hotKeyPresets).enumerated() {
            let sub = NSMenu()
            for (i, s) in presets.enumerated() {
                let m = add(sub, s.name, #selector(setShortcut), tag: i)
                m.representedObject = id
                m.state = i == defaults.integer(forKey: key) ? .on : .off
            }
            menu.addItem(withTitle: title, action: nil, keyEquivalent: "").submenu = sub
        }
        menu.addItem(.separator())
        toggle(menu, "Calculator", "calc")
        toggle(menu, "Conversions", "convert")
        toggle(menu, "System Commands", "system")
        toggle(menu, "File Search", "files")
        toggle(menu, "Clipboard History", "clipboard")
        add(menu, "Clear Clipboard History", #selector(clearClipboard))
        toggle(menu, "Open Apps in Full Screen", "fullscreen")
        let skips = NSMenu()
        if let front = NSWorkspace.shared.frontmostApplication, let id = front.bundleIdentifier,
           id != Bundle.main.bundleIdentifier, !Fullscreen.skip.contains(id) {
            add(skips, "Skip “\(front.localizedName ?? id)”", #selector(toggleSkip)).representedObject = id
            skips.addItem(.separator())
        }
        for id in Fullscreen.skip.sorted(by: { appName($0).localizedCompare(appName($1)) == .orderedAscending }) {
            let m = add(skips, appName(id), #selector(toggleSkip))  // checked; picking one removes it
            m.representedObject = id
            m.state = .on
        }
        menu.addItem(withTitle: "Full Screen Exceptions", action: nil, keyEquivalent: "").submenu = skips
        let folder = defaults.string(forKey: "scriptsFolder").map { "Scripts Folder: " + URL(fileURLWithPath: $0).lastPathComponent + "…" }
        add(menu, folder ?? "Choose Scripts Folder…", #selector(chooseScripts))
        toggle(menu, "Run Scripts in Terminal", "scriptsInTerminal")
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

    func toggle(_ menu: NSMenu, _ title: String, _ key: String) {
        let m = add(menu, title, #selector(toggleSetting))
        m.representedObject = key
        m.state = defaults.bool(forKey: key) ? .on : .off
    }

    @objc func open() { if !Lilith.panel.isVisible { Lilith.panel.toggle() } }  // NSObject has its own `panel`

    @objc func setShortcut(_ m: NSMenuItem) {
        let id = m.representedObject as! Int, key = hotKeyPresets[id].0
        if registerHotKey(id, m.tag) { return defaults.set(m.tag, forKey: key) }
        NSSound.beep()  // taken by another app; restore the old one
        _ = registerHotKey(id, defaults.integer(forKey: key))
    }

    @objc func toggleSetting(_ m: NSMenuItem) {
        let key = m.representedObject as! String
        defaults.set(!defaults.bool(forKey: key), forKey: key)
        if key == "fullscreen", defaults.bool(forKey: key) { Fullscreen.askForAccess() }
        if key == "clipboard" {
            Clipboard.history.removeAll()
            _ = registerHotKey(1, defaults.integer(forKey: "clipboardShortcut"))  // frees the keys while off
        }
    }

    @objc func toggleSkip(_ m: NSMenuItem) { Fullscreen.toggle(m.representedObject as! String) }

    @objc func clearClipboard() { Clipboard.history.removeAll() }

    @objc func chooseScripts() {
        let p = NSOpenPanel()
        p.canChooseFiles = false
        p.canChooseDirectories = true
        p.message = "Choose a folder of .sh scripts to run from Lilith"
        NSApp.activate()  // accessory app: otherwise the dialog opens behind other windows
        if p.runModal() == .OK, let url = p.url { defaults.set(url.path, forKey: "scriptsFolder") }
    }

    @objc func toggleLogin() {
        let s = SMAppService.mainApp
        do { try s.status == .enabled ? s.unregister() : s.register() } catch { NSSound.beep() }
    }
}
let statusMenu = StatusMenu()

app.run()
