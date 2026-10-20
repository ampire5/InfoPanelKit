/// One line of an info panel: a label and its value. Rows without a value are not built, so `value` is never empty.
public struct InfoRow: Equatable, Sendable {
    public let label: String
    public let value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

/// A titled group of rows. `id` is what the user's section order and collapsed state are kept by, so it stays the same
/// when the title is localised or reworded; it defaults to the title.
public struct InfoSection: Equatable, Sendable {
    public let id: String
    public let title: String
    public let rows: [InfoRow]

    public init(id: String? = nil, title: String, rows: [InfoRow]) {
        self.id = id ?? title
        self.title = title
        self.rows = rows
    }
}

/// The panel's content as text, for copying.
public enum InfoText {
    /// Each section as its title, then a `Label: value` line per row; sections are separated by a blank line.
    /// Sections without rows are left out, as the panel does not show them.
    public static func plain(_ sections: [InfoSection]) -> String {
        sections
            .filter { !$0.rows.isEmpty }
            .map { section in
                ([section.title] + section.rows.map { "\($0.label): \($0.value)" }).joined(separator: "\n")
            }
            .joined(separator: "\n\n")
    }
}
