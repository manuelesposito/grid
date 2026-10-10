// Grid: a menu bar icon that arranges the windows on the front window's screen in rows.
import AppKit
import ApplicationServices
import ServiceManagement
import Carbon.HIToolbox

final class App: NSObject, NSApplicationDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    // The first four sit in the menu; the rest under More. Control-Option-1 to 9 follow this order.
    let layouts: [[Int]] = [[2], [3], [2, 1], [2, 2], [4], [5], [3, 3], [4, 4], [5, 5]]
    var gap: CGFloat {
        get { CGFloat(UserDefaults.standard.double(forKey: "gap")) }
        set { UserDefaults.standard.set(Double(newValue), forKey: "gap") }
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        screenClock = true
        UserDefaults.standard.register(defaults: ["gap": 8.0])
        item.button?.image = icon(coding, w: 36, h: 28, radius: 6)
        item.button?.setAccessibilityLabel("Grid")
        rebuild()
        registerHotKeys()
        focus.onCover = { [weak self] in self?.wake() }
        // When Grid quits or is restarted, a focused window goes back first.
        signal(SIGTERM, SIG_IGN)
        quitSignal.setEventHandler { [weak self] in _ = self?.focus.end(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { exit(0) } }
        quitSignal.resume()
        // Ask for permission on first start.
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
    }

    func rebuild() {
        let menu = NSMenu()
        let auto = NSMenuItem(title: "Automatic", action: #selector(pickAuto), keyEquivalent: "0")
        auto.keyEquivalentModifierMask = [.control, .option]; auto.target = self
        menu.addItem(auto)
        menu.addItem(halfItem("Automatic", key: "0", action: #selector(pickAutoHalf)))
        // Focus is put away for now (2026-10-10): the code stays, but it has no menu item, no shortcut
        // and no setting. Set focusShown to true to bring it back.
        if focusShown {
            let f = NSMenuItem(title: "Focus", action: #selector(toggleFocus), keyEquivalent: "f")
            f.keyEquivalentModifierMask = [.control, .option]; f.target = self; f.state = focus.armed ? .on : .off
            menu.addItem(f)
        }
        // Everything that is set once and left alone sits together.
        let settings = NSMenu()
        if focusShown {
            let fs = NSMenuItem(title: "Focus Zoom", action: nil, keyEquivalent: "")
            let fsMenu = NSMenu()
            for z in [1, 1.5, 2] {
                let m = NSMenuItem(title: "\(z.formatted()) ×", action: #selector(setFocusZoom(_:)), keyEquivalent: "")
                m.target = self; m.representedObject = z; m.state = abs(focus.zoom - z) < 0.01 ? .on : .off
                fsMenu.addItem(m)
            }
            fs.submenu = fsMenu
            settings.addItem(fs)
        }
        menu.addItem(.separator())
        // Workspaces are put away with Focus (2026-10-10): the code stays behind focusShown.
        if focusShown {
        // Workspaces: click opens; hold Option to delete.
        let ws = NSMenuItem(title: "Workspaces", action: nil, keyEquivalent: "")
        let wsMenu = NSMenu()
        for name in workspaces.names {
            let open = NSMenuItem(title: name, action: #selector(openWorkspace(_:)), keyEquivalent: "")
            open.target = self; open.representedObject = name
            wsMenu.addItem(open)
            let del = NSMenuItem(title: "Delete “\(name)”", action: #selector(deleteWorkspace(_:)), keyEquivalent: "")
            del.target = self; del.representedObject = name
            del.isAlternate = true; del.keyEquivalentModifierMask = .option
            wsMenu.addItem(del)
        }
        if !workspaces.names.isEmpty { wsMenu.addItem(.separator()) }
        wsMenu.addItem(withTitle: "Save Workspace…", action: #selector(saveWorkspace), keyEquivalent: "").target = self
        ws.submenu = wsMenu
        menu.addItem(ws)
        menu.addItem(.separator())
        }
        // Every layout in the menu itself, nothing under a More item (his call, 2026-10-10).
        for (i, l) in layouts.enumerated() {
            let m = NSMenuItem(title: name(l), action: #selector(pick(_:)), keyEquivalent: "")
            m.image = icon(l)
            m.setAccessibilityLabel(name(l))
            m.toolTip = name(l)
            m.tag = i; m.target = self
            m.keyEquivalent = "\(i + 1)"; m.keyEquivalentModifierMask = [.control, .option]
            menu.addItem(m)
            // Hold Shift: the same rows in a band across the middle, half the screen's height.
            let h = halfItem(name(l) + " at half height", key: "\(i + 1)", action: #selector(pickHalf(_:)), icon: icon(l, frame: Frame.full.halved))
            h.tag = i
            menu.addItem(h)
        }
        // One window in a box in the middle of the screen; Shift makes the box half as high.
        let mid = NSMenuItem(title: "In the Middle", action: #selector(pickMiddle), keyEquivalent: "m")
        mid.image = icon([1], frame: .middle); mid.setAccessibilityLabel("In the Middle"); mid.toolTip = "In the Middle"
        mid.keyEquivalentModifierMask = [.control, .option]; mid.target = self
        menu.addItem(mid)
        menu.addItem(halfItem("In the Middle at half height", key: "m", action: #selector(pickMiddleHalf), icon: icon([1], frame: Frame.middle.halved)))
        // One big window and two small ones: Control-Option-Left puts the big one left, -Right right.
        for (rows, title, key, sel, half) in [(bigLeft, "Big Left", NSLeftArrowFunctionKey, #selector(pickBigLeft), #selector(pickBigLeftHalf)),
                                              (bigRight, "Big Right", NSRightArrowFunctionKey, #selector(pickBigRight), #selector(pickBigRightHalf))] {
            let k = String(UnicodeScalar(key)!)
            let m = NSMenuItem(title: title, action: sel, keyEquivalent: k)
            m.image = icon(rows); m.setAccessibilityLabel(title); m.toolTip = title
            m.keyEquivalentModifierMask = [.control, .option]; m.target = self
            menu.addItem(m)
            menu.addItem(halfItem(title + " at half height", key: k, action: half, icon: icon(rows, frame: Frame.full.halved)))
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Custom…", action: #selector(custom), keyEquivalent: "").target = self
        menu.addItem(.separator())
        let g = NSMenuItem(title: "Space between windows", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for size in [0, 4, 8, 12, 16, 24, 32] {
            let m = NSMenuItem(title: size == 0 ? "None" : "\(size) px", action: #selector(setGap(_:)), keyEquivalent: "")
            m.tag = size; m.target = self; m.state = Int(gap) == size ? .on : .off
            sub.addItem(m)
        }
        g.submenu = sub
        settings.addItem(g)
        settings.addItem(.separator())
        let l = NSMenuItem(title: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")
        l.target = self; l.state = SMAppService.mainApp.status == .enabled ? .on : .off
        settings.addItem(l)
        let set = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        set.submenu = settings
        menu.addItem(set)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApp.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
    }

    // The Shift twin of a menu item: shown in its place while Shift is held.
    func halfItem(_ title: String, key: String, action: Selector, icon: NSImage? = nil) -> NSMenuItem {
        let m = NSMenuItem(title: title, action: action, keyEquivalent: key)
        m.keyEquivalentModifierMask = [.control, .option, .shift]; m.target = self
        m.isAlternate = true
        m.image = icon; m.setAccessibilityLabel(title); m.toolTip = title
        return m
    }

    func name(_ l: [Int]) -> String {
        l.count == 1 ? "\(l[0]) in a row" : l.map(String.init).joined(separator: " + ")
    }

    // A small picture of the layout, in the shape of Apple's own window tiling icons: a thin outlined
    // frame, the windows as solid rounded tiles inside it with a little air around them.
    // Drawn in half points, the pixels of the screen, so every edge sits on a whole pixel.
    func icon(_ rows: [Int], frame: Frame = .full, w: Int = 60, h: Int = 38, radius: CGFloat = 7) -> NSImage {
        let line = 3, air = 3, cut = 3
        // The tiles fill the frame's share of the room inside the outline, in the middle of it.
        let fw = w - 2 * (line + air), fh = h - 2 * (line + air)
        let iw = Int((Double(fw) * frame.width).rounded()), ih = Int((Double(fh) * frame.height).rounded())
        let inset = line + air
        let boxX = inset + (fw - iw) / 2, boxY = inset + (fh - ih) / 2
        // Whole-pixel sizes for n parts with cuts between them.
        func parts(_ total: Int, _ n: Int) -> [Int] {
            let room = total - cut * (n - 1)
            return (0..<n).map { room / n + ($0 < room % n ? 1 : 0) }
        }
        var tiles: [NSRect] = []
        if rows == bigLeft || rows == bigRight {
            // One big tile on one side, two stacked on the other.
            let split = Int((Double(iw) * 0.3).rounded()) * 2, hs = parts(ih, 2)
            let bigX = rows == bigLeft ? 0 : iw - split, smallX = rows == bigLeft ? split + cut : 0
            tiles = [NSRect(x: bigX, y: 0, width: split, height: ih),
                     NSRect(x: smallX, y: 0, width: iw - split - cut, height: hs[0]),
                     NSRect(x: smallX, y: hs[0] + cut, width: iw - split - cut, height: hs[1])]
        } else {
            var y = 0
            for (rowH, count) in zip(parts(ih, rows.count), rows) {
                var x = 0
                for colW in parts(iw, count) {
                    tiles.append(NSRect(x: x, y: y, width: colW, height: rowH))
                    x += colW + cut
                }
                y += rowH + cut
            }
        }
        let img = NSImage(size: NSSize(width: w / 2, height: h / 2), flipped: true) { _ in
            let half = NSAffineTransform(); half.scale(by: 0.5); half.concat()
            NSColor.black.set()
            let l = CGFloat(line)
            let frame = NSBezierPath(roundedRect: NSRect(x: l / 2, y: l / 2, width: CGFloat(w) - l, height: CGFloat(h) - l), xRadius: radius - l / 2, yRadius: radius - l / 2)
            frame.lineWidth = l
            frame.stroke()
            for tile in tiles { NSBezierPath(roundedRect: tile.offsetBy(dx: CGFloat(boxX), dy: CGFloat(boxY)), xRadius: 1.5, yRadius: 1.5).fill() }
            return true
        }
        img.isTemplate = true
        return img
    }

    // Control-Option-1 to 9 pick the layouts from anywhere.
    func registerHotKeys() {
        let keys = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            let d = NSApp.delegate as! App
            // Ids: 0-8 the layouts, 50-58 the same at half height, 99/149 automatic, 96/146 in the middle.
            switch id.id {
            case 98: d.undo()
            case 95: d.toggleFocus()
            case 93: d.focus.step(-1)
            case 94: d.focus.step(1)
            case 97: d.run(d.coding)
            case 99: d.run([])
            default: d.run(d.layouts[Int(id.id)])
            }
            return noErr
        }, 1, &spec, nil, nil)
        for (i, key) in keys.enumerated() where i < layouts.count {
            var ref: EventHotKeyRef?
            RegisterEventHotKey(UInt32(key), UInt32(controlKey | optionKey), EventHotKeyID(signature: OSType(0x47524944), id: UInt32(i)), GetApplicationEventTarget(), 0, &ref)
        }
        // Control-Option-0 = automatic, Control-Option-Z = undo.
        // Control-Option-C = coding.
        for (key, id) in [(kVK_ANSI_0, 99), (kVK_ANSI_Z, 98), (kVK_ANSI_C, 97), (kVK_ANSI_F, 95), (kVK_LeftArrow, 93), (kVK_RightArrow, 94)] {
            var ref: EventHotKeyRef?
            RegisterEventHotKey(UInt32(key), UInt32(controlKey | optionKey), EventHotKeyID(signature: OSType(0x47524944), id: UInt32(id)), GetApplicationEventTarget(), 0, &ref)
        }
    }

    let focus = Focus()
    let quitSignal = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
    func applicationWillTerminate(_ n: Notification) { _ = focus.end() }
    let workspaces = Workspaces()

    // A new focus zoom shows right away when focus is on.
    @objc func setFocusZoom(_ m: NSMenuItem) { focus.zoom = m.representedObject as? Double ?? 2; refocus() }
    func refocus() {
        rebuild()
        guard focus.active else { return }
        _ = focus.end { _ = self.focus.start(); self.rebuild() }
    }

    @objc func openWorkspace(_ m: NSMenuItem) {
        guard let name = m.representedObject as? String else { return }
        if !workspaces.open(name) { NSSound.beep() }
    }

    @objc func deleteWorkspace(_ m: NSMenuItem) {
        guard let name = m.representedObject as? String else { return }
        workspaces.delete(name); rebuild()
    }

    @objc func saveWorkspace() {
        let alert = NSAlert()
        alert.messageText = "Save Workspace"
        alert.informativeText = "Saves the windows on this screen, with their places, folders and pages."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 228, height: 24))
        field.placeholderString = "Name, for example Architrave"
        alert.accessoryView = field
        let save = alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        // Nothing to save under no name.
        save.isEnabled = false
        let watcher = FieldWatcher { save.isEnabled = !field.stringValue.trimmingCharacters(in: .whitespaces).isEmpty }
        field.delegate = watcher
        // Remember the screen before the alert takes the focus.
        let front = NSWorkspace.shared.frontmostApplication
        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = field
        guard withExtendedLifetime(watcher, { alert.runModal() }) == .alertFirstButtonReturn else { front?.activate(); return }
        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        front?.activate()
        guard !name.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if !self.workspaces.save(name) { NSSound.beep() }
            self.rebuild()
        }
    }
    // The menu is rebuilt once the window has landed: building it takes a moment, and the animation would wait.
    @objc func toggleFocus() {
        if !focus.toggle() { NSSound.beep() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.rebuild() }
    }

    // Kept across restarts, so a new space can re-arrange right after Grid starts.
    var last: [Int]? {
        get { UserDefaults.standard.array(forKey: "last") as? [Int] }
        set { UserDefaults.standard.set(newValue, forKey: "last") }
    }
    var lastFrame: Frame {
        get { let a = UserDefaults.standard.array(forKey: "lastFrame") as? [Double] ?? []; return a.count == 2 ? Frame(width: a[0], height: a[1]) : .full }
        set { UserDefaults.standard.set([newValue.width, newValue.height], forKey: "lastFrame") }
    }
    // A short sound when there is nothing to arrange.
    func run(_ rows: [Int], frame: Frame = .full) {
        last = rows; lastFrame = frame
        let result = arrange(rows, gap: gap, frame: frame)
        if result.placed == 0 { NSSound.beep() }
        magnet.set(result.after)
    }

    // Grid looks once a second for a leftover Focus cover, and only while there is one: with no
    // cover up, it sleeps. Windows move only when a layout is picked; Grid never arranges on its own.
    var ticker: Timer?
    func wake() {
        guard ticker == nil else { return }
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
    }
    func tick() {
        focus.sweep()
        if focus.made.isEmpty && !focus.active { ticker?.invalidate(); ticker = nil }
    }

    @objc func pickAuto() { run([]) }
    @objc func pickAutoHalf() { run([], frame: Frame.full.halved) }
    @objc func pickBigLeft() { run(bigLeft) }
    @objc func pickBigRight() { run(bigRight) }
    @objc func pickBigLeftHalf() { run(bigLeft, frame: Frame.full.halved) }
    @objc func pickBigRightHalf() { run(bigRight, frame: Frame.full.halved) }
    @objc func pickMiddle() { run([1], frame: .middle) }
    @objc func pickMiddleHalf() { run([1], frame: Frame.middle.halved) }

    @objc func pick(_ m: NSMenuItem) { run(layouts[m.tag]) }
    @objc func pickHalf(_ m: NSMenuItem) { run(layouts[m.tag], frame: Frame.full.halved) }
    // A new space re-arranges the last layout right away, so the change shows.
    @objc func setGap(_ m: NSMenuItem) {
        gap = CGFloat(m.tag); rebuild()
        let rows = last ?? [], frame = lastFrame
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.run(rows, frame: frame) }
    }

    @objc func toggleLogin() {
        let s = SMAppService.mainApp
        if s.status == .enabled { try? s.unregister() } else { try? s.register() }
        rebuild()
    }

    // A diagram with one number beside each row; Arrange waits for at least one window.
    @objc func custom() {
        let alert = NSAlert()
        alert.messageText = "Custom Layout"
        let saved = (UserDefaults.standard.string(forKey: "custom") ?? "3 2").split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }.filter { $0 > 0 }
        let savedFrame = UserDefaults.standard.array(forKey: "customFrame") as? [Double] ?? [1, 1]
        let input = RowsInput(rows: saved, frame: Frame(width: savedFrame[0], height: savedFrame[1]))
        alert.accessoryView = input
        let arrange = alert.addButton(withTitle: "Arrange")
        alert.addButton(withTitle: "Cancel")
        input.changed = { arrange.isEnabled = !input.rows.isEmpty }
        input.changed()
        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = input.wells[0].field
        guard alert.runModal() == .alertFirstButtonReturn, !input.rows.isEmpty else { return }
        let picked = input.rows, frame = input.box
        UserDefaults.standard.set(picked.map(String.init).joined(separator: " "), forKey: "custom")
        UserDefaults.standard.set([frame.width, frame.height], forKey: "customFrame")
        NSApp.hide(nil) // hand focus back so the front window stays first
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.run(picked, frame: frame) }
    }
}

// Tells a dialog when the text in its field changes.
final class FieldWatcher: NSObject, NSTextFieldDelegate {
    let changed: () -> Void
    init(_ changed: @escaping () -> Void) { self.changed = changed }
    func controlTextDidChange(_ n: Notification) { changed() }
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
