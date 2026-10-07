import AppKit

struct Item {
    let title: String
    let subtitle: String
    let icon: () -> NSImage?  // lazy: only visible rows load icons
    let action: () -> Void
}

final class Panel: NSPanel, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    let width: CGFloat = 640, fieldHeight: CGFloat = 56, rowHeight: CGFloat = 44, maxRows = 8
    let field = NSTextField()
    let table = NSTableView()
    let scroll = NSScrollView()
    var apps: [App] = []
    var items: [Item] = []
    var icons: [String: NSImage] = [:]
    // ponytail: all-time activation counts, no decay. Add time decay if old favorites linger.
    var usage = UserDefaults.standard.dictionary(forKey: "usage") as? [String: Int] ?? [:]
    var top: CGFloat = 0

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        delegate = self

        let bg = NSVisualEffectView()
        bg.material = .hudWindow
        bg.state = .active
        bg.wantsLayer = true
        bg.layer?.cornerRadius = 12
        bg.layer?.masksToBounds = true
        contentView = bg

        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 24)
        field.placeholderString = "Search apps, 2+2, or cb for clipboard"
        field.delegate = self
        bg.addSubview(field)

        table.addTableColumn(NSTableColumn(identifier: .init("item")))
        table.headerView = nil
        table.rowHeight = rowHeight
        table.style = .plain
        table.backgroundColor = .clear
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(clicked)
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        bg.addSubview(scroll)

        // Count every app activation (Dock, Cmd-Tab, this launcher) as "use".
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard let id = app?.bundleIdentifier ?? app?.bundleURL?.path else { return }
            MainActor.assumeIsolated {
                guard let self else { return }
                self.usage[id, default: 0] += 1
                UserDefaults.standard.set(self.usage, forKey: "usage")
            }
        }
    }

    override var canBecomeKey: Bool { true }

    func toggle(query: String = "") {
        if isVisible { return orderOut(nil) }
        apps = scanApps()
        field.stringValue = query
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main!
        let vf = screen.visibleFrame
        top = vf.maxY - vf.height * 0.25
        setFrameOrigin(NSPoint(x: vf.midX - width / 2, y: top))
        refresh()
        makeKeyAndOrderFront(nil)
        makeFirstResponder(field)
        field.currentEditor()?.selectedRange = NSRange(location: query.count, length: 0)  // caret after prefill, not select-all
    }

    func refresh() {
        let q = field.stringValue
        let d = UserDefaults.standard
        if d.bool(forKey: "clipboard"), q == "cb" || q.hasPrefix("cb ") {
            items = Array(Clipboard.items(String(q.dropFirst(3))).prefix(maxRows))
        } else {
            let ranked = apps.compactMap { app in
                (q.isEmpty ? usage[app.id] : score(q, app.name)).map { s in
                    (s, Item(title: app.name, subtitle: app.path, icon: { self.icon(app.path) }) {
                        NSWorkspace.shared.open(URL(fileURLWithPath: app.path))
                    })
                }
            } + (d.bool(forKey: "system") ? systemItems(q) : [])
            let calc = d.bool(forKey: "calc") ? calcItem(q) : nil
            items = Array(((calc.map { [$0] } ?? []) + ranked.sorted { $0.0 > $1.0 }.map(\.1)).prefix(maxRows))
        }
        table.reloadData()
        if !items.isEmpty { table.selectRowIndexes([0], byExtendingSelection: false) }

        let listHeight = items.isEmpty ? 0 : CGFloat(items.count) * rowHeight + 8
        let height = fieldHeight + listHeight
        setFrame(NSRect(x: frame.minX, y: top - height, width: width, height: height), display: true)
        field.frame = NSRect(x: 16, y: height - fieldHeight + 12, width: width - 32, height: 32)
        scroll.frame = NSRect(x: 8, y: 4, width: width - 16, height: listHeight)
    }

    func icon(_ path: String) -> NSImage {
        if let cached = icons[path] { return cached }
        let image = NSWorkspace.shared.icon(forFile: path)
        icons[path] = image
        return image
    }

    func run(_ row: Int) {
        guard items.indices.contains(row) else { return }
        orderOut(nil)
        items[row].action()
    }

    @objc func clicked() { run(table.clickedRow) }

    func move(_ delta: Int) {
        guard !items.isEmpty else { return }
        let row = max(0, min(items.count - 1, table.selectedRow + delta))
        table.selectRowIndexes([row], byExtendingSelection: false)
        table.scrollRowToVisible(row)
    }

    // MARK: NSTextFieldDelegate

    func controlTextDidChange(_ obj: Notification) { refresh() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveUp(_:)): move(-1)
        case #selector(NSResponder.moveDown(_:)): move(1)
        case #selector(NSResponder.insertNewline(_:)): run(table.selectedRow)
        case #selector(NSResponder.cancelOperation(_:)): orderOut(nil)
        default: return false
        }
        return true
    }

    // MARK: NSTableView

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = items[row]
        let view = NSView()
        let image = NSImageView(image: item.icon() ?? NSImage())
        image.frame = NSRect(x: 8, y: 6, width: 32, height: 32)
        let title = NSTextField(labelWithString: item.title)
        title.font = .systemFont(ofSize: 15)
        title.frame = NSRect(x: 50, y: 21, width: width - 80, height: 19)
        let subtitle = NSTextField(labelWithString: item.subtitle)
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byTruncatingMiddle
        subtitle.frame = NSRect(x: 50, y: 5, width: width - 80, height: 15)
        [image, title, subtitle].forEach(view.addSubview)
        return view
    }

    // MARK: NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) { orderOut(nil) }
}
