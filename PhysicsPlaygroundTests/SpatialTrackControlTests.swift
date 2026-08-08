//
//  SpatialTrackControlTests.swift
//  PhysicsPlaygroundTests
//
//  First coverage of `SpatialTrackControl`, written the day it got its
//  first caller. It had been in the tree since 2026-07-29 with **zero
//  shipping call sites** — its only constructions were in `Archive/`,
//  which is not in the build — so none of this code had ever run, and
//  three real defects were sitting in it (a collider the size of a beach
//  ball, no enabled state, and no accessibility value). Those are fixed;
//  these tests are what keeps them fixed.
//
//  `TrackLayoutTests` covers the arithmetic. This file covers the CONTROL:
//  the entity it builds, the model it writes, and the guards around both.
//  It builds real `Entity` objects and calls `adjust` directly, which is
//  the only kind of interaction testing available here — no automation can
//  synthesise a pinch (see `docs/ON_DEVICE_TESTS.md`).
//

import XCTest
import RealityKit
import simd
import RenderKit

@MainActor
final class SpatialTrackControlTests: XCTestCase {

    private let length = 0.26

    /// One part per million of the test range.
    ///
    /// Not a fudge, and worth stating once: a hand arrives here as
    /// `SIMD3<Double>` but is measured against `root.position`, which is
    /// `SIMD3<Float>` because entity transforms are. So every value crosses
    /// a float, and a 0…100 range comes back carrying about 2e-6 of float
    /// epsilon. Asserting to 1e-9 tests the width of a Float's mantissa
    /// rather than the control's arithmetic. Exact equality is still
    /// demanded where the code genuinely clamps (see the pinning test).
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

    /// THE COMPLAINT THIS FILE'S OWN HEADER MADE, finally answered.
    ///
    ///     // a track replaces a `Slider`, and a slider is already an
    ///     // adjustable element that speaks its value. Migrating
    ///     // without this trades a control someone could operate blind
    ///     // for one they cannot.
    ///
    /// The value was added when that was written; the adjustability was
    /// not, because `SpatialActions` lived a layer above RenderKit until
    /// 2026-08-08.
    func testTheRailCanBeAdjustedWithoutHands() {
        let (track, box) = makeTrack(range: 0...100)
        box.value = 50
        track.refresh()

        XCTAssertTrue(SpatialActions.adjust(track.root, by: 1))
        XCTAssertEqual(box.value, 55, accuracy: 1e-9,
                       "one increment should be a twentieth of the range")
        XCTAssertTrue(SpatialActions.adjust(track.root, by: -3))
        XCTAssertEqual(box.value, 40, accuracy: 1e-9)

        // It must stop at the ends rather than running past them — the
        // same clamp the drag goes through, because it IS that clamp.
        for _ in 0..<40 { SpatialActions.adjust(track.root, by: -1) }
        XCTAssertEqual(box.value, 0, accuracy: 1e-9)
        for _ in 0..<80 { SpatialActions.adjust(track.root, by: 1) }
        XCTAssertEqual(box.value, 100, accuracy: 1e-9)
    }

    /// The bead has to MOVE with the keystroke, not just the number —
    /// `nudge` calls `refresh()` for this reason, and a version that
    /// wrote the value and left the bead behind would look broken to
    /// everyone else in the room.
    func testAdjustingWithoutHandsMovesTheBead() {
        let (track, box) = makeTrack(range: 0...100)
        box.value = 0
        track.refresh()
        let start = track.beadOffset

        SpatialActions.adjust(track.root, by: 10)
        XCTAssertEqual(box.value, 50, accuracy: 1e-9)
        XCTAssertNotEqual(track.beadOffset.x, start.x, accuracy: 1e-4)
    }

    /// A rail with NO subtitle used to announce the value it was built
    /// with for the whole session: the republish sat inside
    /// `if let subtitle`, and most rails have none.
    func testARailWithoutASubtitleStillUpdatesItsSpokenValue() throws {
        let (track, box) = makeTrack(range: 0...100)
        box.value = 0
        track.refresh()
        let first = try XCTUnwrap(track.root.components[AccessibilityComponent.self])
            .value.map { String(localized: $0) }

        box.value = 75
        track.refresh()
        let second = try XCTUnwrap(track.root.components[AccessibilityComponent.self])
            .value.map { String(localized: $0) }

        XCTAssertNotEqual(first, second, """
            the rail spoke "\(first ?? "nil")" both before and after the value             moved from 0 to 75 — the spoken reading is frozen at whatever the             rail was built with.
            """)
        XCTAssertEqual(second, "75")
    }

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

    /// The bead sits AT the value — the whole argument for a track over a
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

    /// The rule from the `SpatialScaleHandle` ban (DECISIONS, 2026-07-29):
    /// an input-targetable collider must be no larger than the thing it
    /// represents. This shipped as a SPHERE of `length * 0.55` — a 29 cm
    /// ball around an object 1 cm thick — which would have shielded the
    /// capacitor it is bolted under from every pinch. Generous along the
    /// rail is the affordance; generous across it is a trap.
    func testTheColliderIsThinAcrossTheRail() throws {
        let (track, _) = makeTrack()
        let collision = try XCTUnwrap(track.root.components[CollisionComponent.self],
                                      "The rail must be grabbable.")
        let bounds = collision.shapes[0].bounds

        XCTAssertLessThan(bounds.extents.y, 0.08,
                          "The collider is taller than a rail 1 cm thick has any right to be.")
        XCTAssertLessThan(bounds.extents.z, 0.08,
                          "The collider is deeper than the rail — it will shield what it is bolted to.")
        XCTAssertGreaterThan(bounds.extents.x, Float(length),
                             "Grabbing anywhere ALONG the rail must work.")
    }

    // MARK: Accessibility

    /// A track replaces a `Slider`, and a slider already speaks its value.
    /// Migrating without this trades a control someone can operate blind
    /// for one they cannot.
    func testVoiceOverIsToldTheSettingNotJustTheName() throws {
        let (track, box) = makeTrack()

        box.value = 42
        track.refresh()
        let accessibility = try XCTUnwrap(
            track.root.components[AccessibilityComponent.self])
        XCTAssertNotNil(accessibility.value,
                        "VoiceOver would read the rail's name and not its setting.")
    }

    // MARK: The standing warning

    /// `adjust` has no scale term, which is correct for a scaled ANCESTOR
    /// (the hand and `root.position` are both in the parent's frame, so a
    /// rig cancels) and wrong for a scaled root. Pinned here so that
    /// anybody who "helpfully" scales a track meets a failing test rather
    /// than a rail whose far half is dead.
    func testATrackRootIsNeverScaled() {
        let (track, _) = makeTrack()
        XCTAssertEqual(track.root.scale, SIMD3<Float>(1, 1, 1),
                       "Scaling a track's own root stretches the rail without stretching the range it maps.")
    }

    private func beadX(_ track: SpatialTrackControl) -> Float {
        track.beadOffset.x
    }
}
