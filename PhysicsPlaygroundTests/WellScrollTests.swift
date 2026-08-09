//
//  WellScrollTests.swift
//  PhysicsPlaygroundTests
//
//  A SHELF YOU CAN BOTH BROWSE AND TAKE FROM.
//
//  Circuit Workshop stands twelve kinds of part and the owner's note was
//  that twelve at once is a lot to look past. A window of six with a
//  scroll is the answer — and it means one pinch on one slot now has two
//  possible meanings, which is the part that can go wrong.
//
//  `ScrollGesture` is that decision, lifted out of the gesture closure
//  into arithmetic so it can be tested at all: `simctl` has no tap verb
//  and XCUITest has no entity API, so a rule left inside a closure is
//  verified by hand in a headset forever.
//
//  THE WINDOW IS OPT-IN, and that is the other thing worth pinning. Five
//  modules have three or four sources and want none of this; `Well` with
//  no `visibleCount` must behave exactly as it did before the feature
//  existed, or adding a window to one module changed the other five.
//

import XCTest
import RealityKit
import RenderKit
import simd
@testable import PhysicsPlayground

@MainActor
final class WellScrollTests: XCTestCase {

    private func rack(_ count: Int, visible: Int? = nil,
                      spawned: @escaping () -> Void = {}) -> Well {
        let specs = (0..<count).map { index in
            Well.Spec(name: "slot\(index)", tint: .white, label: "Slot \(index)",
                      preview: {
                          ModelEntity(mesh: .generateSphere(radius: 0.015))
                      },
                      position: CircuitsPartsLayout.rightSlot(index: index),
                      spawn: { _ in spawned(); return UUID() })
        }
        let well = Well(specs)
        well.visibleCount = visible
        well.update(dt: 1 / 90)
        return well
    }

    /// Asked of the well rather than walked out of the scene graph: the
    /// slots hang off a sliding rack inside `root` and the carets hang
    /// off `root` itself, and a test that knows that is a test that
    /// breaks when the hierarchy is rearranged for a reason it does not
    /// care about.
    private func enabledSlots(_ well: Well) -> [String] {
        (0..<well.slotCount).compactMap { index in
            guard let source = well.source(at: index), source.isEnabled else {
                return nil
            }
            return source.name
        }
    }

    /// The sliding strip — the thing that must move when you scroll, and
    /// must not when you do not.
    private func rackEntity(_ well: Well) throws -> Entity {
        try XCTUnwrap(well.root.children.first)
    }

    // MARK: The rule

    func testATremorDecidesNothing() {
        XCTAssertEqual(ScrollGesture.classify(travel: .zero, axis: .vertical),
                       .undecided)
        XCTAssertEqual(
            ScrollGesture.classify(travel: [0, 0.004, 0.003], axis: .vertical),
            .undecided)
    }

    func testTravellingAlongTheRackScrolls() {
        for travel: SIMD3<Float> in [[0, 0.08, 0], [0, -0.08, 0], [0, 0.08, 0.03]] {
            XCTAssertEqual(ScrollGesture.classify(travel: travel, axis: .vertical),
                           .scroll)
        }
    }

    func testTravellingOutOfTheRackPulls() {
        XCTAssertEqual(ScrollGesture.classify(travel: [0, 0, 0.09], axis: .vertical),
                       .pull)
        XCTAssertEqual(
            ScrollGesture.classify(travel: [0, 0.02, 0.09], axis: .vertical), .pull)
    }

    /// THE ASYMMETRY. A drag 40 mm out and 30 mm along is going out MORE
    /// than along and is still a browse, because it does not beat the
    /// along-component by the bias. This is the case a naive
    /// `abs(z) > abs(y)` would spawn on — and a spurious spawn drops an
    /// unwanted part on a bench that persists across launches, where a
    /// spurious scroll is undone by scrolling back.
    func testAnOutwardDragThatDriftsAlongIsStillAScroll() {
        XCTAssertEqual(
            ScrollGesture.classify(travel: [0, 0.030, 0.040], axis: .vertical),
            .scroll)
        XCTAssertEqual(
            ScrollGesture.classify(travel: [0, 0.030, 0.060], axis: .vertical),
            .pull)
    }

    /// Pushing INTO the rack is never taking from it.
    func testPushingIntoTheRackNeverPulls() {
        for travel: SIMD3<Float> in [[0, 0, -0.2], [0, 0.05, -0.2], [0, -0.05, -0.3]] {
            XCTAssertNotEqual(
                ScrollGesture.classify(travel: travel, axis: .vertical), .pull)
        }
    }

    /// The axis matters: the same travel is a scroll on a vertical rack
    /// and a pull on a horizontal one.
    func testTheAxisDecidesWhatCountsAsAlong() {
        let travel = SIMD3<Float>(0, 0.09, 0)
        XCTAssertEqual(ScrollGesture.classify(travel: travel, axis: .vertical),
                       .scroll)
        XCTAssertEqual(ScrollGesture.classify(travel: travel, axis: .horizontal),
                       .undecided,
                       "no travel along a horizontal rack and none out of it")
    }

    // MARK: The window

    /// THE FEATURE IS OPT-IN. Five modules never asked for it.
    func testAWellWithNoWindowShowsEverything() throws {
        let well = rack(9)
        XCTAssertEqual(enabledSlots(well).count, 9)
        XCTAssertEqual(try rackEntity(well).position.y, 0,
                       "a well with no window moved its rack")
    }

    func testAWindowedRackShowsExactlyItsWindow() {
        let well = rack(12, visible: 6)
        XCTAssertEqual(enabledSlots(well).count, 6)
        XCTAssertTrue(enabledSlots(well).contains("well-slot0"))
        XCTAssertFalse(enabledSlots(well).contains("well-slot6"))
    }

    /// Scrolling moves the window, and the rack slides so the window
    /// stays where the first slot was authored — otherwise the parts
    /// would walk down the room as you browsed.
    func testScrollingMovesTheWindowAndNotTheHole() throws {
        let well = rack(12, visible: 6)
        let restingY = try rackEntity(well).position.y
        well.scroll(by: 3)
        well.update(dt: 1 / 90)

        XCTAssertFalse(enabledSlots(well).contains("well-slot0"))
        XCTAssertTrue(enabledSlots(well).contains("well-slot3"))
        XCTAssertTrue(enabledSlots(well).contains("well-slot8"))
        XCTAssertEqual(enabledSlots(well).count, 6)

        // Slot 3 now sits where slot 0 used to: the rack lifted by
        // exactly three pitches.
        let pitch = CircuitsPartsLayout.rightRowPitch
        XCTAssertEqual(try rackEntity(well).position.y,
                       restingY + 3 * pitch, accuracy: 1e-5)
    }

    /// It must stop at both ends. A rack scrolled past its last slot is
    /// an empty shelf with no clue which way gets the parts back.
    func testScrollingStopsAtBothEnds() {
        let well = rack(12, visible: 6)
        well.scroll(by: 99)
        well.update(dt: 1 / 90)
        XCTAssertTrue(enabledSlots(well).contains("well-slot11"),
                      "scrolled to the end and the last slot is not shown")
        XCTAssertEqual(enabledSlots(well).count, 6)
        XCTAssertFalse(well.canScrollDown)

        well.scroll(by: -99)
        well.update(dt: 1 / 90)
        XCTAssertTrue(enabledSlots(well).contains("well-slot0"))
        XCTAssertFalse(well.canScrollUp)
    }

    /// A rack shorter than its window does not scroll at all.
    func testAShortRackDoesNotScroll() {
        let well = rack(4, visible: 6)
        well.scroll(by: 2)
        well.update(dt: 1 / 90)
        XCTAssertEqual(enabledSlots(well).count, 4)
        XCTAssertFalse(well.canScrollUp)
        XCTAssertFalse(well.canScrollDown)
    }

    // MARK: Dragging it

    func testDraggingAlongTheRackScrollsItAndSpawnsNothing() throws {
        var spawns = 0
        let well = rack(12, visible: 6, spawned: { spawns += 1 })
        let slot = try XCTUnwrap(well.source(at: 1))
        XCTAssertTrue(well.beginDrag(slot, hand: .zero))
        for step in 1...12 {
            XCTAssertNil(well.updateDrag(hand: [0, -Float(step) * 0.02, 0.003]))
        }
        well.update(dt: 1 / 90)
        well.endDrag()

        XCTAssertEqual(spawns, 0, "browsing the rack spawned \(spawns) parts")
        XCTAssertTrue(well.canScrollUp, "the rack did not move")
    }

    /// A pull resolves ONCE, however many frames the hand keeps going.
    func testPullingResolvesExactlyOnce() throws {
        let well = rack(12, visible: 6)
        let slot = try XCTUnwrap(well.source(at: 2))
        XCTAssertTrue(well.beginDrag(slot, hand: .zero))
        var resolved: [Int] = []
        for step in 1...20 {
            if let index = well.updateDrag(hand: [0, 0, Float(step) * 0.01]) {
                resolved.append(index)
            }
        }
        well.endDrag()
        XCTAssertEqual(resolved, [2],
                       "a pull resolved \(resolved.count) times: \(resolved)")
    }

    // MARK: The affordance

    private func caret(_ well: Well, _ direction: String) -> Entity? {
        well.root.children.first { $0.name == "\(Well.caretName)-\(direction)" }
    }

    /// A RACK WITH NO MARK IS A RACK OF SIX. The parts a user cannot see
    /// are the ones they will not build with, and a drag is invisible —
    /// so the window has to say that it is a window.
    ///
    /// This test exists because the first version of the scroll shipped
    /// `canScrollUp`/`canScrollDown` with a comment saying "the caller
    /// draws whatever tells the user so", and no caller did.
    func testTheRackSaysWhenThereIsMore() throws {
        let well = rack(12, visible: 6)
        XCTAssertEqual(caret(well, "up")?.isEnabled, false,
                       "an up caret at the top of the rack points nowhere")
        XCTAssertEqual(caret(well, "down")?.isEnabled, true,
                       "six of twelve are hidden and nothing says so")

        well.scroll(by: 6)
        well.update(dt: 1 / 90)
        XCTAssertEqual(caret(well, "up")?.isEnabled, true)
        XCTAssertEqual(caret(well, "down")?.isEnabled, false,
                       "a down caret at the end of the rack points nowhere")
    }

    /// …and a rack that fits has no carets at all.
    func testAShortRackHasNoCarets() {
        let well = rack(4, visible: 6)
        XCTAssertNil(caret(well, "up"))
        XCTAssertNil(caret(well, "down"))
    }

    /// PRESSING ONE MOVES A PAGE. At six of twelve that is one press to
    /// the end — stepping a slot at a time would be six presses to learn
    /// what is down there.
    func testPressingACaretMovesAWholePage() throws {
        let well = rack(12, visible: 6)
        let down = try XCTUnwrap(caret(well, "down"))
        XCTAssertTrue(well.handleTap(down))
        well.update(dt: 1 / 90)
        XCTAssertTrue(enabledSlots(well).contains("well-slot11"))
        XCTAssertFalse(enabledSlots(well).contains("well-slot0"))
    }

    /// The carets are operable without hands — they are the ONLY route
    /// for a VoiceOver user, who cannot drag the rack at all.
    func testTheCaretsWorkWithoutHands() throws {
        let well = rack(12, visible: 6)
        let down = try XCTUnwrap(caret(well, "down"))
        XCTAssertTrue(SpatialActions.activate(down),
                      "the caret announces itself and cannot be pressed")
        well.update(dt: 1 / 90)
        XCTAssertTrue(well.canScrollUp, "activating the caret did not scroll")
    }

    /// A tap that misses them falls through, or the rack becomes a hole
    /// in that side of the room.
    func testATapElsewhereIsNotConsumed() {
        let well = rack(12, visible: 6)
        XCTAssertFalse(well.handleTap(Entity()))
    }

    // MARK: The one-of-a-kind slot

    /// A `handOver` slot gives up the object it parks and reports NO new
    /// id — the caller has nothing to drag because the thing already
    /// existed. It must not read as a refusal.
    func testAHandOverSlotHandsOverInsteadOfSpawning() throws {
        var handed: SIMD3<Double>?
        var spawns = 0
        let spec = Well.Spec(
            name: "multimeter", tint: .white, label: "Multimeter",
            preview: { ModelEntity(mesh: .generateSphere(radius: 0.015)) },
            position: .zero,
            spawn: { _ in spawns += 1; return UUID() },
            handOver: { handed = $0 })
        let well = Well([spec])
        well.update(dt: 1 / 90)

        let source = try XCTUnwrap(well.source(at: 0))
        let id = well.pull(source, at: SIMD3(1, 2, 3))

        XCTAssertNil(id, "a one-of-a-kind slot minted a new object")
        XCTAssertEqual(spawns, 0, "`spawn` ran on a slot that parks an object")
        XCTAssertEqual(handed, SIMD3(1, 2, 3),
                       "the instrument was not handed to the hand's position")
    }
}
