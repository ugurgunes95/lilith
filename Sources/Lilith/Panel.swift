import AppKit
import Quartz

struct Item {
    let title: String
    let subtitle: String
    let icon: () -> NSImage?  // lazy: only visible rows load icons
    var path: String? = nil  // set = ⌘K actions available
    var keepOpen = false  // Quick Look needs the panel alive as its controller
    let action: () -> Void
}

final class Panel: NSPanel, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate, QLPreviewPanelDataSource {
    let width: CGFloat = 640, fieldHeight: CGFloat = 56, rowHeight: CGFloat = 44, maxRows = 8
    let field = NSTextField()
    let table = NSTableView()
    let scroll = NSScrollView()
    var apps: [App] = []
    var scripts: [String] = []
    let files = FileSearch()
    var items: [Item] = []
    var icons: [String: NSImage] = [:]
    // ponytail: all-time activation counts, no decay. Add time decay if old favorites linger.
    var usage = UserDefaults.standard.dictionary(forKey: "usage") as? [String: Int] ?? [:]
    var top: CGFloat = 0
    var inActions = false
    var previewURL: URL?

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        delegate = self
        files.onUpdate = { [weak self] in self?.refresh() }

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
        field.placeholderString = "Search apps, files, 2+2, or cb for clipboard"
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
    override var canBecomeMain: Bool { true }  // stays main while the preview is key, so it keeps controlling it

    func toggle(query: String = "") {
        if isVisible { return orderOut(nil) }
        NSApp.unhideWithoutActivation()  // closing a preview hides the app, and a hidden app's windows can't show
        apps = scanApps()
        scripts = scanScripts()
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
        inActions = false
        let q = field.stringValue
        let d = UserDefaults.standard
        if d.bool(forKey: "clipboard"), q == "cb" || q.hasPrefix("cb ") {
            items = Array(Clipboard.items(String(q.dropFirst(3))).prefix(maxRows))
        } else {
            let ranked = apps.compactMap { app in
                (q.isEmpty ? usage[app.id] : score(q, app.name)).map { s in
                    (s, Item(title: app.name, subtitle: app.path, icon: { self.icon(app.path) }, path: app.path) {
                        NSWorkspace.shared.open(URL(fileURLWithPath: app.path))
                    })
                }
            } + scripts.compactMap { path in
                let name = String(URL(fileURLWithPath: path).lastPathComponent.dropLast(3))
                return score(q, name).map { s in
                    (s, Item(title: name, subtitle: path, icon: { self.icon(path) }, path: path) {
                        runScript(path) { self.showOutput(name, $0, $1) }
                    })
                }
            } + (d.bool(forKey: "system") ? systemItems(q) : [])
            let calc = d.bool(forKey: "calc") ? calcItem(q) : nil
            files.search(d.bool(forKey: "files") ? q : "")
            let found = files.results.map { path in
                Item(title: FileManager.default.displayName(atPath: path), subtitle: (path as NSString).abbreviatingWithTildeInPath,
                     icon: { self.icon(path) }, path: path, keepOpen: true) { self.preview(path) }
            }
            let link = urlItem(q)
            items = Array((([link, calc].compactMap { $0 }) + ranked.sorted { $0.0 > $1.0 }.map(\.1) + found).prefix(maxRows))
        }
        layout()
    }

    /// Reopens the panel with a finished script's output, one row per line; Enter copies. Silent on clean exit with no output.
    func showOutput(_ name: String, _ out: String, _ status: Int32) {
        let lines = out.split(whereSeparator: \.isNewline).suffix(200)  // ponytail: last 200 lines only
        if lines.isEmpty && status == 0 { return }
        if !isVisible { toggle() }
        let header = Item(title: "\(name) · exit \(status)", subtitle: lines.isEmpty ? "No output" : "Enter copies all, or pick a line",
                          icon: { symbol(status == 0 ? "checkmark.circle" : "xmark.octagon") }) { Lilith.copy(out) }
        items = [header] + lines.map { line in Item(title: String(line), subtitle: "", icon: { nil }) { Lilith.copy(String(line)) } }
        layout()
    }

    func layout() {
        table.reloadData()
        if !items.isEmpty { table.selectRowIndexes([0], byExtendingSelection: false) }

        let listHeight = items.isEmpty ? 0 : CGFloat(min(items.count, maxRows)) * rowHeight + 8
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
        if !items[row].keepOpen { orderOut(nil) }
        items[row].action()
    }

    /// ⌘K: actions for the selected file/app/script, replacing the result list. Esc goes back.
    func showActions() {
        guard items.indices.contains(table.selectedRow), let path = items[table.selectedRow].path else { return NSSound.beep() }
        let name = items[table.selectedRow].title, url = URL(fileURLWithPath: path)
        items = [
            Item(title: "Quick Look", subtitle: name, icon: { symbol("eye") }, keepOpen: true) { self.preview(path) },
            Item(title: "Open", subtitle: name, icon: { symbol("arrow.up.forward.app") }) { NSWorkspace.shared.open(url) },
            Item(title: "Reveal in Finder", subtitle: name, icon: { symbol("folder") }) {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            },
        ]
        layout()
        inActions = true
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
              event.charactersIgnoringModifiers == "k" else { return super.performKeyEquivalent(with: event) }
        showActions()
        return true
    }

    // MARK: Quick Look (panel stays open: it's the preview's controller via the responder chain)

    func preview(_ path: String) {
        previewURL = URL(fileURLWithPath: path)
        let ql = QLPreviewPanel.shared()!
        NSApp.activate()  // the launcher takes keys without activating us; the preview needs a real active app to get focus
        ql.isVisible ? ql.reloadData() : ql.makeKeyAndOrderFront(nil)
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }
    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) { panel.dataSource = self }
    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        orderOut(nil)  // preview closed = done, like opening a file; never grab focus back from another app
        NSApp.hide(nil)  // undo the activation so focus returns to the previous app
    }
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { previewURL == nil ? 0 : 1 }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! { previewURL as NSURL? }

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
        case #selector(NSResponder.cancelOperation(_:)): inActions ? refresh() : orderOut(nil)
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

    func windowDidResignKey(_ notification: Notification) {
        if QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible { return }  // focus went to the preview
        orderOut(nil)
    }
}
