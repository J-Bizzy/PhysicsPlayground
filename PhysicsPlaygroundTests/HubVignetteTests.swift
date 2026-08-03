//
//  HubVignetteTests.swift
//  Physics Playground — app tests
//
//  The miniatures are the front door: six of them on the home screen and
//  seven in the labs ring, and nothing about how they are placed is
//  checkable by eye at review time — a screenshot shows one pose of one
//  exhibit at one moment.
//
//  Both hosts (`HubSpaceView.buildExhibit`, `Palette.init`) fit a
//  miniature by measuring `visualBounds(...).extents` ONCE, at build
//  time, and dividing their slot size by `max(x, y)`. Two things follow
//  from that, and both of them were bugs:
//
//    • Neither host consults the bounds CENTRE, so whatever origin a
//      builder happened to author to became the middle of the bubble.
//      The pendulum rig hung entirely in the upper half of its slot.
//    • The measurement happens before a single frame of animation, so a
//      miniature whose motion leaves its resting bounds is fitted from
//      a box smaller than the one it uses. The projectile created its
//      strobe dots at the origin and only put them on the arc on the
//      first `animate`, so the fit never saw the trajectory at all.
//
//  `HubVignettes.fit` fixes both by centring an inner frame and sampling
//  the closure before it measures. These tests pin that, and in doing so
//  they pin the assumption the whole arrangement rests on: that
//  `visualBounds` on an UNPARENTED entity reflects transforms written a
//  moment earlier, with no scene and no update tick. If that ever stops
//  being true, this file fails rather than the gallery quietly going
//  crooked again.
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
                              "kinematics", "pendulums", "gravitylab", "labs"]

    private static let side = HubVignettes.frameHalf * 2

    /// What the hosts measure, measured the same way they measure it.
    private func hostBounds(_ entity: Entity) -> BoundingBox {
        entity.visualBounds(relativeTo: nil)
    }

    /// Every transform in the hierarchy, flattened.
    ///
    /// Bounds cannot answer "did anything move" any more, and that is by
    /// design: `fit` pins an invisible square to the root so the hosts
    /// measure the same number whatever pose the miniature is in. Which
    /// means a miniature whose animation closure captured nothing would
    /// sit perfectly still inside a perfectly correct box. This walks
    /// what the closure actually writes.
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

    /// An unparented entity reports bounds that include a child moved
    /// after it was added — no scene, no update tick.
    ///
    /// This is not a test of the app so much as a test of the platform,
    /// and it is first because `fit` is built entirely on top of it. If
    /// RealityKit ever starts caching bounds until a frame runs, every
    /// other test in this file would fail in a confusing way and this
    /// one would say why.
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
    /// bounds centre IS the offset from the middle of the slot.
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

    /// Every miniature reports the same size to the fit, so the hosts'
    /// `slotSize / largest` is one number for all of them.
    ///
    /// This is what makes six differently-shaped exhibits read as one
    /// set: without it the widest miniature is scaled by its width and
    /// comes out a streak beside a square one.
    func testEveryMiniatureNormalisesToTheCommonSquare() {
        for id in Self.ids {
            let extents = hostBounds(HubVignettes.make(for: id).entity).extents
            let largest = max(extents.x, extents.y)
            XCTAssertEqual(largest, Self.side, accuracy: Self.side * 0.01,
                           "\(id) does not fill the common square")
        }
    }

    /// And none of them is a sliver on the other axis. `fit` makes the
    /// sizes consistent; only composition can make the SHAPES
    /// consistent, and a miniature that fills its square in one
    /// direction and a third of it in the other still reads as an
    /// accident next to its neighbours.
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

    /// Running a miniature through its own cycle never carries it
    /// outside the square it was fitted to.
    ///
    /// This is the regression guard for the whole class of bug: the
    /// hosts cannot re-measure, so anything the animation reaches that
    /// the fit did not see is a miniature overflowing its bubble and
    /// crossing into its neighbour's. A little slack, because a fit
    /// normalises the LARGER axis and a round bob may bulge a hair past
    /// it on the other.
    func testMotionStaysInsideTheFittedSquare() {
        for id in Self.ids {
            let built = HubVignettes.make(for: id)
            let allowed = Self.side / 2 * 1.06

            for step in 0..<32 {
                // Deliberately not the cycle `fit` sampled: a whole
                // minute at an unrelated cadence lands between the
                // samples and catches a miniature that is only tidy at
                // the two dozen instants it was measured at.
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

    // MARK: The bead

    /// Only the labs emblem answers to openness. A gallery exhibit has
    /// nothing to be open or shut about, and a stray hook there would be
    /// a sign someone had wired the palette's state into the wrong
    /// miniature.
    func testOnlyTheLabsEmblemTakesAnOpenness() {
        XCTAssertNotNil(HubVignettes.make(for: "labs").setOpenness)
        for id in Self.ids where id != "labs" {
            XCTAssertNil(HubVignettes.make(for: id).setOpenness,
                         "\(id) should not care whether the ring is open")
        }
    }

    /// Opening the ring visibly changes the emblem, and closing it puts
    /// the emblem back. The palette eases `openness` every frame, so a
    /// hook that only ever grew would leave the bead shrunken forever.
    func testOpeningTheBeadIsReversible() {
        let built = HubVignettes.make(for: "labs")
        built.animate(0)
        let shut = pose(built.entity)

        built.setOpenness?(1)
        built.animate(0)
        XCTAssertNotEqual(pose(built.entity), shut,
                          "opening the ring did nothing to the emblem")

        built.setOpenness?(0)
        built.animate(0)
        XCTAssertEqual(pose(built.entity), shut,
                       "the emblem did not return when the ring closed")
    }

    /// And the emblem still measures the same square whatever the ring is
    /// doing. The unfold writes a scale of its own, and the first version
    /// wrote it to the very entity `fit` had scaled — so shutting the ring
    /// left the bead a different size than it started, permanently.
    func testOpeningTheBeadDoesNotDisturbTheFit() {
        let built = HubVignettes.make(for: "labs")
        for value in [Float(0), 0.5, 1, 0.5, 0] {
            built.setOpenness?(value)
            built.animate(0)
            let extents = hostBounds(built.entity).extents
            XCTAssertEqual(max(extents.x, extents.y), Self.side,
                           accuracy: Self.side * 0.01,
                           "openness \(value) resized the bead's own square")
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
