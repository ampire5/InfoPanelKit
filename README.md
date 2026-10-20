# InfoPanelKit

The info panel shared by FrameScrub and Loupe: titled sections of label/value rows on glass, which the user can
drag, resize, reorder and collapse.

Requirements: macOS 26+, swift-tools 6.2 (the targets build in the Swift 5 language mode).

![The info panel over a photo in Loupe](https://raw.githubusercontent.com/ampire5/Loupe/main/docs/images/info.webp)

Two libraries:

- `InfoPanelModel` (Foundation and CoreGraphics only): `InfoRow`, `InfoSection`, `InfoText.plain` (the content as
  text, for copying), `PanelPlacement`/`PanelCorner`/`PanelEdges`/`PanelSize` (where the panel sits and how it is
  dragged and resized inside its area) and `SectionLayout` (section order and collapsed sections, kept per app as a
  string).
- `InfoPanelKit`: the AppKit side, re-exporting `InfoPanelModel`: `InfoPanelView` (the panel), `PanelFieldEditor`,
  `GlassBackdrop` and `InfoPanelController`, which lays the panel over a host view of yours (no window or `NSPanel`
  of its own: a subview of the host, inside an area of it you define) and runs it — placement, drag, resize, section
  order and collapsed sections, visibility, the context menu — keeping all of it per app in `UserDefaults` under a key
  prefix.

## Usage

The controller puts the panel into `host` (the window's content view, not flipped) below `sibling` (`nil`: on top of
everything) and keeps it inside `area`, given in host points with y down:

```swift
import AppKit
import InfoPanelKit

let panel = InfoPanelController(host: contentView, below: nil, keyPrefix: "infoPanel",
                                defaultOrder: ["file", "image"],
                                defaultPlacement: PanelPlacement(corner: .topRight, dx: 12, dy: 12),
                                area: { [unowned contentView] in CGRect(origin: .zero, size: contentView.bounds.size) })
panel.isAvailable = true                    // the app has something to show (a file is open)
panel.show([
    InfoSection(id: "file", title: "File", rows: [InfoRow(label: "Name", value: "IMG_0042.jxl")]),
    InfoSection(id: "image", title: "Image", rows: [InfoRow(label: "Size", value: "8192 × 5464")]),
])
panel.toggle()                              // View › Show/Hide Info (stored as `<prefix>Visible`)
// From the host's layout, and whenever `area` changes:
panel.place()
```

The panel is on screen (`isShown`) while the user wants it (`isVisible`, `setVisible(_:)`, `toggle()`) and the app has
something to show (`isAvailable`). Hooks and knobs on `InfoPanelController`:

- `hidesWhenEmpty`: no sections from the last `show`, no panel (off by default: an empty panel still shows its glass).
- `onShownChange` (start or stop what refreshes the panel) and `panelFrame` (is the pointer over it?).
- `copyAll()`: the sections, in the user's order, as text on the pasteboard (`InfoText.plain`); also in the panel's
  context menu, with Reset Section Order (`resetSectionOrder()`) and Reset Position (`resetPosition()`).
- `InfoPanelController.stateDidChange`: posted after a controller stored something (object: its `UserDefaults`,
  `userInfo["prefix"]`: its key prefix). Controllers with the same prefix and defaults — one per window — follow each
  other through it.
- Event interception: `wheel` is asked first about every wheel event over the panel (return `true` to take it, so
  nothing scrolls); `otherMouse` gets the middle and side buttons; `plainKey` gets a key typed while a value is
  selected (anything but ⌘C with text selected and ⌘A), so the app can hand it back to its own view. For the values'
  field editor, return `panel.fieldEditor(for: client)` from `windowWillReturnFieldEditor(_:to:)`.
- `fontSize` and `middleTruncated` (labels whose values stay on one line, cut in the middle).

`infopanel-demo` is a small executable for trying the view by hand.

`PanelPlacement.swift` is Loupe's `LoupeCore/PanelPlacement.swift` (master), with `PanelCorner.isLeft` and `isTop`
made public.

## Tests

    swift test

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/ampire5/InfoPanelKit.git", from: "0.1.0"),
],
// in your target:
dependencies: [.product(name: "InfoPanelKit", package: "InfoPanelKit"), .product(name: "InfoPanelModel", package: "InfoPanelKit")]
```

Used by [Loupe](https://github.com/ampire5/Loupe) and [FrameScrub](https://github.com/ampire5/FrameScrub).

## Issues and contributions

Bug reports and pull requests are welcome at [github.com/ampire5/InfoPanelKit/issues](https://github.com/ampire5/InfoPanelKit/issues).
Please run `swift test` before sending a change.

## License

MIT — see [LICENSE](LICENSE).
