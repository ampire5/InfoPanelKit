# InfoPanelKit

The info panel shared by FrameScrub and Loupe: titled sections of label/value rows on glass, which the user can
drag, resize, reorder and collapse.

Two libraries:

- `InfoPanelModel` (Foundation and CoreGraphics only): `InfoRow`, `InfoSection`, `InfoText.plain` (the content as
  text, for copying), `PanelPlacement`/`PanelCorner`/`PanelEdges`/`PanelSize` (where the panel sits and how it is
  dragged and resized inside its area) and `SectionLayout` (section order and collapsed sections, kept per app as a
  string).
- `InfoPanelKit`: the AppKit side, re-exporting `InfoPanelModel`: `InfoPanelView` (the panel), `PanelFieldEditor`,
  `GlassBackdrop` and `InfoPanelController`, which runs the panel in a window (placement, drag, resize, section order
  and collapsed sections, visibility, the context menu) and keeps it per app in `UserDefaults` under a key prefix.

`infopanel-demo` is a small executable for trying the view by hand.

`PanelPlacement.swift` is Loupe's `LoupeCore/PanelPlacement.swift` (master), with `PanelCorner.isLeft` and `isTop`
made public. Loupe is not migrated to this package yet.

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

## License

MIT — see [LICENSE](LICENSE).
