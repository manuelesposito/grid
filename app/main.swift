// Grid: a menu bar icon that arranges the windows on the front window's screen in rows.
import AppKit
import ApplicationServices
import ServiceManagement
import Carbon.HIToolbox

final class App: NSObject, NSApplicationDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    // The first four sit in the menu; the rest under More. Control-Option-1 to 9 follow this order.
    let layouts: [[Int]] = [[2], [3], [2, 1], [2, 2], [4], [5], [3, 3], [4, 4], [5, 5]]
    let shown = 4
    var gap: CGFloat {
        get { CGFloat(UserDefaults.standard.double(forKey: "gap")) }
        set { UserDefaults.standard.set(Double(newValue), forKey: "gap") }
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        UserDefaults.standard.register(defaults: ["gap": 8.0])
        item.button?.image = icon([2, 2], w: 36, h: 28, radius: 6)
        item.button?.setAccessibilityLabel("Grid")
        // Start at login, once; the menu can turn it off.
        if !UserDefaults.standard.bool(forKey: "loginSet") {
            try? SMAppService.mainApp.register()
            UserDefaults.standard.set(true, forKey: "loginSet")
        }
        rebuild()
        registerHotKeys()
        waiting.start()
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
        let jump = NSMenuItem(title: "Go to Waiting Window", action: #selector(jumpToWaiting), keyEquivalent: "w")
        jump.keyEquivalentModifierMask = [.control, .option]; jump.target = self
        menu.addItem(jump)
        let f = NSMenuItem(title: "Focus", action: #selector(toggleFocus), keyEquivalent: "f")
        f.keyEquivalentModifierMask = [.control, .option]; f.target = self; f.state = focus.active ? .on : .off
        menu.addItem(f)
        // Everything that is set once and left alone sits together.
        let settings = NSMenu()
        let fs = NSMenuItem(title: "Focus Zoom", action: nil, keyEquivalent: "")
        let fsMenu = NSMenu()
        for z in [1, 1.25, 1.5, 1.75, 2] {
            let m = NSMenuItem(title: "\(z.formatted()) ×", action: #selector(setFocusZoom(_:)), keyEquivalent: "")
            m.target = self; m.representedObject = z; m.state = abs(focus.zoom - z) < 0.01 ? .on : .off
            fsMenu.addItem(m)
        }
        fs.submenu = fsMenu
        settings.addItem(fs)
        let fd = NSMenuItem(title: "Focus Darkness", action: nil, keyEquivalent: "")
        let fdMenu = NSMenu()
        for d in [0, 0.25, 0.5, 0.75, 0.9] {
            let m = NSMenuItem(title: d == 0 ? "None" : "\(Int(d * 100)) %", action: #selector(setFocusShade(_:)), keyEquivalent: "")
            m.target = self; m.representedObject = d; m.state = abs(focus.shade - d) < 0.01 ? .on : .off
            fdMenu.addItem(m)
        }
        fd.submenu = fdMenu
        settings.addItem(fd)
        menu.addItem(.separator())
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
        let more = NSMenu()
        let code = NSMenuItem(title: "", action: #selector(pickCoding), keyEquivalent: "c")
        code.image = icon(coding)
        code.setAccessibilityLabel("Coding"); code.toolTip = "Coding"
        code.keyEquivalentModifierMask = [.control, .option]; code.target = self
        more.addItem(code)
        for (i, l) in layouts.enumerated() {
            let m = NSMenuItem(title: "", action: #selector(pick(_:)), keyEquivalent: "")
            m.image = icon(l)
            m.setAccessibilityLabel(name(l))
            m.toolTip = name(l)
            m.tag = i; m.target = self
            m.keyEquivalent = "\(i + 1)"; m.keyEquivalentModifierMask = [.control, .option]
            (i < shown ? menu : more).addItem(m)
        }
        more.addItem(.separator())
        more.addItem(withTitle: "Custom…", action: #selector(custom), keyEquivalent: "").target = self
        let moreItem = NSMenuItem(title: "More", action: nil, keyEquivalent: "")
        moreItem.submenu = more
        menu.addItem(moreItem)
        menu.addItem(.separator())
        let u = NSMenuItem(title: "Undo", action: #selector(undo), keyEquivalent: "z")
        u.keyEquivalentModifierMask = [.control, .option]; u.target = self
        menu.addItem(u)
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
        let wt = NSMenuItem(title: "Mark Waiting Claude Windows", action: #selector(toggleWaiting), keyEquivalent: "")
        wt.target = self; wt.state = waiting.enabled ? .on : .off
        settings.addItem(.separator())
        settings.addItem(wt)
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

    func name(_ l: [Int]) -> String {
        l.count == 1 ? "\(l[0]) in a row" : l.map(String.init).joined(separator: " + ")
    }

    // A small picture of the layout: the screen as one solid rounded shape, split by fine cuts.
    // Drawn in half points, the pixels of the screen, so every edge sits on a whole pixel.
    func icon(_ rows: [Int], w: Int = 60, h: Int = 38, radius: CGFloat = 7) -> NSImage {
        let cut = 2
        // Whole-pixel sizes for n parts with cuts between them.
        func parts(_ total: Int, _ n: Int) -> [Int] {
            let room = total - cut * (n - 1)
            return (0..<n).map { room / n + ($0 < room % n ? 1 : 0) }
        }
        var tiles: [NSRect] = []
        if rows == coding {
            // Big browser tile on the left, two stacked on the right.
            let split = 36, hs = parts(h, 2)
            tiles = [NSRect(x: 0, y: 0, width: split, height: h),
                     NSRect(x: split + cut, y: 0, width: w - split - cut, height: hs[0]),
                     NSRect(x: split + cut, y: hs[0] + cut, width: w - split - cut, height: hs[1])]
        } else {
            var y = 0
            for (rowH, count) in zip(parts(h, rows.count), rows) {
                var x = 0
                for colW in parts(w, count) {
                    tiles.append(NSRect(x: x, y: y, width: colW, height: rowH))
                    x += colW + cut
                }
                y += rowH + cut
            }
        }
        let img = NSImage(size: NSSize(width: w / 2, height: h / 2), flipped: true) { _ in
            let half = NSAffineTransform(); half.scale(by: 0.5); half.concat()
            NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: w, height: h), xRadius: radius, yRadius: radius).addClip()
            NSColor.black.setFill()
            for tile in tiles { NSBezierPath(roundedRect: tile, xRadius: 1, yRadius: 1).fill() }
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
            switch id.id {
            case 98: d.undo()
            case 96: d.jumpToWaiting()
            case 95: d.toggleFocus()
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
        for (key, id) in [(kVK_ANSI_0, 99), (kVK_ANSI_Z, 98), (kVK_ANSI_C, 97), (kVK_ANSI_W, 96), (kVK_ANSI_F, 95)] {
            var ref: EventHotKeyRef?
            RegisterEventHotKey(UInt32(key), UInt32(controlKey | optionKey), EventHotKeyID(signature: OSType(0x47524944), id: UInt32(id)), GetApplicationEventTarget(), 0, &ref)
        }
    }

    let waiting = Waiting()
    let focus = Focus()
    let quitSignal = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
    func applicationWillTerminate(_ n: Notification) { _ = focus.end() }
    let workspaces = Workspaces()

    // A new focus zoom shows right away when focus is on.
    @objc func setFocusZoom(_ m: NSMenuItem) { focus.zoom = m.representedObject as? Double ?? 2; refocus() }
    // A new darkness shows right away when focus is on.
    @objc func setFocusShade(_ m: NSMenuItem) { focus.shade = m.representedObject as? Double ?? 0.75; rebuild() }
    func refocus() {
        rebuild()
        guard focus.active else { return }
        _ = focus.end()
        DispatchQueue.main.asyncAfter(deadline: .now() + glideTime + 0.1) { _ = self.focus.start(); self.rebuild() }
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
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.placeholderString = "Name, for example Architrave"
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        // Remember the screen before the alert takes the focus.
        let front = NSWorkspace.shared.frontmostApplication
        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { front?.activate(); return }
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
    @objc func toggleWaiting() { waiting.enabled.toggle(); rebuild() }

    // Empty rows = automatic, [0] = coding.
    let coding = [0]
    // Kept across restarts, so a new space can re-arrange right after Grid starts.
    var last: [Int]? {
        get { UserDefaults.standard.array(forKey: "last") as? [Int] }
        set { UserDefaults.standard.set(newValue, forKey: "last") }
    }
    var undoFrames: [(AXUIElement, CGRect)] = []
    // A short sound when there is nothing to arrange.
    func run(_ rows: [Int]) {
        last = rows
        let result = rows == coding ? arrangeCoding(gap: gap) : arrange(rows, gap: gap)
        if result.placed == 0 { NSSound.beep() } else if undoFrames.isEmpty || !sameWindows(result.before) { undoFrames = result.before }
    }

    // Undo keeps the places from before the first of several arrangements in a row.
    func sameWindows(_ b: [(AXUIElement, CGRect)]) -> Bool {
        Set(b.map { CFHash($0.0) }) == Set(undoFrames.map { CFHash($0.0) })
    }

    @objc func undo() {
        guard !undoFrames.isEmpty else { NSSound.beep(); return }
        glide(undoFrames.compactMap { w, f in axFrame(w).map { (w, $0, f) } })
        undoFrames = []
    }

    @objc func pickAuto() { run([]) }
    @objc func jumpToWaiting() { if !waiting.jump() { NSSound.beep() } }
    @objc func pickCoding() { run(coding) }

    @objc func pick(_ m: NSMenuItem) { run(layouts[m.tag]) }
    // A new space re-arranges the last layout right away, so the change shows.
    @objc func setGap(_ m: NSMenuItem) {
        gap = CGFloat(m.tag); rebuild()
        let rows = last ?? []
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.run(rows) }
    }

    @objc func toggleLogin() {
        let s = SMAppService.mainApp
        if s.status == .enabled { try? s.unregister() } else { try? s.register() }
        rebuild()
    }

    @objc func custom() {
        let alert = NSAlert()
        alert.messageText = "Windows per row"
        alert.informativeText = "One number per row, for example: 3 2"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        field.stringValue = UserDefaults.standard.string(forKey: "custom") ?? "3 2"
        alert.accessoryView = field
        alert.addButton(withTitle: "Arrange")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let rows = field.stringValue.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }.filter { $0 > 0 }
        guard !rows.isEmpty else { return }
        UserDefaults.standard.set(field.stringValue, forKey: "custom")
        NSApp.hide(nil) // hand focus back so the front window stays first
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.run(rows) }
    }
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
