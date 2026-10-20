import AppKit

/// Runs an app's info panel in its window: opens and closes it, places it, lets the user drag it to a corner, resize
/// it, reorder and collapse its sections, and keeps all of that per app in `UserDefaults` under `<prefix>Placement`,
/// `<prefix>Size`, `<prefix>Sections` and `<prefix>Visible`.
///
/// The panel is on screen (`isShown`) while the user wants it (`isVisible`, View › Show/Hide) and the app has
/// something to show (`isAvailable`). The app gives it sections (`show`) whenever they change, and calls `place` from
/// the host's layout and whenever the area it may cover changes. A drag follows the pointer and a drop keeps the
/// nearest corner of the area and the offset from it (`PanelPlacement.nearest`); a resize keeps the size and then the
/// place in the same way; a double click on a header, or Reset Position in the panel's menu, forgets both.
///
/// Controllers with one prefix and one `defaults` (an app's windows) follow each other: whatever one stores — shown or
/// not, place, size, section order and collapse — the others show at once (`stateDidChange`).
@MainActor public final class InfoPanelController {
    /// Posted by a controller after it stored something: object its `defaults`, `userInfo["prefix"]` its key prefix.
    public static let stateDidChange = Notification.Name("InfoPanelControllerStateDidChange")

    private let host: NSView
    private weak var sibling: NSView?
    private let defaultOrder: [String]
    private let defaultPlacement: PanelPlacement
    private let defaultSize: PanelSize
    private let defaults: UserDefaults
    private let area: () -> CGRect
    private let pasteboard: NSPasteboard
    private let placementKey, sizeKey, sectionsKey, visibleKey: String
    private let prefix: String
    private nonisolated(unsafe) var follower: NSObjectProtocol?

    /// Made the first time the panel is shown; out of the host while it is not shown.
    private(set) var panel: InfoPanelView?
    /// The window's field editor for the panel's values, made the first time one is selected.
    private var editor: PanelFieldEditor?
    /// The sections the app gave last, in its order.
    private var sections: [InfoSection] = []
    /// The panel's frame (area points, y down) while it is dragged (where the pointer holds it, maybe past an edge of
    /// the area) or resized; the stored place is used again once the press ends.
    private var dragFrame: CGRect?
    /// A resize in progress: the frame at the press, the edges it moves, how far the pointer went (window points, y
    /// up) and the size that makes.
    private var resizing: (start: CGRect, edges: PanelEdges, dx: CGFloat, dy: CGFloat, size: PanelSize)?

    /// The panel goes into `host` (the window's content view, not flipped) below `sibling` (nil: on top of the rest).
    /// `area` is the part of the host the panel may cover, in host points with y down, as `PanelPlacement` measures.
    public convenience init(host: NSView, below sibling: NSView?, keyPrefix: String, defaultOrder: [String],
                            defaultPlacement: PanelPlacement, defaultSize: PanelSize = .standard,
                            defaults: UserDefaults = .standard, area: @escaping () -> CGRect) {
        self.init(host: host, below: sibling, keyPrefix: keyPrefix, defaultOrder: defaultOrder,
                  defaultPlacement: defaultPlacement, defaultSize: defaultSize, defaults: defaults, area: area,
                  pasteboard: .general)
    }

    /// `pasteboard` is where Copy All, and ⌘C in a value, put the text (tests give their own).
    init(host: NSView, below sibling: NSView?, keyPrefix: String, defaultOrder: [String],
         defaultPlacement: PanelPlacement, defaultSize: PanelSize = .standard, defaults: UserDefaults,
         area: @escaping () -> CGRect, pasteboard: NSPasteboard) {
        self.host = host
        self.sibling = sibling
        self.defaultOrder = defaultOrder
        self.defaultPlacement = defaultPlacement
        self.defaultSize = defaultSize
        self.defaults = defaults
        self.area = area
        self.pasteboard = pasteboard
        placementKey = keyPrefix + "Placement"
        sizeKey = keyPrefix + "Size"
        sectionsKey = keyPrefix + "Sections"
        visibleKey = keyPrefix + "Visible"
        prefix = keyPrefix
        follower = NotificationCenter.default.addObserver(forName: Self.stateDidChange, object: defaults,
                                                          queue: nil) { [weak self] note in
            let prefix = note.userInfo?["prefix"] as? String
            let sender = note.userInfo?["sender"] as? AnyObject
            MainActor.assumeIsolated {
                guard let self, prefix == self.prefix, sender !== self else { return }
                self.follow()
            }
        }
    }

    deinit {
        if let follower { NotificationCenter.default.removeObserver(follower) }
    }

    /// Tells the other controllers of this prefix that something was stored.
    private func announce() {
        NotificationCenter.default.post(name: Self.stateDidChange, object: defaults,
                                        userInfo: ["prefix": prefix, "sender": self])
    }

    /// Another window stored something: shown or not, place, size and sections as it left them.
    private func follow() {
        dragFrame = nil
        resizing = nil
        update()
        refresh()
    }

    // MARK: Showing

    /// The user wants the panel (kept across launches); closed unless they opened it.
    public var isVisible: Bool { defaults.bool(forKey: visibleKey) }

    public func setVisible(_ visible: Bool) {
        defaults.set(visible, forKey: visibleKey)
        update()
        announce()
    }

    public func toggle() { setVisible(!isVisible) }

    /// The app has something to show (a video is open); the panel is on screen only then.
    public var isAvailable = false {
        didSet { if isAvailable != oldValue { update() } }
    }

    /// No sections, no panel: while the last `show` gave none, the panel is off screen even when visible and
    /// available. Off by default (an empty panel still shows its glass).
    public var hidesWhenEmpty = false {
        didSet { if hidesWhenEmpty != oldValue { update() } }
    }

    /// The panel is on screen: visible and available (and not empty, with `hidesWhenEmpty`).
    public var isShown: Bool { panel?.superview === host }

    /// The panel's frame in the host while it is on screen (nil while it is not), so the app can tell when the
    /// pointer is over it.
    public var panelFrame: NSRect? { isShown ? panel?.frame : nil }

    /// The panel came on screen (true) or left it, so the app starts or stops what refreshes it.
    public var onShownChange: ((Bool) -> Void)?

    /// Shows `sections` in the user's order (`SectionLayout`), collapsed as the user left them. Kept while the panel is
    /// not shown, for when it is, and for Copy All.
    public func show(_ sections: [InfoSection]) {
        self.sections = sections
        update()
        refresh()
    }

    /// Opens or closes the panel to match `isVisible` and `isAvailable`.
    private func update() {
        let wanted = isVisible && isAvailable && !(hidesWhenEmpty && sections.isEmpty)
        guard wanted != isShown else { return }
        if wanted { open() } else { close() }
        onShownChange?(isShown)
    }

    private func open() {
        let panel = self.panel ?? makePanel()
        if let sibling, sibling.superview === host {
            host.addSubview(panel, positioned: .below, relativeTo: sibling)
        } else {
            host.addSubview(panel)
        }
        refresh()
    }

    private func close() {
        guard let panel else { return }
        // A value selected in the panel holds the keys: they go back to whoever had them before.
        if selecting { panel.endSelection() }
        panel.removeFromSuperview()
        dragFrame = nil
        resizing = nil
    }

    private func makePanel() -> InfoPanelView {
        let panel = InfoPanelView()
        panel.fontSize = fontSize
        panel.middleTruncated = middleTruncated
        panel.onDrag = { [weak self] dx, dy in self?.drag(dx: dx, dy: dy) }
        panel.onDragEnd = { [weak self] in self?.drop() }
        panel.onResize = { [weak self] edges, dx, dy in self?.resize(edges: edges, dx: dx, dy: dy) }
        panel.onResizeEnd = { [weak self] in self?.endResize() }
        panel.onTitleDoubleClick = { [weak self] in self?.resetPosition() }
        panel.onReorder = { [weak self] id, before in
            guard let self else { return }
            layout = layout.moving(id, before: before, defaultOrder: defaultOrder)
            refresh()
        }
        panel.onCollapse = { [weak self] id, collapsed in
            guard let self else { return }
            if collapsed { layout.collapsed.insert(id) } else { layout.collapsed.remove(id) }
            refresh()
        }
        panel.onContextMenu = { [weak self] in self?.contextMenu() }
        panel.wheel = { [weak self] event in self?.wheel?(event) ?? false }
        panel.otherMouse = { [weak self] event in self?.otherMouse?(event) }
        self.panel = panel
        return panel
    }

    /// The sections in the user's order on the panel, and the panel placed for their height. A selected value whose
    /// field the new content took away (the rows were built again) gives the keys back as a press on a header does.
    private func refresh() {
        guard let panel, isShown else { return }
        let wasSelecting = selecting
        panel.show(ordered, collapsed: layout.collapsed)
        if wasSelecting, !selecting { panel.endSelection() }
        place()
    }

    private var ordered: [InfoSection] { layout.ordered(sections, defaultOrder: defaultOrder) }

    /// The field editor of a value in the panel has the keys.
    private var selecting: Bool {
        guard let panel, let editor = host.window?.firstResponder as? NSTextView else { return false }
        return editor.isDescendant(of: panel)
    }

    // MARK: Look and bindings

    /// The values' size (`InfoPanelView.fontSize`).
    public var fontSize: CGFloat = 12 {
        didSet {
            panel?.fontSize = fontSize
            place()
        }
    }

    /// Labels of the rows whose value stays on one line, cut in the middle (`InfoPanelView.middleTruncated`).
    public var middleTruncated: Set<String> = [] {
        didSet {
            panel?.middleTruncated = middleTruncated
            place()
        }
    }

    /// Asked first about every wheel event over the panel; true: the app took it and nothing scrolls.
    public var wheel: ((NSEvent) -> Bool)?
    /// The middle and side buttons over the panel, for the app's bindings of them.
    public var otherMouse: ((NSEvent) -> Void)?
    /// A key typed while a value is selected, other than ⌘C with text selected and ⌘A (an arrow, a letter, Esc, ⌘C
    /// with nothing selected, a ⌘ or ⌃ binding): the app's, which makes the view it belongs to the first responder and
    /// hands it the key. Nil: the field editor handles it.
    public var plainKey: ((NSEvent) -> Void)? {
        didSet { editor?.onPlainKey = plainKey }
    }

    /// The window's field editor for `client`, for the window delegate's `windowWillReturnFieldEditor`: the panel's
    /// (⌘C with text selected, ⌘A; every other key to `plainKey`) for its values, nil for anything else.
    public func fieldEditor(for client: Any?) -> Any? {
        guard let panel, let view = client as? NSView, view.isDescendant(of: panel) else { return nil }
        if let editor { return editor }
        let editor = PanelFieldEditor()
        editor.isFieldEditor = true
        editor.onPlainKey = plainKey
        editor.pasteboard = pasteboard
        self.editor = editor
        return editor
    }

    // MARK: Placement

    /// Where the panel was last dropped; none: the default place.
    private var placement: PanelPlacement {
        PanelPlacement(stored: defaults.string(forKey: placementKey)) ?? defaultPlacement
    }

    /// The size the panel's edges were last dragged to; none: the default size.
    private var size: PanelSize {
        PanelSize(stored: defaults.string(forKey: sizeKey)) ?? defaultSize
    }

    /// Sets the panel's frame: as tall as its content when there is room, at the stored corner and offset (or where a
    /// drag holds it), always inside the area (`PanelPlacement`). Cheap enough for every layout pass of the host.
    public func place() {
        guard let panel, isShown else { return }
        let area = area()
        let wanted = resizing?.size ?? size
        // The width first: the content's height is measured at it.
        panel.contentWidth = PanelPlacement.size(wanted, content: 0, in: area).width
        let size = PanelPlacement.size(wanted, content: Double(panel.contentHeight), in: area)
        let placed = dragFrame.map { PanelPlacement.clamped(CGRect(origin: $0.origin, size: size), in: area) }
            ?? placement.frame(size: size, in: area)
        let frame = host.backingAlignedRect(
            NSRect(x: placed.minX, y: host.bounds.height - placed.maxY, width: placed.width, height: placed.height),
            options: .alignAllEdgesNearest)
        if panel.frame != frame { panel.frame = frame }
    }

    /// The panel's frame in area points (y down).
    private func currentFrame(_ panel: InfoPanelView) -> CGRect {
        CGRect(x: panel.frame.minX, y: host.bounds.height - panel.frame.maxY, width: panel.frame.width,
               height: panel.frame.height)
    }

    /// The panel follows the pointer (window points, y up; the area's y is down).
    private func drag(dx: CGFloat, dy: CGFloat) {
        guard let panel else { return }
        var frame = dragFrame ?? currentFrame(panel)
        frame.origin.x += dx
        frame.origin.y -= dy
        // Where the pointer holds it, even past an edge: `place` keeps it inside the area, so a drag back brings it
        // back under the pointer where it was grabbed.
        dragFrame = frame
        place()
    }

    /// Dropped: stored as the nearest corner of the area and the offset from it.
    private func drop() {
        guard dragFrame != nil, let panel else { return }
        dragFrame = nil
        let placement = PanelPlacement.nearest(to: currentFrame(panel), in: area())
        defaults.set(placement.stored, forKey: placementKey)
        place()
        announce()
    }

    /// An edge dragged: the grabbed edges follow the pointer from where they were at the press, down to the minimum
    /// size and up to the area's edges; dragging the top or bottom gives the panel a height of its own.
    private func resize(edges: PanelEdges, dx: CGFloat, dy: CGFloat) {
        guard let panel else { return }
        let start = resizing?.start ?? currentFrame(panel)
        let totalX = (resizing?.dx ?? 0) + dx, totalY = (resizing?.dy ?? 0) + dy
        let frame = PanelPlacement.resized(start, edges: edges, dx: Double(totalX), dy: -Double(totalY), in: area())
        let height = edges.isDisjoint(with: [.top, .bottom]) ? size.height : Double(frame.height)
        resizing = (start, edges, totalX, totalY, PanelSize(width: Double(frame.width), height: height))
        dragFrame = frame
        place()
    }

    /// Released: the size is stored, then the place as after a move.
    private func endResize() {
        guard let resizing else { return }
        defaults.set(resizing.size.stored, forKey: sizeKey)
        self.resizing = nil
        drop()
    }

    /// Back to the default place and size, the stored ones forgotten.
    public func resetPosition() {
        dragFrame = nil
        resizing = nil
        defaults.removeObject(forKey: placementKey)
        defaults.removeObject(forKey: sizeKey)
        place()
        announce()
    }

    // MARK: Sections

    /// The user's section order and collapsed sections; an empty layout is not kept.
    private var layout: SectionLayout {
        get { SectionLayout(stored: defaults.string(forKey: sectionsKey)) ?? SectionLayout() }
        set {
            if newValue == SectionLayout() {
                defaults.removeObject(forKey: sectionsKey)
            } else {
                defaults.set(newValue.stored, forKey: sectionsKey)
            }
            announce()
        }
    }

    /// Back to the default order; collapsed sections stay collapsed.
    public func resetSectionOrder() {
        layout.order = []
        refresh()
    }

    /// The sections (as the panel orders them) as text (`InfoText.plain`), on the general pasteboard.
    public func copyAll() {
        pasteboard.clearContents()
        pasteboard.setString(InfoText.plain(ordered), forType: .string)
    }

    // MARK: Menu

    /// The panel's menu for a right click.
    private func contextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(PanelMenuItem(title: "Copy All") { [weak self] in self?.copyAll() })
        menu.addItem(PanelMenuItem(title: "Reset Section Order") { [weak self] in self?.resetSectionOrder() })
        menu.addItem(PanelMenuItem(title: "Reset Position") { [weak self] in self?.resetPosition() })
        return menu
    }
}

/// A menu item that runs a closure.
private final class PanelMenuItem: NSMenuItem {
    private let run: () -> Void

    init(title: String, run: @escaping () -> Void) {
        self.run = run
        super.init(title: title, action: #selector(runAction), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func runAction() { run() }
}
