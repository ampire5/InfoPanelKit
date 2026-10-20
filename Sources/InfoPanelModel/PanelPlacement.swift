import CoreGraphics

/// The viewer corner a floating panel keeps to.
public enum PanelCorner: String, CaseIterable, Sendable {
    case topLeft = "top-left", topRight = "top-right", bottomLeft = "bottom-left", bottomRight = "bottom-right"

    public var isLeft: Bool { self == .topLeft || self == .bottomLeft }
    public var isTop: Bool { self == .topLeft || self == .topRight }
}

/// Where the info panel sits: a corner of the area it may occupy and its distance from that
/// corner, so after a resize or in full screen it stays at the same corner. Rects are in points with the origin at the
/// top left and y down; `area` is the part of the viewer the panel may cover (under the bar, above a strip on screen).
/// The panel is always kept inside the area.
public struct PanelPlacement: Equatable, Sendable {
    /// The default distance from the area's edges.
    public static let margin = 12.0
    /// Top left, 12 pt in from both edges.
    public static let standard = PanelPlacement(corner: .topLeft, dx: margin, dy: margin)

    public var corner: PanelCorner
    /// From the corner's vertical edge (left or right) inwards.
    public var dx: Double
    /// From the corner's horizontal edge (top or bottom) inwards.
    public var dy: Double

    public init(corner: PanelCorner, dx: Double, dy: Double) {
        self.corner = corner
        self.dx = dx
        self.dy = dy
    }

    /// The panel's height: its content's, but at most the area's less a margin above and below.
    public static func height(content: Double, in area: CGRect) -> Double {
        max(0, min(content, Double(area.height) - 2 * margin))
    }

    /// The frame of a panel of `size` placed by this corner and offset in `area`, kept inside it.
    public func frame(size: CGSize, in area: CGRect) -> CGRect {
        let x = corner.isLeft ? area.minX + dx : area.maxX - dx - size.width
        let y = corner.isTop ? area.minY + dy : area.maxY - dy - size.height
        return Self.clamped(CGRect(origin: CGPoint(x: x, y: y), size: size), in: area)
    }

    /// `frame` moved (not resized) to lie inside `area`; wider or taller than the area, it keeps to its left or top edge.
    public static func clamped(_ frame: CGRect, in area: CGRect) -> CGRect {
        func fit(_ origin: CGFloat, _ length: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
            max(low, min(origin, high - length))
        }
        return CGRect(x: fit(frame.minX, frame.width, area.minX, area.maxX),
                      y: fit(frame.minY, frame.height, area.minY, area.maxY),
                      width: frame.width, height: frame.height)
    }

    /// Where a panel dropped at `frame` belongs: the area corner nearest its centre and its distance from that corner,
    /// measured after keeping it inside the area (so never negative).
    public static func nearest(to frame: CGRect, in area: CGRect) -> PanelPlacement {
        let f = clamped(frame, in: area)
        let left = f.midX < area.midX, top = f.midY < area.midY
        let corner: PanelCorner = top ? (left ? .topLeft : .topRight) : (left ? .bottomLeft : .bottomRight)
        let dx = left ? f.minX - area.minX : area.maxX - f.maxX
        let dy = top ? f.minY - area.minY : area.maxY - f.maxY
        return PanelPlacement(corner: corner, dx: max(0, Double(dx)), dy: max(0, Double(dy)))
    }

    /// `top-left 12 12`, as `UserDefaults` keeps it.
    public var stored: String { "\(corner.rawValue) \(Self.number(dx)) \(Self.number(dy))" }

    /// Nil for anything but `<corner> <dx> <dy>` with finite, non-negative offsets.
    public init?(stored: String?) {
        let parts = stored?.split(separator: " ") ?? []
        guard parts.count == 3, let corner = PanelCorner(rawValue: String(parts[0])),
              let dx = Double(parts[1]), let dy = Double(parts[2]),
              dx.isFinite, dy.isFinite, dx >= 0, dy >= 0 else { return nil }
        self.init(corner: corner, dx: dx, dy: dy)
    }

    static func number(_ v: Double) -> String {
        v == v.rounded() && abs(v) < 1e15 ? String(Int(v)) : String(v)
    }
}

/// The edges of the panel a press near them resizes (area coordinates: `top` is the edge with the smaller y).
public struct PanelEdges: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let left = PanelEdges(rawValue: 1 << 0)
    public static let right = PanelEdges(rawValue: 1 << 1)
    public static let top = PanelEdges(rawValue: 1 << 2)
    public static let bottom = PanelEdges(rawValue: 1 << 3)
}

/// The size the user gave the panel by dragging its edges: a width, and a height once a top or bottom edge was dragged
/// (until then the height follows the content). Kept like the placement, for every window and across launches.
public struct PanelSize: Equatable, Sendable {
    public static let minWidth = 280.0
    public static let minHeight = 120.0
    /// 380 pt wide, as tall as the content.
    public static let standard = PanelSize(width: 380, height: nil)

    public var width: Double
    /// Nil: as tall as the content.
    public var height: Double?

    public init(width: Double, height: Double?) {
        self.width = width
        self.height = height
    }

    /// `380` or `380 500`, as `UserDefaults` keeps it.
    public var stored: String {
        height.map { "\(PanelPlacement.number(width)) \(PanelPlacement.number($0))" } ?? PanelPlacement.number(width)
    }

    /// Nil for anything but one or two finite, positive numbers.
    public init?(stored: String?) {
        let parts = (stored?.split(separator: " ") ?? []).map { Double($0) }
        guard (1...2).contains(parts.count), parts.allSatisfy({ $0.map { $0.isFinite && $0 > 0 } ?? false }) else {
            return nil
        }
        self.init(width: parts[0]!, height: parts.count == 2 ? parts[1]! : nil)
    }
}

extension PanelPlacement {
    /// How far in from an edge a press resizes, and how far along a side from a corner it takes both edges.
    static let edgeZone = 6.0
    static let cornerZone = 14.0

    /// The panel's size in `area`: its width and its set height (or the content's), each at most the area's less a
    /// margin on both sides.
    public static func size(_ size: PanelSize, content: Double, in area: CGRect) -> CGSize {
        CGSize(width: max(0, min(size.width, Double(area.width) - 2 * margin)),
               height: height(content: size.height ?? content, in: area))
    }

    /// The edges a press at `p` (panel coordinates, y down) would resize; none away from the edges or outside the panel.
    public static func edges(at p: CGPoint, size: CGSize) -> PanelEdges {
        let x = Double(p.x), y = Double(p.y), w = Double(size.width), h = Double(size.height)
        guard x >= 0, y >= 0, x <= w, y <= h else { return [] }
        var edges: PanelEdges = []
        if x < edgeZone { edges.insert(.left) } else if x > w - edgeZone { edges.insert(.right) }
        if y < edgeZone { edges.insert(.top) } else if y > h - edgeZone { edges.insert(.bottom) }
        // Near a corner, a press on one edge takes the other too.
        if !edges.isDisjoint(with: [.left, .right]) {
            if y < cornerZone { edges.insert(.top) } else if y > h - cornerZone { edges.insert(.bottom) }
        }
        if !edges.isDisjoint(with: [.top, .bottom]) {
            if x < cornerZone { edges.insert(.left) } else if x > w - cornerZone { edges.insert(.right) }
        }
        return edges
    }

    /// `frame` with its `edges` moved by `dx`, `dy` (area coordinates, y down); the other edges stay. A moved edge stops
    /// at the minimum size and at the area's edge.
    public static func resized(_ frame: CGRect, edges: PanelEdges, dx: Double, dy: Double, in area: CGRect) -> CGRect {
        var minX = Double(frame.minX), maxX = Double(frame.maxX), minY = Double(frame.minY), maxY = Double(frame.maxY)
        if edges.contains(.left) { minX = max(Double(area.minX), min(minX + dx, maxX - PanelSize.minWidth)) }
        if edges.contains(.right) { maxX = min(Double(area.maxX), max(maxX + dx, minX + PanelSize.minWidth)) }
        if edges.contains(.top) { minY = max(Double(area.minY), min(minY + dy, maxY - PanelSize.minHeight)) }
        if edges.contains(.bottom) { maxY = min(Double(area.maxY), max(maxY + dy, minY + PanelSize.minHeight)) }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
