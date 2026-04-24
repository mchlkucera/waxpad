import AppKit
import Carbon

// MARK: - Config

let notesDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".quick-notes")
// Global hotkey: Option+N
let hotKeyCombo: (keyCode: UInt32, modifiers: UInt32) = (
    UInt32(kVK_ANSI_N),
    UInt32(optionKey)
)

// MARK: - App Entry

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)

// Main menu for standard key equivalents
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
        ensureNotesDir()
        setupMenuBar()
        setupPanel()
        registerHotKey()
    }

    func ensureNotesDir() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: notesDir.path) {
            try? fm.createDirectory(at: notesDir, withIntermediateDirectories: true)
            let welcome = notesDir.appendingPathComponent("scratch.md")
            try? "# Scratch\n\nStart typing here...\n- [ ] First task\n- [x] Done task".write(
                to: welcome, atomically: true, encoding: .utf8)
        }
    }

    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let btn = statusItem.button {
            btn.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "Waxpad")
            btn.action = #selector(togglePanel)
            btn.target = self
        }
    }

    func setupPanel() {
        panel = NotesPanel()
        restoreWindowFrame()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        saveWindowFrame()
    }

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
        let frame = panel.frame
        UserDefaults.standard.set(NSStringFromRect(frame), forKey: "WaxpadWindowFrame")
    }

    func restoreWindowFrame() {
        if let frameStr = UserDefaults.standard.string(forKey: "WaxpadWindowFrame") {
            let frame = NSRectFromString(frameStr)
            // Verify the saved position is still on a visible screen
            if NSScreen.screens.contains(where: { $0.frame.intersects(frame) }) {
                panel.setFrame(frame, display: false)
                return
            }
        }
        // Fallback: center on active screen
        if let activeScreen = NSScreen.screens.first(where: {
            NSMouseInRect(NSEvent.mouseLocation, $0.frame, false)
        }) {
            let panelSize = panel.frame.size
            let screenFrame = activeScreen.visibleFrame
            let x = screenFrame.midX - panelSize.width / 2
            let y = screenFrame.midY - panelSize.height / 2
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }

    func registerHotKey() {
        let id = EventHotKeyID(signature: OSType(0x514E), id: 1)
        var ref: EventHotKeyRef?
        RegisterEventHotKey(hotKeyCombo.keyCode, hotKeyCombo.modifiers, id,
                            GetApplicationEventTarget(), 0, &ref)
        hotKeyRef = ref

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                       eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            guard let delegate = NSApp.delegate as? AppDelegate else { return noErr }
            delegate.togglePanel()
            return noErr
        }, 1, &eventType, nil, nil)
    }
}

// MARK: - Markdown Styler

class MarkdownStyler {
    static let bodyFont = NSFont.systemFont(ofSize: 13, weight: .regular)
    static let bodyMonoFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    static let boldFont = NSFont.systemFont(ofSize: 13, weight: .bold)
    static let h1Font = NSFont.systemFont(ofSize: 18, weight: .bold)
    static let h2Font = NSFont.systemFont(ofSize: 16, weight: .bold)
    static let h3Font = NSFont.systemFont(ofSize: 14, weight: .semibold)
    static let textColor = NSColor.white
    static let dimColor = NSColor(white: 1.0, alpha: 0.35)
    static let accentColor = NSColor(calibratedRed: 0.4, green: 0.7, blue: 1.0, alpha: 1.0)
    static let codeColor = NSColor(calibratedRed: 1.0, green: 0.6, blue: 0.4, alpha: 1.0)
    static let checkDoneColor = NSColor(white: 1.0, alpha: 0.45)
    static let codeBgColor = NSColor(white: 1.0, alpha: 0.08)
    static let hrColor = NSColor(white: 1.0, alpha: 0.2)

    static let headingPattern = try! NSRegularExpression(pattern: "^(#{1,3})\\s+(.+)$", options: .anchorsMatchLines)
    static let boldPattern = try! NSRegularExpression(pattern: "\\*\\*(.+?)\\*\\*", options: [])
    static let italicPattern = try! NSRegularExpression(pattern: "(?<!\\*)\\*(?!\\*)(.+?)(?<!\\*)\\*(?!\\*)", options: [])
    static let inlineCodePattern = try! NSRegularExpression(pattern: "`([^`]+)`", options: [])
    static let checkboxUnchecked = try! NSRegularExpression(pattern: "^(\\s*- )(\\[ \\])(.*)$", options: .anchorsMatchLines)
    static let checkboxChecked = try! NSRegularExpression(pattern: "^(\\s*- )(\\[x\\])(.*)$", options: .anchorsMatchLines)
    static let bulletPattern = try! NSRegularExpression(pattern: "^(\\s*)([-*])\\s", options: .anchorsMatchLines)
    static let blockQuotePattern = try! NSRegularExpression(pattern: "^>\\s?(.*)$", options: .anchorsMatchLines)
    static let linkPattern = try! NSRegularExpression(pattern: "\\[([^\\]]+)\\]\\(([^)]+)\\)", options: [])
    static let hrPattern = try! NSRegularExpression(pattern: "^-{3,}$", options: .anchorsMatchLines)
    static let numberedListPattern = try! NSRegularExpression(pattern: "^(\\s*)(\\d+\\.)\\s", options: .anchorsMatchLines)

    static func style(_ textStorage: NSTextStorage) {
        let text = textStorage.string
        let fullRange = NSRange(location: 0, length: (text as NSString).length)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 3
        paragraphStyle.paragraphSpacing = 4

        textStorage.setAttributes([
            .font: bodyFont,
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle,
        ], range: fullRange)

        let ns = text as NSString

        // Headings
        headingPattern.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            guard let match else { return }
            let hashRange = match.range(at: 1)
            let textRange = match.range(at: 2)
            let level = hashRange.length
            let font = level == 1 ? h1Font : level == 2 ? h2Font : h3Font
            textStorage.addAttribute(.font, value: font, range: textRange)
            textStorage.addAttribute(.foregroundColor, value: dimColor, range: hashRange)
        }

        // Bold
        boldPattern.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            guard let match else { return }
            textStorage.addAttribute(.font, value: boldFont, range: match.range(at: 1))
            let startMarker = NSRange(location: match.range.location, length: 2)
            let endMarker = NSRange(location: match.range.location + match.range.length - 2, length: 2)
            textStorage.addAttribute(.foregroundColor, value: dimColor, range: startMarker)
            textStorage.addAttribute(.foregroundColor, value: dimColor, range: endMarker)
        }

        // Italic
        italicPattern.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            guard let match else { return }
            let innerRange = match.range(at: 1)
            let italicDesc = bodyFont.fontDescriptor.withSymbolicTraits(.italic)
            let italic = NSFont(descriptor: italicDesc, size: bodyFont.pointSize) ?? bodyFont
            textStorage.addAttribute(.font, value: italic, range: innerRange)
            let startMarker = NSRange(location: match.range.location, length: 1)
            let endMarker = NSRange(location: match.range.location + match.range.length - 1, length: 1)
            textStorage.addAttribute(.foregroundColor, value: dimColor, range: startMarker)
            textStorage.addAttribute(.foregroundColor, value: dimColor, range: endMarker)
        }

        // Inline code
        inlineCodePattern.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            guard let match else { return }
            textStorage.addAttribute(.font, value: bodyMonoFont, range: match.range(at: 1))
            textStorage.addAttribute(.foregroundColor, value: codeColor, range: match.range(at: 1))
            textStorage.addAttribute(.backgroundColor, value: codeBgColor, range: match.range)
            let startTick = NSRange(location: match.range.location, length: 1)
            let endTick = NSRange(location: match.range.location + match.range.length - 1, length: 1)
            textStorage.addAttribute(.foregroundColor, value: dimColor, range: startTick)
            textStorage.addAttribute(.foregroundColor, value: dimColor, range: endTick)
        }

        // Unchecked checkboxes
        checkboxUnchecked.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            guard let match else { return }
            textStorage.addAttribute(.foregroundColor, value: dimColor, range: match.range(at: 1))
            textStorage.addAttribute(.foregroundColor, value: accentColor, range: match.range(at: 2))
        }

        // Checked checkboxes
        checkboxChecked.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            guard let match else { return }
            let textRange = match.range(at: 3)
            textStorage.addAttribute(.foregroundColor, value: dimColor, range: match.range(at: 1))
            textStorage.addAttribute(.foregroundColor, value: accentColor, range: match.range(at: 2))
            textStorage.addAttribute(.foregroundColor, value: checkDoneColor, range: textRange)
            textStorage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: textRange)
            textStorage.addAttribute(.strikethroughColor, value: checkDoneColor, range: textRange)
        }

        // Bullet points
        bulletPattern.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            guard let match else { return }
            textStorage.addAttribute(.foregroundColor, value: dimColor, range: match.range(at: 2))
        }

        // Numbered lists
        numberedListPattern.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            guard let match else { return }
            textStorage.addAttribute(.foregroundColor, value: dimColor, range: match.range(at: 2))
        }

        // Block quotes
        blockQuotePattern.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            guard let match else { return }
            let quoteStyle = NSMutableParagraphStyle()
            quoteStyle.headIndent = 16
            quoteStyle.firstLineHeadIndent = 16
            quoteStyle.lineSpacing = 3
            textStorage.addAttributes([
                .paragraphStyle: quoteStyle,
                .foregroundColor: NSColor(white: 1.0, alpha: 0.6),
            ], range: match.range)
            let marker = NSRange(location: match.range.location, length: 1)
            textStorage.addAttribute(.foregroundColor, value: accentColor, range: marker)
        }

        // Horizontal rules (---)
        hrPattern.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            guard let match else { return }
            textStorage.addAttribute(.foregroundColor, value: hrColor, range: match.range)
            textStorage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: match.range)
            textStorage.addAttribute(.strikethroughColor, value: hrColor, range: match.range)
        }

        // Links
        linkPattern.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            guard let match else { return }
            let textRange = match.range(at: 1)
            let urlRange = match.range(at: 2)
            textStorage.addAttribute(.foregroundColor, value: accentColor, range: textRange)
            textStorage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: textRange)
            let openBracket = NSRange(location: match.range.location, length: 1)
            let closeBracketAndUrl = NSRange(location: textRange.location + textRange.length,
                                              length: match.range.length - textRange.length - 1)
            textStorage.addAttribute(.foregroundColor, value: dimColor, range: openBracket)
            textStorage.addAttribute(.foregroundColor, value: dimColor, range: closeBracketAndUrl)
            let url = ns.substring(with: urlRange)
            textStorage.addAttribute(.link, value: url, range: textRange)
        }
    }
}

// MARK: - Styled Editor

class StyledEditor: NSTextView {
    var isRestyling = false

    override func keyDown(with event: NSEvent) {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Cmd+Enter: toggle checkbox
        if mods == .command && event.keyCode == 36 {
            toggleCheckbox()
            return
        }
        // Cmd+B: bold
        if mods == .command && event.charactersIgnoringModifiers == "b" {
            wrapSelection(with: "**")
            return
        }
        // Cmd+I: italic
        if mods == .command && event.charactersIgnoringModifiers == "i" {
            wrapSelection(with: "*")
            return
        }
        // Cmd+E: inline code
        if mods == .command && event.charactersIgnoringModifiers == "e" {
            wrapSelection(with: "`")
            return
        }
        // Enter: continue lists/checkboxes
        if event.keyCode == 36 && mods.isEmpty {
            if handleListContinuation() { return }
        }
        super.keyDown(with: event)
    }

    override func insertTab(_ sender: Any?) {
        if handleListIndent(outdent: false) { return }
        insertText("  ", replacementRange: selectedRange())
    }

    override func insertBacktab(_ sender: Any?) {
        if handleListIndent(outdent: true) { return }
    }

    // MARK: - Smart Paste (Cmd+V with URL on selection → markdown link)

    override func paste(_ sender: Any?) {
        let pb = NSPasteboard.general
        guard let pasteString = pb.string(forType: .string) else {
            super.paste(sender)
            return
        }

        let sel = selectedRange()
        // If there's selected text and clipboard contains a URL, make a markdown link
        if sel.length > 0,
           let url = URL(string: pasteString.trimmingCharacters(in: .whitespacesAndNewlines)),
           let scheme = url.scheme, (scheme == "http" || scheme == "https") {
            let selectedText = (string as NSString).substring(with: sel)
            let link = "[\(selectedText)](\(pasteString.trimmingCharacters(in: .whitespacesAndNewlines)))"
            if shouldChangeText(in: sel, replacementString: link) {
                textStorage?.replaceCharacters(in: sel, with: link)
                didChangeText()
                setSelectedRange(NSRange(location: sel.location + link.count, length: 0))
            }
            return
        }

        // Otherwise: paste as plain text (strip any rich formatting from clipboard)
        if shouldChangeText(in: sel, replacementString: pasteString) {
            textStorage?.replaceCharacters(in: sel, with: pasteString)
            didChangeText()
            setSelectedRange(NSRange(location: sel.location + (pasteString as NSString).length, length: 0))
        }
    }

    // MARK: - Wrap Selection (Bold/Italic/Code)

    func wrapSelection(with marker: String) {
        let sel = selectedRange()
        let text = string as NSString

        if sel.length > 0 {
            let selected = text.substring(with: sel)
            // Check if already wrapped — unwrap
            let mLen = marker.count
            if sel.location >= mLen && sel.location + sel.length + mLen <= text.length {
                let beforeRange = NSRange(location: sel.location - mLen, length: mLen)
                let afterRange = NSRange(location: sel.location + sel.length, length: mLen)
                if text.substring(with: beforeRange) == marker && text.substring(with: afterRange) == marker {
                    // Unwrap
                    let fullRange = NSRange(location: sel.location - mLen, length: sel.length + mLen * 2)
                    if shouldChangeText(in: fullRange, replacementString: selected) {
                        textStorage?.replaceCharacters(in: fullRange, with: selected)
                        didChangeText()
                        setSelectedRange(NSRange(location: sel.location - mLen, length: sel.length))
                    }
                    return
                }
            }
            // Wrap
            let wrapped = marker + selected + marker
            if shouldChangeText(in: sel, replacementString: wrapped) {
                textStorage?.replaceCharacters(in: sel, with: wrapped)
                didChangeText()
                setSelectedRange(NSRange(location: sel.location + mLen, length: sel.length))
            }
        } else {
            // No selection — insert markers and place cursor between
            let insert = marker + marker
            if shouldChangeText(in: sel, replacementString: insert) {
                textStorage?.replaceCharacters(in: sel, with: insert)
                didChangeText()
                setSelectedRange(NSRange(location: sel.location + marker.count, length: 0))
            }
        }
    }

    // MARK: - List Continuation

    func handleListContinuation() -> Bool {
        let text = string as NSString
        let cursor = selectedRange().location
        let lineRange = text.lineRange(for: NSRange(location: cursor, length: 0))
        let line = text.substring(with: lineRange).trimmingCharacters(in: .newlines)

        let patterns: [(regex: String, emptyCheck: String, newPrefix: String?)] = [
            ("^(\\s*)- \\[ \\] (.+)$", "^(\\s*)- \\[ \\] $", "- [ ] "),
            ("^(\\s*)- \\[x\\] (.+)$", "^(\\s*)- \\[x\\] $", "- [ ] "),
            ("^(\\s*)- (.+)$", "^(\\s*)- $", "- "),
            ("^(\\s*)\\* (.+)$", "^(\\s*)\\* $", "* "),
            ("^(\\s*)(\\d+)\\. (.+)$", "^(\\s*)(\\d+)\\. $", nil),
        ]

        for (contentPattern, emptyPattern, prefix) in patterns {
            // Empty list item → exit list mode
            if let emptyRegex = try? NSRegularExpression(pattern: emptyPattern),
               emptyRegex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) != nil {
                let replaceRange = NSRange(location: lineRange.location, length: lineRange.length)
                if shouldChangeText(in: replaceRange, replacementString: "\n") {
                    textStorage?.replaceCharacters(in: replaceRange, with: "\n")
                    didChangeText()
                    setSelectedRange(NSRange(location: lineRange.location + 1, length: 0))
                }
                return true
            }

            // Continue the list
            if let regex = try? NSRegularExpression(pattern: contentPattern),
               let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) {
                let indent = (line as NSString).substring(with: match.range(at: 1))
                var newLinePrefix: String
                if let prefix = prefix {
                    newLinePrefix = indent + prefix
                } else {
                    let num = Int((line as NSString).substring(with: match.range(at: 2))) ?? 0
                    newLinePrefix = indent + "\(num + 1). "
                }
                let insertion = "\n" + newLinePrefix
                let insertAt = NSRange(location: cursor, length: 0)
                if shouldChangeText(in: insertAt, replacementString: insertion) {
                    textStorage?.replaceCharacters(in: insertAt, with: insertion)
                    didChangeText()
                    setSelectedRange(NSRange(location: cursor + insertion.count, length: 0))
                }
                return true
            }
        }
        return false
    }

    // MARK: - List Indentation

    func handleListIndent(outdent: Bool) -> Bool {
        let text = string as NSString
        let cursor = selectedRange().location
        let lineRange = text.lineRange(for: NSRange(location: cursor, length: 0))
        let line = text.substring(with: lineRange)

        let listPattern = try! NSRegularExpression(pattern: "^(\\s*)([-*]|\\d+\\.|\\- \\[[ x]\\])")
        guard listPattern.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) != nil else {
            return false
        }

        if outdent {
            if line.hasPrefix("  ") {
                let newLine = String(line.dropFirst(2))
                if shouldChangeText(in: lineRange, replacementString: newLine) {
                    textStorage?.replaceCharacters(in: lineRange, with: newLine)
                    didChangeText()
                    setSelectedRange(NSRange(location: max(lineRange.location, cursor - 2), length: 0))
                }
                return true
            }
        } else {
            let newLine = "  " + line
            if shouldChangeText(in: lineRange, replacementString: newLine) {
                textStorage?.replaceCharacters(in: lineRange, with: newLine)
                didChangeText()
                setSelectedRange(NSRange(location: cursor + 2, length: 0))
            }
            return true
        }
        return false
    }

    // MARK: - Checkbox Toggle

    func toggleCheckbox() {
        let text = string as NSString
        let cursorLocation = selectedRange().location
        let lineRange = text.lineRange(for: NSRange(location: cursorLocation, length: 0))
        let line = text.substring(with: lineRange)

        var newLine: String
        if line.contains("- [ ]") {
            newLine = line.replacingOccurrences(of: "- [ ]", with: "- [x]")
        } else if line.contains("- [x]") {
            newLine = line.replacingOccurrences(of: "- [x]", with: "- [ ]")
        } else {
            let trimmed = line.trimmingCharacters(in: .newlines)
            let indent = String(line.prefix(while: { $0 == " " || $0 == "\t" }))
            let content = trimmed.trimmingCharacters(in: .whitespaces)
            if content.hasPrefix("- ") || content.hasPrefix("* ") {
                newLine = indent + "- [ ] " + String(content.dropFirst(2)) + "\n"
            } else {
                newLine = indent + "- [ ] " + content + "\n"
            }
        }

        if shouldChangeText(in: lineRange, replacementString: newLine) {
            textStorage?.replaceCharacters(in: lineRange, with: newLine)
            didChangeText()
            let newCursor = min(lineRange.location + newLine.count - 1,
                                (string as NSString).length)
            setSelectedRange(NSRange(location: newCursor, length: 0))
        }
    }

    // MARK: - Restyle (undo-safe)

    func restyleMarkdown() {
        guard !isRestyling, let ts = textStorage else { return }
        isRestyling = true
        let sel = selectedRange()
        // Disable undo registration during restyling
        undoManager?.disableUndoRegistration()
        ts.beginEditing()
        MarkdownStyler.style(ts)
        ts.endEditing()
        undoManager?.enableUndoRegistration()
        if sel.location <= (string as NSString).length {
            setSelectedRange(sel)
        }
        isRestyling = false
    }
}

// MARK: - Tab Button

class TabButton: NSView {
    static let activeTextColor = NSColor(white: 1.0, alpha: 0.90)
    static let inactiveTextColor = NSColor(white: 1.0, alpha: 0.45)
    static let activeBg = NSColor(white: 1.0, alpha: 0.10)
    static let hoverBg = NSColor(white: 1.0, alpha: 0.06)
    static let pressedBg = NSColor(white: 1.0, alpha: 0.14)
    static let pillRadius: CGFloat = 6
    static let hPad: CGFloat = 10
    static let vPad: CGFloat = 4

    let label = NSTextField(labelWithString: "")
    var isActive = false { didSet { updateAppearance() } }
    var isHovered = false { didSet { updateAppearance() } }
    var isPressed = false { didSet { updateAppearance() } }
    var onClick: (() -> Void)?
    var onRightClick: (() -> Void)?
    var trackingArea: NSTrackingArea?

    init(title: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = Self.pillRadius

        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        label.textColor = Self.inactiveTextColor
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.stringValue = title
        addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.hPad),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.hPad),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 20),
        ])

        updateAppearance()
    }

    required init?(coder: NSCoder) { fatalError() }

    func updateAppearance() {
        label.font = NSFont.systemFont(ofSize: 12, weight: isActive ? .medium : .regular)
        label.textColor = isActive ? Self.activeTextColor : Self.inactiveTextColor

        if isPressed {
            layer?.backgroundColor = Self.pressedBg.cgColor
        } else if isActive {
            layer?.backgroundColor = Self.activeBg.cgColor
        } else if isHovered {
            layer?.backgroundColor = Self.hoverBg.cgColor
        } else {
            layer?.backgroundColor = nil
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp], owner: self)
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false; isPressed = false }
    override func mouseDown(with event: NSEvent) {
        if event.type == .rightMouseDown { return }
        isPressed = true
    }
    override func mouseUp(with event: NSEvent) {
        isPressed = false
        if bounds.contains(convert(event.locationInWindow, from: nil)) {
            onClick?()
        }
    }
    override func rightMouseDown(with event: NSEvent) {
        onRightClick?()
        // Show context menu
        if let menu = menu {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }
    }

    override var intrinsicContentSize: NSSize {
        let textSize = label.intrinsicContentSize
        return NSSize(width: textSize.width + Self.hPad * 2, height: 20)
    }
}

// MARK: - Add Button (the "+")

class AddButton: NSView {
    static let iconColor = NSColor(white: 1.0, alpha: 0.35)
    static let iconHoverColor = NSColor(white: 1.0, alpha: 0.45)
    static let hoverBg = NSColor(white: 1.0, alpha: 0.06)

    let icon = NSTextField(labelWithString: "+")
    var isHovered = false { didSet { updateAppearance() } }
    var onClick: (() -> Void)?
    var trackingArea: NSTrackingArea?

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 5

        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        icon.textColor = Self.iconColor
        icon.alignment = .center
        addSubview(icon)

        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            widthAnchor.constraint(equalToConstant: 20),
            heightAnchor.constraint(equalToConstant: 20),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func updateAppearance() {
        icon.textColor = isHovered ? Self.iconHoverColor : Self.iconColor
        layer?.backgroundColor = isHovered ? Self.hoverBg.cgColor : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp], owner: self)
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }
    override func mouseDown(with event: NSEvent) { onClick?() }

    override var intrinsicContentSize: NSSize { NSSize(width: 20, height: 20) }
}

// MARK: - Notes Panel

class NotesPanel: NSPanel {
    let tabBar = NSScrollView()
    let tabStack = NSStackView()
    let addButton = AddButton()
    let titleField = NSTextField()
    let editor = StyledEditor()
    let editorScroll = NSScrollView()
    var currentFile: URL?
    var saveTimer: Timer?
    var fileWatcher: DispatchSourceFileSystemObject?
    var notes: [URL] = []
    var tabButtons: [TabButton] = []

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .hudWindow],
            backing: .buffered,
            defer: false
        )
        self.title = "Waxpad"
        self.level = .floating
        self.isFloatingPanel = true
        self.hidesOnDeactivate = false
        self.animationBehavior = .none
        self.isMovableByWindowBackground = true
        self.center()
        setupUI()
        loadNotes()
        // Save frame on every move/resize so it survives force-kill
        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: self, queue: nil) { _ in
            UserDefaults.standard.set(NSStringFromRect(self.frame), forKey: "WaxpadWindowFrame")
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: self, queue: nil) { _ in
            UserDefaults.standard.set(NSStringFromRect(self.frame), forKey: "WaxpadWindowFrame")
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func setupUI() {
        guard let content = contentView else { return }
        content.wantsLayer = true

        tabBar.translatesAutoresizingMaskIntoConstraints = false
        tabBar.hasHorizontalScroller = false
        tabBar.hasVerticalScroller = false
        tabBar.drawsBackground = false
        tabBar.borderType = .noBorder

        tabStack.translatesAutoresizingMaskIntoConstraints = false
        tabStack.orientation = .horizontal
        tabStack.spacing = 2
        tabStack.alignment = .centerY
        tabStack.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 4)
        tabBar.documentView = tabStack

        addButton.translatesAutoresizingMaskIntoConstraints = false
        addButton.onClick = { [weak self] in self?.addNote() }

        let tabRow = NSStackView(views: [tabBar, addButton])
        tabRow.translatesAutoresizingMaskIntoConstraints = false
        tabRow.orientation = .horizontal
        tabRow.spacing = 4
        tabRow.alignment = .centerY
        tabRow.edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 6, right: 8)

        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.isEditable = true
        titleField.isBordered = false
        titleField.drawsBackground = false
        titleField.font = NSFont.systemFont(ofSize: 20, weight: .bold)
        titleField.textColor = .white
        titleField.placeholderString = "Note title..."
        titleField.focusRingType = .none
        titleField.delegate = self
        titleField.lineBreakMode = .byTruncatingTail
        titleField.cell?.wraps = false
        titleField.cell?.isScrollable = true

        let sep = NSBox()
        sep.translatesAutoresizingMaskIntoConstraints = false
        sep.boxType = .separator

        editorScroll.translatesAutoresizingMaskIntoConstraints = false
        editorScroll.hasVerticalScroller = true
        editorScroll.hasHorizontalScroller = false
        editorScroll.drawsBackground = false
        editorScroll.borderType = .noBorder
        editorScroll.documentView = editor

        editor.minSize = NSSize(width: 0, height: 0)
        editor.maxSize = NSSize(width: .max, height: .max)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.containerSize = NSSize(width: 0, height: .max)
        editor.textContainer?.widthTracksTextView = true
        editor.textContainerInset = NSSize(width: 12, height: 8)
        editor.isRichText = true
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isAutomaticLinkDetectionEnabled = false
        editor.insertionPointColor = .white
        editor.drawsBackground = false
        editor.allowsUndo = true
        editor.delegate = self
        editor.typingAttributes = [
            .font: MarkdownStyler.bodyFont,
            .foregroundColor: MarkdownStyler.textColor,
        ]

        content.addSubview(tabRow)
        content.addSubview(titleField)
        content.addSubview(sep)
        content.addSubview(editorScroll)

        NSLayoutConstraint.activate([
            tabRow.topAnchor.constraint(equalTo: content.topAnchor, constant: 4),
            tabRow.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            tabRow.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            tabRow.heightAnchor.constraint(equalToConstant: 34),

            titleField.topAnchor.constraint(equalTo: tabRow.bottomAnchor, constant: 8),
            titleField.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            titleField.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),

            sep.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 8),
            sep.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            sep.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),

            editorScroll.topAnchor.constraint(equalTo: sep.bottomAnchor, constant: 4),
            editorScroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            editorScroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            editorScroll.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
    }

    // MARK: - Notes Management

    func loadNotes() {
        let fm = FileManager.default
        notes = (try? fm.contentsOfDirectory(at: notesDir, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "md" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
        rebuildTabs()
        if !notes.isEmpty && currentFile == nil {
            selectNote(at: 0)
        }
    }

    func rebuildTabs() {
        tabButtons.forEach { $0.removeFromSuperview() }
        tabButtons.removeAll()

        for (i, url) in notes.enumerated() {
            let title = noteTitle(from: url)
            let tab = TabButton(title: title)
            tab.translatesAutoresizingMaskIntoConstraints = false
            tab.onClick = { [weak self] in self?.selectNote(at: i) }
            // Right-click context menu
            let menu = NSMenu()
            let deleteItem = NSMenuItem(title: "Delete Note", action: #selector(deleteNoteFromMenu(_:)), keyEquivalent: "")
            deleteItem.tag = i
            deleteItem.target = self
            menu.addItem(deleteItem)
            tab.menu = menu
            tab.onRightClick = {} // handled by menu
            tabStack.addArrangedSubview(tab)
            tabButtons.append(tab)
        }
        highlightActiveTab()
    }

    func noteTitle(from url: URL) -> String {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return url.deletingPathExtension().lastPathComponent
        }
        let firstLine = content.prefix(while: { $0 != "\n" })
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "^#+\\s*", with: "", options: .regularExpression)
        return firstLine.isEmpty ? url.deletingPathExtension().lastPathComponent : String(firstLine)
    }

    func highlightActiveTab() {
        guard let file = currentFile, let idx = notes.firstIndex(of: file) else { return }
        for (i, tab) in tabButtons.enumerated() {
            tab.isActive = i == idx
        }
    }

    func selectNote(at index: Int) {
        guard index >= 0, index < notes.count else { return }
        saveCurrentNote()
        currentFile = notes[index]
        let content = (try? String(contentsOf: notes[index], encoding: .utf8)) ?? ""
        let lines = content.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        let title = (lines.first ?? "")
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "^#+\\s*", with: "", options: .regularExpression)
        let body = lines.count > 1 ? String(lines[1]) : ""
        let trimmedBody = body.hasPrefix("\n") ? String(body.dropFirst()) : body

        titleField.stringValue = title
        // Reset undo manager when switching notes
        editor.undoManager?.removeAllActions()
        editor.string = trimmedBody
        editor.restyleMarkdown()
        highlightActiveTab()
        watchFile(notes[index])
    }

    func scheduleSave() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            self?.saveCurrentNote()
        }
    }

    func saveCurrentNote() {
        guard let file = currentFile else { return }
        let title = titleField.stringValue.trimmingCharacters(in: .whitespaces)
        let heading = title.isEmpty ? "" : "# \(title)"
        let body = editor.string
        let content = heading + "\n" + body
        try? content.write(to: file, atomically: true, encoding: .utf8)
    }

    func renameCurrentFile() {
        guard let file = currentFile else { return }
        let title = titleField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }

        let safe = title
            .replacingOccurrences(of: "[/\\\\:]", with: "-", options: .regularExpression)
            .prefix(60)
        let newName = safe + ".md"
        let newURL = notesDir.appendingPathComponent(String(newName))

        if newURL != file && !FileManager.default.fileExists(atPath: newURL.path) {
            saveCurrentNote()
            try? FileManager.default.moveItem(at: file, to: newURL)
            currentFile = newURL
            loadNotes()
            if let idx = notes.firstIndex(of: newURL) {
                selectNote(at: idx)
            }
        }
        if let idx = notes.firstIndex(of: currentFile ?? file) {
            tabButtons[idx].label.stringValue = title
        }
    }

    // MARK: - File Watching

    func watchFile(_ url: URL) {
        fileWatcher?.cancel()
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: .write, queue: .main
        )
        source.setEventHandler { [weak self] in
            guard let self, let file = self.currentFile else { return }
            if let content = try? String(contentsOf: file, encoding: .utf8) {
                let lines = content.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
                let title = (lines.first ?? "")
                    .trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "^#+\\s*", with: "", options: .regularExpression)
                let body = lines.count > 1 ? String(lines[1]) : ""
                let trimmedBody = body.hasPrefix("\n") ? String(body.dropFirst()) : body
                if title != self.titleField.stringValue || trimmedBody != self.editor.string {
                    self.titleField.stringValue = title
                    let sel = self.editor.selectedRange()
                    self.editor.string = trimmedBody
                    self.editor.restyleMarkdown()
                    if sel.location <= trimmedBody.count {
                        self.editor.setSelectedRange(sel)
                    }
                }
            }
        }
        source.setCancelHandler { Darwin.close(fd) }
        source.resume()
        fileWatcher = source
    }

    // MARK: - Actions

    @objc func addNote() {
        let name = "note-\(Int(Date().timeIntervalSince1970)).md"
        let file = notesDir.appendingPathComponent(name)
        try? "# New Note\n".write(to: file, atomically: true, encoding: .utf8)
        loadNotes()
        if let idx = notes.firstIndex(of: file) {
            selectNote(at: idx)
            self.makeFirstResponder(titleField)
            titleField.selectText(nil)
        }
    }

    @objc func deleteNoteFromMenu(_ sender: NSMenuItem) {
        let idx = sender.tag
        guard idx >= 0, idx < notes.count else { return }
        let alert = NSAlert()
        alert.messageText = "Delete \"\(noteTitle(from: notes[idx]))\"?"
        alert.informativeText = "This cannot be undone."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        try? FileManager.default.removeItem(at: notes[idx])
        if currentFile == notes[idx] {
            currentFile = nil
            editor.string = ""
            titleField.stringValue = ""
        }
        loadNotes()
    }
}

// MARK: - Title Field Delegate

extension NotesPanel: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        scheduleSave()
        if let file = currentFile, let idx = notes.firstIndex(of: file) {
            let title = titleField.stringValue.trimmingCharacters(in: .whitespaces)
            tabButtons[idx].label.stringValue = title.isEmpty ? "Untitled" : title
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        renameCurrentFile()
        if let movement = obj.userInfo?["NSTextMovement"] as? Int,
           movement == NSReturnTextMovement {
            self.makeFirstResponder(editor)
            editor.setSelectedRange(NSRange(location: 0, length: 0))
        }
    }
}

// MARK: - Editor Delegate

extension NotesPanel: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        guard !editor.isRestyling else { return }
        scheduleSave()
        editor.restyleMarkdown()
    }
}
