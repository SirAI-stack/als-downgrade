// ALS Downgrade - by Carni
import Cocoa

final class DropZone: NSView {
    var onFiles: (([URL]) -> Void)?
    var hot = false { didSet { needsDisplay = true } }
    let label = NSTextField(labelWithString: "Drop a .als or project folder")
    let glyph = NSImageView()
    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
        label.alignment = .center
        label.font = .systemFont(ofSize: 13, weight: .regular)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 3
        label.preferredMaxLayoutWidth = 280
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false
        glyph.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: nil)
        glyph.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 34, weight: .light)
        glyph.contentTintColor = .tertiaryLabelColor
        glyph.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glyph); addSubview(label)
        NSLayoutConstraint.activate([
            glyph.centerXAnchor.constraint(equalTo: centerXAnchor),
            glyph.bottomAnchor.constraint(equalTo: centerYAnchor, constant: -8),
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.topAnchor.constraint(equalTo: centerYAnchor, constant: 6),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ r: NSRect) {
        let p = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 18, yRadius: 18)
        (hot ? NSColor.controlAccentColor.withAlphaComponent(0.14) : NSColor.labelColor.withAlphaComponent(0.04)).setFill()
        p.fill()
        if hot { NSColor.controlAccentColor.setStroke(); p.lineWidth = 2; p.stroke() }
    }
    func urls(_ s: NSDraggingInfo) -> [URL] {
        let u = s.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return u.filter { $0.pathExtension.lowercased() == "als" || $0.hasDirectoryPath }
    }
    override func draggingEntered(_ s: NSDraggingInfo) -> NSDragOperation {
        if urls(s).isEmpty { return [] }; hot = true; return .copy
    }
    override func draggingExited(_ s: NSDraggingInfo?) { hot = false }
    override func performDragOperation(_ s: NSDraggingInfo) -> Bool {
        hot = false; let u = urls(s); if u.isEmpty { return false }; onFiles?(u); return true
    }
    override func mouseDown(with e: NSEvent) {
        let p = NSOpenPanel(); p.allowsMultipleSelection = true; p.canChooseDirectories = true
        if p.runModal() == .OK { onFiles?(p.urls) }
    }
}

final class PillButton: NSButton {
    init(_ t: String) {
        super.init(frame: .zero)
        isBordered = false; wantsLayer = true
        layer?.cornerRadius = 17; layer?.cornerCurve = .continuous
        attributedTitle = NSAttributedString(string: t, attributes: [
            .foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 13, weight: .semibold)])
        heightAnchor.constraint(equalToConstant: 34).isActive = true
        widthAnchor.constraint(equalToConstant: 170).isActive = true
        refresh()
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isEnabled: Bool { didSet { refresh() } }
    func refresh() {
        layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        alphaValue = isEnabled ? 1 : 0.6
    }
    override func updateLayer() { refresh() }
}

final class InfoController: NSViewController {
    override func loadView() {
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 34, left: 24, bottom: 22, right: 24)
        func add(_ t: String, _ f: NSFont, _ c: NSColor = .labelColor, after: CGFloat = 0) {
            let l = NSTextField(wrappingLabelWithString: t); l.font = f; l.textColor = c
            l.preferredMaxLayoutWidth = 300; l.isSelectable = false
            l.translatesAutoresizingMaskIntoConstraints = false
            l.widthAnchor.constraint(equalToConstant: 300).isActive = true
            stack.addArrangedSubview(l)
            if after > 0 { stack.setCustomSpacing(after, after: l) }
        }
        let body = NSFont.systemFont(ofSize: 12), head = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let dim = NSColor.secondaryLabelColor
        add("ALS Downgrade", .systemFont(ofSize: 17, weight: .semibold))
        add("Version 1.1", body, dim, after: 10)
        add("Opens Ableton Live projects saved with a newer version in the Live you have. Your original file is never changed.", body, after: 12)
        add("Supported versions", head)
        add("✓  Live 12.4 → Live 12.0: tested with real projects", body)
        add("•  Other Live 12 versions: expected to work", body)
        add("•  Live 12 → Live 10 or 11: experimental, command line", body)
        add("×  Live 9 or older: not supported", body, dim, after: 12)
        add("What it does", head)
        add("Rewrites the project using the format files inside your own Live, keeps tracks, clips, MIDI and automation, and relinks collected audio from the project Samples folder.", body, after: 12)
        add("Good to know", head)
        add("Devices that do not exist in your Live are removed, with a warning. Third-party plugins must be installed. Keep the .als inside its project folder.", body, after: 14)
        add("By Carni", head)
        add("Free and open source, MIT License.", body, dim)
        add("Not affiliated with Ableton AG.", body, dim)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.widthAnchor.constraint(equalToConstant: 348).isActive = true
        view = stack
    }
}

final class App: NSObject, NSApplicationDelegate {
    var win: NSWindow!
    let zone = DropZone(frame: .zero)
    let text = NSTextView()
    let scroll = NSScrollView()
    let openBtn = PillButton("Open in Live")
    let advBtn = NSButton(title: "Advanced", target: nil, action: nil)
    let infoBtn = NSButton()
    var infoWin: NSWindow?
    let spin = NSProgressIndicator()
    var logHeight: NSLayoutConstraint!
    var created: [String] = []
    var pending: [URL] = []

    func applicationDidFinishLaunching(_ n: Notification) {
        win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 330),
                       styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                       backing: .buffered, defer: false)
        win.title = "ALS Downgrade"; win.titleVisibility = .hidden; win.titlebarAppearsTransparent = true
        win.isMovableByWindowBackground = true; win.center(); win.isReleasedWhenClosed = false
        let fx = NSVisualEffectView(); fx.material = .underWindowBackground; fx.blendingMode = .behindWindow; fx.state = .active
        win.contentView = fx
        scroll.documentView = text; scroll.hasVerticalScroller = true; scroll.borderType = .noBorder
        scroll.drawsBackground = false; text.drawsBackground = false
        text.isEditable = false; text.autoresizingMask = [.width]
        text.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        text.textColor = .secondaryLabelColor
        openBtn.target = self; openBtn.action = #selector(openLive); openBtn.keyEquivalent = "\r"; openBtn.isHidden = true
        advBtn.target = self; advBtn.action = #selector(toggleLog)
        advBtn.isBordered = false
        advBtn.attributedTitle = NSAttributedString(string: "Advanced", attributes: [
            .foregroundColor: NSColor.secondaryLabelColor, .font: NSFont.systemFont(ofSize: 11)])
        infoBtn.isBordered = false; infoBtn.setAccessibilityLabel("Info")
        infoBtn.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: "Info")
        infoBtn.contentTintColor = .secondaryLabelColor
        infoBtn.target = self; infoBtn.action = #selector(showInfo)
        let by = NSTextField(labelWithString: "By Carni")
        by.font = .systemFont(ofSize: 11); by.textColor = .tertiaryLabelColor
        spin.style = .spinning; spin.controlSize = .small; spin.isDisplayedWhenStopped = false
        zone.onFiles = { [weak self] in self?.convert($0) }
        let root = win.contentView!
        for v in [zone, scroll, openBtn, advBtn, infoBtn, by, spin] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(v)
        }
        logHeight = scroll.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            infoBtn.topAnchor.constraint(equalTo: root.topAnchor, constant: 8),
            infoBtn.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            zone.topAnchor.constraint(equalTo: root.topAnchor, constant: 40),
            zone.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 22),
            zone.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -22),
            zone.heightAnchor.constraint(equalToConstant: 190),
            openBtn.topAnchor.constraint(equalTo: zone.bottomAnchor, constant: 18),
            openBtn.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            spin.centerYAnchor.constraint(equalTo: openBtn.centerYAnchor),
            spin.leadingAnchor.constraint(equalTo: openBtn.trailingAnchor, constant: 10),
            scroll.topAnchor.constraint(equalTo: openBtn.bottomAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: zone.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: zone.trailingAnchor),
            logHeight,
            advBtn.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 6),
            advBtn.leadingAnchor.constraint(equalTo: zone.leadingAnchor),
            advBtn.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -10),
            by.centerYAnchor.constraint(equalTo: advBtn.centerYAnchor),
            by.trailingAnchor.constraint(equalTo: zone.trailingAnchor),
        ])
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if !pending.isEmpty { convert(pending); pending = [] }
    }
    func application(_ a: NSApplication, open urls: [URL]) {
        if win == nil { pending += urls } else { convert(urls) }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ a: NSApplication) -> Bool { true }
    func applicationShouldHandleReopen(_ a: NSApplication, hasVisibleWindows f: Bool) -> Bool {
        win.makeKeyAndOrderFront(nil); return true
    }
    @objc func showInfo() {
        if infoWin == nil {
            let w = NSWindow(contentViewController: InfoController())
            w.styleMask = [.titled, .closable, .fullSizeContentView]
            w.title = "About ALS Downgrade"; w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true; w.isMovableByWindowBackground = true
            w.isReleasedWhenClosed = false; w.center(); infoWin = w
        }
        infoWin?.makeKeyAndOrderFront(nil)
    }
    @objc func toggleLog() {
        let show = logHeight.constant == 0
        logHeight.constant = show ? 170 : 0
        var f = win.frame; let d: CGFloat = show ? 170 : -170
        f.size.height += d; f.origin.y -= d
        win.setFrame(f, display: true, animate: true)
    }
    func status(_ s: String) { zone.label.stringValue = s }
    func say(_ m: String) {
        DispatchQueue.main.async { self.text.string += m + "\n"; self.text.scrollToEndOfDocument(nil) }
    }
    func convert(_ urls: [URL]) {
        win.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        created = []; openBtn.isHidden = true; spin.startAnimation(nil)
        status("Converting…"); text.string = ""
        if run("/usr/bin/xcode-select", ["-p"]) != 0 {
            spin.stopAnimation(nil)
            status("First install Apple's free developer tools.\nmacOS will show a window: click Install.")
            _ = run("/usr/bin/xcode-select", ["--install"])
            return
        }
        let script = Bundle.main.path(forResource: "als_downgrade", ofType: "py")!
        DispatchQueue.global().async {
            let p = Process(); let pipe = Pipe()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            p.arguments = [script, "--repair"] + urls.map { $0.path }
            p.standardOutput = pipe; p.standardError = pipe
            var out = ""
            do {
                try p.run()
                let d = pipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                out = String(decoding: d, as: UTF8.self)
            } catch { out = "Could not run the converter: \(error.localizedDescription)" }
            let lines = out.components(separatedBy: "\n")
            let files = lines.filter { $0.hasPrefix("  Created: ") }.map { String($0.dropFirst(11)) }
            let warn = lines.filter { $0.contains("!") }.count
            DispatchQueue.main.async {
                self.spin.stopAnimation(nil)
                self.text.string = out
                self.created = files
                self.openBtn.isEnabled = true; self.openBtn.isHidden = files.isEmpty
                if let f = files.first {
                    let n = URL(fileURLWithPath: f).lastPathComponent
                    self.status(files.count > 1 ? "✓ \(files.count) projects converted" : "✓ \(n)")
                    if warn > 0 { self.status(self.zone.label.stringValue + "\n\(warn) warning(s), see Advanced") }
                } else if out.contains("Already compatible") {
                    self.status("Already compatible with your Live")
                } else {
                    self.status("Could not convert. See Advanced.")
                }
            }
        }
    }
    func liveLog() -> String? {
        let base = NSHomeDirectory() + "/Library/Preferences/Ableton"
        let dirs = (try? FileManager.default.contentsOfDirectory(atPath: base)) ?? []
        let logs = dirs.map { base + "/" + $0 + "/Log.txt" }.filter { FileManager.default.fileExists(atPath: $0) }
        func date(_ p: String) -> Date {
            ((try? FileManager.default.attributesOfItem(atPath: p))?[.modificationDate] as? Date) ?? .distantPast
        }
        return logs.max { date($0) < date($1) }
    }
    func run(_ tool: String, _ args: [String]) -> Int32 {
        let p = Process(); p.executableURL = URL(fileURLWithPath: tool); p.arguments = args
        p.standardOutput = Pipe(); p.standardError = Pipe()
        do { try p.run() } catch { return -1 }
        p.waitUntilExit(); return p.terminationStatus
    }
    func liveRunning() -> Bool { run("/usr/bin/pgrep", ["-x", "Live"]) == 0 }
    func stamp(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"; return f.string(from: d)
    }
    func logLines(since: String) -> [Substring] {
        guard let p = liveLog(), let d = FileManager.default.contents(atPath: p) else { return [] }
        return String(decoding: d, as: UTF8.self).precomposedStringWithCanonicalMapping
            .split(separator: "\n").filter { $0.count > 19 && $0.prefix(19) >= since }
    }
    // A file sent while Live is starting can be lost, so success only counts
    // once Live's own log confirms that this project was loaded.
    func deliver(_ file: URL, livePath: String) {
        let name = file.path.precomposedStringWithCanonicalMapping
        let start = stamp(Date())
        var ready = liveRunning()
        if !ready {
            DispatchQueue.main.async { self.status("Starting Live…") }
            _ = run("/usr/bin/open", ["-a", livePath])
        }
        var lastSend = -100, warned = false
        for t in 0..<180 {
            let lines = logLines(since: start)
            if lines.contains(where: { $0.contains("Loading document") && $0.contains(name) }) {
                for _ in 0..<10 {
                    Thread.sleep(forTimeInterval: 1)
                    if !liveRunning() { done("Live closed while opening this project."); return }
                }
                done("✓ Opened in Live"); return
            }
            if !ready && lines.contains(where: { $0.contains("Loaded document was created") }) {
                ready = true; Thread.sleep(forTimeInterval: 2)
            }
            if !ready && !warned && lines.contains(where: { $0.contains("Message Box") }) {
                warned = true; DispatchQueue.main.async { self.status("Live is showing a dialog: answer it") }
            }
            if ready && t - lastSend >= 8 {
                if !liveRunning() { done("Live closed. Try again."); return }
                lastSend = t
                _ = run("/usr/bin/open", ["-a", livePath, file.path])
            }
            Thread.sleep(forTimeInterval: 1)
        }
        done("Live did not load the project. Check for a dialog.")
    }
    func done(_ m: String) { say(m); DispatchQueue.main.async { self.status(m) } }
    // Abre con la app predeterminada de los .als (AbletonBlock), que ya sabe
    // arrancar Live y entregarle el proyecto. Nunca lanza Live por su cuenta.
    @objc func openLive() {
        guard let file = created.first.map({ URL(fileURLWithPath: $0) }) else { return }
        NSWorkspace.shared.open(file)
        status("✓ Sent to Live")
    }
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
