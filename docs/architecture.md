# InfoPanelKit architecture

Current map; update when controller/view/model ownership changes. This package presents information supplied by
its host. It does not inspect media, stat files or schedule application metadata reads.

## Targets and ownership

| Target | Owns | Entry points |
|---|---|---|
| InfoPanelModel | Sections/rows/text representation and placement/layout rules | `Sources/InfoPanelModel/InfoSection.swift`, `Sources/InfoPanelModel/PanelPlacement.swift`, `Sources/InfoPanelModel/SectionLayout.swift` |
| InfoPanelKit | AppKit controller, glass panel view and field editor | `Sources/InfoPanelKit/InfoPanelController.swift`, `Sources/InfoPanelKit/InfoPanelView.swift`, `Sources/InfoPanelKit/PanelFieldEditor.swift` |
| infopanel-demo | Manual host example | `Sources/infopanel-demo/main.swift` |

The UI target depends on the model target. Applications retain a controller and provide its parent/available area,
sections and event hooks. The controller owns panel placement, visible/available state and preference coordination;
the view owns row/section presentation and user interaction. The host owns data validity and read cancellation.

## Data and lifetime flow

Host reads facts → builds InfoSection values → `show` → layout/view. Visibility is a combination of user intent,
host availability and optional empty-content hiding. The host calls `place` when its usable area changes.
`UserDefaults` keys are namespaced by the supplied prefix; controllers sharing defaults/prefix follow preference
changes through `stateDidChange`. Notifications are posted and followed synchronously on the main actor;
the sender is passed as an `InfoPanelController`, preserving that ownership across the callback. Section
order/collapse and position are presentation preferences, not media state.

UI work belongs to the main actor. `onShownChange` lets the host start/stop updates; hiding a panel must not leave a
host diagnostics timer running. Wheel/key/other-mouse hooks and the shared field editor preserve host input routing.
The package must not start its own filesystem reads to fill a row.

## Verification and change entry points

- Placement/section rules: `Tests/InfoPanelModelTests`.
- Visibility, editing, layout and preferences: `Tests/InfoPanelKitTests`.
- Metadata or loading behavior: change the host application's loader, not the panel kit.

Run `swift test --jobs 4`, then use the demo or app real-window benchmark for layout/input changes. See
[README](../README.md) for integration hooks. Follow host application glass/reveal requirements; keep media-specific policy outside this package.
