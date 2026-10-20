import AppKit
import Testing
@testable import InfoPanelKit

extension PanelTests {
    /// One test at a time: the presses run nested run loops (`Clicks.click`), in which another test's main-actor work
    /// would otherwise run too.
    @MainActor @Suite(.serialized) struct InfoPanelViewTests {
        private func panel() -> InfoPanelView {
            let view = InfoPanelView()
            view.frame = NSRect(x: 0, y: 0, width: 380, height: 600)
            view.contentWidth = 380
            view.layoutSubtreeIfNeeded()
            return view
        }

        private func sections(video codec: String = "h264") -> [InfoSection] {
            [
                InfoSection(title: "File", rows: [InfoRow(label: "Name", value: "a.mp4"),
                                                  InfoRow(label: "Size", value: "12 MB")]),
                InfoSection(title: "Video", rows: [InfoRow(label: "Codec", value: codec),
                                                   InfoRow(label: "Resolution", value: "1920 × 1080")]),
            ]
        }

        /// The value field of the row at `row` (column 1), made if it is not on screen.
        private func valueField(_ view: InfoPanelView, row: Int) -> NSTextField? {
            (view.outline.view(atColumn: 1, row: row, makeIfNecessary: true) as? NSTableCellView)?.textField
        }

        /// Style B: white values, quieter labels set against them, headers in small spaced capitals.
        @Test func styleB() throws {
            let view = panel()
            view.show(sections(), collapsed: [])
            let value = try #require(valueField(view, row: 1))
            #expect(value.textColor == NSColor(white: 1, alpha: InfoPanelStyle.valueAlpha))
            let label = try #require((view.outline.view(atColumn: 0, row: 1, makeIfNecessary: true) as? NSTableCellView)?.textField)
            #expect(label.textColor == NSColor(white: 1, alpha: 0.55))
            #expect(label.alignment == .right)
            let header = try #require(view.outline.view(atColumn: 0, row: 0, makeIfNecessary: true) as? SectionHeaderView)
            #expect(header.title.stringValue == "FILE")
            #expect(header.title.font?.pointSize == view.fontSize - 2)
            let kern = header.title.attributedStringValue.attribute(.kern, at: 0, effectiveRange: nil) as? CGFloat
            #expect(kern == 0.08 * (view.fontSize - 2))
            #expect(header.title.textColor == NSColor(white: 1, alpha: 0.5))
            #expect(InfoPanelStyle.tint == 0.46 && InfoPanelStyle.sectionGap == 11)
        }

        @Test func chevronShowsOnHoverAndWhenCollapsed() throws {
            let view = panel()
            view.show(sections(), collapsed: ["Video"])
            let file = try #require(view.outline.view(atColumn: 0, row: 0, makeIfNecessary: true) as? SectionHeaderView)
            #expect(!file.chevronVisible && file.button.isHidden)
            file.isHovered = true
            #expect(file.chevronVisible && !file.button.isHidden)
            #expect(file.title.textColor == NSColor(white: 1, alpha: 0.8))
            #expect(file.button.title == "⌄")
            file.isHovered = false
            let video = try #require(view.outline.view(atColumn: 0, row: 3, makeIfNecessary: true) as? SectionHeaderView)
            #expect(video.chevronVisible && !video.button.isHidden)
            #expect(video.button.title == "›")
        }

        @Test func showsHeadersAndRows() {
            let view = panel()
            view.show(sections(), collapsed: [])
            #expect(view.outline.numberOfRows == 6)
        }

        @Test func collapsedSectionShowsOnlyItsHeader() {
            let view = panel()
            view.show(sections(), collapsed: ["File"])
            #expect(view.outline.numberOfRows == 4)
        }

        @Test func sameShapeUpdateKeepsTheFields() throws {
            let view = panel()
            view.show(sections(), collapsed: [])
            // Row 4 is Video's first row (File header, 2 rows, Video header, Codec).
            let field = try #require(valueField(view, row: 4))
            #expect(field.stringValue == "h264")
            view.show(sections(video: "hevc"), collapsed: [])
            #expect(view.outline.numberOfRows == 6)
            let after = try #require(valueField(view, row: 4))
            #expect(after === field)
            #expect(after.stringValue == "hevc")
            // An unchanged value keeps its field too.
            #expect(valueField(view, row: 1)?.stringValue == "a.mp4")
        }

        @Test func newShapeRebuilds() {
            let view = panel()
            view.show(sections(), collapsed: [])
            let more = sections() + [InfoSection(title: "Audio", rows: [InfoRow(label: "Codec", value: "aac")])]
            view.show(more, collapsed: [])
            #expect(view.outline.numberOfRows == 8)
            let header = view.outline.view(atColumn: 0, row: 6, makeIfNecessary: true) as? SectionHeaderView
            #expect(header?.title.stringValue == "AUDIO")
        }

        @Test func contentHeightGrowsWithAWrappingValue() {
            let view = panel()
            view.show(sections(), collapsed: [])
            let oneLine = view.contentHeight
            let long = String(repeating: "word ", count: 400)
            view.show(sections(video: long), collapsed: [])
            #expect(view.contentHeight > oneLine + 100)
        }

        @Test func headerToggleReportsCollapse() throws {
            let view = panel()
            view.show(sections(), collapsed: [])
            var reported: [(String, Bool)] = []
            view.onCollapse = { reported.append(($0, $1)) }
            let header = try #require(view.outline.view(atColumn: 0, row: 0, makeIfNecessary: true)
                                          as? SectionHeaderView)
            header.button.performClick(nil)
            #expect(reported.count == 1)
            #expect(reported.first?.0 == "File")
            #expect(reported.first?.1 == true)
            #expect(view.outline.numberOfRows == 4)
            header.button.performClick(nil)
            #expect(reported.last?.1 == false)
            #expect(view.outline.numberOfRows == 6)
        }

        @Test func sameShapeWithOtherCollapsedSectionsCollapsesInPlace() throws {
            let view = panel()
            view.show(sections(), collapsed: [])
            let field = try #require(valueField(view, row: 4))
            let open = view.contentHeight
            view.show(sections(), collapsed: ["File", "Video"])
            #expect(view.outline.numberOfRows == 2)
            #expect(view.contentHeight < open)
            view.show(sections(), collapsed: ["File"])
            #expect(view.outline.numberOfRows == 4)
            #expect(valueField(view, row: 2) === field)
        }

        /// The panel in a window, laid out, so the outline has measured its rows.
        private func laidOut(_ sections: [InfoSection], collapsed: Set<String> = []) -> (NSWindow, InfoPanelView) {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 600), styleMask: [.borderless],
                                  backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let view = panel()
            window.contentView?.addSubview(view)
            view.show(sections, collapsed: collapsed)
            window.contentView?.layoutSubtreeIfNeeded()
            window.display()
            return (window, view)
        }

        @Test func contentHeightIsWhatTheOutlineLaysOut() {
            var more = sections(video: String(repeating: "word ", count: 60))
            more.append(InfoSection(title: "Lines", rows: [InfoRow(label: "Three", value: "1\n2\n3")]))
            let (_, view) = laidOut(more)
            let outline = view.outline
            // Top inset 12, the rows (each ending in the 3 pt row spacing), bottom inset 12 less that spacing.
            #expect(view.contentHeight == 12 + outline.rect(ofRow: outline.numberOfRows - 1).maxY + 9)
            // The wrapped value and the three lines take their height (one line is under 20 pt).
            #expect(outline.rect(ofRow: 4).height > 60)
            #expect(outline.rect(ofRow: 7).height > 40)
        }

        @Test func valueTakingMoreLinesInPlaceGrowsItsRow() {
            let (window, view) = laidOut(sections())
            let before = view.contentHeight
            view.show(sections(video: String(repeating: "word ", count: 60)), collapsed: [])
            window.contentView?.layoutSubtreeIfNeeded()
            window.display()
            let outline = view.outline
            #expect(outline.rect(ofRow: 4).height > 60)
            #expect(view.contentHeight > before + 40)
            #expect(view.contentHeight == 12 + outline.rect(ofRow: outline.numberOfRows - 1).maxY + 9)
        }

        @Test func sectionsShownBeforeThePanelHasASizeExpandOnceItIsLaidOut() {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 600), styleMask: [.borderless],
                                  backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let view = InfoPanelView()
            window.contentView?.addSubview(view)
            view.show(sections(), collapsed: ["Video"])
            // Only the headers until the outline has room (expanding before makes AppKit's row height cache re-enter);
            // the content's height is known already.
            #expect(view.outline.numberOfRows == 2)
            let height = view.contentHeight
            view.frame = NSRect(x: 0, y: 0, width: 380, height: 600)
            window.contentView?.layoutSubtreeIfNeeded()
            #expect(view.outline.numberOfRows == 4)
            #expect(view.contentHeight == height)
        }

        /// Sections whose rows run past the visible area (AppKit measures those rows only when it needs the total
        /// height): expanding them must not make AppKit's row height cache re-enter itself, which it logs.
        @Test func expandingSectionsPastTheVisibleAreaDoesNotReenterTheOutline() {
            let long = String(repeating: "word ", count: 600)
            let tall = (0..<4).map { s in
                InfoSection(title: "S\(s)",
                            rows: (0..<30).map { InfoRow(label: "L\($0)", value: $0 == 0 && s == 0 ? long : "v") })
            }
            let log = standardError {
                let (window, view) = laidOut(tall)
                view.show(tall, collapsed: Set(tall.map(\.id)))
                view.show(tall, collapsed: [])
                window.contentView?.layoutSubtreeIfNeeded()
                window.display()
                #expect(view.outline.numberOfRows == 124)
                view.contentWidth = 300
                window.contentView?.layoutSubtreeIfNeeded()
                window.display()
            }
            #expect(!log.contains("reentrant"))
        }

        /// What `body` wrote to the standard error (AppKit's warnings go there).
        private func standardError(_ body: () -> Void) -> String {
            let pipe = Pipe()
            let saved = dup(STDERR_FILENO)
            dup2(pipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO)
            body()
            fflush(stderr)
            dup2(saved, STDERR_FILENO)
            close(saved)
            pipe.fileHandleForWriting.closeFile()
            return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        }

        @Test func pressesGoWhereTheirGestureBelongs() throws {
            let (window, view) = laidOut(sections())
            let outline = view.outline
            let host = try #require(window.contentView)
            /// The host point at `p` in `from`'s coordinates.
            func at(_ p: NSPoint, in from: NSView) -> NSPoint { host.convert(p, from: from) }
            func centre(_ v: NSView) -> NSPoint { at(NSPoint(x: v.bounds.midX, y: v.bounds.midY), in: v) }
            let header = try #require(outline.view(atColumn: 0, row: 0, makeIfNecessary: false) as? SectionHeaderView)
            let labelCell = outline.view(atColumn: 0, row: 1, makeIfNecessary: false) as? NSTableCellView
            let label = try #require(labelCell?.textField)
            let value = try #require(valueField(view, row: 1))
            // A header's row drags its section, its triangle collapses it.
            #expect(view.hitTest(centre(header.title)) === outline)
            #expect(view.hitTest(at(NSPoint(x: 300, y: outline.rect(ofRow: 0).midY), in: outline)) === outline)
            // The chevron, hidden until the pointer is over the header: the row's (drag) till then.
            #expect(view.hitTest(centre(header.button)) === outline)
            header.isHovered = true
            #expect(view.hitTest(centre(header.button)) === header.button)
            header.isHovered = false
            // A value's text selects; a label and the room beside a short value move the panel.
            #expect(view.hitTest(centre(value)) === value)
            #expect(view.hitTest(centre(label)) === view)
            #expect(view.hitTest(at(NSPoint(x: 360, y: outline.rect(ofRow: 1).midY), in: outline)) === view)
            // Near an edge the panel resizes, over a header and a value too.
            #expect(view.hitTest(at(NSPoint(x: 2, y: outline.rect(ofRow: 0).midY), in: outline)) === view)
            #expect(view.hitTest(at(NSPoint(x: 377, y: outline.rect(ofRow: 1).midY), in: outline)) === view)
        }

        @Test func theWheelIsOfferedToTheAppFirst() throws {
            let (_, view) = laidOut(sections(video: String(repeating: "word ", count: 2_000)))
            func scroll() throws -> NSEvent {
                let cg = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: -5,
                                              wheel2: 0, wheel3: 0))
                return try #require(NSEvent(cgEvent: cg))
            }
            var offered = 0
            view.wheel = { _ in offered += 1; return true }
            view.scrollWheel(with: try scroll())
            #expect(offered == 1)
            view.wheel = { _ in offered += 1; return false }
            view.scrollWheel(with: try scroll())
            // Each event is offered once (one the scroll view passes back up is not offered again).
            #expect(offered == 2)
        }

        @Test func otherButtonsAndTheMenuAreTheOwners() throws {
            let view = panel()
            var events: [NSEvent.EventType] = []
            view.otherMouse = { events.append($0.type) }
            for type in [NSEvent.EventType.otherMouseDown, .otherMouseDragged, .otherMouseUp] {
                let event = try #require(NSEvent.mouseEvent(with: type, location: .zero, modifierFlags: [],
                                                            timestamp: 0, windowNumber: 0, context: nil,
                                                            eventNumber: 0, clickCount: 1, pressure: 0))
                switch type {
                case .otherMouseDown: view.otherMouseDown(with: event)
                case .otherMouseDragged: view.otherMouseDragged(with: event)
                default: view.otherMouseUp(with: event)
                }
            }
            #expect(events == [.otherMouseDown, .otherMouseDragged, .otherMouseUp])
            let menu = NSMenu(title: "Panel")
            view.onContextMenu = { menu }
            let click = try #require(NSEvent.mouseEvent(with: .rightMouseDown, location: .zero, modifierFlags: [],
                                                        timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0,
                                                        clickCount: 1, pressure: 0))
            #expect(view.menu(for: click) === menu)
        }

        @Test func headerSpansTheRow() throws {
            let title = "A section title longer than any label"
            let (_, view) = laidOut([InfoSection(id: "File", title: title, rows: sections()[0].rows)] + [sections()[1]])
            let header = try #require(view.outline.view(atColumn: 0, row: 0, makeIfNecessary: false)
                                          as? SectionHeaderView)
            let row = try #require(header.superview)
            // The whole title shows, though the label column is narrower, and it stays inside the row.
            #expect(header.frame.width < 100)
            #expect(header.title.frame.width >= header.title.intrinsicContentSize.width)
            #expect(row.convert(header.title.frame, from: header).maxX <= row.bounds.maxX - 14)
            let label = try #require(view.outline.view(atColumn: 0, row: 1, makeIfNecessary: false))
            #expect(label.frame.width < 100)
        }

        @Test func dropBetweenSectionsReportsTheReorder() {
            let view = panel()
            view.show(sections() + [InfoSection(title: "Audio", rows: [InfoRow(label: "Codec", value: "aac")])],
                      collapsed: [])
            var reported: [(String, String?)] = []
            view.onReorder = { reported.append(($0, $1)) }
            let outline = view.outline
            for (id, index) in [("Audio", 0), ("File", 3)] {
                _ = view.source.outlineView(outline, acceptDrop: FakeDrag(id: id, source: outline), item: nil,
                                            childIndex: index)
            }
            #expect(reported.map(\.0) == ["Audio", "File"])
            #expect(reported.map(\.1) == ["File", nil])
        }

        /// A value being selected has the field editor; the first press on a header still reaches the outline, and the
        /// keys go back to whoever had them before (an app's view, or no one: the window). Before the other press
        /// tests: the press was lost on the process's first selection (the suite runs in order).
        @Test(arguments: [false, true]) func pressOnAHeaderWorksWhileAValueIsSelected(appHasTheKeys: Bool) throws {
            let clicks = try Clicks.make()
            defer { clicks.settle() }
            var doubles = 0
            clicks.view.onTitleDoubleClick = { doubles += 1 }
            let app = KeyView()
            clicks.window.contentView?.addSubview(app, positioned: .below, relativeTo: nil)
            if appHasTheKeys { clicks.window.makeFirstResponder(app) }
            let keys: NSResponder = appHasTheKeys ? app : clicks.window
            clicks.click(clicks.value, count: 1)
            #expect(clicks.window.firstResponder === clicks.editor)
            // The press selects the header's row (invisibly), as one that starts a drag would.
            clicks.click(clicks.headerTitle, count: 1)
            #expect(clicks.view.outline.selectedRow == 0)
            #expect(clicks.window.firstResponder === keys)
            clicks.click(clicks.value, count: 1)
            clicks.click(clicks.headerTitle, count: 2)
            #expect(doubles == 1)
            #expect(clicks.window.firstResponder === keys)
        }

        @Test func doubleClickOnAHeaderAsksForTheDefaultPlace() throws {
            let clicks = try Clicks.make()
            defer { clicks.settle() }
            var doubles = 0
            clicks.view.onTitleDoubleClick = { doubles += 1 }
            clicks.click(clicks.headerTitle, count: 2)
            #expect(doubles == 1)
        }

        @Test func onlyThePanelsOwnHeadersDrop() {
            let view = panel()
            view.show(sections(), collapsed: [])
            let outline = view.outline
            #expect(view.source.outlineView(outline, validateDrop: FakeDrag(id: "File", source: nil),
                                            proposedItem: nil, proposedChildIndex: 1) == [])
            #expect(view.source.outlineView(outline, validateDrop: FakeDrag(id: "File", source: outline),
                                            proposedItem: nil, proposedChildIndex: 1) == .move)
        }
    }
}

/// Stands in for the app's view under the panel, which has the keys.
private final class KeyView: NSView {
    override var acceptsFirstResponder: Bool { true }
}

/// A window that counts as key without being on screen, so presses sent to it act as on a key window.
private final class KeyWindow: NSWindow {
    override var isKeyWindow: Bool { true }
    override var canBecomeKey: Bool { true }
}

/// The panel in a key window with a `PanelFieldEditor`, and presses sent through the window as AppKit would: the
/// mouse up is queued first, so the press's tracking loop finds it.
@MainActor private final class Clicks: NSObject, NSWindowDelegate {
    let window = KeyWindow(contentRect: NSRect(x: -4000, y: -4000, width: 380, height: 600), styleMask: [.titled],
                           backing: .buffered, defer: false)
    let view = InfoPanelView()
    let editor = PanelFieldEditor()
    /// Window points: the middle of the first header's title and of the first value's text.
    private(set) var headerTitle = NSPoint.zero
    private(set) var value = NSPoint.zero
    private var time = ProcessInfo.processInfo.systemUptime

    override init() {
        super.init()
        Self.launch()
        window.isReleasedWhenClosed = false
        editor.isFieldEditor = true
        window.delegate = self
        view.frame = NSRect(x: 0, y: 0, width: 380, height: 600)
        window.contentView?.addSubview(view)
        view.show([InfoSection(title: "File", rows: [InfoRow(label: "Name", value: "a.mp4 some value")]),
                   InfoSection(title: "Video", rows: [InfoRow(label: "Codec", value: "h264")])], collapsed: [])
        window.orderFront(nil)
        window.contentView?.layoutSubtreeIfNeeded()
        window.display()
    }

    /// The test process as a launched app (no Dock icon), as the panel's apps are: a field editor ends a selection
    /// differently in an app that has not finished launching, which hid the lost press on a header.
    private static var launched = false
    private static func launch() {
        guard !launched else { return }
        launched = true
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApp.finishLaunching()
    }

    static func make() throws -> Clicks {
        let clicks = Clicks()
        let outline = clicks.view.outline
        let header = try #require(outline.view(atColumn: 0, row: 0, makeIfNecessary: false) as? SectionHeaderView)
        let field = try #require((outline.view(atColumn: 1, row: 1, makeIfNecessary: false) as? NSTableCellView)?
            .textField)
        clicks.headerTitle = header.title.convert(NSPoint(x: header.title.bounds.midX, y: header.title.bounds.midY),
                                                  to: nil)
        clicks.value = field.convert(NSPoint(x: field.bounds.midX, y: field.bounds.midY), to: nil)
        return clicks
    }

    func windowWillReturnFieldEditor(_ sender: NSWindow, to client: Any?) -> Any? { editor }

    /// `count` presses at `p`, a double click for 2. Each press's mouse up is posted to the app first, so the press's
    /// tracking loop finds it. Posting an event stops the run loop it runs in; that is a nested run here, not the main
    /// one the test process lives in (stopping that one ends the process).
    func click(_ p: NSPoint, count: Int) {
        time += 1
        for clicks in 1...count {
            var done = false
            CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue) {
                MainActor.assumeIsolated {
                    NSApp.postEvent(self.event(.leftMouseUp, p, clicks), atStart: false)
                    self.window.sendEvent(self.event(.leftMouseDown, p, clicks))
                    // Everything queued, as the event loop would (what the field editor leaves matters).
                    while let e = NSApp.nextEvent(matching: .any, until: Date(), inMode: .default, dequeue: true) {
                        self.window.sendEvent(e)
                    }
                    done = true
                }
            }
            while !done { CFRunLoopRunInMode(.defaultMode, 0.05, false) }
            // A stop that came while the nested run was already ending (AppKit posts during the press too) stays
            // pending for the next run; it is taken here, so it cannot end the main one.
            while CFRunLoopRunInMode(.defaultMode, 0, true) == .stopped {}
        }
    }

    /// Runs the run loop (nested) past the double-click interval, so what AppKit left to do after the presses (it
    /// posts events later, which stops the run loop) happens here and not in the main run once the test is over.
    func settle() {
        let end = Date().addingTimeInterval(NSEvent.doubleClickInterval + 0.3)
        while Date() < end { CFRunLoopRunInMode(.defaultMode, 0.05, false) }
        while CFRunLoopRunInMode(.defaultMode, 0, true) == .stopped {}
    }

    private func event(_ type: NSEvent.EventType, _ p: NSPoint, _ clicks: Int) -> NSEvent {
        time += 0.05
        return NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: time,
                                  windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: clicks,
                                  pressure: type == .leftMouseUp ? 0 : 1)!
    }
}

/// A drag of the section `id` from `source`, for the outline's drop methods.
@MainActor private final class FakeDrag: NSObject, @MainActor NSDraggingInfo {
    let draggingPasteboard: NSPasteboard
    let draggingSource: Any?

    init(id: String, source: Any?) {
        draggingPasteboard = NSPasteboard(name: NSPasteboard.Name("infopanel-tests-\(UUID())"))
        draggingPasteboard.clearContents()
        draggingPasteboard.setString(id, forType: InfoPanelView.sectionType)
        draggingSource = source
    }

    var draggingDestinationWindow: NSWindow? { nil }
    var draggingSourceOperationMask: NSDragOperation { .move }
    var draggingLocation: NSPoint { .zero }
    var draggedImageLocation: NSPoint { .zero }
    var draggedImage: NSImage? { nil }
    var draggingSequenceNumber: Int { 1 }
    var draggingFormation: NSDraggingFormation = .default
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions = [], for view: NSView?,
                                classes classArray: [AnyClass],
                                searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:],
                                using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
    func resetSpringLoading() {}
}
