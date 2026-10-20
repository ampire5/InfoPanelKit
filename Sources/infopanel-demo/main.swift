// A window to try InfoPanelKit's panel by hand, run by `InfoPanelController` (keys `demoPanel…` in the
// `infopanel-demo` defaults): a moving picture stands in for a video, the panel shows four sections (one with a long
// wrapping value, one with a three-line value) whose values change twice a second. Drag a header to reorder, press a
// triangle to collapse, select a value while it changes, scroll the long panel, drag the panel or its edges, right
// click it for its menu, ⌘I to hide and show it; all of it is there again after ⌘Q and a relaunch. Keys and what the
// app takes are printed.
import AppKit
import InfoPanelKit

/// Stands in for the video under the panel: bright, moving colour, so the glass and its legibility show.
final class FakeVideoView: NSView {
    private var phase: CGFloat = 0
    private var timer: Timer?

    override init(frame: NSRect) {
        super.init(frame: frame)
        timer = Timer.scheduledTimer(withTimeInterval: 1 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.phase += 0.02
                self.needsDisplay = true
            }
        }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ dirtyRect: NSRect) {
        NSGradient(colors: [.systemTeal, .systemIndigo, .systemOrange])?.draw(in: bounds, angle: 30 + 20 * sin(phase))
        let colours: [NSColor] = [.white, .systemYellow, .systemPink, .systemGreen]
        for (i, colour) in colours.enumerated() {
            let t = phase * (1 + CGFloat(i) * 0.3) + CGFloat(i) * 1.7
            let r = 60 + CGFloat(i) * 25
            let centre = NSPoint(x: bounds.midX + cos(t) * bounds.width * 0.35,
                                 y: bounds.midY + sin(t * 1.3) * bounds.height * 0.3)
            colour.withAlphaComponent(0.8).setFill()
            NSBezierPath(ovalIn: NSRect(x: centre.x - r, y: centre.y - r, width: 2 * r, height: 2 * r)).fill()
        }
    }
}

/// The window's content: lays the panel out again whenever it is resized, and has the keys (it prints them).
final class HostView: NSView {
    var onLayout: (() -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func layout() {
        super.layout()
        onLayout?()
    }
    override func keyDown(with event: NSEvent) { print("key:", event.charactersIgnoringModifiers ?? "") }
    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self) }
}

@MainActor final class Demo: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let defaultOrder = ["File", "Video", "Playback", "Diagnostics"]
    private var window: NSWindow!
    private let host = HostView()
    private var panel: InfoPanelController!
    private var tick = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 640),
                          styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered,
                          defer: false)
        window.title = "InfoPanelKit Demo"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = host
        let video = FakeVideoView(frame: host.bounds)
        video.autoresizingMask = [.width, .height]
        host.addSubview(video)
        configurePanel()
        NSApp.mainMenu = mainMenu()
        refresh()
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(host)
        NSApp.activate()
        print("window:", window.windowNumber)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func windowWillReturnFieldEditor(_ sender: NSWindow, to client: Any?) -> Any? { panel.fieldEditor(for: client) }

    private func configurePanel() {
        let host = host
        panel = InfoPanelController(host: host, below: nil, keyPrefix: "demoPanel", defaultOrder: defaultOrder,
                                    defaultPlacement: PanelPlacement(corner: .topRight, dx: 12, dy: 12),
                                    area: { CGRect(origin: .zero, size: host.bounds.size) })
        panel.middleTruncated = ["Folder"]
        panel.onShownChange = { print("shown:", $0) }
        panel.wheel = { event in
            // ⌥ + wheel stands in for an app binding: the app takes it and nothing scrolls.
            guard event.modifierFlags.contains(.option) else { return false }
            print("wheel taken by the app:", event.scrollingDeltaY)
            return true
        }
        panel.otherMouse = { print("other mouse:", $0.type.rawValue, "button", $0.buttonNumber) }
        // A plain key typed while a value is selected: the keys go back to the host, which gets this one too.
        panel.plainKey = { [weak self] event in
            guard let self else { return }
            window.makeFirstResponder(host)
            host.keyDown(with: event)
        }
        host.onLayout = { [weak self] in self?.panel.place() }
        // Shown on the first launch; after that as the user left it (View › Show/Hide Panel, ⌘I).
        if UserDefaults.standard.object(forKey: "demoPanelVisible") == nil { panel.setVisible(true) }
        panel.isAvailable = true
    }

    private func mainMenu() -> NSMenu {
        let main = NSMenu()
        let app = NSMenu()
        app.addItem(withTitle: "Quit InfoPanelKit Demo", action: #selector(NSApplication.terminate(_:)),
                    keyEquivalent: "q")
        main.addItem(withTitle: "", action: nil, keyEquivalent: "").submenu = app
        let view = NSMenu(title: "View")
        view.addItem(withTitle: "Show/Hide Panel", action: #selector(togglePanel), keyEquivalent: "i").target = self
        main.addItem(withTitle: "View", action: nil, keyEquivalent: "").submenu = view
        return main
    }

    @objc private func togglePanel() { panel.toggle() }

    // MARK: Content

    private func refresh() {
        tick += 1
        let seconds = Double(tick) / 2
        let position = String(format: "%02d:%04.1f / 42:17.0", Int(seconds) / 60,
                              seconds.truncatingRemainder(dividingBy: 60))
        let description = (0..<40).map { "Sentence \($0 + 1) of a long description that wraps over many lines." }
            .joined(separator: " ")
        panel.show([
            InfoSection(title: "File", rows: [
                InfoRow(label: "Name", value: "Big Buck Bunny (2008) 1080p.mkv"),
                InfoRow(label: "Folder", value: "/Volumes/Media/Movies/Animation/Blender Foundation/Open Movies/2008"),
                InfoRow(label: "Size", value: "2.31 GB"),
            ]),
            InfoSection(title: "Video", rows: [
                InfoRow(label: "Codec", value: "HEVC Main 10"),
                InfoRow(label: "Resolution", value: "1920 × 1080"),
                InfoRow(label: "Frame rate", value: "24.000 fps"),
                InfoRow(label: "Description", value: description),
            ]),
            InfoSection(title: "Playback", rows: [
                InfoRow(label: "Position", value: position),
                InfoRow(label: "Speed", value: tick % 20 < 10 ? "1×" : "2×"),
            ]),
            InfoSection(title: "Diagnostics", rows: [
                InfoRow(label: "Pipeline",
                        value: "decoded \(tick * 12) frames\ndropped \(tick / 7)\nqueue \(tick % 5) of 8"),
                InfoRow(label: "Renderer", value: "Metal, 10-bit"),
            ]),
        ])
    }
}

setvbuf(stdout, nil, _IOLBF, 0)   // what the panel reports shows at once in a pipe too
MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let demo = Demo()
    app.delegate = demo
    app.run()
}
