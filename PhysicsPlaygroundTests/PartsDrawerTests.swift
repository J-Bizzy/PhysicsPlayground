//
//  PartsDrawerTests.swift
//  PhysicsPlaygroundTests
//
//  TWO GESTURES ON ONE OBJECT, WHICH IS THE PART THAT CAN GO WRONG.
//
//  The parts drawer answers a pinch-drag two ways: across the strip
//  scrolls it, out of the drawer pulls a component onto the bench. There
//  is no mode switch, because a scroll bar beside the drawer would be a
//  control beside a control and the drawer exists to remove those.
//
//  So the whole design rests on one classification, and this project's
//  standing problem is that a rule living inside a gesture closure is a
//  rule nobody can test — `simctl` has no tap verb and XCUITest has no
//  entity API, so it would be verified by hand, in a headset, forever.
//  `DrawerGesture` is that rule lifted out into arithmetic. The
//  interesting cases are all here and none of them need a hand.
//
//  THE BIAS IS NOT 50/50 and that is the substance of the test. A hand
//  arcing out of a drawer drifts sideways as it goes — wrists rotate —
//  so a pull that only just beats its own sideways component is more
//  likely a scroll. The asymmetry is deliberate because the two failures
//  are not equal: a spurious scroll moves the strip somewhere you can
//  see and undo by scrolling back, while a spurious pull drops an
//  unwanted component onto a bench that persists across launches.
//

import XCTest
import RealityKit
import simd
@testable import PhysicsPlayground

@MainActor
final class PartsDrawerTests: XCTestCase {

    // MARK: The rule

    /// A hand that has barely moved has not said anything yet.
    ///
    /// Deciding early is how a tremor becomes a spawned component: the
    /// classifier runs every frame of a drag, so the first frame after
    /// the pinch lands is the one where travel is a millimetre of noise.
    func testATremorDecidesNothing() {
        XCTAssertEqual(DrawerGesture.classify(travel: .zero), .undecided)
        XCTAssertEqual(DrawerGesture.classify(travel: [0.004, 0, 0.003]),
                       .undecided)
        XCTAssertEqual(DrawerGesture.classify(travel: [0, 0, 0.011]),
                       .undecided,
                       "11 mm is inside the dead zone and must not spawn")
    }

    /// Sideways is a scroll, either way along the strip.
    func testTravellingAcrossTheStripScrolls() {
        XCTAssertEqual(DrawerGesture.classify(travel: [0.08, 0, 0]), .scroll)
        XCTAssertEqual(DrawerGesture.classify(travel: [-0.08, 0, 0]), .scroll)
        // With a little drift out of the drawer, which is what a real
        // sideways drag looks like.
        XCTAssertEqual(DrawerGesture.classify(travel: [0.08, 0, 0.03]), .scroll)
    }

    /// Straight out is a pull.
    func testTravellingOutOfTheDrawerPulls() {
        XCTAssertEqual(DrawerGesture.classify(travel: [0, 0, 0.09]), .pull)
        XCTAssertEqual(DrawerGesture.classify(travel: [0.02, 0, 0.09]), .pull)
    }

    /// THE ASYMMETRY, stated as a case rather than as a constant.
    ///
    /// A drag 40 mm out and 30 mm across is going out MORE than across —
    /// and it is still a scroll, because it does not beat the sideways
    /// component by the bias. This is the case that would spawn an
    /// unwanted part under a naive `abs(z) > abs(x)`.
    func testAnOutwardDragThatDriftsSidewaysIsStillAScroll() {
        XCTAssertEqual(DrawerGesture.classify(travel: [0.030, 0, 0.040]),
                       .scroll, """
                       a drag only 4:3 in favour of out is the shape of a \
                       sideways pull with wrist rotation in it — spawning here \
                       drops a component on a bench that persists across \
                       launches
                       """)
        // Beat it clearly and it is a pull.
        XCTAssertEqual(DrawerGesture.classify(travel: [0.030, 0, 0.060]), .pull)
    }

    /// PUSHING IN IS NEVER A PULL. Negative z is a hand moving away from
    /// the reader, into the cabinet; taking its magnitude would make
    /// shoving the strip backwards spawn a part.
    ///
    /// Asserted as "not a pull" rather than "is a scroll", and the first
    /// draft got that wrong. A hand travelling straight back has no
    /// sideways component at all, so there is nothing for it to scroll —
    /// `.undecided` is the correct answer and the test was demanding a
    /// decision the input does not contain. What actually matters is the
    /// half that cannot be allowed to happen.
    func testPushingIntoTheDrawerNeverSpawns() {
        for travel: SIMD3<Float> in [[0, 0, -0.20], [0.01, 0, -0.20],
                                     [0.05, 0, -0.20], [-0.05, 0, -0.30]] {
            XCTAssertNotEqual(DrawerGesture.classify(travel: travel), .pull,
                              "a hand moving into the cabinet spawned a part")
        }
        // With real sideways travel it is a scroll, push-back and all.
        XCTAssertEqual(DrawerGesture.classify(travel: [0.05, 0, -0.20]), .scroll)
    }

    // MARK: The drawer itself

    private func makeDrawer(count: Int = 6,
                            spawned: (@escaping () -> Void) = {}) -> PartsDrawer {
        PartsDrawer((0..<count).map { index in
            Well.Spec(name: "part\(index)", tint: .white,
                      label: "Part \(index)",
                      preview: {
                          ModelEntity(mesh: .generateSphere(radius: 0.018))
                      },
                      position: .zero,
                      spawn: { _ in spawned(); return UUID() })
        })
    }

    /// It opens shut, and a tap on the cabinet opens it.
    func testTheDrawerStartsClosed() {
        let drawer = makeDrawer()
        XCTAssertFalse(drawer.isOpen)
        XCTAssertTrue(drawer.handleTap(drawer.root))
        XCTAssertTrue(drawer.isOpen)
    }

    /// A tap that misses the cabinet entirely must fall through, or the
    /// drawer becomes a hole in that side of the room.
    func testATapElsewhereIsNotConsumed() {
        let drawer = makeDrawer()
        XCTAssertFalse(drawer.handleTap(Entity()))
    }

    /// THE PARTS DO NOT EXIST UNTIL THERE IS SOMEWHERE FOR THEM TO BE.
    ///
    /// Eleven components hanging in front of a shut cabinet is worse than
    /// the two columns of wells this replaced, which is the whole reason
    /// the drawer was asked for.
    func testAShutDrawerShowsNoParts() {
        let drawer = makeDrawer()
        for _ in 0..<60 { drawer.update(dt: 1 / 90) }
        let visible = drawer.root.findEntity(named: "drawer-part0")
        XCTAssertEqual(visible?.isEnabled, false)
    }

    func testAnOpenDrawerShowsThemAndSlidesOut() throws {
        let drawer = makeDrawer()
        _ = drawer.handleTap(drawer.root)
        for _ in 0..<120 { drawer.update(dt: 1 / 90) }

        let part = try XCTUnwrap(drawer.root.findEntity(named: "drawer-part0"))
        XCTAssertTrue(part.isEnabled)
        let body = try XCTUnwrap(drawer.root.findEntity(named: "parts-drawer"))
        XCTAssertEqual(body.position.z, PartsDrawer.travel, accuracy: 1e-3,
                       "the drawer did not ride out")
    }

    /// Scrolling must stop at both ends. A strip that runs past its last
    /// part leaves an empty drawer and no way to know which direction
    /// gets the parts back.
    func testScrollingStopsAtBothEnds() {
        let drawer = makeDrawer(count: 12)
        _ = drawer.handleTap(drawer.root)
        for _ in 0..<120 { drawer.update(dt: 1 / 90) }

        XCTAssertTrue(drawer.beginDrag(drawer.root, hand: .zero))
        // Far past the end, in both directions.
        _ = drawer.updateDrag(hand: [-5, 0, 0])
        drawer.update(dt: 1 / 90)
        let farLeft = drawer.root.findEntity(named: "drawer-part11")
        XCTAssertEqual(farLeft?.isEnabled, true,
                       "scrolled to the end and the last part is not in the mouth")

        drawer.endDrag()
        XCTAssertTrue(drawer.beginDrag(drawer.root, hand: .zero))
        _ = drawer.updateDrag(hand: [5, 0, 0])
        drawer.update(dt: 1 / 90)
        let farRight = drawer.root.findEntity(named: "drawer-part0")
        XCTAssertEqual(farRight?.isEnabled, true,
                       "scrolled back and the first part is not in the mouth")
        drawer.endDrag()
    }

    /// A PULL SPAWNS EXACTLY ONCE, however many frames the hand keeps
    /// moving. The drag callback runs every frame; returning the spec
    /// each time would put a component on the bench per frame.
    func testAPullSpawnsOnlyOnce() throws {
        let drawer = makeDrawer()
        _ = drawer.handleTap(drawer.root)
        for _ in 0..<120 { drawer.update(dt: 1 / 90) }

        let part = try XCTUnwrap(drawer.root.findEntity(named: "drawer-part0"))
        XCTAssertTrue(drawer.beginDrag(part, hand: .zero))

        var spawns = 0
        for step in 1...20 {
            if drawer.updateDrag(hand: [0, 0, Float(step) * 0.01]) != nil {
                spawns += 1
            }
        }
        XCTAssertEqual(spawns, 1, "a pull spawned \(spawns) components")
        drawer.endDrag()
    }

    /// …and a scroll never spawns, however far it goes.
    func testAScrollNeverSpawns() throws {
        let drawer = makeDrawer()
        _ = drawer.handleTap(drawer.root)
        for _ in 0..<120 { drawer.update(dt: 1 / 90) }

        let part = try XCTUnwrap(drawer.root.findEntity(named: "drawer-part1"))
        XCTAssertTrue(drawer.beginDrag(part, hand: .zero))
        for step in 1...20 {
            XCTAssertNil(drawer.updateDrag(hand: [Float(step) * -0.01, 0, 0.004]))
        }
        drawer.endDrag()
    }

    /// A tap on a part while the drawer is open must be consumed WITHOUT
    /// shutting it. Closing the drawer under a hand reaching into it is
    /// the rudest possible answer to a missed grab.
    func testTappingAPartDoesNotShutTheDrawer() throws {
        let drawer = makeDrawer()
        _ = drawer.handleTap(drawer.root)
        for _ in 0..<120 { drawer.update(dt: 1 / 90) }

        let part = try XCTUnwrap(drawer.root.findEntity(named: "drawer-part0"))
        XCTAssertTrue(drawer.handleTap(part))
        XCTAssertTrue(drawer.isOpen)
    }

    /// The multimeter stows inside, which is the whole point of it no
    /// longer standing beside the bench.
    func testAStowedInstrumentRidesTheStrip() {
        let drawer = makeDrawer()
        let meter = Entity()
        meter.name = "meter"
        drawer.stow(meter)
        XCTAssertNotNil(drawer.root.findEntity(named: "meter"))
    }
}
