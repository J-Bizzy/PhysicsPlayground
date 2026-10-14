//
//  SpatialTrackControlTests.swift
//  PhysicsPlaygroundTests
//
//  The control: the entity it builds, the model it writes, and the
//  guards around both (`TrackLayoutTests` covers the arithmetic). Its
//  first real caller found three defects in code that had never run.
//

import XCTest
import RealityKit
import simd
import RenderKit

@MainActor
final class SpatialTrackControlTests: XCTestCase {

    private let length = 0.26

    /// One part per million of the test range: a hand arrives as Double but
    /// is measured against a Float `root.position`, so every value carries
    /// float epsilon. Exact equality is still demanded where the code clamps.
    private let tolerance = 1e-4

    /// A track over 0…100, sitting at the origin facing +z, with its value
    /// in a box the test can read back.
    private func makeTrack(value: Box = Box(),
                           range: ClosedRange<Double> = 0...100,
                           center: SIMD3<Float> = .zero,
                           normal: SIMD3<Float> = [0, 0, 1])
    -> (SpatialTrackControl, Box) {
        let track = SpatialTrackControl(
            name: "Test", center: center, normal: normal, accent: .white,
            range: range, layout: TrackLayout(length: length),
            read: { value.value }, write: { value.value = $0 },
            format: { String(format: "%.0f", $0) })
        return (track, value)
    }

    final class Box {
        var value: Double = 0
    }

    // MARK: Operable without hands




    // MARK: The mapping, through the entity

    /// The claim the bead makes by existing: where your hand is along the
    /// rail is the value. Both ends and the middle, because a mapping that
    /// is right in the middle and wrong at the ends is the classic
    /// off-by-half-a-length error.
    func testTheHandsPlaceAlongTheRailIsTheValue() {
        let (track, box) = makeTrack()

        track.adjust(hand: SIMD3(-length / 2, 0, 0))
        XCTAssertEqual(box.value, 0, accuracy: tolerance,
                       "The low end of the rail must be the low end of the range.")

        track.adjust(hand: SIMD3(length / 2, 0, 0))
        XCTAssertEqual(box.value, 100, accuracy: tolerance,
                       "The high end of the rail must be the high end of the range.")

        track.adjust(hand: SIMD3(0, 0, 0))
        XCTAssertEqual(box.value, 50, accuracy: tolerance,
                       "Half way along the rail must be half way through the range.")
    }

    /// Absolute, not relative — the difference from the dial this control
    /// replaced. A hand arriving at the same place always means the same
    /// value, no matter what path it took or where the drag began.
    func testTheSameHandPositionAlwaysMeansTheSameValue() {
        let (track, box) = makeTrack()

        track.adjust(hand: SIMD3(0.05, 0, 0))
        let direct = box.value

        // The scenic route: several intermediate positions, ending in the
        // same place. A dial would have accumulated all of it.
        for x in [-0.13, 0.13, -0.04, 0.09, 0.05] {
            track.adjust(hand: SIMD3(x, 0, 0))
        }
        XCTAssertEqual(box.value, direct, accuracy: tolerance,
                       "A track has nothing to accumulate; the path must not matter.")
    }

    /// A hand drifts while it drags. Only the along-rail component may
    /// count, or the value slides as the wrist wanders.
    func testOffAxisDriftDoesNotMoveTheValue() {
        let (track, box) = makeTrack()

        track.adjust(hand: SIMD3(0.04, 0, 0))
        let level = box.value

        for drift in [SIMD3(0.04, 0.20, 0), SIMD3(0.04, -0.15, 0.3),
                      SIMD3(0.04, 0, -0.4)] {
            track.adjust(hand: drift)
            XCTAssertEqual(box.value, level, accuracy: tolerance,
                           "Drift off the rail changed the value.")
        }
    }

    /// Reaching past the end pins to the end rather than running off the
    /// scale — a range has ends, and a hand can always go further.
    func testReachingPastTheEndPinsToTheEnd() {
        let (track, box) = makeTrack()

        // Exactly, not approximately: reaching past an end goes through
        // `min`/`max` at the bound, so no float slop can survive. If this
        // one ever needs a tolerance, the clamp has stopped clamping.
        track.adjust(hand: SIMD3(-5, 0, 0))
        XCTAssertEqual(box.value, 0)

        track.adjust(hand: SIMD3(5, 0, 0))
        XCTAssertEqual(box.value, 100)
    }

    /// The rail is placed in the parent's space and may be turned to face
    /// its reader; the mapping must survive both.
    func testTheMappingSurvivesBeingMovedAndTurned() {
        let box = Box()
        let (track, _) = makeTrack(value: box,
                                   center: [0.85, 1.2, -0.5],
                                   normal: [1, 0, 0.3])

        // The rail's own +x axis, in parent space, at the far end.
        let along = track.root.orientation.act(SIMD3<Float>(1, 0, 0))
        let farEnd = track.root.position + along * Float(length / 2)
        track.adjust(hand: SIMD3<Double>(farEnd))
        XCTAssertEqual(box.value, 100, accuracy: 1e-4,
                       "A moved and turned rail must still map its own ends.")

        let nearEnd = track.root.position - along * Float(length / 2)
        track.adjust(hand: SIMD3<Double>(nearEnd))
        XCTAssertEqual(box.value, 0, accuracy: 1e-4)
    }

    // MARK: The bead reads the model back

    /// `refresh()` is the caller's obligation and the reason the bead can
    /// be trusted: a reset, an experiment or a debug launch arg changes the
    /// model without touching the control, and the bead must move anyway.
    func testRefreshMovesTheBeadToAValueNobodyDragged() {
        let (track, box) = makeTrack()

        track.adjust(hand: SIMD3(-length / 2, 0, 0))
        let low = beadX(track)

        box.value = 100          // as a reset or a launch arg would do it
        track.refresh()
        XCTAssertGreaterThan(beadX(track), low + Float(length) * 0.9,
                             "The bead ignored a change it did not cause.")
    }

    /// The bead sits at the value — the whole argument for a track over a
    /// dial is that the setting is legible from across the room.
    func testTheBeadSitsAtTheValue() {
        let (track, box) = makeTrack()

        for (value, expected) in [(0.0, -length / 2), (50.0, 0.0), (100.0, length / 2)] {
            box.value = value
            track.refresh()
            XCTAssertEqual(Double(beadX(track)), expected, accuracy: 1e-4,
                           "The bead is not where \(value) is.")
        }
    }

    // MARK: The guards

    /// An instrument belongs to an apparatus and disappears with it. The
    /// case this exists for: a drag already in flight when the apparatus is
    /// switched off. The gesture keeps delivering `onChanged`, so without
    /// the guard the track keeps writing to a model nobody is looking at.
    func testADisabledTrackClaimsNothingAndWritesNothing() {
        let (track, box) = makeTrack()
        track.adjust(hand: SIMD3(0, 0, 0))
        let beforeDisabling = box.value

        track.isEnabled = false

        XCTAssertFalse(track.owns(track.root),
                       "A disabled track must not claim a pinch.")
        XCTAssertFalse(track.adjust(hand: SIMD3(length / 2, 0, 0)),
                       "A disabled track must refuse to adjust.")
        XCTAssertEqual(box.value, beforeDisabling, accuracy: tolerance,
                       "A disabled track wrote to the model.")
        XCTAssertFalse(track.isAdjusting,
                       "Disabling must end any drag in flight.")
    }

    func testAnEnabledTrackClaimsItsOwnEntitiesAndNothingElse() {
        let (track, _) = makeTrack()
        let child = Entity()
        track.root.addChild(child)

        XCTAssertTrue(track.owns(track.root))
        XCTAssertTrue(track.owns(child), "Ownership must walk up from a child.")
        XCTAssertFalse(track.owns(Entity()), "An unrelated entity was claimed.")
    }

    // MARK: The collider — the defect that would have broken a module


    // MARK: Accessibility


    // MARK: The standing warning

    /// `adjust` has no scale term, which is correct for a scaled ancestor
    /// and wrong for a scaled root; pinned so nobody scales a track.
    func testATrackRootIsNeverScaled() {
        let (track, _) = makeTrack()
        XCTAssertEqual(track.root.scale, SIMD3<Float>(1, 1, 1),
                       "Scaling a track's own root stretches the rail without stretching the range it maps.")
    }

    private func beadX(_ track: SpatialTrackControl) -> Float {
        track.beadOffset.x
    }
}
