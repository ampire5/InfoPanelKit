import Foundation

/// How the user arranged the panel's sections: their order and which are collapsed. Kept per app, as a string in
/// `UserDefaults`. Only ids are kept, so sections that come and go (no audio track, no Stash) never disturb it.
public struct SectionLayout: Equatable, Sendable {
    /// Section ids in the order the user left them; may name sections that are absent now, or never were.
    public var order: [String]
    public var collapsed: Set<String>

    public init(order: [String] = [], collapsed: Set<String> = []) {
        self.order = order
        self.collapsed = collapsed
    }

    /// `sections` in the user's order. A section the order does not name follows its neighbour before it in
    /// `defaultOrder` (or leads, with none), so a new section lands where it belongs without moving the others.
    /// Sections outside both orders come last, as given.
    public func ordered(_ sections: [InfoSection], defaultOrder: [String]) -> [InfoSection] {
        let order = fullOrder(defaultOrder: defaultOrder)
        let byId = Dictionary(sections.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let known = Set(order)
        return order.compactMap { byId[$0] } + sections.filter { !known.contains($0.id) }
    }

    /// The layout with `id` moved before `target`, or last when `target` is nil or not in the order. The order is
    /// made whole first, so the move holds even for sections the stored order did not name yet.
    public func moving(_ id: String, before target: String?, defaultOrder: [String]) -> SectionLayout {
        var order = fullOrder(defaultOrder: defaultOrder)
        guard id != target else { return SectionLayout(order: order, collapsed: collapsed) }
        order.removeAll { $0 == id }
        order.insert(id, at: target.flatMap { order.firstIndex(of: $0) } ?? order.endIndex)
        return SectionLayout(order: order, collapsed: collapsed)
    }

    /// The stored order without repeats, then each default id it lacks, placed after the default id before it.
    private func fullOrder(defaultOrder: [String]) -> [String] {
        var result: [String] = []
        for id in order where !result.contains(id) { result.append(id) }
        for (index, id) in defaultOrder.enumerated() where !result.contains(id) {
            let anchor = defaultOrder[..<index].reversed().compactMap { result.firstIndex(of: $0) }.first
            result.insert(id, at: anchor.map { $0 + 1 } ?? 0)
        }
        return result
    }

    private struct Record: Codable {
        var order: [String]
        var collapsed: [String]
    }

    /// `{"order":[…],"collapsed":[…]}`, as `UserDefaults` keeps it. `collapsed` is sorted, so equal layouts store
    /// equal strings.
    public var stored: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let record = Record(order: order, collapsed: collapsed.sorted())
        return (try? encoder.encode(record)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    /// Nil for anything `stored` did not produce.
    public init?(stored: String?) {
        guard let data = stored?.data(using: .utf8),
              let record = try? JSONDecoder().decode(Record.self, from: data) else { return nil }
        self.init(order: record.order, collapsed: Set(record.collapsed))
    }
}
