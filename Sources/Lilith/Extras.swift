import AppKit
import Carbon

func symbol(_ name: String) -> NSImage? { NSImage(systemSymbolName: name, accessibilityDescription: nil) }

func copy(_ s: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(s, forType: .string)
}

/// Sends Cmd+V to whatever app regains focus once the panel closes. Needs Accessibility; first call prompts.
/// Without permission the text is still on the clipboard for a manual paste.
func paste() {
    guard AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary) else { return }
    // ponytail: fixed 0.1s for focus to return to the previous app. Raise it if pastes land too early.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: down)
            e?.flags = .maskCommand
            e?.post(tap: .cghidEventTap)
        }
    }
}

// MARK: Calculator

/// Recursive descent over + - * / ^ and parens. nil = not a valid expression. Comma accepted as decimal point.
func calc(_ input: String) -> Double? {
    let c = Array(input.replacingOccurrences(of: ",", with: ".").filter { !$0.isWhitespace })
    var i = 0
    func peek() -> Character? { i < c.count ? c[i] : nil }
    func expr() -> Double? {
        guard var v = term() else { return nil }
        while let op = peek(), op == "+" || op == "-" {
            i += 1
            guard let r = term() else { return nil }
            v = op == "+" ? v + r : v - r
        }
        return v
    }
    func term() -> Double? {
        guard var v = unary() else { return nil }
        while let op = peek(), op == "*" || op == "/" {
            i += 1
            guard let r = unary() else { return nil }
            v = op == "*" ? v * r : v / r
        }
        return v
    }
    // Unary minus binds looser than ^, so -2^2 = -4 and 2^-1 = 0.5.
    func unary() -> Double? {
        if peek() == "-" { i += 1; return unary().map { -$0 } }
        guard let b = atom() else { return nil }
        if peek() == "^" { i += 1; return unary().map { pow(b, $0) } }
        return b
    }
    func atom() -> Double? {
        if peek() == "(" {
            i += 1
            guard let v = expr(), peek() == ")" else { return nil }
            i += 1
            return v
        }
        let start = i
        while let d = peek(), d.isASCII, d.isNumber || d == "." { i += 1 }
        return Double(String(c[start..<i]))
    }
    guard let v = expr(), i == c.count, v.isFinite else { return nil }
    return v
}

let numberFormat: NumberFormatter = {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.usesGroupingSeparator = false
    f.maximumFractionDigits = 10
    return f
}()

func calcItem(_ q: String) -> Item? {
    guard q.contains(where: { "+-*/^".contains($0) }), let v = calc(q),
          let s = numberFormat.string(from: v as NSNumber) else { return nil }
    return Item(title: s, subtitle: "\(q) · Enter to copy", icon: { symbol("equal.circle") }) { copy(s) }
}

// MARK: System commands

let systemCommands = [
    ("Sleep", "moon", "sleep"),
    ("Restart", "arrow.clockwise", "restart"),
    ("Shut Down", "power", "shut down"),
    ("Log Out", "rectangle.portrait.and.arrow.right", "log out"),
]

/// Scored like apps but -500, so apps win ties within a tier ("re" → Reminders before Restart).
func systemItems(_ q: String) -> [(Int, Item)] {
    systemCommands.compactMap { title, icon, verb in
        score(q, title).map { s in
            (s - 500, Item(title: title, subtitle: "System", icon: { symbol(icon) }) {
                NSAppleScript(source: "tell application \"System Events\" to \(verb)")?.executeAndReturnError(nil)
            })
        }
    }
}

// MARK: Clipboard history

// ponytail: text only, stored plaintext in the app's UserDefaults plist (readable by this macOS user only). Encrypt via Keychain if that's not enough.
enum Clipboard {
    static var history = UserDefaults.standard.stringArray(forKey: "clipboardHistory") ?? [] {
        didSet { UserDefaults.standard.set(history, forKey: "clipboardHistory") }
    }
    static var count = NSPasteboard.general.changeCount

    // NSPasteboard has no change notification; polling changeCount is the standard approach.
    static func start() {
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in poll() }
    }

    static func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != count else { return }
        count = pb.changeCount
        // Password managers mark secrets with these (nspasteboard.org); never record them.
        let skip: Set<NSPasteboard.PasteboardType> = [.init("org.nspasteboard.ConcealedType"), .init("org.nspasteboard.TransientType")]
        guard UserDefaults.standard.bool(forKey: "clipboard"), skip.isDisjoint(with: pb.types ?? []),
              let s = pb.string(forType: .string), !s.isEmpty else { return }
        history.removeAll { $0 == s }
        history.insert(s, at: 0)
        if history.count > 50 { history.removeLast() }
    }

    static func items(_ q: String) -> [Item] {
        history.filter { q.isEmpty || $0.localizedCaseInsensitiveContains(q) }.map { s in
            let line = s.split(whereSeparator: \.isNewline).joined(separator: " ")
            return Item(title: String(line.prefix(200)), subtitle: "Clipboard · Enter to paste", icon: { symbol("doc.on.clipboard") }) { copy(s); paste() }
        }
    }
}
