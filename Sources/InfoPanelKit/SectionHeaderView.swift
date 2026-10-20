import AppKit

/// A section's header row in the info panel: the title in small spaced capitals, a hairline to the row's end and, at
/// the end, the chevron that collapses the section — shown while the pointer is over the header and always while the
/// section is collapsed. The outline gives it the label column's cell (the value column's is empty), and the title,
/// rule and chevron reach past it to the row's end. The outline's own triangle is hidden, so the chevron is the one
/// place a section collapses; the press reaches it rather than the outline (`InfoPanelView.hitTest`), and anywhere else
/// on the row the outline takes the press, to drag the section to another place.
@MainActor final class SectionHeaderView: NSView {
    /// The chevron: `⌄` while the section is expanded, `›` while it is collapsed.
    let button = NSButton(title: "", target: nil, action: nil)
    let title: NSTextField
    /// The chevron was pressed: true when the section is now expanded.
    var onToggle: ((Bool) -> Void)?

    /// The pointer is over the header's row: the title brightens and the chevron shows.
    var isHovered = false {
        didSet { if isHovered != oldValue { updateLook() } }
    }

    /// The chevron is on screen.
    var chevronVisible: Bool { isHovered || !isExpanded }

    private let rule = NSView()
    private let text: String
    private let font: NSFont
    /// How far from the row's end the chevron stops.
    private let trailing: CGFloat
    /// The chevron's end held inside the row view, which the outline puts this view in.
    private var rowEnd: NSLayoutConstraint?
    private var hover: NSTrackingArea?

    /// `leading` and `trailing` are the room before the title and after the chevron; `gap` the room above the title,
    /// which keeps a section apart from the one before it (none for the first).
    init(title text: String, font: NSFont, leading: CGFloat, trailing: CGFloat, gap: CGFloat, expanded: Bool) {
        title = NSTextField(labelWithString: "")
        self.text = text
        self.font = font
        self.trailing = trailing
        super.init(frame: .zero)
        button.isBordered = false
        button.setButtonType(.onOff)
        button.state = expanded ? .on : .off
        button.font = .systemFont(ofSize: font.pointSize + 1, weight: .semibold)
        button.target = self
        button.action = #selector(toggled)
        title.font = font
        title.lineBreakMode = .byTruncatingTail
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        rule.wantsLayer = true
        rule.layer?.backgroundColor = NSColor(white: 1, alpha: InfoPanelStyle.ruleAlpha).cgColor
        for view in [title, rule, button] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        button.setContentHuggingPriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: leading),
            title.topAnchor.constraint(equalTo: topAnchor, constant: gap),
            title.bottomAnchor.constraint(equalTo: bottomAnchor),
            rule.leadingAnchor.constraint(equalTo: title.trailingAnchor, constant: 8),
            rule.trailingAnchor.constraint(equalTo: button.leadingAnchor, constant: -6),
            rule.heightAnchor.constraint(equalToConstant: 0.5),
            rule.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            button.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            button.widthAnchor.constraint(equalToConstant: 12),
        ])
        updateLook()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        rowEnd?.isActive = false
        rowEnd = superview.map {
            button.trailingAnchor.constraint(equalTo: $0.trailingAnchor, constant: -trailing)
        }
        rowEnd?.isActive = true
    }

    var isExpanded: Bool {
        get { button.state == .on }
        set {
            button.state = newValue ? .on : .off
            updateLook()
        }
    }

    // MARK: Hover

    /// Over the whole row: the header's own frame is the label column's only.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hover { removeTrackingArea(hover) }
        var rect = bounds
        if let superview { rect.size.width = max(bounds.width, superview.bounds.maxX - frame.minX) }
        let area = NSTrackingArea(rect: rect, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(area)
        hover = area
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    private func updateLook() {
        let alpha = isHovered ? InfoPanelStyle.headerHoverAlpha : InfoPanelStyle.headerAlpha
        let colour = NSColor(white: 1, alpha: alpha)
        title.attributedStringValue = NSAttributedString(string: text.uppercased(), attributes: [
            .font: font, .foregroundColor: colour, .kern: InfoPanelStyle.headerKern * font.pointSize,
        ])
        title.textColor = colour
        button.attributedTitle = NSAttributedString(string: isExpanded ? "⌄" : "›", attributes: [
            .font: button.font ?? font, .foregroundColor: NSColor(white: 1, alpha: InfoPanelStyle.headerHoverAlpha),
        ])
        button.isHidden = !chevronVisible
    }

    @objc private func toggled() {
        updateLook()
        onToggle?(isExpanded)
    }
}
