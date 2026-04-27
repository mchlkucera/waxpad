import AppKit
import Carbon

extension NSAttributedString.Key {
    static let hiddenSyntax = NSAttributedString.Key("WaxpadHiddenSyntax")
}

// MARK: - Config

let notesDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".waxpad-notes")

// MARK: - App Entry

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)

let mainMenu = NSMenu()
let editMenuItem = NSMenuItem()
editMenuItem.submenu = {
    let m = NSMenu(title: "Edit")
    m.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
    m.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
    m.addItem(.separator())
    m.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    m.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    m.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    m.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    return m
}()
mainMenu.addItem(editMenuItem)
app.mainMenu = mainMenu
app.run()

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var panel: NotesPanel!
    var hotKeyRef: EventHotKeyRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !FileManager.default.fileExists(atPath: notesDir.path) {
            try? FileManager.default.createDirectory(at: notesDir, withIntermediateDirectories: true)
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let btn = statusItem.button {
            btn.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "Waxpad")
            btn.action = #selector(togglePanel)
            btn.target = self
        }

        panel = NotesPanel()
        restoreWindowFrame()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        registerHotKey()
    }

    func applicationWillTerminate(_ notification: Notification) { saveWindowFrame() }

    @objc func togglePanel() {
        if panel.isVisible {
            saveWindowFrame()
            panel.orderOut(nil)
        } else {
            restoreWindowFrame()
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func saveWindowFrame() {
        UserDefaults.standard.set(NSStringFromRect(panel.frame), forKey: "WaxpadWindowFrame")
    }

    func restoreWindowFrame() {
        if let s = UserDefaults.standard.string(forKey: "WaxpadWindowFrame") {
            let f = NSRectFromString(s)
            if NSScreen.screens.contains(where: { $0.frame.intersects(f) }) {
                panel.setFrame(f, display: false)
                return
            }
        }
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) {
            let sf = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: sf.midX - panel.frame.width / 2, y: sf.midY - panel.frame.height / 2))
        }
    }

    func registerHotKey() {
        let id = EventHotKeyID(signature: OSType(0x514E), id: 1)
        var ref: EventHotKeyRef?
        RegisterEventHotKey(UInt32(kVK_ANSI_N), UInt32(optionKey), id,
                            GetApplicationEventTarget(), 0, &ref)
        hotKeyRef = ref
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                       eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ -> OSStatus in
            (NSApp.delegate as? AppDelegate)?.togglePanel()
            return noErr
        }, 1, &eventType, nil, nil)
    }
}

// MARK: - Markdown Styler

struct MarkdownStyler {
    static let bodyFont = NSFont.systemFont(ofSize: 15, weight: .regular)
    static let boldFont = NSFont.systemFont(ofSize: 15, weight: .bold)
    static let monoFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    static let h1Font = NSFont.systemFont(ofSize: 22, weight: .bold)
    static let h2Font = NSFont.systemFont(ofSize: 18, weight: .bold)
    static let h3Font = NSFont.systemFont(ofSize: 16, weight: .semibold)
    static let textColor = NSColor(white: 0.93, alpha: 1.0)
    static let dimColor = NSColor(white: 1.0, alpha: 0.28)
    static let accentColor = NSColor(calibratedRed: 0.35, green: 0.55, blue: 0.95, alpha: 1.0)
    static let checkDoneColor = NSColor(white: 1.0, alpha: 0.38)

    private static let heading = try! NSRegularExpression(pattern: "^(#{1,3})\\s+(.+)$", options: .anchorsMatchLines)
    private static let bold = try! NSRegularExpression(pattern: "\\*\\*(.+?)\\*\\*", options: [])
    private static let italic = try! NSRegularExpression(pattern: "(?<!\\*)\\*(?!\\*)(.+?)(?<!\\*)\\*(?!\\*)", options: [])
    private static let inlineCode = try! NSRegularExpression(pattern: "`([^`]+)`", options: [])
    private static let unchecked = try! NSRegularExpression(pattern: "^(\\s*)(- \\[ \\])(.*)$", options: .anchorsMatchLines)
    private static let checked = try! NSRegularExpression(pattern: "^(\\s*)(- \\[x\\])(.*)$", options: .anchorsMatchLines)
    private static let bullet = try! NSRegularExpression(pattern: "^(\\s*)([-*])\\s", options: .anchorsMatchLines)
    private static let numbered = try! NSRegularExpression(pattern: "^(\\s*)(\\d+\\.)\\s", options: .anchorsMatchLines)
    private static let blockquote = try! NSRegularExpression(pattern: "^>\\s?(.*)$", options: .anchorsMatchLines)
    private static let link = try! NSRegularExpression(pattern: "\\[([^\\]]+)\\]\\(([^)]+)\\)", options: [])
    private static let hr = try! NSRegularExpression(pattern: "^-{3,}$", options: .anchorsMatchLines)

    static func style(_ ts: NSTextStorage) {
        let text = ts.string
        let full = NSRange(location: 0, length: (text as NSString).length)
        let ns = text as NSString

        let para = NSMutableParagraphStyle()
        para.lineSpacing = 0
        para.paragraphSpacing = 6

        ts.setAttributes([.font: bodyFont, .foregroundColor: textColor, .paragraphStyle: para], range: full)

        // Headings — dim the ## prefix, never hide it (hiding causes layout jumps)
        heading.enumerateMatches(in: text, range: full) { m, _, _ in
            guard let m else { return }
            let level = m.range(at: 1).length
            let font = level == 1 ? h1Font : level == 2 ? h2Font : h3Font
            ts.addAttribute(.font, value: font, range: m.range)
            ts.addAttribute(.foregroundColor, value: dimColor, range: m.range(at: 1))
            let hp = NSMutableParagraphStyle()
            hp.lineSpacing = 2; hp.paragraphSpacingBefore = 12; hp.paragraphSpacing = 4
            ts.addAttribute(.paragraphStyle, value: hp, range: m.range)
        }

        // Bold
        bold.enumerateMatches(in: text, range: full) { m, _, _ in
            guard let m else { return }
            ts.addAttribute(.font, value: boldFont, range: m.range(at: 1))
            for r in [NSRange(location: m.range.location, length: 2),
                       NSRange(location: m.range.location + m.range.length - 2, length: 2)] {
                ts.addAttribute(.foregroundColor, value: dimColor, range: r)
                ts.addAttribute(.hiddenSyntax, value: true, range: r)
            }
        }

        // Italic
        italic.enumerateMatches(in: text, range: full) { m, _, _ in
            guard let m else { return }
            let desc = bodyFont.fontDescriptor.withSymbolicTraits(.italic)
            ts.addAttribute(.font, value: NSFont(descriptor: desc, size: bodyFont.pointSize) ?? bodyFont, range: m.range(at: 1))
            for r in [NSRange(location: m.range.location, length: 1),
                       NSRange(location: m.range.location + m.range.length - 1, length: 1)] {
                ts.addAttribute(.foregroundColor, value: dimColor, range: r)
                ts.addAttribute(.hiddenSyntax, value: true, range: r)
            }
        }

        // Inline code
        inlineCode.enumerateMatches(in: text, range: full) { m, _, _ in
            guard let m else { return }
            ts.addAttribute(.font, value: monoFont, range: m.range(at: 1))
            ts.addAttribute(.foregroundColor, value: accentColor, range: m.range(at: 1))
            for r in [NSRange(location: m.range.location, length: 1),
                       NSRange(location: m.range.location + m.range.length - 1, length: 1)] {
                ts.addAttribute(.foregroundColor, value: dimColor, range: r)
                ts.addAttribute(.hiddenSyntax, value: true, range: r)
            }
        }

        // Unchecked checkboxes — just dim the prefix
        unchecked.enumerateMatches(in: text, range: full) { m, _, _ in
            guard let m else { return }
            ts.addAttribute(.foregroundColor, value: dimColor, range: m.range(at: 2))
        }

        // Checked checkboxes — dim prefix, strikethrough text
        checked.enumerateMatches(in: text, range: full) { m, _, _ in
            guard let m else { return }
            ts.addAttribute(.foregroundColor, value: dimColor, range: m.range(at: 2))
            ts.addAttribute(.foregroundColor, value: checkDoneColor, range: m.range(at: 3))
            ts.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: m.range(at: 3))
            ts.addAttribute(.strikethroughColor, value: checkDoneColor, range: m.range(at: 3))
        }

        // Bullets (skip checkbox lines)
        bullet.enumerateMatches(in: text, range: full) { m, _, _ in
            guard let m else { return }
            let lineRange = ns.lineRange(for: m.range)
            let line = ns.substring(with: lineRange)
            if line.contains("[ ]") || line.contains("[x]") { return }
            ts.addAttribute(.foregroundColor, value: dimColor, range: m.range(at: 2))
            let indentPx = CGFloat(m.range(at: 1).length) * 8 + 16
            let bp = NSMutableParagraphStyle()
            bp.paragraphSpacing = 6; bp.headIndent = indentPx
            ts.addAttribute(.paragraphStyle, value: bp, range: lineRange)
        }

        // Numbered lists
        numbered.enumerateMatches(in: text, range: full) { m, _, _ in
            guard let m else { return }
            ts.addAttribute(.foregroundColor, value: dimColor, range: m.range(at: 2))
        }

        // Blockquotes
        blockquote.enumerateMatches(in: text, range: full) { m, _, _ in
            guard let m else { return }
            let qp = NSMutableParagraphStyle()
            qp.headIndent = 18; qp.firstLineHeadIndent = 18; qp.lineSpacing = 2
            ts.addAttributes([.paragraphStyle: qp, .foregroundColor: NSColor(white: 1.0, alpha: 0.6)], range: m.range)
            ts.addAttribute(.foregroundColor, value: accentColor, range: NSRange(location: m.range.location, length: 1))
        }

        // Horizontal rules
        hr.enumerateMatches(in: text, range: full) { m, _, _ in
            guard let m else { return }
            let c = NSColor(white: 1.0, alpha: 0.15)
            ts.addAttribute(.foregroundColor, value: c, range: m.range)
            ts.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: m.range)
            ts.addAttribute(.strikethroughColor, value: c, range: m.range)
        }

        // Links
        link.enumerateMatches(in: text, range: full) { m, _, _ in
            guard let m else { return }
            let tr = m.range(at: 1)
            ts.addAttribute(.foregroundColor, value: accentColor, range: tr)
            ts.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: tr)
            ts.addAttribute(.link, value: ns.substring(with: m.range(at: 2)), range: tr)
            let open = NSRange(location: m.range.location, length: 1)
            let rest = NSRange(location: tr.location + tr.length, length: m.range.length - tr.length - 1)
            for r in [open, rest] {
                ts.addAttribute(.foregroundColor, value: dimColor, range: r)
                ts.addAttribute(.hiddenSyntax, value: true, range: r)
            }
        }
    }
}

// MARK: - Layout Manager

class WaxpadLayoutManager: NSLayoutManager {
    override func setGlyphs(_ glyphs: UnsafePointer<CGGlyph>,
                            properties props: UnsafePointer<NSLayoutManager.GlyphProperty>,
                            characterIndexes charIndexes: UnsafePointer<Int>,
                            font aFont: NSFont, forGlyphRange glyphRange: NSRange) {
        var mg = Array(UnsafeBufferPointer(start: glyphs, count: glyphRange.length))
        var mp = Array(UnsafeBufferPointer(start: props, count: glyphRange.length))
        for i in 0..<glyphRange.length {
            let ci = charIndexes[i]
            if ci < (textStorage?.length ?? 0),
               textStorage?.attribute(.hiddenSyntax, at: ci, effectiveRange: nil) != nil {
                mg[i] = CGGlyph.max; mp[i] = .null
            }
        }
        mg.withUnsafeBufferPointer { g in
            mp.withUnsafeBufferPointer { p in
                super.setGlyphs(g.baseAddress!, properties: p.baseAddress!,
                               characterIndexes: charIndexes, font: aFont, forGlyphRange: glyphRange)
            }
        }
    }
}

// MARK: - Editor

class StyledEditor: NSTextView {
    var isRestyling = false
    var previousRevealedLine: NSRange?
    weak var notesPanel: NotesPanel?

    override func keyDown(with event: NSEvent) {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let chars = event.charactersIgnoringModifiers ?? ""

        switch (mods, event.keyCode, chars) {
        case (.command, 36, _):             toggleCheckbox(); return
        case (.command, _, "b"):            wrapSelection(with: "**"); return
        case (.command, _, "i"):            wrapSelection(with: "*"); return
        case (.command, _, "e"):            wrapSelection(with: "`"); return
        case ([.command, .option], _, "1"): toggleLinePrefix("# "); return
        case ([.command, .option], _, "2"): toggleLinePrefix("## "); return
        case ([.command, .option], _, "3"): toggleLinePrefix("### "); return
        case ([.command, .shift], 25, _):   toggleCheckbox(); return
        case ([.command, .shift], 33, _):   notesPanel?.switchTab(delta: -1); return
        case ([.command, .shift], 30, _):   notesPanel?.switchTab(delta: 1); return
        default: break
        }

        if mods == .command, let d = chars.first, d >= "1" && d <= "9" {
            notesPanel?.selectNote(at: Int(String(d))! - 1); return
        }
        if event.keyCode == 36 && mods.isEmpty && handleListContinuation() { return }
        super.keyDown(with: event)
    }

    override func insertTab(_ sender: Any?) {
        if handleListIndent(outdent: false) { return }
        insertText("    ", replacementRange: selectedRange())
    }

    override func insertBacktab(_ sender: Any?) {
        _ = handleListIndent(outdent: true)
    }

    override func paste(_ sender: Any?) {
        guard let paste = NSPasteboard.general.string(forType: .string) else { super.paste(sender); return }
        let sel = selectedRange()
        if sel.length > 0,
           let url = URL(string: paste.trimmingCharacters(in: .whitespacesAndNewlines)),
           let s = url.scheme, s == "http" || s == "https" {
            let text = (string as NSString).substring(with: sel)
            let link = "[\(text)](\(paste.trimmingCharacters(in: .whitespacesAndNewlines)))"
            replaceText(in: sel, with: link, cursorAt: sel.location + link.count)
            return
        }
        replaceText(in: sel, with: paste, cursorAt: sel.location + (paste as NSString).length)
    }

    private func replaceText(in range: NSRange, with str: String, cursorAt pos: Int) {
        if shouldChangeText(in: range, replacementString: str) {
            textStorage?.replaceCharacters(in: range, with: str)
            didChangeText()
            setSelectedRange(NSRange(location: pos, length: 0))
        }
    }

    func wrapSelection(with marker: String) {
        let sel = selectedRange()
        let text = string as NSString
        let mLen = marker.count
        if sel.length > 0 {
            let selected = text.substring(with: sel)
            if sel.location >= mLen && sel.location + sel.length + mLen <= text.length {
                let before = NSRange(location: sel.location - mLen, length: mLen)
                let after = NSRange(location: sel.location + sel.length, length: mLen)
                if text.substring(with: before) == marker && text.substring(with: after) == marker {
                    replaceText(in: NSRange(location: sel.location - mLen, length: sel.length + mLen * 2),
                                with: selected, cursorAt: sel.location - mLen)
                    return
                }
            }
            replaceText(in: sel, with: marker + selected + marker, cursorAt: sel.location + mLen)
        } else {
            replaceText(in: sel, with: marker + marker, cursorAt: sel.location + mLen)
        }
    }

    func toggleCheckbox() {
        let text = string as NSString
        let lineRange = text.lineRange(for: NSRange(location: selectedRange().location, length: 0))
        let line = text.substring(with: lineRange)
        var newLine: String
        if line.contains("- [ ]") {
            newLine = line.replacingOccurrences(of: "- [ ]", with: "- [x]")
        } else if line.contains("- [x]") {
            newLine = line.replacingOccurrences(of: "- [x]", with: "- [ ]")
        } else {
            let indent = String(line.prefix(while: { $0 == " " || $0 == "\t" }))
            let content = line.trimmingCharacters(in: .whitespacesAndNewlines)
            newLine = indent + "- [ ] " + (content.hasPrefix("- ") || content.hasPrefix("* ")
                ? String(content.dropFirst(2)) : content) + "\n"
        }
        replaceText(in: lineRange, with: newLine,
                     cursorAt: min(lineRange.location + newLine.count - 1, (string as NSString).length))
    }

    func toggleLinePrefix(_ prefix: String) {
        let text = string as NSString
        let lineRange = text.lineRange(for: NSRange(location: selectedRange().location, length: 0))
        let line = text.substring(with: lineRange)
        let newLine = line.hasPrefix(prefix)
            ? String(line.dropFirst(prefix.count))
            : prefix + line.replacingOccurrences(of: "^#{1,3}\\s+", with: "", options: .regularExpression)
        replaceText(in: lineRange, with: newLine,
                     cursorAt: min(lineRange.location + newLine.count - 1, (string as NSString).length))
    }

    func handleListContinuation() -> Bool {
        let text = string as NSString
        let cursor = selectedRange().location
        let lineRange = text.lineRange(for: NSRange(location: cursor, length: 0))
        let line = text.substring(with: lineRange).trimmingCharacters(in: .newlines)
        let nsLine = line as NSString
        let lr = NSRange(location: 0, length: nsLine.length)

        let patterns: [(content: String, empty: String, prefix: String?)] = [
            ("^(\\s*)- \\[ \\] (.+)$", "^(\\s*)- \\[ \\] $", "- [ ] "),
            ("^(\\s*)- \\[x\\] (.+)$", "^(\\s*)- \\[x\\] $", "- [ ] "),
            ("^(\\s*)- (.+)$",          "^(\\s*)- $",          "- "),
            ("^(\\s*)\\* (.+)$",        "^(\\s*)\\* $",        "* "),
            ("^(\\s*)(\\d+)\\. (.+)$",  "^(\\s*)(\\d+)\\. $",  nil),
        ]

        for (contentPat, emptyPat, prefix) in patterns {
            if let re = try? NSRegularExpression(pattern: emptyPat),
               re.firstMatch(in: line, range: lr) != nil {
                replaceText(in: lineRange, with: "\n", cursorAt: lineRange.location + 1)
                return true
            }
            if let re = try? NSRegularExpression(pattern: contentPat),
               let m = re.firstMatch(in: line, range: lr) {
                let indent = nsLine.substring(with: m.range(at: 1))
                let newPrefix: String
                if let p = prefix { newPrefix = indent + p }
                else { newPrefix = indent + "\((Int(nsLine.substring(with: m.range(at: 2))) ?? 0) + 1). " }
                let insertion = "\n" + newPrefix
                replaceText(in: NSRange(location: cursor, length: 0), with: insertion,
                             cursorAt: cursor + insertion.count)
                return true
            }
        }
        return false
    }

    func handleListIndent(outdent: Bool) -> Bool {
        let text = string as NSString
        let cursor = selectedRange().location
        let lineRange = text.lineRange(for: NSRange(location: cursor, length: 0))
        let line = text.substring(with: lineRange)
        let pat = try! NSRegularExpression(pattern: "^(\\s*)([-*]|\\d+\\.|\\- \\[[ x]\\])")
        guard pat.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) != nil else { return false }
        if outdent {
            guard line.hasPrefix("    ") else { return false }
            replaceText(in: lineRange, with: String(line.dropFirst(4)), cursorAt: max(lineRange.location, cursor - 4))
        } else {
            replaceText(in: lineRange, with: "    " + line, cursorAt: cursor + 4)
        }
        return true
    }

    func restyleMarkdown() {
        guard !isRestyling, let ts = textStorage else { return }
        isRestyling = true
        let sel = selectedRange()
        undoManager?.disableUndoRegistration()
        ts.beginEditing()
        MarkdownStyler.style(ts)
        let ns = string as NSString
        if sel.location <= ns.length {
            let cursorLine = ns.lineRange(for: NSRange(location: sel.location, length: 0))
            ts.removeAttribute(.hiddenSyntax, range: cursorLine)
            previousRevealedLine = cursorLine
        }
        ts.endEditing()
        if let lm = layoutManager {
            let full = NSRange(location: 0, length: ns.length)
            lm.invalidateGlyphs(forCharacterRange: full, changeInLength: 0, actualCharacterRange: nil)
            lm.invalidateLayout(forCharacterRange: full, actualCharacterRange: nil)
        }
        undoManager?.enableUndoRegistration()
        if sel.location <= ns.length { setSelectedRange(sel) }
        isRestyling = false
    }
}

// MARK: - Tab Button

class TabButton: NSView {
    let label = NSTextField(labelWithString: "")
    var isActive = false { didSet { refresh() } }
    var isHovered = false { didSet { refresh() } }
    var isPressed = false { didSet { refresh() } }
    var onClick: (() -> Void)?
    var onDoubleClick: (() -> Void)?
    private var tracking: NSTrackingArea?

    init(title: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.systemFont(ofSize: 12.5)
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.stringValue = title
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 26),
        ])
        refresh()
    }
    required init?(coder: NSCoder) { fatalError() }

    func refresh() {
        label.font = NSFont.systemFont(ofSize: 12.5, weight: isActive ? .medium : .regular)
        label.textColor = isActive ? NSColor(white: 0.95, alpha: 1.0) : NSColor(white: 1.0, alpha: 0.40)
        if isPressed { layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.16).cgColor }
        else if isActive { layer?.backgroundColor = MarkdownStyler.accentColor.withAlphaComponent(0.15).cgColor }
        else if isHovered { layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.07).cgColor }
        else { layer?.backgroundColor = nil }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        tracking = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp], owner: self)
        addTrackingArea(tracking!)
    }
    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false; isPressed = false }
    override func mouseDown(with event: NSEvent) { isPressed = true }
    override func mouseUp(with event: NSEvent) {
        isPressed = false
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        event.clickCount == 2 ? onDoubleClick?() : onClick?()
    }
    override var intrinsicContentSize: NSSize {
        NSSize(width: label.intrinsicContentSize.width + 24, height: 26)
    }
}

// MARK: - Empty State Button


// MARK: - Notes Panel

class NotesPanel: NSPanel, NSTextViewDelegate {
    let tabStack = NSStackView()
    let editor: StyledEditor
    var currentFile: URL?
    var notes: [URL] = []
    var tabButtons: [TabButton] = []
    private var saveTimer: Timer?
    private var fileWatcher: DispatchSourceFileSystemObject?
    private var emptyStateView: NSView?
    private var editorScroll: NSScrollView?
    private var addBtnLabel: NSTextField?
    private var addBtnWrap: NSView?

    init() {
        let ts = NSTextStorage()
        let lm = WaxpadLayoutManager()
        let tc = NSTextContainer(containerSize: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        tc.widthTracksTextView = true
        lm.addTextContainer(tc)
        ts.addLayoutManager(lm)
        editor = StyledEditor(frame: .zero, textContainer: tc)

        super.init(contentRect: NSRect(x: 0, y: 0, width: 540, height: 440),
                   styleMask: [.titled, .resizable, .fullSizeContentView, .utilityWindow, .hudWindow],
                   backing: .buffered, defer: false)

        editor.notesPanel = self
        title = ""
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        for btn in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(btn)?.isHidden = true
        }
        level = .floating
        isFloatingPanel = true
        hidesOnDeactivate = false
        animationBehavior = .none
        isMovableByWindowBackground = true
        backgroundColor = NSColor(calibratedRed: 0.09, green: 0.09, blue: 0.10, alpha: 0.99)
        isOpaque = false
        hasShadow = true
        center()
        setupUI()
        loadNotes()

        for n in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            NotificationCenter.default.addObserver(forName: n, object: self, queue: nil) { _ in
                UserDefaults.standard.set(NSStringFromRect(self.frame), forKey: "WaxpadWindowFrame")
            }
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func setupUI() {
        guard let content = contentView else { return }
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor(calibratedRed: 0.10, green: 0.10, blue: 0.11, alpha: 1.0).cgColor
        content.layer?.cornerRadius = 14
        content.layer?.masksToBounds = true
        content.layer?.borderWidth = 1
        content.layer?.borderColor = NSColor(white: 1.0, alpha: 0.08).cgColor

        let tabBar = NSScrollView()
        tabBar.translatesAutoresizingMaskIntoConstraints = false
        tabBar.hasHorizontalScroller = false
        tabBar.hasVerticalScroller = false
        tabBar.verticalScrollElasticity = .none
        tabBar.drawsBackground = false
        tabBar.borderType = .noBorder

        tabStack.translatesAutoresizingMaskIntoConstraints = false
        tabStack.orientation = .horizontal
        tabStack.spacing = 4
        tabStack.alignment = .centerY
        tabStack.edgeInsets = NSEdgeInsets(top: 0, left: 20, bottom: 0, right: 4)
        tabBar.documentView = tabStack

        let addBtn = NSTextField(labelWithString: "+")
        addBtn.translatesAutoresizingMaskIntoConstraints = false
        addBtn.font = NSFont.systemFont(ofSize: 16, weight: .light)
        addBtn.textColor = NSColor(white: 1.0, alpha: 0.30)
        let addWrap = NSView()
        addWrap.translatesAutoresizingMaskIntoConstraints = false
        addWrap.wantsLayer = true
        addWrap.layer?.cornerRadius = 7
        addWrap.addSubview(addBtn)
        NSLayoutConstraint.activate([
            addBtn.centerXAnchor.constraint(equalTo: addWrap.centerXAnchor),
            addBtn.centerYAnchor.constraint(equalTo: addWrap.centerYAnchor),
            addWrap.widthAnchor.constraint(equalToConstant: 26),
            addWrap.heightAnchor.constraint(equalToConstant: 26),
        ])
        addWrap.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(addNote)))
        addBtnLabel = addBtn
        addBtnWrap = addWrap

        let tabRow = NSStackView(views: [tabBar, addWrap])
        tabRow.translatesAutoresizingMaskIntoConstraints = false
        tabRow.orientation = .horizontal
        tabRow.spacing = 4
        tabRow.alignment = .centerY
        tabRow.edgeInsets = NSEdgeInsets(top: 0, left: -4, bottom: 0, right: 12)

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.documentView = editor
        editorScroll = scroll

        editor.minSize = NSSize(width: 0, height: 0)
        editor.maxSize = NSSize(width: .max, height: .max)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.containerSize = NSSize(width: 0, height: .max)
        editor.textContainer?.widthTracksTextView = true
        editor.textContainerInset = NSSize(width: 20, height: 14)
        editor.isRichText = true
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isAutomaticLinkDetectionEnabled = false
        editor.insertionPointColor = MarkdownStyler.accentColor
        editor.drawsBackground = false
        editor.allowsUndo = true
        editor.isEditable = false
        editor.delegate = self
        editor.typingAttributes = [.font: MarkdownStyler.bodyFont, .foregroundColor: MarkdownStyler.textColor]

        content.addSubview(tabRow)
        content.addSubview(scroll)
        NSLayoutConstraint.activate([
            tabRow.topAnchor.constraint(equalTo: content.safeAreaLayoutGuide.topAnchor, constant: 2),
            tabRow.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            tabRow.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            tabRow.heightAnchor.constraint(equalToConstant: 34),
            scroll.topAnchor.constraint(equalTo: tabRow.bottomAnchor, constant: 4),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
    }

    // MARK: - Empty State

    func showEmptyState() {
        guard emptyStateView == nil, let content = contentView else { return }
        editorScroll?.isHidden = true

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let emoji = NSTextField(labelWithString: "📝")
        emoji.font = NSFont.systemFont(ofSize: 32)
        emoji.alignment = .center
        emoji.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "No notes yet")
        title.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        title.textColor = NSColor(white: 1.0, alpha: 0.5)
        title.alignment = .center
        title.translatesAutoresizingMaskIntoConstraints = false

        let subtitle = NSTextField(labelWithString: "Hit + to get started")
        subtitle.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        subtitle.textColor = NSColor(white: 1.0, alpha: 0.25)
        subtitle.alignment = .center
        subtitle.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(emoji)
        container.addSubview(title)
        container.addSubview(subtitle)
        content.addSubview(container)

        NSLayoutConstraint.activate([
            container.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            container.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            emoji.topAnchor.constraint(equalTo: container.topAnchor),
            emoji.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            title.topAnchor.constraint(equalTo: emoji.bottomAnchor, constant: 8),
            title.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 4),
            subtitle.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            subtitle.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        emptyStateView = container

        // Make the + button pop
        let accent = MarkdownStyler.accentColor
        addBtnLabel?.textColor = accent
        addBtnWrap?.layer?.backgroundColor = accent.withAlphaComponent(0.15).cgColor
        addBtnWrap?.layer?.borderWidth = 1
        addBtnWrap?.layer?.borderColor = accent.withAlphaComponent(0.4).cgColor
    }

    func hideEmptyState() {
        emptyStateView?.removeFromSuperview()
        emptyStateView = nil
        editorScroll?.isHidden = false
        editor.isEditable = true
        // Reset + button to normal
        addBtnLabel?.textColor = NSColor(white: 1.0, alpha: 0.30)
        addBtnWrap?.layer?.backgroundColor = nil
        addBtnWrap?.layer?.borderWidth = 0
    }

    // MARK: - Notes

    func loadNotes() {
        notes = (try? FileManager.default.contentsOfDirectory(at: notesDir, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "md" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
        rebuildTabs()
        if notes.isEmpty {
            currentFile = nil
            editor.string = ""
            editor.isEditable = false
            showEmptyState()
        } else {
            hideEmptyState()
            editor.isEditable = true
            if currentFile == nil { selectNote(at: 0) }
        }
    }

    func rebuildTabs() {
        tabButtons.forEach { $0.removeFromSuperview() }
        tabButtons.removeAll()
        for (i, url) in notes.enumerated() {
            let tab = TabButton(title: url.deletingPathExtension().lastPathComponent)
            tab.translatesAutoresizingMaskIntoConstraints = false
            tab.onClick = { [weak self] in self?.selectNote(at: i) }
            tab.onDoubleClick = { [weak self] in self?.renameNote(at: i) }
            let menu = NSMenu()
            let del = NSMenuItem(title: "Delete Note", action: #selector(deleteNote(_:)), keyEquivalent: "")
            del.tag = i; del.target = self; menu.addItem(del)
            tab.menu = menu
            tabStack.addArrangedSubview(tab)
            tabButtons.append(tab)
        }
        highlightActiveTab()
    }

    func highlightActiveTab() {
        guard let f = currentFile, let idx = notes.firstIndex(of: f) else { return }
        for (i, tab) in tabButtons.enumerated() { tab.isActive = i == idx }
    }

    func selectNote(at index: Int) {
        guard index >= 0, index < notes.count else { return }
        saveCurrentNote()
        currentFile = notes[index]
        editor.undoManager?.removeAllActions()
        editor.string = (try? String(contentsOf: notes[index], encoding: .utf8)) ?? ""
        editor.restyleMarkdown()
        highlightActiveTab()
        watchFile(notes[index])
    }

    func switchTab(delta: Int) {
        guard let f = currentFile, let idx = notes.firstIndex(of: f) else { return }
        let next = idx + delta
        if next >= 0 && next < notes.count { selectNote(at: next) }
    }

    func saveCurrentNote() {
        guard let f = currentFile, FileManager.default.fileExists(atPath: f.path) else { return }
        try? editor.string.write(to: f, atomically: true, encoding: .utf8)
    }

    func scheduleSave() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            self?.saveCurrentNote()
        }
    }

    func renameNote(at index: Int) {
        guard index >= 0, index < notes.count else { return }
        let url = notes[index]
        let current = url.deletingPathExtension().lastPathComponent

        let alert = NSAlert()
        alert.messageText = "Rename Note"
        alert.informativeText = "Enter a new name:"
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        input.stringValue = current
        alert.accessoryView = input
        alert.window.initialFirstResponder = input
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let newName = input.stringValue.trimmingCharacters(in: .whitespaces)
        guard !newName.isEmpty, newName != current else { return }

        let safe = newName.replacingOccurrences(of: "[/\\\\:]", with: "-", options: .regularExpression).prefix(60)
        let newURL = notesDir.appendingPathComponent(String(safe) + ".md")

        if newURL != url && !FileManager.default.fileExists(atPath: newURL.path) {
            saveCurrentNote()
            try? FileManager.default.moveItem(at: url, to: newURL)
        }

        let wasSelected = (currentFile == url)
        loadNotes()
        if wasSelected, let idx = notes.firstIndex(of: FileManager.default.fileExists(atPath: newURL.path) ? newURL : url) {
            selectNote(at: idx)
        }
    }

    @objc func addNote() {
        var file = notesDir.appendingPathComponent("New Note.md")
        var c = 2
        while FileManager.default.fileExists(atPath: file.path) {
            file = notesDir.appendingPathComponent("New Note \(c).md"); c += 1
        }
        try? "".write(to: file, atomically: true, encoding: .utf8)
        loadNotes()
        if let idx = notes.firstIndex(of: file) { selectNote(at: idx); makeFirstResponder(editor) }
    }

    @objc func deleteNote(_ sender: NSMenuItem) {
        let idx = sender.tag
        guard idx >= 0, idx < notes.count else { return }
        let alert = NSAlert()
        alert.messageText = "Delete \"\(notes[idx].deletingPathExtension().lastPathComponent)\"?"
        alert.informativeText = "This cannot be undone."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        try? FileManager.default.removeItem(at: notes[idx])
        if currentFile == notes[idx] { currentFile = nil; editor.string = "" }
        loadNotes()
    }

    func watchFile(_ url: URL) {
        fileWatcher?.cancel()
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .delete, .rename], queue: .main)
        source.setEventHandler { [weak self] in
            guard let self, let file = self.currentFile else { return }
            // File was deleted or renamed externally — swap to another note
            if !FileManager.default.fileExists(atPath: file.path) {
                self.fileWatcher?.cancel()
                self.currentFile = nil
                self.loadNotes()
                if !self.notes.isEmpty { self.selectNote(at: 0) }
                else { self.editor.string = "" }
                return
            }
            // File was modified externally — reload content
            guard let content = try? String(contentsOf: file, encoding: .utf8),
                  content != self.editor.string else { return }
            let sel = self.editor.selectedRange()
            self.editor.string = content
            self.editor.restyleMarkdown()
            if sel.location <= content.count { self.editor.setSelectedRange(sel) }
        }
        source.setCancelHandler { Darwin.close(fd) }
        source.resume()
        fileWatcher = source
    }

    // MARK: - NSTextViewDelegate

    func textDidChange(_ notification: Notification) {
        guard !editor.isRestyling else { return }
        scheduleSave()
        editor.restyleMarkdown()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard !editor.isRestyling else { return }
        let ns = editor.string as NSString
        guard ns.length > 0 else { return }
        let sel = editor.selectedRange()
        guard sel.location <= ns.length else { return }
        let line = ns.lineRange(for: NSRange(location: sel.location, length: 0))
        if let prev = editor.previousRevealedLine, NSEqualRanges(prev, line) { return }
        editor.restyleMarkdown()
    }
}
