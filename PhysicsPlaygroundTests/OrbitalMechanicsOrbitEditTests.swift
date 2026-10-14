//
//  OrbitalMechanicsOrbitEditTests.swift
//  Orbit-edit wiring: display space in, sim state out. The math is in
//  PhysicsCoreTests/OrbitalElementsTests; the pinch itself is on-device only.
//

import XCTest
import PhysicsCore
import simd
@testable import PhysicsPlayground

@MainActor
final class OrbitalMechanicsOrbitEditTests: XCTestCase {

    private func earth(in model: OrbitalMechanicsModel) -> OrbitalMechanicsModel.OrbitingBody {
        model.bodies.first { $0.body.name == "Earth" }!
    }

    // MARK: Which bodies earn a ring

    func testEveryPlanetHasARingButTheSunDoesNot() {
        let model = OrbitalMechanicsModel()
        let sun = model.primaryBody!
        XCTAssertNil(model.orbitFrame(for: sun.id),
                     "the primary is the focus, not a thing in orbit")
        for body in model.bodies where body.id != sun.id {
            XCTAssertNotNil(model.orbitFrame(for: body.id),
                            "\(body.body.name) has no orbit ring")
        }
    }

    /// A ring is a two-body statement: with twin suns no body dominates, so the ring goes out.
    func testTwinSunsExtinguishTheRing() {
        let model = OrbitalMechanicsModel()
        let earthID = earth(in: model).id
        XCTAssertNotNil(model.orbitFrame(for: earthID))
        model.makeBinary()
        XCTAssertNil(model.orbitFrame(for: earthID),
                     "a ring survived the primary being split in half")
    }

    /// The ring reports the orbit the body is actually on: Earth at 1 AU, period one year.
    func testTheRingAgreesWithTheOrbitTheBodyIsOn() {
        let model = OrbitalMechanicsModel()
        let elements = model.orbitElements(for: earth(in: model).id)!
        XCTAssertEqual(elements.semiMajorAxis! / CelestialBody.astronomicalUnit,
                       1, accuracy: 1e-6)
        XCTAssertEqual(elements.eccentricity, 0, accuracy: 1e-9)
        XCTAssertEqual(elements.period! / 86_400, 365.25, accuracy: 0.5)
        XCTAssertEqual(elements.kind, .ellipse)
    }

    // MARK: The drag

    func testDraggingTheFarBeadStretchesTheOrbit() {
        let model = OrbitalMechanicsModel()
        let id = earth(in: model).id
        let before = model.orbitFrame(for: id)!
        XCTAssertTrue(model.beginOrbitEdit(bodyID: id, holding: .far))

        // Far bead to twice its radius along the apse line, in display space.
        let target = -before.periapsisDirection * (before.apoapsisRadius * 2)
        model.dragApsis(toDisplayPoint: target * model.simToDisplay)

        let after = model.orbitFrame(for: id)!
        XCTAssertEqual(after.apoapsisRadius / (before.apoapsisRadius * 2), 1,
                       accuracy: 1e-9, "the far end did not follow the hand")
        XCTAssertEqual(after.periapsisRadius / before.periapsisRadius, 1,
                       accuracy: 1e-9, "the near end moved on its own")
        XCTAssertGreaterThan(after.eccentricity, before.eccentricity,
                             "stretching one end did not make it more eccentric")
    }

    /// The same display point must mean the same orbit whatever the view scale —
    /// a failure means `displayPoint(fromWorld:)` stopped undoing the two-hand rig.
    func testTheDragIsIndependentOfTheViewScale() {
        func orbitAfterDrag() -> ApsisFrame {
            let model = OrbitalMechanicsModel()
            let id = earth(in: model).id
            let start = model.orbitFrame(for: id)!
            model.beginOrbitEdit(bodyID: id, holding: .far)
            model.dragApsis(toDisplayPoint:
                -start.periapsisDirection * start.apoapsisRadius * 1.7
                * model.simToDisplay)
            return model.orbitFrame(for: id)!
        }
        let a = orbitAfterDrag(), b = orbitAfterDrag()
        XCTAssertEqual(a.apoapsisRadius, b.apoapsisRadius)
        XCTAssertEqual(a.periapsisRadius, b.periapsisRadius)
    }

    /// Lifting a bead out of the ecliptic tilts the whole orbit.
    func testLiftingABeadTiltsTheOrbit() {
        let model = OrbitalMechanicsModel()
        let id = earth(in: model).id
        let before = model.orbitFrame(for: id)!
        XCTAssertEqual(before.orbitNormal.y, 1, accuracy: 1e-9,
                       "Earth should start in the reference plane")

        model.beginOrbitEdit(bodyID: id, holding: .far)
        let tilt = 0.4
        let lifted = -before.periapsisDirection * cos(tilt)
            + before.orbitNormal * sin(tilt)
        model.dragApsis(toDisplayPoint:
            lifted * before.apoapsisRadius * model.simToDisplay)

        let after = model.orbitFrame(for: id)!
        let turned = acos(min(max(simd_dot(after.orbitNormal,
                                           before.orbitNormal), -1), 1))
        XCTAssertEqual(turned, tilt, accuracy: 1e-6,
                       "the orbit did not tilt with its bead")
        XCTAssertEqual(model.orbitElements(for: id)!.inclination, tilt,
                       accuracy: 1e-6)
    }

    // MARK: What the edit does to the rest of the system

    /// The edited body holds still while everything else keeps orbiting.
    func testTheEditedBodyIsFrozenWhileTheSystemRuns() {
        let model = OrbitalMechanicsModel()
        let id = earth(in: model).id
        let marsID = model.bodies.first { $0.body.name == "Mars" }!.id
        model.beginOrbitEdit(bodyID: id, holding: .far)

        let earthBefore = model.bodies.first { $0.id == id }!.body.position
        let marsBefore = model.bodies.first { $0.id == marsID }!.body.position
        for _ in 0..<120 { model.step(dt: 1.0 / 90.0) }

        XCTAssertEqual(
            simd_distance(model.bodies.first { $0.id == id }!.body.position,
                          earthBefore), 0, accuracy: 1e-6,
            "the body being edited drifted out from under the hand")
        XCTAssertGreaterThan(
            simd_distance(model.bodies.first { $0.id == marsID }!.body.position,
                          marsBefore), 1e6,
            "the rest of the system stopped")
    }

    /// Letting go leaves the body on exactly the orbit the ring showed.
    func testReleasingLeavesTheBodyOnTheOrbitItWasGiven() {
        let model = OrbitalMechanicsModel()
        let id = earth(in: model).id
        let start = model.orbitFrame(for: id)!
        model.beginOrbitEdit(bodyID: id, holding: .far)
        model.dragApsis(toDisplayPoint:
            -start.periapsisDirection * start.apoapsisRadius * 1.8
            * model.simToDisplay)
        let authored = model.orbitElements(for: id)!
        model.endOrbitEdit()

        XCTAssertFalse(model.isEditingOrbit)
        XCTAssertNil(model.heldBodyID, "the body is still held after release")

        for _ in 0..<400 { model.step(dt: 1.0 / 90.0) }
        let after = model.orbitElements(for: id)!
        // Perturbed by the other planets, so 2% tolerance — but the same orbit.
        XCTAssertEqual(after.semiMajorAxis! / authored.semiMajorAxis!, 1,
                       accuracy: 0.02, "the authored orbit did not hold")
        XCTAssertEqual(after.eccentricity, authored.eccentricity, accuracy: 0.02)
    }

    func testReleasingClearsTheTrailThatDescribedTheOldOrbit() {
        let model = OrbitalMechanicsModel()
        let id = earth(in: model).id
        for _ in 0..<200 { model.step(dt: 1.0 / 90.0) }
        XCTAssertFalse(model.bodies.first { $0.id == id }!.trail.isEmpty)

        model.beginOrbitEdit(bodyID: id, holding: .far)
        model.endOrbitEdit()
        XCTAssertTrue(model.bodies.first { $0.id == id }!.trail.isEmpty,
                      "the trail still describes an orbit that no longer exists")
    }

    // MARK: Edges

    func testTheFarBeadCannotBeGrabbedOnAnUnboundOrbit() {
        let model = OrbitalMechanicsModel()
        let id = earth(in: model).id
        // Escape without moving far — `hold` teleports the body, and a big displacement
        // changes the escape speed being measured. 5 cm in 30 ms × 8.6e4 ≈ 140 km/s vs 42.
        let start = SIMD3<Double>(0.5, 0, 0)
        model.grab(id: id, at: start, timestamp: 0)
        model.hold(id: id, at: start, timestamp: 0)
        model.hold(id: id, at: start + SIMD3(0, 0, -0.05), timestamp: 0.03)
        model.release(id: id, timestamp: 0.03)

        guard let frame = model.orbitFrame(for: id), !frame.hasApoapsis else {
            return XCTFail("the throw did not unbind the orbit")
        }
        XCTAssertFalse(model.beginOrbitEdit(bodyID: id, holding: .far),
                       "grabbed a far bead on an orbit that has no far end")
        XCTAssertTrue(model.beginOrbitEdit(bodyID: id, holding: .near),
                      "the near bead should still work on a hyperbola")
    }

    func testAnEditCannotStartWhereThereIsNoRing() {
        let model = OrbitalMechanicsModel()
        XCTAssertFalse(
            model.beginOrbitEdit(bodyID: model.primaryBody!.id, holding: .near),
            "the Sun accepted an orbit edit")
    }

    /// Deleting the edited body must not leave a gesture holding nothing.
    func testDeletingTheEditedBodyEndsTheEdit() {
        let model = OrbitalMechanicsModel()
        let id = earth(in: model).id
        model.beginOrbitEdit(bodyID: id, holding: .far)
        model.removeBody(id: id)
        XCTAssertFalse(model.isEditingOrbit)
        XCTAssertNil(model.heldBodyID)
    }

    func testResetEndsAnyEditInFlight() {
        let model = OrbitalMechanicsModel()
        model.beginOrbitEdit(bodyID: earth(in: model).id, holding: .far)
        model.reset()
        XCTAssertFalse(model.isEditingOrbit)
        XCTAssertNil(model.heldBodyID)
    }

    // MARK: The readout's one μ

    /// Period and escape speed must share one gravitational parameter — GM vs G(M+m) drift is the trap.
    func testTheReadoutUsesOneGravitationalParameter() {
        let model = OrbitalMechanicsModel()
        let jupiter = model.bodies.first { $0.body.name == "Jupiter" }!
        let readout = model.readout(for: jupiter)!
        let elements = model.orbitElements(for: jupiter.id)!

        XCTAssertEqual(readout.periodDays! / (elements.period! / 86_400), 1,
                       accuracy: 1e-9,
                       "the readout's period and the ring's disagree")
        // v_esc = √2 × v_circ at the same radius, exactly.
        let circular = NBody.circularOrbitSpeed(
            centralMass: model.primaryBody!.body.mass + jupiter.body.mass,
            distance: readout.distanceAU * CelestialBody.astronomicalUnit,
            gravitationalConstant: model.effectiveG) / 1000
        XCTAssertEqual(readout.escapeSpeedKmPerS / circular, 2.0.squareRoot(),
                       accuracy: 1e-9)
    }

    // MARK: A body in the hand

    /// A held body's velocity is zeroed, so its osculating conic is a degenerate
    /// radial line — no honest ring; the prediction tube is the instrument for that moment.
    func testAHeldBodyHasNoOrbitRing() {
        let model = OrbitalMechanicsModel()
        let id = earth(in: model).id
        XCTAssertNotNil(model.orbitFrame(for: id))

        model.grab(id: id, at: SIMD3(0.5, 0, 0), timestamp: 0)
        model.hold(id: id, at: SIMD3(0.5, 0, 0), timestamp: 0)
        XCTAssertNil(model.orbitFrame(for: id),
                     "a ring was drawn around a body with no velocity")

        model.release(id: id, timestamp: 0.05)
        XCTAssertNil(model.heldBodyID)
    }

    /// …but an orbit edit borrows `heldID` without being a hold: the ring must survive the gesture that reshapes it.
    func testAnOrbitEditKeepsItsRing() {
        let model = OrbitalMechanicsModel()
        let id = earth(in: model).id
        XCTAssertTrue(model.beginOrbitEdit(bodyID: id, holding: .far))
        XCTAssertEqual(model.heldBodyID, id)
        XCTAssertNotNil(model.orbitFrame(for: id),
                        "the ring vanished during the drag that reshapes it")
        model.endOrbitEdit()
        XCTAssertNotNil(model.orbitFrame(for: id))
    }

    /// A body let go by a still hand takes the circular orbit at that radius
    /// (2026-09-06). Before this it was released at rest and fell straight
    /// in, and a test pinned that "so nobody fixes it later": a hand cannot
    /// express 30 km/s to a few percent, so nobody could place a planet.
    func testABodyReleasedByAStillHandHoldsItsRadius() {
        let model = OrbitalMechanicsModel()
        let id = earth(in: model).id
        let sun = model.primaryBody!.body.position
        let start = model.bodies.first { $0.id == id }!.body.position

        model.grab(id: id, at: start * model.simToDisplay, timestamp: 0)
        model.hold(id: id, at: start * model.simToDisplay, timestamp: 0)
        model.release(id: id, timestamp: 0.05)

        for _ in 0..<400 { model.step(dt: 1.0 / 90.0) }
        let now = model.bodies.first { $0.id == id }!.body
        let primary = model.primaryBody!.body
        XCTAssertEqual(simd_length(now.position - primary.position) / simd_length(start - sun), 1,
                       accuracy: 1e-3, "the placed orbit did not hold its radius")
        XCTAssertEqual(model.orbitElements(for: id)!.eccentricity, 0, accuracy: 1e-3)
    }


    // MARK: Occlusion is measured in the ring's own frame

    /// Occlusion depends only on the relative arrangement in the ring's frame — the call site
    /// (`OrbitalMechanicsRenderer.syncOrbitRing`) must pass ring-frame coordinates, not system ones;
    /// the renderer half cannot be driven from a test and is verified on device.
    func testOcclusionDoesNotDependOnWhereTheSystemSits() {
        let beadInRingFrame = SIMD3<Float>(0.30, 0, 0)
        let beadRadius: Float = 0.01

        // A planet sitting exactly on the bead, in the ring's frame.
        let planetInRingFrame = (center: beadInRingFrame, radius: Float(0.05))

        for primary in [SIMD3<Float>.zero,
                        SIMD3<Float>(0.2, 0, 0),
                        SIMD3<Float>(-1.4, 0.3, 0.8)] {
            XCTAssertTrue(
                OrbitRing.isOccluded(bead: beadInRingFrame, radius: beadRadius,
                                     by: [planetInRingFrame]),
                "a bead inside a planet must hide with the primary at \(primary)")
        }

        XCTAssertFalse(
            OrbitRing.isOccluded(bead: SIMD3(0.30, 0, 0), radius: beadRadius,
                                 by: [(center: SIMD3(-0.30, 0, 0), radius: 0.05)]),
            "a bead in open space was hidden")
    }
}
