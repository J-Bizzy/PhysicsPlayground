//
//  WellScrollTests.swift
//  PhysicsPlaygroundTests
//
//  A shelf you can both browse and take from: a drag on a slot is the
//  caller's pull, the crown is the one thing that scrolls and the column
//  rides it one to one, the crown turns with the column, the window
//  fades at its ends, and nothing stands behind the parts.
//

import XCTest
import RealityKit
import RenderKit
import simd
@testable import PhysicsPlayground

@MainActor
final class WellScrollTests: XCTestCase {

    private func rack(_ count: Int, visible: Int? = nil,
                      facing: SIMD3<Float>? = nil,
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
        well.facing = facing
        well.windowTitle = "Parts"
        well.visibleCount = visible
        well.update(dt: 1 / 90)
        return well
    }

    private func enabledSlots(_ well: Well) -> [String] {
        (0..<well.slotCount).compactMap { index in
            guard let source = well.source(at: index), source.isEnabled else {
                return nil
            }
            return source.name
        }
    }

    /// The sliding strip: `root`'s first child.
    private func rackEntity(_ well: Well) throws -> Entity {
        try XCTUnwrap(well.root.children.first)
    }

    private func settle(_ well: Well, frames: Int = 400) {
        for _ in 0..<frames where !well.isSettled {
            well.update(dt: 1 / 90)
        }
    }

    private let pitch = CircuitsPartsLayout.rightRowPitch

    // MARK: The window

    /// The window is opt-in: a well without one behaves as it always did.
    func testAWellWithNoWindowShowsEverything() throws {
        let well = rack(9)
        XCTAssertEqual(enabledSlots(well).count, 9)
        XCTAssertEqual(try rackEntity(well).position.y, 0,
                       "a well with no window moved its rack")
        XCTAssertNil(well.shelfEntity, "a well with no window grew a shelf")
        XCTAssertNil(well.crown)
        for index in 0..<9 {
            XCTAssertEqual(well.windowOpacity(at: index), 1)
        }
    }

    func testAWindowedRackShowsExactlyItsWindow() {
        let well = rack(12, visible: 6)
        XCTAssertEqual(enabledSlots(well).count, 6)
        XCTAssertTrue(enabledSlots(well).contains("well-slot0"))
        XCTAssertFalse(enabledSlots(well).contains("well-slot6"))
    }

    /// Scrolling moves the window; the rack slides so the window stays
    /// where the first slot was authored.
    func testScrollingMovesTheWindowAndNotTheHole() throws {
        let well = rack(12, visible: 6)
        let restingY = try rackEntity(well).position.y
        well.scroll(by: 3)
        well.update(dt: 1 / 90)

        XCTAssertFalse(enabledSlots(well).contains("well-slot0"))
        XCTAssertTrue(enabledSlots(well).contains("well-slot3"))
        XCTAssertTrue(enabledSlots(well).contains("well-slot8"))
        XCTAssertEqual(enabledSlots(well).count, 6)

        XCTAssertEqual(try rackEntity(well).position.y,
                       restingY + 3 * pitch, accuracy: 1e-5)
    }

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

    func testAShortRackDoesNotScroll() {
        let well = rack(4, visible: 6)
        well.scroll(by: 2)
        well.update(dt: 1 / 90)
        XCTAssertEqual(enabledSlots(well).count, 4)
        XCTAssertFalse(well.canScrollUp)
        XCTAssertFalse(well.canScrollDown)
    }

    // MARK: A drag on a slot is a pull, never a scroll

    /// The shelf never claims a drag that starts on a part: that drag is
    /// the caller's pull, whichever way the hand goes.
    func testDraggingASlotIsNeverAScroll() throws {
        let well = rack(12, visible: 6)
        let slot = try XCTUnwrap(well.source(at: 1))
        XCTAssertFalse(well.beginDrag(slot, hand: .zero))
        XCTAssertFalse(well.isDragging)
        XCTAssertEqual(well.scrollOffset, 0)
        XCTAssertEqual(well.sourceIndex(of: slot), 1, "a slot knows its index")
        XCTAssertNil(well.sourceIndex(of: try XCTUnwrap(well.crown)))
    }

    // MARK: The crown

    /// The crown is the handle, and the column rides the hand one to one:
    /// roll it up and the later slots come up. Nothing spawns.
    func testRollingTheCrownScrollsTheRackOneToOneAndSpawnsNothing() throws {
        var spawns = 0
        let well = rack(12, visible: 6, spawned: { spawns += 1 })
        let crown = try XCTUnwrap(well.crown)
        XCTAssertTrue(well.beginDrag(crown, hand: .zero))
        XCTAssertTrue(well.isDragging)
        for step in 1...12 {
            well.updateDrag(hand: [0, Float(step) * 0.01, 0])
            well.update(dt: 1 / 90)
        }
        XCTAssertEqual(well.scrollOffset, 0.12, accuracy: 1e-5,
                       "the strip did not follow the hand one to one")
        XCTAssertTrue(enabledSlots(well).contains("well-slot6"),
                      "rolling the crown up did not bring the next slot up")
        XCTAssertFalse(enabledSlots(well).contains("well-slot0"))
        // The hand comes to rest before letting go, so there is no flick.
        for _ in 0..<30 { well.update(dt: 1 / 90) }
        well.endDrag()
        XCTAssertFalse(well.isDragging)
        settle(well)

        XCTAssertEqual(spawns, 0, "scrolling by the crown spawned \(spawns) parts")
        XCTAssertTrue(well.canScrollUp, "the rack did not move")
        let slots = (well.scrollOffset / pitch).rounded()
        XCTAssertEqual(well.scrollOffset, slots * pitch, accuracy: 1e-5,
                       "the release did not settle on a whole slot")
        XCTAssertEqual(well.scrollIndex, Int(slots))
    }

    /// The regression. The scene's one drag gesture reports the crown on
    /// every frame, so the view presses it every frame; a press that
    /// re-anchored the grab measured zero travel and the thumb this
    /// replaced never moved by hand at all.
    func testAPressRepeatedEveryFrameStillScrolls() throws {
        let well = rack(12, visible: 6)
        let crown = try XCTUnwrap(well.crown)
        for step in 0...12 {
            let hand = SIMD3<Float>(0, Float(step) * 0.008, 0)
            XCTAssertTrue(well.beginDrag(crown, hand: hand),
                          "a crown already held refused the gesture that holds it")
            well.updateDrag(hand: hand)
            well.update(dt: 1 / 90)
        }
        XCTAssertEqual(well.scrollOffset, 12 * 0.008, accuracy: 1e-5, """
            re-pressing the crown every frame moved the grab under the hand: \
            the strip travelled \(well.scrollOffset) m for 0.096 m of hand.
            """)
        well.endDrag()
    }

    /// The whole rack passes under the hand: a long enough roll puts the
    /// last slot in the window.
    func testALongRollReachesTheLastSlot() throws {
        let well = rack(12, visible: 6)
        let crown = try XCTUnwrap(well.crown)
        XCTAssertTrue(well.beginDrag(crown, hand: .zero))
        well.updateDrag(hand: [0, 1.0, 0])
        for _ in 0..<30 { well.update(dt: 1 / 90) }
        well.endDrag()
        settle(well)
        XCTAssertTrue(enabledSlots(well).contains("well-slot11"))
        XCTAssertFalse(well.canScrollDown)
    }

    func testRollingTheCrownDownAtTheTopOnlyStretchesTheEnd() throws {
        let well = rack(12, visible: 6)
        let crown = try XCTUnwrap(well.crown)
        XCTAssertTrue(well.beginDrag(crown, hand: .zero))
        well.updateDrag(hand: [0, -0.10, 0])
        XCTAssertLessThan(well.scrollOffset, 0)
        XCTAssertGreaterThan(well.scrollOffset, -0.10, "the end did not resist")
        well.endDrag()
        settle(well)
        XCTAssertEqual(well.scrollOffset, 0, accuracy: 1e-5)
        XCTAssertEqual(enabledSlots(well).count, 6)
    }

    /// The crown turns for the column's travel, arc over radius, its
    /// front face rolling the way the strip goes — so at rest it reads
    /// out where the shelf is.
    func testTheCrownTurnsWithTheColumn() throws {
        let well = rack(12, visible: 6)
        let crown = try XCTUnwrap(well.crown)
        let spindle = try XCTUnwrap(well.crownSpindle)
        XCTAssertEqual(well.crownAngle, 0)
        XCTAssertEqual(spindle.orientation.angle, 0, accuracy: 1e-5)

        XCTAssertTrue(well.beginDrag(crown, hand: .zero))
        well.updateDrag(hand: [0, 0.02, 0])
        well.update(dt: 1 / 90)
        XCTAssertEqual(abs(well.crownAngle), 0.02 / Well.Rack.crownRadius, accuracy: 1e-5)
        XCTAssertEqual(spindle.orientation.angle, 0.02 / Well.Rack.crownRadius,
                       accuracy: 1e-4, "the crown did not turn for the strip's travel")
        // The point on the rim nearest the viewer moved up with the hand.
        XCTAssertGreaterThan(spindle.orientation.act([0, 0, 1]).y, 0,
                             "the crown's front face rolled against the hand")
        // The hand rests before letting go, so the release is not a flick.
        for _ in 0..<30 { well.update(dt: 1 / 90) }
        well.endDrag()
        settle(well)
        XCTAssertEqual(well.scrollIndex, 0)

        well.scroll(by: 3)
        well.update(dt: 1 / 90)
        XCTAssertEqual(abs(well.crownAngle), 3 * pitch / Well.Rack.crownRadius,
                       accuracy: 1e-4)
        XCTAssertEqual(spindle.orientation.angle,
                       (3 * pitch / Well.Rack.crownRadius)
                           .truncatingRemainder(dividingBy: 2 * .pi),
                       accuracy: 1e-3)
    }

    /// A slot leaving the window fades over part of a pitch rather than
    /// vanishing at the edge.
    func testASlotAtTheWindowsEdgeFadesRatherThanPops() throws {
        let well = rack(12, visible: 6)
        let crown = try XCTUnwrap(well.crown)
        XCTAssertTrue(well.beginDrag(crown, hand: .zero))
        well.updateDrag(hand: [0, 0.5 * pitch, 0])
        well.update(dt: 1 / 90)
        let leaving = well.windowOpacity(at: 0)
        XCTAssertGreaterThan(leaving, 0, "the first slot vanished at once")
        XCTAssertLessThan(leaving, 1, "the first slot has not started to fade")
        XCTAssertEqual(well.windowOpacity(at: 3), 1, "a slot mid-window faded")
        let arriving = well.windowOpacity(at: 6)
        XCTAssertGreaterThan(arriving, 0, "the seventh slot has not started to arrive")
        XCTAssertLessThan(arriving, 1)
        XCTAssertEqual(
            try XCTUnwrap(well.source(at: 0)?.components[OpacityComponent.self]).opacity,
            leaving, accuracy: 1e-4, "the fade is not what the slot wears")
        well.endDrag()
    }

    /// A shelf faced at the viewer turns its slots and its furniture with
    /// one yaw, and still reads the crown along the column.
    func testAFacedShelfTurnsWithOneYaw() throws {
        let viewer = CircuitsPartsLayout.viewer
        let well = rack(12, visible: 6, facing: viewer)
        let yaw = Well.Rack.yaw(from: CircuitsPartsLayout.rightSlot(index: 0), toward: viewer)
        XCTAssertNotEqual(yaw, 0)
        let slot = try XCTUnwrap(well.source(at: 2))
        XCTAssertEqual(slot.orientation.angle, abs(yaw), accuracy: 1e-4,
                       "the slot did not turn to face the viewer")
        let shelf = try XCTUnwrap(well.shelfEntity)
        XCTAssertEqual(shelf.orientation.angle, abs(yaw), accuracy: 1e-4,
                       "the shelf did not turn with its slots")
        let crown = try XCTUnwrap(well.crown)
        XCTAssertTrue(well.beginDrag(crown, hand: .zero))
        well.updateDrag(hand: [0.03, 0.05, -0.02])
        XCTAssertEqual(well.scrollOffset, 0.05, accuracy: 1e-5,
                       "a faced shelf did not read the hand along its column")
        well.endDrag()
    }

    // MARK: The arrival

    /// The column arrives coasting up into place with the crown rolling,
    /// and lands exactly where it was.
    func testTheColumnArrivesCoastingIntoPlace() throws {
        let well = rack(12, visible: 6)
        well.arrive()
        XCTAssertFalse(well.isSettled, "the arrival did not move the column")
        XCTAssertLessThan(well.scrollOffset, 0, "the column arrives from below")
        XCTAssertNotEqual(well.crownAngle, 0, "the crown is not rolling with the arrival")
        well.update(dt: 1 / 90)
        XCTAssertEqual(enabledSlots(well).count, 6,
                       "the arrival showed a slot outside the window")
        settle(well)
        XCTAssertEqual(well.scrollOffset, 0, accuracy: 1e-5)
        XCTAssertEqual(well.scrollIndex, 0)
        XCTAssertEqual(well.crownAngle, 0, accuracy: 1e-5)
    }

    /// From wherever the window stands — a debug scroll survives it.
    func testTheArrivalKeepsAScrolledWindow() {
        let well = rack(12, visible: 6)
        well.scroll(by: 4)
        well.arrive()
        XCTAssertLessThan(well.scrollOffset, 4 * pitch)
        XCTAssertGreaterThan(well.scrollOffset, 3 * pitch)
        settle(well)
        XCTAssertEqual(well.scrollOffset, 4 * pitch, accuracy: 1e-5)
        XCTAssertEqual(well.scrollIndex, 4)
    }

    /// The arrival is gentler than a hand's settle: it is there to be
    /// seen, and a snap that finishes during the fade-in is not.
    func testTheArrivalIsSlowerThanAHandsSettle() throws {
        let arriving = rack(12, visible: 6)
        arriving.arrive()
        let released = rack(12, visible: 6)
        let crown = try XCTUnwrap(released.crown)
        XCTAssertTrue(released.beginDrag(crown, hand: .zero))
        released.updateDrag(hand: [0, -Well.Rack.arrivalDrop * pitch, 0])
        released.endDrag()
        let start = arriving.scrollOffset
        for _ in 0..<20 {
            arriving.update(dt: 1 / 90)
            released.update(dt: 1 / 90)
        }
        XCTAssertLessThan(abs(released.scrollOffset), abs(arriving.scrollOffset),
                          "the arrival closes as fast as a hand's settle")
        XCTAssertGreaterThan(arriving.scrollOffset, start, "the arrival is not closing")
    }

    func testAShortShelfHasNoArrival() {
        let well = rack(4, visible: 6)
        well.arrive()
        XCTAssertTrue(well.isSettled)
        XCTAssertEqual(well.scrollOffset, 0)
    }

    // MARK: The shelf's furniture

    /// Nothing stands behind the parts: no pane, no box, no target on the
    /// shelf itself — only the title above, the spine beside, and the
    /// crown on it.
    func testAWindowedRackHasNoPane() throws {
        let well = rack(12, visible: 6)
        let shelf = try XCTUnwrap(well.shelfEntity)
        XCTAssertNil(shelf.components[CollisionComponent.self])
        XCTAssertNil(shelf.components[InputTargetComponent.self])
        var widest: Float = 0
        func walk(_ entity: Entity) {
            if let model = entity as? ModelEntity, let mesh = model.model?.mesh {
                widest = max(widest, mesh.bounds.extents.x)
            }
            for child in entity.children { walk(child) }
        }
        walk(shelf)
        XCTAssertLessThan(widest, 0.10, "something \(widest) m wide stands behind the parts")
        let track = Well.Rack.track(head: CircuitsPartsLayout.rightSlot(index: 0),
                                    pitch: pitch, visible: 6, facing: nil)
        XCTAssertEqual(track.length, 5 * pitch + 2 * Well.Rack.trackOverhang,
                       accuracy: 1e-6)
        XCTAssertEqual(track.center.x,
                       CircuitsPartsLayout.rightSlot(index: 0).x + Well.Rack.trackOffset,
                       accuracy: 1e-6, "the spine does not stand beside the column")
    }

    /// The crown stands on the spine at the window's middle, edge-on to
    /// the viewer, and its pinch target is no larger than the collider
    /// rule allows for the wheel it represents.
    func testTheCrownStandsOnTheSpineAndFitsItsTarget() throws {
        let well = rack(12, visible: 6)
        let crown = try XCTUnwrap(well.crown)
        let shelf = try XCTUnwrap(well.shelfEntity)
        let head = CircuitsPartsLayout.rightSlot(index: 0)
        let at = crown.position(relativeTo: nil)
        XCTAssertEqual(at.x, head.x + Well.Rack.trackOffset, accuracy: 1e-5)
        XCTAssertEqual(at.y, head.y - 2.5 * pitch, accuracy: 1e-5,
                       "the crown is not at the window's middle")
        XCTAssertEqual(at.z, head.z + Well.Rack.crownLift, accuracy: 1e-5)
        XCTAssertTrue(crown.isDescendant(of: shelf))

        XCTAssertNotNil(crown.components[InputTargetComponent.self])
        XCTAssertNotNil(crown.components[HoverEffectComponent.self])
        let shapes = try XCTUnwrap(crown.components[CollisionComponent.self]).shapes
        XCTAssertEqual(shapes.count, 1)
        let target = shapes[0].bounds.extents
        let visual = crown.visualBounds(relativeTo: crown).extents
        for (axis, v, c) in [("x", visual.x, target.x), ("y", visual.y, target.y),
                             ("z", visual.z, target.z)] {
            let allowed = max(v * 1.15, v + 0.03)
            XCTAssertLessThanOrEqual(c, allowed + 1e-4,
                                     "the crown's target is \(c) m on \(axis) for a \(v) m wheel")
            XCTAssertGreaterThan(c, v - 1e-4, "the crown's target is smaller than the crown")
        }
        // The milled wheel is what stands there: as wide across as the
        // spine's offset leaves room for, and round the other two ways.
        XCTAssertEqual(visual.y, 2 * Well.Rack.crownRadius, accuracy: 0.002)
        XCTAssertEqual(visual.z, 2 * Well.Rack.crownRadius, accuracy: 0.002)
        XCTAssertLessThan(visual.x, visual.y, "the crown stands on end")
    }

    /// The crown's placement box is what the placement tests measure, and
    /// it agrees with the built crown.
    func testTheCrownsBoxIsWhereTheCrownIs() throws {
        let viewer = CircuitsPartsLayout.viewer
        let well = rack(12, visible: 6, facing: viewer)
        let crown = try XCTUnwrap(well.crown)
        let box = Well.Rack.crown(head: CircuitsPartsLayout.rightSlot(index: 0),
                                  pitch: pitch, visible: 6, facing: viewer)
        let at = crown.position(relativeTo: nil)
        XCTAssertEqual(simd_distance(at, box.center), 0, accuracy: 1e-4,
                       "the crown's box is centred \(box.center), the crown at \(at)")
        let extents = crown.visualBounds(relativeTo: nil).extents
        XCTAssertGreaterThanOrEqual(box.halfExtents.x * 2 + 1e-4, extents.x)
        XCTAssertGreaterThanOrEqual(box.halfExtents.y * 2 + 1e-4, extents.y)
        XCTAssertGreaterThanOrEqual(box.halfExtents.z * 2 + 1e-4, extents.z)
    }

    func testAShortShelfHasNoCrown() {
        let well = rack(4, visible: 6)
        XCTAssertNotNil(well.shelfEntity)
        XCTAssertNil(well.crown)
    }

    /// VoiceOver cannot roll a wheel: adjusting the crown pages the shelf.
    func testTheShelfPagesWithoutHands() throws {
        let well = rack(12, visible: 6)
        let crown = try XCTUnwrap(well.crown)
        let accessibility = try XCTUnwrap(crown.components[AccessibilityComponent.self])
        XCTAssertEqual(accessibility.value.map(String.init(localized:)), "1 to 6 of 12")
        XCTAssertTrue(SpatialActions.adjust(crown, by: 1),
                      "the crown announces itself and cannot be adjusted")
        well.update(dt: 1 / 90)
        XCTAssertTrue(enabledSlots(well).contains("well-slot11"))
        XCTAssertFalse(enabledSlots(well).contains("well-slot0"))
        let after = try XCTUnwrap(crown.components[AccessibilityComponent.self])
        XCTAssertEqual(after.value.map(String.init(localized:)), "7 to 12 of 12")
        XCTAssertTrue(SpatialActions.adjust(crown, by: -1))
        well.update(dt: 1 / 90)
        XCTAssertTrue(enabledSlots(well).contains("well-slot0"))
    }

    func testATapOnTheCrownIsSwallowedAndATapElsewhereIsNot() throws {
        let well = rack(12, visible: 6)
        XCTAssertTrue(well.handleTap(try XCTUnwrap(well.crown)))
        XCTAssertFalse(well.handleTap(Entity()))
        XCTAssertFalse(well.handleTap(try XCTUnwrap(well.source(at: 0))),
                       "a tap on a slot is the caller's, not the shelf's")
    }

    // MARK: The one-of-a-kind slot

    /// A `handOver` slot gives up the object it parks and reports no new
    /// id — a success, not a refusal.
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
