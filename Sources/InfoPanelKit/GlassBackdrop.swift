import AppKit

/// A rounded Liquid Glass backdrop for overlays. Always dark, so white text and icons read on bright frames too. Add
/// content to `content`; size the backdrop from outside. `tint` is how much black the glass takes (the info panel
/// 0.46, buttons and OSD 0.25); `hairline` draws a thin light edge round it.
public final class GlassBackdrop: NSView {
    public let content = NSView()

    public init(cornerRadius: CGFloat, tint: CGFloat = 0.25, hairline: Bool = false) {
        super.init(frame: .zero)
        appearance = NSAppearance(named: .darkAqua)
        let glass = NSGlassEffectView()
        glass.cornerRadius = cornerRadius
        glass.tintColor = NSColor(white: 0, alpha: tint)
        glass.contentView = content
        // Glass has a size of its own; pinned with low hugging and compression so it never sizes its owner.
        glass.translatesAutoresizingMaskIntoConstraints = false
        for orientation in [NSLayoutConstraint.Orientation.horizontal, .vertical] {
            glass.setContentHuggingPriority(.init(1), for: orientation)
            glass.setContentCompressionResistancePriority(.init(1), for: orientation)
        }
        addSubview(glass)
        NSLayoutConstraint.activate([
            glass.leadingAnchor.constraint(equalTo: leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: trailingAnchor),
            glass.topAnchor.constraint(equalTo: topAnchor),
            glass.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        if hairline {
            let edge = GlassEdge()
            edge.wantsLayer = true
            edge.layer?.cornerRadius = cornerRadius
            edge.layer?.cornerCurve = .continuous
            edge.layer?.borderWidth = 0.5
            edge.layer?.borderColor = NSColor(white: 1, alpha: InfoPanelStyle.ruleAlpha).cgColor
            edge.translatesAutoresizingMaskIntoConstraints = false
            addSubview(edge)
            NSLayoutConstraint.activate([
                edge.leadingAnchor.constraint(equalTo: leadingAnchor),
                edge.trailingAnchor.constraint(equalTo: trailingAnchor),
                edge.topAnchor.constraint(equalTo: topAnchor),
                edge.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }
    }


    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

/// The backdrop's light edge: drawn only, so presses go through it to the content.
private final class GlassEdge: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
