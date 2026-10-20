import CoreGraphics
import Testing
@testable import InfoPanelModel

@Suite struct PanelPlacementTests {
    /// A viewer under a 24 pt bar, 1000 × 700.
    private let area = CGRect(x: 0, y: 24, width: 1000, height: 700)
    private let size = CGSize(width: 320, height: 400)

    @Test func standardIsTopLeftTwelveIn() {
        #expect(PanelPlacement.standard.frame(size: size, in: area) == CGRect(x: 12, y: 36, width: 320, height: 400))
    }

    @Test func eachCornerMeasuresFromItsOwnEdges() {
        let cases: [(PanelCorner, CGRect)] = [
            (.topLeft, CGRect(x: 20, y: 24 + 30, width: 320, height: 400)),
            (.topRight, CGRect(x: 1000 - 20 - 320, y: 24 + 30, width: 320, height: 400)),
            (.bottomLeft, CGRect(x: 20, y: 724 - 30 - 400, width: 320, height: 400)),
            (.bottomRight, CGRect(x: 1000 - 20 - 320, y: 724 - 30 - 400, width: 320, height: 400)),
        ]
        for (corner, expected) in cases {
            #expect(PanelPlacement(corner: corner, dx: 20, dy: 30).frame(size: size, in: area) == expected)
        }
    }

    @Test func dropPicksTheNearestCornerAndItsOffset() {
        // Centre in the right half, lower half: bottom right, measured from the right and bottom edges.
        let dropped = CGRect(x: 600, y: 300, width: 320, height: 400)
        #expect(PanelPlacement.nearest(to: dropped, in: area) == PanelPlacement(corner: .bottomRight, dx: 80, dy: 24))
        let topLeft = CGRect(x: 40, y: 50, width: 320, height: 400)
        #expect(PanelPlacement.nearest(to: topLeft, in: area) == PanelPlacement(corner: .topLeft, dx: 40, dy: 26))
        let topRight = CGRect(x: 650, y: 30, width: 320, height: 200)
        #expect(PanelPlacement.nearest(to: topRight, in: area) == PanelPlacement(corner: .topRight, dx: 30, dy: 6))
        let bottomLeft = CGRect(x: 5, y: 500, width: 320, height: 200)
        #expect(PanelPlacement.nearest(to: bottomLeft, in: area) == PanelPlacement(corner: .bottomLeft, dx: 5, dy: 24))
    }

    @Test func aDropPastAnEdgeCountsAsAtTheEdge() {
        let outside = CGRect(x: 900, y: -50, width: 320, height: 200)   // past the right edge and above the bar
        #expect(PanelPlacement.nearest(to: outside, in: area) == PanelPlacement(corner: .topRight, dx: 0, dy: 0))
    }

    @Test func aResizeKeepsTheCornerAndOffset() {
        let placement = PanelPlacement.nearest(to: CGRect(x: 600, y: 300, width: 320, height: 400), in: area)
        let wider = CGRect(x: 0, y: 0, width: 1600, height: 1000)   // full screen: bar floating, no strip
        #expect(placement.frame(size: size, in: wider) == CGRect(x: 1600 - 80 - 320, y: 1000 - 24 - 400, width: 320, height: 400))
    }

    @Test func alwaysInsideTheArea() {
        // A smaller window than the one the offsets were made in: pushed back in, never past the top.
        let far = PanelPlacement(corner: .bottomRight, dx: 900, dy: 600)
        #expect(far.frame(size: size, in: area) == CGRect(x: 0, y: 24, width: 320, height: 400))
        // The narrowest window (320 pt): the 320 pt panel fills its width exactly, not past the left edge.
        let narrow = CGRect(x: 0, y: 24, width: 320, height: 300)
        #expect(PanelPlacement.standard.frame(size: CGSize(width: 320, height: 276), in: narrow).minX == 0)
        #expect(PanelPlacement(corner: .topRight, dx: 12, dy: 12).frame(size: CGSize(width: 320, height: 276), in: narrow).minX == 0)
        // Wider than the area: kept to the left edge.
        #expect(PanelPlacement.clamped(CGRect(x: 50, y: 30, width: 400, height: 100), in: narrow).minX == 0)
    }

    @Test func heightIsTheContentsUpToTheAreaLessMargins() {
        #expect(PanelPlacement.height(content: 300, in: area) == 300)
        #expect(PanelPlacement.height(content: 2000, in: area) == 700 - 24)
        #expect(PanelPlacement.height(content: 300, in: CGRect(x: 0, y: 0, width: 320, height: 10)) == 0)
    }

    @Test func storedRoundTrip() {
        for placement in [PanelPlacement.standard, PanelPlacement(corner: .bottomRight, dx: 80, dy: 24.5)] {
            #expect(PanelPlacement(stored: placement.stored) == placement)
        }
        #expect(PanelPlacement.standard.stored == "top-left 12 12")
        for bad in [nil, "", "top-left 12", "middle 1 2", "top-left -1 2", "top-left x 2", "top-left inf 2", "top-left 1 2 3"] {
            #expect(PanelPlacement(stored: bad) == nil)
        }
    }

    // MARK: size and resize

    @Test func sizeStoredRoundTrip() {
        for size in [PanelSize.standard, PanelSize(width: 512.5, height: 400)] {
            #expect(PanelSize(stored: size.stored) == size)
        }
        #expect(PanelSize.standard.stored == "380")
        #expect(PanelSize(width: 400, height: 300).stored == "400 300")
        for bad in [nil, "", "x", "400 y", "-1", "0", "400 0", "inf", "400 300 2"] {
            #expect(PanelSize(stored: bad) == nil)
        }
    }

    @Test func sizeIsTheWidthAndContentHeightWithinTheArea() {
        #expect(PanelPlacement.size(.standard, content: 300, in: area) == CGSize(width: 380, height: 300))
        #expect(PanelPlacement.size(.standard, content: 2000, in: area) == CGSize(width: 380, height: 700 - 24))
        // A height set by hand holds, whatever the content, up to the area.
        let fixed = PanelSize(width: 500, height: 450)
        #expect(PanelPlacement.size(fixed, content: 100, in: area) == CGSize(width: 500, height: 450))
        #expect(PanelPlacement.size(fixed, content: 100, in: CGRect(x: 0, y: 0, width: 400, height: 300))
                == CGSize(width: 400 - 24, height: 300 - 24))
    }

    @Test func edgesUnderThePointer() {
        let size = CGSize(width: 380, height: 400)
        #expect(PanelPlacement.edges(at: CGPoint(x: 190, y: 200), size: size).isEmpty)
        #expect(PanelPlacement.edges(at: CGPoint(x: 2, y: 200), size: size) == .left)
        #expect(PanelPlacement.edges(at: CGPoint(x: 378, y: 200), size: size) == .right)
        #expect(PanelPlacement.edges(at: CGPoint(x: 190, y: 1), size: size) == .top)
        #expect(PanelPlacement.edges(at: CGPoint(x: 190, y: 399), size: size) == .bottom)
        // Corners take both edges, a little way along each side.
        #expect(PanelPlacement.edges(at: CGPoint(x: 1, y: 10), size: size) == [.left, .top])
        #expect(PanelPlacement.edges(at: CGPoint(x: 370, y: 398), size: size) == [.right, .bottom])
        #expect(PanelPlacement.edges(at: CGPoint(x: 379, y: 3), size: size) == [.right, .top])
        // Outside the panel: none.
        #expect(PanelPlacement.edges(at: CGPoint(x: -3, y: 200), size: size).isEmpty)
    }

    @Test func resizeMovesOnlyTheGrabbedEdges() {
        let frame = CGRect(x: 100, y: 100, width: 380, height: 400)
        #expect(PanelPlacement.resized(frame, edges: .right, dx: 50, dy: 30, in: area)
                == CGRect(x: 100, y: 100, width: 430, height: 400))
        #expect(PanelPlacement.resized(frame, edges: .left, dx: -40, dy: 0, in: area)
                == CGRect(x: 60, y: 100, width: 420, height: 400))
        #expect(PanelPlacement.resized(frame, edges: [.left, .top], dx: 20, dy: 10, in: area)
                == CGRect(x: 120, y: 110, width: 360, height: 390))
        #expect(PanelPlacement.resized(frame, edges: .bottom, dx: 0, dy: -50, in: area)
                == CGRect(x: 100, y: 100, width: 380, height: 350))
    }

    @Test func resizeStopsAtTheMinimumAndTheArea() {
        let frame = CGRect(x: 100, y: 100, width: 380, height: 400)
        // Narrower than the minimum: the dragged edge stops, the other stays.
        #expect(PanelPlacement.resized(frame, edges: .left, dx: 300, dy: 0, in: area)
                == CGRect(x: 480 - PanelSize.minWidth, y: 100, width: PanelSize.minWidth, height: 400))
        #expect(Double(PanelPlacement.resized(frame, edges: .bottom, dx: 0, dy: -1000, in: area).height) == PanelSize.minHeight)
        // Past the area's edges: stops there.
        #expect(PanelPlacement.resized(frame, edges: .right, dx: 2000, dy: 0, in: area).maxX == area.maxX)
        #expect(PanelPlacement.resized(frame, edges: .top, dx: 0, dy: -500, in: area).minY == area.minY)
    }
}
