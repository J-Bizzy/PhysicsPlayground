//
//  HubVignetteTests.swift
//  Physics Playground — app tests
//
//  Both hosts fit a miniature by measuring its bounds once at build time
//  and dividing their slot size by the larger axis. `HubVignettes.fit`
//  centres an inner frame and samples the animation before it measures;
//  these pin that, and the platform assumption underneath it — that
//  `visualBounds` on an unparented entity reflects transforms written a
//  moment earlier, with no scene and no update tick.
//

import XCTest
import RealityKit
import simd
@testable import PhysicsPlayground

@MainActor
final class HubVignetteTests: XCTestCase {

    /// Every id the two hosts can ask for: the six modules plus the labs
    /// emblem in the palette bead.
    private static let ids = ["electrostatics", "circuits", "magnetism",
                              "kinematics", "pendulums", "gravitylab"]

    private static let side = HubVignettes.frameHalf * 2

    /// What the hosts measure, measured the same way they measure it.
    private func hostBounds(_ entity: Entity) -> BoundingBox {
        entity.visualBounds(relativeTo: nil)
    }

    /// Every transform in the hierarchy, flattened: `fit` pins an invisible
    /// square to the root, so bounds cannot answer "did anything move".
    private func pose(_ entity: Entity) -> [SIMD4<Float>] {
        var columns: [SIMD4<Float>] = []
        func walk(_ node: Entity) {
            let matrix = node.transform.matrix
            columns.append(contentsOf: [matrix.columns.0, matrix.columns.1,
                                        matrix.columns.2, matrix.columns.3])
            for child in node.children { walk(child) }
        }
        walk(entity)
        return columns
    }

    // MARK: The assumption everything else rests on

    /// An unparented entity reports bounds that include a child moved after
    /// it was added — a test of the platform, first because `fit` is built
    /// on it.
    func testVisualBoundsSeeUnparentedTransformsImmediately() {
        let root = Entity()
        let child = ModelEntity(mesh: .generateSphere(radius: 0.01))
        root.addChild(child)

        let before = hostBounds(root)
        XCTAssertEqual(before.center.x, 0, accuracy: 1e-5)

        child.position.x = 0.5
        let after = hostBounds(root)
        XCTAssertEqual(after.center.x, 0.5, accuracy: 1e-4,
                       "visualBounds did not see a transform written to an "
                       + "unparented hierarchy — HubVignettes.fit cannot work")
    }

    // MARK: Centring and common size

    /// Every miniature arrives centred on its own origin.
    ///
    /// The hosts place the vignette at `.zero` inside the bubble, so the
    /// bounds centre is the offset from the middle of the slot.
    func testEveryMiniatureIsCentredOnItsOrigin() {
        for id in Self.ids {
            let bounds = hostBounds(HubVignettes.make(for: id).entity)
            let slack = Self.side * 0.02
            XCTAssertEqual(bounds.center.x, 0, accuracy: slack,
                           "\(id) hangs off-centre horizontally")
            XCTAssertEqual(bounds.center.y, 0, accuracy: slack,
                           "\(id) hangs off-centre vertically")
        }
    }

    /// Every miniature reports the same size to the fit, which is what
    /// makes six differently shaped exhibits read as one set.
    func testEveryMiniatureNormalisesToTheCommonSquare() {
        for id in Self.ids {
            let extents = hostBounds(HubVignettes.make(for: id).entity).extents
            let largest = max(extents.x, extents.y)
            XCTAssertEqual(largest, Self.side, accuracy: Self.side * 0.01,
                           "\(id) does not fill the common square")
        }
    }

    /// And none of them is a sliver on the other axis: only composition can
    /// make the shapes consistent.
    func testNoMiniatureIsAStreak() {
        for id in Self.ids {
            let extents = HubVignettes.make(for: id).contentExtents
            let shortest = min(extents.x, extents.y)
            XCTAssertGreaterThan(
                shortest, Self.side * 0.45,
                "\(id) fills \(extents.x) x \(extents.y) of its square — "
                + "too flat to sit beside the others")
        }
    }

    // MARK: Motion stays inside the bubble

    /// Running a miniature through its own cycle never carries it outside
    /// the square it was fitted to; a little slack for a round bob bulging
    /// past the shorter axis.
    func testMotionStaysInsideTheFittedSquare() {
        for id in Self.ids {
            let built = HubVignettes.make(for: id)
            let allowed = Self.side / 2 * 1.06

            for step in 0..<32 {
                // Deliberately not the cycle `fit` sampled, so a miniature that is only
                // tidy at the instants it was measured at is caught.
                built.animate(Double(step) * 1.9)
                let bounds = hostBounds(built.entity)
                XCTAssertLessThan(
                    max(abs(bounds.min.x), abs(bounds.max.x)), allowed,
                    "\(id) reaches outside its bubble horizontally at step \(step)")
                XCTAssertLessThan(
                    max(abs(bounds.min.y), abs(bounds.max.y)), allowed,
                    "\(id) reaches outside its bubble vertically at step \(step)")
            }
        }
    }

    /// A miniature actually moves. Six of these are the only thing on the
    /// home screen that says the app is running, and a closure that
    /// captured nothing would pass every test above.
    func testEveryMiniatureActuallyMoves() {
        for id in Self.ids {
            let built = HubVignettes.make(for: id)
            built.animate(0)
            let start = pose(built.entity)
            var moved = false
            for step in 1...24 {
                built.animate(Double(step) * 0.31)
                if pose(built.entity) != start { moved = true; break }
            }
            XCTAssertTrue(moved, "\(id) is a still life")
        }
    }




    // MARK: Unknown ids

    /// A module registered before its art exists still gets an exhibit,
    /// and that exhibit obeys the same contract as the rest — the
    /// fallback is the one builder guaranteed to be reached by code
    /// nobody has written yet.
    func testTheFallbackObeysTheContract() {
        let built = HubVignettes.make(for: "no-such-module")
        let bounds = hostBounds(built.entity)
        XCTAssertEqual(max(bounds.extents.x, bounds.extents.y), Self.side,
                       accuracy: Self.side * 0.01)
        XCTAssertEqual(bounds.center.x, 0, accuracy: Self.side * 0.02)
        XCTAssertEqual(bounds.center.y, 0, accuracy: Self.side * 0.02)
    }
}
