import AppKit
import Carbon

if CommandLine.arguments.contains("--selftest") {
    selftest()
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let panel = Panel()

// Carbon hotkey: global, needs no Accessibility permission. Option+Space hardcoded until settings MVP.
var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
    MainActor.assumeIsolated { panel.toggle() }
    return noErr
}, 1, &spec, nil, nil)
var hotKey: EventHotKeyRef?
RegisterEventHotKey(UInt32(kVK_Space), UInt32(optionKey), EventHotKeyID(signature: OSType(0x4C4E4348), id: 1),
                    GetApplicationEventTarget(), 0, &hotKey)

app.run()
