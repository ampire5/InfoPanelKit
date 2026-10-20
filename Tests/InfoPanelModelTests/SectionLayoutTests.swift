import CoreGraphics
import Testing
@testable import InfoPanelModel

@Suite struct SectionLayoutTests {
    private let defaults = ["File", "Stash", "Video", "Audio", "Playback", "Picture", "Diagnostics"]

    private func s(_ id: String) -> InfoSection {
        InfoSection(title: id, rows: [InfoRow(label: "a", value: "1")])
    }

    @Test func emptyLayoutKeepsTheDefaultOrder() {
        #expect(SectionLayout().ordered([s("Video"), s("File")], defaultOrder: defaults).map(\.id) == ["File", "Video"])
    }

    @Test func orderKeepsAbsentSectionsPlace() {
        let layout = SectionLayout(order: ["Video", "Stash", "File"])
        #expect(layout.ordered([s("File"), s("Video")], defaultOrder: defaults).map(\.id) == ["Video", "File"])
        #expect(layout.ordered([s("File"), s("Stash"), s("Video")], defaultOrder: defaults).map(\.id)
                == ["Video", "Stash", "File"])
    }

    @Test func unknownStoredIdsAreIgnored() {
        let layout = SectionLayout(order: ["Gone", "Video", "File"])
        #expect(layout.ordered([s("File"), s("Video")], defaultOrder: defaults).map(\.id) == ["Video", "File"])
    }

    @Test func newSectionGoesAfterItsDefaultNeighbour() {
        // "Audio" is not in the stored order: it follows "Video", its neighbour before it in the default order.
        let layout = SectionLayout(order: ["Video", "File"])
        #expect(layout.ordered([s("File"), s("Video"), s("Audio")], defaultOrder: defaults).map(\.id)
                == ["Video", "Audio", "File"])
    }

    @Test func newFirstSectionGoesToTheFront() {
        let layout = SectionLayout(order: ["Video", "Stash"])
        #expect(layout.ordered([s("Stash"), s("File"), s("Video")], defaultOrder: defaults).map(\.id)
                == ["File", "Video", "Stash"])
    }

    @Test func sectionsOutsideTheDefaultsComeLastInTheirOwnOrder() {
        let sections = [s("Extra"), s("Video"), s("Other"), s("File")]
        #expect(SectionLayout().ordered(sections, defaultOrder: defaults).map(\.id) == ["File", "Video", "Extra", "Other"])
    }

    @Test func duplicatesInStoredOrderCountOnce() {
        let layout = SectionLayout(order: ["Video", "File", "Video", "File"])
        #expect(layout.ordered([s("File"), s("Video")], defaultOrder: defaults).map(\.id) == ["Video", "File"])
    }

    @Test func movingPutsTheSectionBeforeTheTarget() {
        let first = SectionLayout().moving("Diagnostics", before: "File", defaultOrder: defaults)
        #expect(first.order == ["Diagnostics", "File", "Stash", "Video", "Audio", "Playback", "Picture"])
        let last = SectionLayout().moving("File", before: nil, defaultOrder: defaults)
        #expect(last.order == ["Stash", "Video", "Audio", "Playback", "Picture", "Diagnostics", "File"])
        let middle = first.moving("Diagnostics", before: "Audio", defaultOrder: defaults)
        #expect(middle.order == ["File", "Stash", "Video", "Diagnostics", "Audio", "Playback", "Picture"])
    }

    @Test func movingKeepsCollapsedSections() {
        let layout = SectionLayout(collapsed: ["Video"]).moving("Audio", before: "File", defaultOrder: defaults)
        #expect(layout.collapsed == ["Video"])
    }

    @Test func movingMaterialisesNewSectionsWhereOrderedWouldPutThem() {
        let layout = SectionLayout(order: ["Video", "File"]).moving("File", before: "Video", defaultOrder: defaults)
        #expect(layout.order == ["File", "Video", "Audio", "Playback", "Picture", "Diagnostics", "Stash"])
    }

    @Test func storedRoundTrips() {
        let layout = SectionLayout(order: ["Video", "File"], collapsed: ["Stash", "Audio"])
        #expect(SectionLayout(stored: layout.stored) == layout)
    }

    @Test func equalLayoutsStoreEqualStrings() {
        #expect(SectionLayout(order: ["File"], collapsed: ["A", "B", "C"]).stored
                == SectionLayout(order: ["File"], collapsed: ["C", "B", "A"]).stored)
    }

    @Test func badStoredStringIsNil() {
        #expect(SectionLayout(stored: nil) == nil)
        #expect(SectionLayout(stored: "") == nil)
        #expect(SectionLayout(stored: "garbage{") == nil)
    }

    @Test func tinyAreaKeepsThePanelInside() {
        let area = CGRect(x: 0, y: 0, width: 200, height: 90)
        let size = PanelPlacement.size(.standard, content: 500, in: area)
        #expect(size.width >= 0 && size.height >= 0)
        #expect(area.contains(PanelPlacement(corner: .topRight, dx: 12, dy: 12).frame(size: size, in: area)) || size == .zero)
    }
}
