import AppKit

/// The panel's look (style B): darker glass, white values, quieter labels set against them, quiet headers in small
/// spaced capitals with a hairline.
enum InfoPanelStyle {
    static let tint: CGFloat = 0.46
    static let labelAlpha: CGFloat = 0.55
    static let valueAlpha: CGFloat = 1.0
    static let headerAlpha: CGFloat = 0.5
    static let headerHoverAlpha: CGFloat = 0.8
    static let ruleAlpha: CGFloat = 0.18
    static let sectionGap: CGFloat = 11
    /// The headers' letter spacing, in ems.
    static let headerKern: CGFloat = 0.08
}

/// An info panel: `InfoSection`s on dark glass, each a header (a disclosure triangle and the title) over two-column
/// rows (a quiet label, the value in monospaced digits), the values selectable for copying. The rows live in an
/// `NSOutlineView`: a section is a top-level item, its rows its children, so a section collapses (the triangle,
/// `onCollapse`) and is dragged by its header to another place among the sections (`onReorder`); the owner keeps the
/// order and the collapsed sections and shows the sections again in that order.
///
/// The owner sets its frame (`PanelPlacement`): as tall as `contentHeight` when there is room, longer content scrolls
/// inside it. It owns every mouse event over it (what is under it neither pans, zooms nor scrubs from them) and shows
/// the arrow there. A drag anywhere but on a header or a value's text moves it (`onDrag`, `onDragEnd`); a double click
/// on a header asks for the default place (`onTitleDoubleClick`). A press within a few points of an edge resizes it
/// instead (`onResize`, `onResizeEnd`; `PanelPlacement.edges`), under the matching resize cursor; the owner sets its
/// width (`contentWidth`). The wheel and the middle and side buttons are offered to the app first (`wheel`,
/// `otherMouse`), so its bindings work over the panel as over what is under it.
@MainActor public final class InfoPanelView: NSView {
    public static let cornerRadius: CGFloat = 14
    private static let inset = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
    /// Between the label and the value column (width), and between rows (height).
    private static let spacing = NSSize(width: 10, height: 3)
    /// Above each header but the first, so a section stands apart from the rows of the one before it.
    private static let sectionGap = InfoPanelStyle.sectionGap
    private static let labelColour = NSColor(white: 1, alpha: InfoPanelStyle.labelAlpha)
    private static let valueColour = NSColor(white: 1, alpha: InfoPanelStyle.valueAlpha)
    /// What a dragged header puts on the pasteboard: its section's id.
    static let sectionType = NSPasteboard.PasteboardType("local.infopanel.section")

    /// The outline places each cell half the column spacing in from its column's edges; the cells pad the rest of the
    /// panel's side insets themselves.
    private static var sidePadding: CGFloat { inset.left - spacing.width / 2 }

    private let backdrop = GlassBackdrop(cornerRadius: InfoPanelView.cornerRadius, tint: InfoPanelStyle.tint,
                                         hairline: true)
    private let scrollView = PanelScrollView()
    let outline = PanelOutlineView()
    /// The outline's data source and delegate (the outline holds them weakly).
    private(set) lazy var source = PanelOutlineSource(panel: self)
    let labelColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("label"))
    private let valueColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("value"))
    /// What the outline shows, kept while only values change (the stats timer), so the outline keeps its rows and
    /// views: a selection in an unchanged value stays, and nothing is laid out again but a value that took more or
    /// fewer lines.
    private(set) var items: [SectionItem] = []
    private var shown: [InfoSection] = []
    private var collapsed: Set<String> = []
    /// The label column's text width of the last rebuild, so a new panel width only moves the value column's wrap.
    private var labelWidth: CGFloat = 0
    /// The pointer's last window position during a drag of the panel, and whether it moved since the press.
    private var dragPoint: NSPoint?
    private var dragMoved = false
    /// The edges the press being dragged resizes; empty for a press that moves the panel.
    private var resizeEdges: PanelEdges = []
    /// Set while a scroll over the glass is handed to the scroll view: what it passes back up the responder chain
    /// (content shorter than the panel) ends here instead of coming round again.
    private var forwardingScroll = false

    /// A drag moved the pointer by `dx`, `dy` (window points, y up).
    public var onDrag: ((CGFloat, CGFloat) -> Void)?
    /// The drag that moved the panel ended.
    public var onDragEnd: (() -> Void)?
    /// A press on `edges` moved the pointer by `dx`, `dy` (window points, y up).
    public var onResize: ((PanelEdges, CGFloat, CGFloat) -> Void)?
    /// The drag that resized the panel ended.
    public var onResizeEnd: (() -> Void)?
    /// A double click on a section header.
    public var onTitleDoubleClick: (() -> Void)?
    /// A header was dropped: the section `id` goes before the section `before` (nil: last). The panel does not move
    /// it itself; the owner keeps the order (`SectionLayout.moving`) and shows the sections again.
    public var onReorder: ((_ id: String, _ before: String?) -> Void)?
    /// The triangle collapsed or expanded the section `id`; the panel has done it already, the owner keeps it.
    public var onCollapse: ((_ id: String, _ collapsed: Bool) -> Void)?
    /// The menu for a right click on the panel; a value's text keeps the system's text menu (Copy, Look Up).
    public var onContextMenu: (() -> NSMenu?)?
    /// Asked first about every wheel event over the panel (an app binding of a held button and the wheel); true: it
    /// took the event and nothing scrolls.
    public var wheel: ((NSEvent) -> Bool)?
    /// The middle and side buttons' downs, drags and ups over the panel, for the app's bindings of them.
    public var otherMouse: ((NSEvent) -> Void)?

    /// The values' size; labels are as large, titles a point smaller and semibold. A change rebuilds the rows.
    public var fontSize: CGFloat = 12 {
        didSet { if fontSize != oldValue { rebuild(shown) } }
    }

    /// Labels of the rows whose value stays on one line, cut in the middle (a long path keeps its start and its end;
    /// the whole value is its tooltip). A change rebuilds the rows.
    public var middleTruncated: Set<String> = [] {
        didSet { if middleTruncated != oldValue { rebuild(shown) } }
    }

    public init() {
        super.init(frame: .zero)
        appearance = NSAppearance(named: .darkAqua)
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        addSubview(backdrop)
        // In the glass: the glass view clips and composites its content view.
        let content = backdrop.content
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay   // nothing on screen until the content scrolls
        scrollView.horizontalScrollElasticity = .none
        // The outline's rows already end in the row spacing, so the bottom inset leaves it out.
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: Self.inset.top, left: 0,
                                                bottom: Self.inset.bottom - Self.spacing.height, right: 0)
        // The glass's rounded corners clip the scrolled content.
        scrollView.wantsLayer = true
        scrollView.layer?.cornerRadius = Self.cornerRadius
        scrollView.layer?.masksToBounds = true
        scrollView.wheel = { [weak self] event in self?.wheel?(event) ?? false }
        scrollView.onTile = { [weak self] in
            guard let self, expansionPending else { return }
            syncExpansion()
        }
        content.addSubview(scrollView)
        configureOutline()
        scrollView.documentView = outline
        NSLayoutConstraint.activate([
            backdrop.leadingAnchor.constraint(equalTo: leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: trailingAnchor),
            backdrop.topAnchor.constraint(equalTo: topAnchor),
            backdrop.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: content.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        setColumnWidths()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    private func configureOutline() {
        labelColumn.resizingMask = []
        valueColumn.resizingMask = []
        outline.addTableColumn(labelColumn)
        outline.addTableColumn(valueColumn)
        outline.outlineTableColumn = labelColumn
        outline.headerView = nil
        outline.style = .plain
        outline.backgroundColor = .clear
        outline.selectionHighlightStyle = .none
        outline.intercellSpacing = Self.spacing
        outline.usesAutomaticRowHeights = true
        outline.columnAutoresizingStyle = .noColumnAutoresizing
        outline.indentationPerLevel = 0
        outline.allowsColumnReordering = false
        outline.allowsColumnResizing = false
        outline.allowsTypeSelect = false
        outline.focusRingType = .none
        outline.autoresizesOutlineColumn = false
        outline.dataSource = source
        outline.delegate = source
        outline.target = self
        outline.doubleAction = #selector(outlineDoubleClicked)
        outline.onPressWhileEditing = { [weak self] in self?.endSelection() }
        outline.registerForDraggedTypes([Self.sectionType])
        outline.setDraggingSourceOperationMask(.move, forLocal: true)
        outline.draggingDestinationFeedbackStyle = .gap
    }

    // MARK: Content

    /// The height the content wants (the panel's height when there is room for it): the rows the outline shows,
    /// measured from their views at the current width. Measured once per change of what it shows, since the owner
    /// asks on every layout pass; independent of what is on screen, so it holds while the panel is still too small.
    public var contentHeight: CGFloat {
        if let measuredHeight { return measuredHeight }
        var height = Self.inset.top + Self.inset.bottom - Self.spacing.height
        for item in items {
            height += item.header.fittingSize.height + Self.spacing.height
            if !collapsed.contains(item.id) {
                for row in item.rows { height += row.height + Self.spacing.height }
            }
        }
        measuredHeight = height
        return height
    }
    private var measuredHeight: CGFloat?

    /// The panel's width, which the values wrap to: a change moves the value column's wrap in place (no rebuild, so a
    /// selection stays) and measures the height again.
    public var contentWidth: CGFloat = PanelSize.standard.width {
        didSet {
            guard contentWidth != oldValue else { return }
            setColumnWidths()
            let width = valueTextWidth
            for row in items.flatMap(\.rows) { row.valueField.preferredMaxLayoutWidth = width }
            measuredHeight = nil
            let rows = outline.numberOfRows
            if rows > 0 { outline.noteHeightOfRows(withIndexesChanged: IndexSet(0..<rows)) }
        }
    }

    /// The label column: the side padding and the widest label (one column for every section, so the values line up
    /// down the whole panel); the value column takes the rest of the width.
    private var labelColumnWidth: CGFloat { Self.sidePadding + labelWidth }
    private var valueColumnWidth: CGFloat {
        max(40 + Self.sidePadding, contentWidth - labelColumnWidth - 2 * Self.spacing.width)
    }
    private var valueTextWidth: CGFloat { valueColumnWidth - Self.sidePadding }

    private func setColumnWidths() {
        labelColumn.width = labelColumnWidth
        valueColumn.width = valueColumnWidth
    }

    private var valueFont: NSFont { .monospacedDigitSystemFont(ofSize: fontSize, weight: .regular) }
    private var labelFont: NSFont { .systemFont(ofSize: fontSize) }
    private var titleFont: NSFont { .systemFont(ofSize: fontSize - 2, weight: .semibold) }

    /// Shows `sections` (those with rows), `collapsed` naming the sections that show only their header. The same
    /// sections, titles and labels as now only set the values that changed (the stats timer refreshes twice a second);
    /// anything else rebuilds the rows.
    public func show(_ sections: [InfoSection], collapsed: Set<String>) {
        let sections = sections.filter { !$0.rows.isEmpty }
        guard Self.sameShape(sections, shown) else {
            self.collapsed = collapsed
            rebuild(sections)
            return
        }
        var changedHeights = IndexSet()
        for (item, section) in zip(items, sections) {
            for (row, new) in zip(item.rows, section.rows) where row.valueField.stringValue != new.value {
                let height = row.height
                row.set(new.value)
                if row.height != height {
                    let index = outline.row(forItem: row)
                    if index >= 0 { changedHeights.insert(index) }
                    measuredHeight = nil
                }
            }
        }
        if !changedHeights.isEmpty { outline.noteHeightOfRows(withIndexesChanged: changedHeights) }
        shown = sections
        apply(collapsed)
    }

    /// Expands and collapses the sections to match `collapsed`, without animation (the owner restoring them).
    private func apply(_ collapsed: Set<String>) {
        guard collapsed != self.collapsed else { return }
        self.collapsed = collapsed
        measuredHeight = nil
        for item in items { item.header.isExpanded = !collapsed.contains(item.id) }
        syncExpansion()
    }

    /// Expands the sections that are not collapsed and collapses the others. AppKit measures rows (automatic heights)
    /// lazily, and expanding a section while rows below the visible area are still unmeasured makes its row height
    /// cache re-enter itself, which it logs as a reentrant operation that is to become an assert. So the sections are
    /// expanded last to first (each one's rows are measured while they are in view, before the sections above push
    /// them down), and with no visible area at all (a panel not placed yet) this waits for the scroll view to tile
    /// with one (`PanelScrollView.onTile`). `contentHeight` does not depend on it.
    private func syncExpansion() {
        guard !scrollView.contentView.bounds.isEmpty else {
            expansionPending = true
            return
        }
        expansionPending = false
        for item in items.reversed() {
            let expanded = !collapsed.contains(item.id)
            guard outline.isItemExpanded(item) != expanded else { continue }
            if expanded { outline.expandItem(item) } else { outline.collapseItem(item) }
        }
    }
    private var expansionPending = false

    private static func sameShape(_ a: [InfoSection], _ b: [InfoSection]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { x, y in
            x.id == y.id && x.title == y.title && x.rows.map(\.label) == y.rows.map(\.label)
        }
    }

    private func rebuild(_ sections: [InfoSection]) {
        shown = sections
        measuredHeight = nil
        let labelFont = labelFont
        labelWidth = ceil(sections.flatMap(\.rows).map {
            ($0.label as NSString).size(withAttributes: [.font: labelFont]).width
        }.max() ?? 0) + 4
        setColumnWidths()
        let valueWidth = valueTextWidth
        items = sections.enumerated().map { index, section in
            let header = SectionHeaderView(title: section.title, font: titleFont,
                                           leading: Self.sidePadding, trailing: Self.inset.right,
                                           gap: index == 0 ? 0 : Self.sectionGap,
                                           expanded: !collapsed.contains(section.id))
            let rows = section.rows.map { row in
                let item = RowItem(row, labelFont: labelFont, valueFont: valueFont, labelColour: Self.labelColour,
                                   valueColour: Self.valueColour, padding: Self.sidePadding, valueWidth: valueWidth,
                                   middleTruncated: middleTruncated.contains(row.label))
                item.valueField.onPress = { [weak self] in self?.valuePressed() }
                return item
            }
            let item = SectionItem(id: section.id, header: header, rows: rows)
            header.onToggle = { [weak self, weak item] expanded in
                guard let self, let item else { return }
                self.toggle(item, expanded: expanded)
            }
            return item
        }
        outline.reloadData()
        syncExpansion()
    }

    private func toggle(_ item: SectionItem, expanded: Bool) {
        if expanded {
            collapsed.remove(item.id)
            outline.animator().expandItem(item)
        } else {
            collapsed.insert(item.id)
            outline.animator().collapseItem(item)
        }
        measuredHeight = nil
        onCollapse?(item.id, !expanded)
    }

    // MARK: Selecting a value

    /// Who had the keys before a press on a value made the field editor the first responder (a press on another value
    /// while one is selected keeps it): they get them back when a press on a header ends the selection.
    private weak var keysBeforeSelection: NSResponder?

    private func valuePressed() {
        guard let responder = window?.firstResponder else { return }
        if let view = responder as? NSView, view.isDescendant(of: self) { return }
        keysBeforeSelection = responder
    }

    /// A press on a header while a value's text is selected (the field editor, inside the outline, is the first
    /// responder): the outline takes a press only when the first responder lets go, and it never becomes one itself,
    /// so without this the press is lost (the first click of a double click, or the start of a drag). The keys go
    /// back to whoever had them before the value was selected (the window, if no one). The controller ends a selection
    /// so too when it hides the panel, and when new content took the selected value's field away.
    func endSelection() {
        guard let window else { return }
        if let back = keysBeforeSelection, window.makeFirstResponder(back) { return }
        window.makeFirstResponder(nil)
    }

    @objc private func outlineDoubleClicked() {
        if outline.item(atRow: outline.clickedRow) is SectionItem { onTitleDoubleClick?() }
    }

    // MARK: Mouse: everything over the panel is the panel's

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.cursorUpdate, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
                                       owner: self))
    }

    /// The arrow, not the cursor of what is under the panel (the selectable values keep their I-beam); a resize cursor
    /// on an edge.
    public override func cursorUpdate(with event: NSEvent) { setCursor(at: event) }

    /// Along the edges the cursor changes without leaving the panel's tracking area.
    public override func mouseMoved(with event: NSEvent) {
        guard dragPoint == nil else { return }
        setCursor(at: event)
    }

    private func setCursor(at event: NSEvent) {
        let edges = edges(at: event)
        guard !edges.isEmpty else { NSCursor.arrow.set(); return }
        let position: NSCursor.FrameResizePosition = switch (edges.contains(.top), edges.contains(.bottom),
                                                              edges.contains(.left)) {
        case (true, _, true): .topLeft
        case (true, _, false): edges.contains(.right) ? .topRight : .top
        case (_, true, true): .bottomLeft
        case (_, true, false): edges.contains(.right) ? .bottomRight : .bottom
        case (_, _, true): .left
        default: .right
        }
        NSCursor.frameResize(position: position, directions: .all).set()
    }

    /// The edges under the event's pointer (`PanelPlacement.edges`, which measures y down).
    private func edges(at event: NSEvent) -> PanelEdges {
        edges(at: convert(event.locationInWindow, from: nil))
    }

    private func edges(at p: NSPoint) -> PanelEdges {
        PanelPlacement.edges(at: CGPoint(x: p.x, y: bounds.height - p.y), size: bounds.size)
    }

    /// Near an edge the panel itself is hit (to resize, over the scroller and the values too). Elsewhere a value's
    /// text (to select it), the scroller, the field editor of a value being selected and a header's triangle keep
    /// their events, a header's chevron too (also past the header's frame); the rest of a header row is the outline's (to drag the section); anywhere else the panel itself
    /// is hit, so a press there drags it and a scroll goes to the scroll view from here.
    public override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        guard let superview else { return hit }
        if !edges(at: convert(point, from: superview)).isEmpty { return self }
        // A header's chevron sits at the row's end, past the header's own frame (the label column), where hit-testing
        // the header would not look.
        for item in items where !item.header.button.isHidden && item.header.window != nil {
            let button = item.header.button
            if button.bounds.contains(button.convert(point, from: superview)) { return button }
        }
        var view: NSView? = hit
        while let v = view, v !== self {
            if (v as? NSTextField)?.isSelectable == true || v is NSScroller || v is NSTextView { return hit }
            if v is NSButton, v.superview is SectionHeaderView { return hit }
            view = v.superview
        }
        if hit === outline || hit.isDescendant(of: outline),
           outline.item(atRow: outline.row(at: outline.convert(point, from: superview))) is SectionItem {
            return outline
        }
        return self
    }

    public override func mouseDown(with event: NSEvent) {
        dragPoint = event.locationInWindow
        dragMoved = false
        resizeEdges = edges(at: event)
    }

    public override func mouseDragged(with event: NSEvent) {
        guard let last = dragPoint else { return }
        let p = event.locationInWindow
        guard p != last else { return }
        dragPoint = p
        dragMoved = true
        if resizeEdges.isEmpty { onDrag?(p.x - last.x, p.y - last.y) } else { onResize?(resizeEdges, p.x - last.x, p.y - last.y) }
    }

    public override func mouseUp(with event: NSEvent) {
        guard dragPoint != nil else { return }
        dragPoint = nil
        if dragMoved { if resizeEdges.isEmpty { onDragEnd?() } else { onResizeEnd?() } }
        resizeEdges = []
        setCursor(at: event)
    }

    public override func scrollWheel(with event: NSEvent) {
        guard !forwardingScroll else { return }
        forwardingScroll = true
        scrollView.scrollWheel(with: event)
        forwardingScroll = false
    }

    public override func menu(for event: NSEvent) -> NSMenu? { onContextMenu?() }

    // What the fields, the outline and the scroll view leave reaches here through the responder chain and stops: what
    // is under the panel is a sibling, never a next responder, so it would not get these anyway; ending them here also
    // keeps them from the window. A right press shows the panel's menu, if there is one.
    public override func rightMouseDown(with event: NSEvent) {
        if let menu = menu(for: event) { NSMenu.popUpContextMenu(menu, with: event, for: self) }
    }
    public override func rightMouseDragged(with event: NSEvent) {}
    public override func rightMouseUp(with event: NSEvent) {}
    // The middle, back and forward buttons are the app's bindings over the panel too.
    public override func otherMouseDown(with event: NSEvent) { otherMouse?(event) }
    public override func otherMouseDragged(with event: NSEvent) { otherMouse?(event) }
    public override func otherMouseUp(with event: NSEvent) { otherMouse?(event) }
    public override func magnify(with event: NSEvent) {}
    public override func smartMagnify(with event: NSEvent) {}
    public override func rotate(with event: NSEvent) {}
    public override func swipe(with event: NSEvent) {}
    public override var acceptsFirstResponder: Bool { false }
}

/// The outline's data source and delegate: the panel's sections as top-level items, their rows as children, and the
/// reorder by dragging a header. Apart from the panel, so its outline methods are not the panel's public API.
@MainActor final class PanelOutlineSource: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
    unowned let panel: InfoPanelView

    init(panel: InfoPanelView) {
        self.panel = panel
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let item else { return panel.items.count }
        return (item as? SectionItem)?.rows.count ?? 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        guard let section = item as? SectionItem else { return panel.items[index] }
        return section.rows[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool { item is SectionItem }

    /// True, though the outline's own triangle is never seen (`PanelOutlineView.frameOfOutlineCell`): an outline does
    /// not collapse an item whose outline cell it does not show, not even when asked to.
    func outlineView(_ outlineView: NSOutlineView, shouldShowOutlineCellForItem item: Any) -> Bool { true }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        let label = tableColumn === panel.labelColumn
        if let section = item as? SectionItem { return label ? section.header : section.spacer }
        guard let row = item as? RowItem else { return nil }
        return label ? row.label : row.value
    }

    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        let rowView = NSTableRowView()
        rowView.isGroupRowStyle = false
        return rowView
    }

    // Reorder: only headers are dragged, and they drop only between sections.

    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> (any NSPasteboardWriting)? {
        guard let section = item as? SectionItem else { return nil }
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(section.id, forType: InfoPanelView.sectionType)
        return pasteboardItem
    }

    /// A drop between sections is taken as it is. One on a header goes before its section; one among a section's rows
    /// goes before that section in its upper half and after it in its lower half (the outline proposes the end of a
    /// section's rows for the gap above the next header).
    func outlineView(_ outlineView: NSOutlineView, validateDrop info: any NSDraggingInfo, proposedItem item: Any?,
                     proposedChildIndex index: Int) -> NSDragOperation {
        guard (info.draggingSource as AnyObject?) === panel.outline, draggedId(info) != nil else { return [] }
        if let section = item as? SectionItem, let position = panel.items.firstIndex(where: { $0 === section }) {
            let after = index != NSOutlineViewDropOnItemIndex && index * 2 > section.rows.count
            outlineView.setDropItem(nil, dropChildIndex: after ? position + 1 : position)
        } else if item != nil {
            return []
        } else if index == NSOutlineViewDropOnItemIndex {
            outlineView.setDropItem(nil, dropChildIndex: panel.items.count)
        }
        return .move
    }

    func outlineView(_ outlineView: NSOutlineView, acceptDrop info: any NSDraggingInfo, item: Any?,
                     childIndex index: Int) -> Bool {
        guard item == nil, let id = draggedId(info) else { return false }
        let items = panel.items
        panel.onReorder?(id, items.indices.contains(index) ? items[index].id : nil)
        return true
    }

    private func draggedId(_ info: any NSDraggingInfo) -> String? {
        info.draggingPasteboard.string(forType: InfoPanelView.sectionType)
    }
}

/// A section: the outline's top-level item. Kept, with its header, while only values change, so the outline keeps the
/// row and its views.
@MainActor final class SectionItem {
    let id: String
    let header: SectionHeaderView
    /// The header row's value cell: the header spans the row, so this one has nothing to show.
    let spacer = NSView()
    let rows: [RowItem]

    init(id: String, header: SectionHeaderView, rows: [RowItem]) {
        self.id = id
        self.header = header
        self.rows = rows
    }
}

/// A row of a section, owning its label and value cells: a new value is set on the field the outline shows (or will
/// show, once the section is expanded or scrolled to).
@MainActor final class RowItem {
    let label: NSTableCellView
    let value: NSTableCellView
    let valueField: PanelValueField
    private let middleTruncated: Bool

    init(_ row: InfoRow, labelFont: NSFont, valueFont: NSFont, labelColour: NSColor, valueColour: NSColor,
         padding: CGFloat, valueWidth: CGFloat, middleTruncated: Bool) {
        self.middleTruncated = middleTruncated
        let labelField = NSTextField(labelWithString: row.label)
        labelField.font = labelFont
        labelField.textColor = labelColour
        labelField.alignment = .right   // set against its value
        label = Self.cell(labelField, leading: padding, trailing: 0, alignedRight: true)
        valueField = PanelValueField(wrappingLabelWithString: "")
        valueField.font = valueFont
        valueField.textColor = valueColour
        valueField.isSelectable = true
        valueField.preferredMaxLayoutWidth = valueWidth
        valueField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        if middleTruncated {
            valueField.cell?.wraps = false
            valueField.cell?.isScrollable = false
            valueField.lineBreakMode = .byTruncatingMiddle
            valueField.maximumNumberOfLines = 1
        }
        value = Self.cell(valueField, leading: 0, trailing: padding)
        set(row.value)
    }

    /// The row's height in the outline: its taller field at the current wrap width.
    var height: CGFloat {
        max(label.textField?.intrinsicContentSize.height ?? 0, valueField.intrinsicContentSize.height)
    }

    func set(_ text: String) {
        valueField.stringValue = text
        // A cut value is still all there on hover.
        if middleTruncated { valueField.toolTip = text }
    }

    /// `field` at the top leading corner of a cell, as wide as its text (up to the cell less `trailing`), so a press
    /// beside a short value moves the panel rather than selecting.
    /// `alignedRight`: the field ends at the cell's end less `trailing` instead (a label set against its value).
    private static func cell(_ field: NSTextField, leading: CGFloat, trailing: CGFloat,
                             alignedRight: Bool = false) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.textField = field
        field.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(field)
        NSLayoutConstraint.activate([
            alignedRight
                ? field.leadingAnchor.constraint(greaterThanOrEqualTo: cell.leadingAnchor, constant: leading)
                : field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: leading),
            alignedRight
                ? field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -trailing)
                : field.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -trailing),
            field.topAnchor.constraint(equalTo: cell.topAnchor),
            field.bottomAnchor.constraint(lessThanOrEqualTo: cell.bottomAnchor),
        ])
        return cell
    }
}

/// The panel's outline. Never the first responder, so the app's keys stay the app's after a press on a header. Its
/// own disclosure triangle has no room (each header has its own button), so nothing is indented for it either.
final class PanelOutlineView: NSOutlineView {
    /// A press reached the outline while a text view inside it (a value's field editor) is the first responder.
    var onPressWhileEditing: (() -> Void)?

    override var acceptsFirstResponder: Bool { false }

    override func mouseDown(with event: NSEvent) {
        if let editor = window?.firstResponder as? NSTextView, editor.isDescendant(of: self) { onPressWhileEditing?() }
        super.mouseDown(with: event)
    }

    override func frameOfOutlineCell(atRow row: Int) -> NSRect { .zero }
}

/// A value's field: reports a press on it (`onPress`), before the press may make the field editor the first responder.
final class PanelValueField: NSTextField {
    var onPress: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onPress?()
        super.mouseDown(with: event)
    }
}

/// The panel's scroll view. Every wheel event over the panel comes here once (straight from a value field or the
/// outline through the responder chain, or handed on by the panel), so this is where the app takes the wheel first
/// (`wheel`): nothing scrolls then. An event that comes round again (passed up from a value field, handed back by the
/// panel) is asked about once.
private final class PanelScrollView: NSScrollView {
    var wheel: ((NSEvent) -> Bool)?
    /// The scroll view laid out its clip view and scrollers.
    var onTile: (() -> Void)?
    private weak var askedEvent: NSEvent?

    override func scrollWheel(with event: NSEvent) {
        if event !== askedEvent {
            askedEvent = event
            if wheel?(event) == true { return }
        }
        super.scrollWheel(with: event)
    }

    override func tile() {
        super.tile()
        onTile?()
    }
}
