import AppKit
import Testing
@testable import InfoPanelKit

extension PanelTests {
    /// A class, so each test's pasteboard is released when it ends (`deinit`). Its defaults are in memory: a
    /// defaults domain on disk, even one removed when the test ends, leaves an empty plist in ~/Library/Preferences.
    @MainActor @Suite(.serialized) final class InfoPanelControllerTests {
        nonisolated private static let pasteboardName = NSPasteboard.Name("infopanel-tests")
        private let defaults: UserDefaults = MemoryDefaults()
        private let host = NSView(frame: NSRect(x: 0, y: 0, width: 1000, height: 700))
        private let pasteboard = NSPasteboard(name: InfoPanelControllerTests.pasteboardName)
        private static let order = ["File", "Video", "Audio"]
        private static let place = PanelPlacement(corner: .topRight, dx: 12, dy: 12)

        deinit {
            NSPasteboard(name: Self.pasteboardName).releaseGlobally()
        }

        private func controller(shown: Bool = true, host other: NSView? = nil, prefix: String = "tPanel")
            -> InfoPanelController {
            let host = other ?? host
            let controller = InfoPanelController(host: host, below: nil, keyPrefix: prefix, defaultOrder: Self.order,
                                                 defaultPlacement: Self.place, defaults: defaults,
                                                 area: { CGRect(origin: .zero, size: host.bounds.size) },
                                                 pasteboard: pasteboard)
            controller.show(sections)
            if shown {
                controller.setVisible(true)
                controller.isAvailable = true
            }
            return controller
        }

        private var sections: [InfoSection] {
            [
                InfoSection(title: "File", rows: [InfoRow(label: "Name", value: "a.mp4")]),
                InfoSection(title: "Video", rows: [InfoRow(label: "Codec", value: "h264")]),
                InfoSection(title: "Audio", rows: [InfoRow(label: "Codec", value: "aac")]),
            ]
        }

        private func panel(_ controller: InfoPanelController) throws -> InfoPanelView {
            try #require(controller.panel)
        }

        // MARK: Windows (one prefix, one defaults)

        private func secondHost() -> NSView { NSView(frame: NSRect(x: 0, y: 0, width: 1000, height: 700)) }

        /// Another window's panel, available but not opened by hand.
        private func other(prefix: String = "tPanel") -> InfoPanelController {
            let b = controller(shown: false, host: secondHost(), prefix: prefix)
            b.isAvailable = true
            return b
        }

        @Test func toggleReachesEveryWindow() {
            let a = controller(shown: false)
            a.isAvailable = true
            let b = other()
            a.setVisible(true)
            #expect(b.isVisible && b.isShown)
            a.toggle()
            #expect(!b.isShown)
        }

        @Test func placeAndSizeReachEveryWindow() throws {
            defaults.set("380 200", forKey: "tPanelSize")
            let a = controller()
            let b = other()
            b.setVisible(true)
            let panel = try panel(a)
            panel.onDrag?(-590, -448)
            panel.onDragEnd?()
            #expect(defaults.string(forKey: "tPanelPlacement") == "bottom-left 18 40")
            #expect(b.panelFrame?.origin == NSPoint(x: 18, y: 40))
            a.resetPosition()
            #expect(a.panelFrame?.maxX == 988)
            #expect(b.panelFrame == a.panelFrame)
        }

        @Test func collapseReachesEveryWindow() throws {
            let a = controller()
            let b = other()
            b.setVisible(true)
            try panel(a).onCollapse?("Video", true)
            #expect(try panel(b).items.first { $0.id == "Video" }?.header.isExpanded == false)
        }

        @Test func otherPrefixIgnored() {
            let a = controller(shown: false)
            a.isAvailable = true
            let b = other(prefix: "otherPanel")
            a.setVisible(true)
            #expect(!b.isShown)
        }

        @Test func releasedControllerStopsListening() {
            let a = controller(shown: false)
            a.isAvailable = true
            weak var gone: InfoPanelController?
            do {
                let b = other()
                gone = b
            }
            #expect(gone == nil)
            a.setVisible(true)
            #expect(a.isShown)
        }

        @Test func emptySectionsHideWhenAsked() {
            let a = controller()
            a.hidesWhenEmpty = true
            #expect(a.isShown)
            a.show([])
            #expect(!a.isShown)
            a.show(sections)
            #expect(a.isShown)
            a.hidesWhenEmpty = false
            a.show([])
            #expect(a.isShown)
        }

        @Test func hiddenUntilVisibleAndAvailable() throws {
            let controller = controller(shown: false)
            var reported: [Bool] = []
            controller.onShownChange = { reported.append($0) }
            #expect(controller.panel == nil)   // made when first shown
            controller.setVisible(true)
            #expect(host.subviews.isEmpty)
            #expect(!controller.isShown)
            #expect(controller.panelFrame == nil)
            controller.isAvailable = true
            #expect(controller.isShown)
            let panel = try panel(controller)
            #expect(panel.superview === host)
            #expect(controller.panelFrame == panel.frame)
            #expect(panel.items.map(\.id) == ["File", "Video", "Audio"])
            controller.isAvailable = false
            #expect(host.subviews.isEmpty)
            #expect(controller.panelFrame == nil)
            controller.isAvailable = true
            controller.toggle()
            #expect(host.subviews.isEmpty)
            #expect(reported == [true, false, true, false])
        }

        @Test func visibilityIsStored() {
            let controller = controller(shown: false)
            #expect(!controller.isVisible)
            controller.toggle()
            #expect(defaults.bool(forKey: "tPanelVisible") == true)
            #expect(self.controller(shown: false).isVisible)
        }

        @Test func defaultPlaceIsTopRight() throws {
            let panel = try panel(controller())
            #expect(panel.frame.maxX == 988)
            #expect(panel.frame.maxY == 688)
            #expect(panel.frame.width == 380)
            #expect(abs(panel.frame.height - panel.contentHeight) <= 1)
        }

        @Test func storedPlacementIsUsed() throws {
            defaults.set("bottom-left 20 30", forKey: "tPanelPlacement")
            defaults.set("400 300", forKey: "tPanelSize")
            let panel = try panel(controller())
            #expect(panel.frame == NSRect(x: 20, y: 30, width: 400, height: 300))
        }

        @Test func placeFollowsTheArea() throws {
            let controller = controller()
            let panel = try panel(controller)
            host.frame.size = NSSize(width: 800, height: 500)
            controller.place()
            #expect(panel.frame.maxX == 788)
            #expect(panel.frame.maxY == 488)
        }

        @Test func dropStoresTheNearestCorner() throws {
            defaults.set("380 200", forKey: "tPanelSize")
            let controller = controller()
            let panel = try panel(controller)
            // From the top right to near the bottom left (window points, y up).
            panel.onDrag?(-500, -300)
            #expect(panel.frame.minX == 108)
            #expect(panel.frame.maxY == 388)
            panel.onDrag?(-90, -(388 - 200 - 40))
            panel.onDragEnd?()
            #expect(defaults.string(forKey: "tPanelPlacement") == "bottom-left 18 40")
            #expect(panel.frame.origin == NSPoint(x: 18, y: 40))
            // Dragged past the area's edge, the panel stays inside it; dragged back, it is under the pointer again,
            // held where it was grabbed (it does not move while the pointer comes back to the edge).
            panel.onDrag?(-100, -100)
            #expect(panel.frame.origin == .zero)
            panel.onDrag?(50, 50)
            #expect(panel.frame.origin == .zero)
            panel.onDrag?(50, 50)
            #expect(panel.frame.origin == NSPoint(x: 18, y: 40))
            panel.onDrag?(-100, -100)
            #expect(panel.frame.origin == .zero)
            panel.onDragEnd?()
            #expect(defaults.string(forKey: "tPanelPlacement") == "bottom-left 0 0")
        }

        @Test func resizeStoresTheSizeThenThePlace() throws {
            let controller = controller()
            let panel = try panel(controller)
            let height = panel.frame.height
            panel.onResize?(.left, -60, 0)
            panel.onResize?(.left, -40, 0)
            #expect(panel.frame.width == 480)
            #expect(panel.frame.maxX == 988)
            panel.onResizeEnd?()
            // Only the width was dragged: the height still follows the content.
            #expect(defaults.string(forKey: "tPanelSize") == "480")
            #expect(defaults.string(forKey: "tPanelPlacement") == "top-right 12 12")
            panel.onResize?([.bottom], 0, -200)
            panel.onResizeEnd?()
            #expect(defaults.string(forKey: "tPanelSize") == PanelSize(width: 480, height: Double(height) + 200).stored)
            #expect(panel.frame.height == height + 200)
        }

        @Test func resetPositionForgetsPlaceAndSize() throws {
            defaults.set("bottom-left 20 30", forKey: "tPanelPlacement")
            defaults.set("400 300", forKey: "tPanelSize")
            let controller = controller()
            let panel = try panel(controller)
            controller.resetPosition()
            #expect(defaults.string(forKey: "tPanelPlacement") == nil)
            #expect(defaults.string(forKey: "tPanelSize") == nil)
            #expect(panel.frame.maxX == 988)
            #expect(panel.frame.maxY == 688)
            #expect(panel.frame.width == 380)
        }

        @Test func doubleClickOnAHeaderResetsThePosition() throws {
            defaults.set("bottom-left 20 30", forKey: "tPanelPlacement")
            let controller = controller()
            let panel = try panel(controller)
            panel.onTitleDoubleClick?()
            #expect(defaults.string(forKey: "tPanelPlacement") == nil)
            #expect(panel.frame.maxX == 988)
        }

        @Test func reorderIsStoredAndApplied() throws {
            let controller = controller()
            let panel = try panel(controller)
            panel.onReorder?("Video", "File")
            let stored = try #require(SectionLayout(stored: defaults.string(forKey: "tPanelSections")))
            #expect(Array(stored.order.prefix(2)) == ["Video", "File"])
            #expect(panel.items.map(\.id) == ["Video", "File", "Audio"])
            controller.show(sections)
            #expect(panel.items.map(\.id) == ["Video", "File", "Audio"])
            // Another launch keeps it.
            let again = try self.panel(self.controller())
            #expect(again.items.map(\.id) == ["Video", "File", "Audio"])
        }

        @Test func collapseIsStoredAndApplied() throws {
            let controller = controller()
            let panel = try panel(controller)
            panel.onCollapse?("File", true)
            let stored = try #require(SectionLayout(stored: defaults.string(forKey: "tPanelSections")))
            #expect(stored.collapsed == ["File"])
            let again = try self.panel(self.controller())
            #expect(again.items.first { $0.id == "File" }?.header.isExpanded == false)
            #expect(again.items.first { $0.id == "Video" }?.header.isExpanded == true)
            // Nothing left to keep: the key goes.
            panel.onCollapse?("File", false)
            #expect(defaults.string(forKey: "tPanelSections") == nil)
        }

        @Test func resetSectionOrderKeepsCollapsed() throws {
            let controller = controller()
            let panel = try panel(controller)
            panel.onReorder?("Audio", "File")
            panel.onCollapse?("Video", true)
            controller.resetSectionOrder()
            let stored = try #require(SectionLayout(stored: defaults.string(forKey: "tPanelSections")))
            #expect(stored.order == [])
            #expect(stored.collapsed == ["Video"])
            #expect(panel.items.map(\.id) == ["File", "Video", "Audio"])
            #expect(panel.items.first { $0.id == "Video" }?.header.isExpanded == false)
        }

        @Test func copyAllPutsPlainText() throws {
            let controller = controller()
            try panel(controller).onReorder?("Audio", "File")
            controller.copyAll()
            #expect(pasteboard.string(forType: .string) == InfoText.plain([sections[2], sections[0], sections[1]]))
        }

        @Test func contextMenuOffersCopyAndResets() throws {
            defaults.set("bottom-left 20 30", forKey: "tPanelPlacement")
            let controller = controller()
            let panel = try panel(controller)
            let menu = try #require(panel.onContextMenu?())
            #expect(menu.items.map(\.title) == ["Copy All", "Reset Section Order", "Reset Position"])
            pasteboard.clearContents()
            for index in menu.items.indices { menu.performActionForItem(at: index) }
            #expect(pasteboard.string(forType: .string) == InfoText.plain(sections))
            #expect(defaults.string(forKey: "tPanelPlacement") == nil)
        }

        @Test func panelSettingsAndBindingsReachThePanel() throws {
            let controller = controller(shown: false)
            controller.fontSize = 14
            controller.middleTruncated = ["Name"]
            var wheels = 0, others = 0
            controller.wheel = { _ in wheels += 1; return true }
            controller.otherMouse = { _ in others += 1 }
            controller.setVisible(true)
            controller.isAvailable = true
            let panel = try panel(controller)
            #expect(panel.fontSize == 14)
            #expect(panel.middleTruncated == ["Name"])
            controller.fontSize = 13
            #expect(panel.fontSize == 13)
            let event = try #require(NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [],
                                                        timestamp: 0, windowNumber: 0, context: nil, subtype: 0,
                                                        data1: 0, data2: 0))
            #expect(panel.wheel?(event) == true)
            panel.otherMouse?(event)
            #expect(wheels == 1)
            #expect(others == 1)
        }

        @Test func fieldEditorIsThePanelsOnly() throws {
            let controller = controller()
            let panel = try panel(controller)
            var keys: [String] = []
            controller.plainKey = { keys.append($0.charactersIgnoringModifiers ?? "") }
            let editor = try #require(controller.fieldEditor(for: panel.outline) as? PanelFieldEditor)
            #expect(editor.isFieldEditor)
            #expect(controller.fieldEditor(for: panel.outline) as? PanelFieldEditor === editor)
            #expect(controller.fieldEditor(for: host) == nil)
            #expect(controller.fieldEditor(for: nil) == nil)
            let key = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                                    windowNumber: 0, context: nil, characters: "i",
                                                    charactersIgnoringModifiers: "i", isARepeat: false, keyCode: 34))
            editor.keyDown(with: key)
            #expect(keys == ["i"])
        }

        /// The field editor keeps ⌘C only while text is selected (a plain click leaves it the first responder with
        /// nothing selected: ⌘C is the app's then, which copies its own thing) and ⌘A; the app's ⌘ and ⌃ bindings are
        /// the app's.
        @Test func fieldEditorKeepsOnlyCopyOfASelectionAndSelectAll() throws {
            let controller = controller()
            let panel = try panel(controller)
            var keys: [NSEvent] = []
            controller.plainKey = { keys.append($0) }
            let editor = try #require(controller.fieldEditor(for: panel.outline) as? PanelFieldEditor)
            editor.string = "a.mp4"
            editor.setSelectedRange(NSRange(location: 5, length: 0))
            pasteboard.clearContents()
            pasteboard.setString("before", forType: .string)
            let copyKey = try key("c", code: 8, [.command])
            editor.keyDown(with: copyKey)
            #expect(keys.map(\.keyCode) == [8])
            #expect(pasteboard.string(forType: .string) == "before")
            for (characters, code, flags) in [("j", UInt16(38), NSEvent.ModifierFlags.control), ("=", 24, .command),
                                              ("0", 29, .command), ("t", 17, .command)] {
                editor.keyDown(with: try key(characters, code: code, flags))
            }
            #expect(keys.map(\.keyCode) == [8, 38, 24, 29, 17])
            editor.setSelectedRange(NSRange(location: 0, length: 3))
            editor.keyDown(with: copyKey)
            #expect(pasteboard.string(forType: .string) == "a.m")
            #expect(keys.count == 5)
            editor.keyDown(with: try key("a", code: 0, [.command]))
            #expect(editor.selectedRange() == NSRange(location: 0, length: 5))
            #expect(keys.count == 5)
        }

        private func key(_ characters: String, code: UInt16, _ flags: NSEvent.ModifierFlags) throws -> NSEvent {
            try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                                          windowNumber: 0, context: nil, characters: characters,
                                          charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
        }

        /// The panel goes directly below the sibling the app named (FrameScrub's seek bar stays over it), each time it
        /// comes on screen.
        @Test func panelGoesDirectlyBelowTheSibling() throws {
            let under = NSView(), sibling = NSView(), over = NSView()
            for view in [under, sibling, over] { host.addSubview(view) }
            let host = host
            let controller = InfoPanelController(host: host, below: sibling, keyPrefix: "tPanel",
                                                 defaultOrder: Self.order, defaultPlacement: Self.place,
                                                 defaults: defaults,
                                                 area: { CGRect(origin: .zero, size: host.bounds.size) },
                                                 pasteboard: pasteboard)
            controller.show(sections)
            controller.setVisible(true)
            controller.isAvailable = true
            let panel = try panel(controller)
            #expect(host.subviews == [under, panel, sibling, over])
            controller.isAvailable = false
            #expect(host.subviews == [under, sibling, over])
            controller.isAvailable = true
            #expect(host.subviews == [under, panel, sibling, over])
        }

        /// A value selected (the field editor has the keys): hiding the panel, or a rebuild that removes the field,
        /// gives the keys back to whoever had them before the selection.
        @Test(arguments: [false, true]) func keysGoBackWhenTheSelectionGoes(byHiding: Bool) throws {
            let window = KeyWindow(contentRect: NSRect(x: -4000, y: -4000, width: 1000, height: 700),
                                   styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            let app = KeyView(frame: host.bounds)
            host.addSubview(app)
            let controller = controller(shown: false)
            let delegate = FieldEditorDelegate(controller)
            window.delegate = delegate
            controller.setVisible(true)
            controller.isAvailable = true
            host.layoutSubtreeIfNeeded()
            window.display()
            window.makeFirstResponder(app)
            let panel = try panel(controller)
            let cell = panel.outline.view(atColumn: 1, row: 1, makeIfNecessary: true) as? NSTableCellView
            let field = try #require(cell?.textField as? PanelValueField)
            field.onPress?()
            // As a press on it would, without one (the field takes the first responder from a press only).
            field.selectText(nil)
            #expect(window.firstResponder is PanelFieldEditor)
            if byHiding {
                controller.setVisible(false)
                #expect(panel.superview == nil)
            } else {
                // File's row has another label now: the rows are built again.
                controller.show([InfoSection(title: "File", rows: [InfoRow(label: "Path", value: "/a.mp4")])]
                                + sections.dropFirst())
            }
            #expect(window.firstResponder === app)
            window.close()
        }
    }
}

/// Defaults kept in memory only (the controller reads and writes them through `object`, `set` and `removeObject`).
private final class MemoryDefaults: UserDefaults {
    private var values: [String: Any] = [:]

    init() { super.init(suiteName: nil)! }

    override func object(forKey key: String) -> Any? { values[key] }
    override func set(_ value: Any?, forKey key: String) { values[key] = value }
    override func removeObject(forKey key: String) { values[key] = nil }
}

/// Stands in for the app's view under the panel, which has the keys.
private final class KeyView: NSView {
    override var acceptsFirstResponder: Bool { true }
}

/// A window that counts as key without being on screen.
private final class KeyWindow: NSWindow {
    override var isKeyWindow: Bool { true }
    override var canBecomeKey: Bool { true }
}

/// The app's window delegate, returning the controller's field editor.
@MainActor private final class FieldEditorDelegate: NSObject, NSWindowDelegate {
    let controller: InfoPanelController

    init(_ controller: InfoPanelController) {
        self.controller = controller
    }

    func windowWillReturnFieldEditor(_ sender: NSWindow, to client: Any?) -> Any? {
        controller.fieldEditor(for: client)
    }
}
