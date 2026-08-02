//
//  PendulumsModelTests.swift
//  PhysicsPlaygroundTests
//
//  This file was ONE test function against a 365-line model — the
//  thinnest coverage in the project, in the module that has just gained
//  five switch plates, two rails and a standing bank of worlds. What the
//  instruments write is now pinned here: the ranges they clamp to, the
//  comparison that decides which world's disc lights, and the promise
//  `setLength` makes that a cable edit does not stop the swing.
//

import PhysicsCore
import XCTest
import simd
@testable import PhysicsPlayground

@MainActor
final class PendulumsModelTests: XCTestCase {

    /// With friction off (and damping deliberately cranked), ten
    /// simulated seconds of swinging lose essentially no amplitude —
    /// the energy-exact integrator plus a severed loss term.
    func testFrictionToggleMakesThePendulumIdeal() {
        let model = PendulumsModel()
        model.frictionOn = false
        guard let first = model.pendulums.first else {
            return XCTFail("no pendulum in the opening scene")
        }
        model.setDamping(id: first.id, 1.0)   // would kill the swing fast

        // Pull the bob out and release it from rest.
        model.beginGrab(id: first.id)
        let start = first.pivot + SIMD3(0.35, -first.length * 0.8, 0)
        model.moveGrabbed(id: first.id, toWorld: start)
        model.release(id: first.id, handVelocity: .zero)

        var earlyPeak = 0.0
        var latePeak = 0.0
        for step in 0..<900 {
            model.step(dt: 1.0 / 90.0)
            let x = abs(model.pendulums[0].state.position.x)
            if step < 180 { earlyPeak = max(earlyPeak, x) }
            if step >= 720 { latePeak = max(latePeak, x) }
        }
        XCTAssertGreaterThan(latePeak, earlyPeak * 0.97,
                             "no friction, no decay")

        // Friction back on: the same setup audibly dies down.
        model.frictionOn = true
        var dampedPeak = 0.0
        for step in 0..<900 {
            model.step(dt: 1.0 / 90.0)
            if step >= 720 {
                dampedPeak = max(dampedPeak, abs(model.pendulums[0].state.position.x))
            }
        }
        XCTAssertLessThan(dampedPeak, latePeak * 0.7,
                          "heavy damping now applies and eats the swing")
    }

    // MARK: The worlds bank — which disc lights

    /// The standing bank of worlds is a READOUT as well as a control, and
    /// it decides which disc is lit with exactly this comparison. Pinning
    /// it here means the lamp and the panel's own "— Moon" line cannot
    /// drift apart: they are the same question asked twice.
    private func litWorld(_ model: PendulumsModel) -> String? {
        SurfaceGravity.bodies
            .first { abs($0.gravity - model.gravity) < 0.01 }?.name
    }

    func testTappingAWorldSetsGravityAndLightsThatDisc() {
        let model = PendulumsModel()
        XCTAssertEqual(litWorld(model), "Earth", "the bench opens on Earth")

        for world in SurfaceGravity.bodies {
            model.gravity = world.gravity
            XCTAssertEqual(litWorld(model), world.name)
        }
    }

    /// Dragging the rail off a world's value must UNLIGHT it — otherwise
    /// the bank claims you are on the Moon while g says otherwise.
    func testDraggingTheRailBetweenWorldsLightsNothing() {
        let model = PendulumsModel()
        let moon = SurfaceGravity.bodies.first { $0.name == "Moon" }!
        model.gravity = moon.gravity
        XCTAssertEqual(litWorld(model), "Moon")

        model.gravity = moon.gravity + 0.5
        XCTAssertNil(litWorld(model), "between worlds, no disc is lit")
    }

    /// Every world the bank offers has to be reachable on the rail too,
    /// or tapping a disc would move the bead somewhere it cannot be
    /// dragged back to.
    func testEveryWorldLiesInsideTheGravityRailsRange() {
        for world in SurfaceGravity.bodies {
            XCTAssertTrue(PendulumsModel.gravityRange.contains(world.gravity),
                          "\(world.name) at \(world.gravity) is off the rail")
        }
    }

    // MARK: What the rails write

    /// A rail cannot write outside its own range, so the model's clamps
    /// are what stop a debug argument or a future caller from putting the
    /// bench somewhere the bead cannot represent.
    func testTheRailRangesAreOrderedAndContainTheirDefaults() {
        XCTAssertTrue(PendulumsModel.gravityRange.contains(9.81))
        XCTAssertTrue(PendulumsModel.timeScaleRange.contains(1.0))
        XCTAssertLessThan(PendulumsModel.timeScaleRange.lowerBound, 1.0)
        XCTAssertGreaterThan(PendulumsModel.timeScaleRange.upperBound, 1.0)
    }

    /// Time scale is not chrome: it decides whether a 2.5 s swing is a
    /// shape you can see or one you wait for. Half speed must advance
    /// half as much physics per rendered frame.
    func testTheTimeRailScalesHowMuchPhysicsRunsPerFrame() {
        func swing(at timeScale: Double) -> Double {
            let model = PendulumsModel()
            model.frictionOn = false
            model.timeScale = timeScale
            let first = model.pendulums[0]
            model.beginGrab(id: first.id)
            model.moveGrabbed(
                id: first.id,
                toWorld: first.pivot + SIMD3(0.30, -first.length * 0.85, 0))
            model.release(id: first.id, handVelocity: .zero)
            for _ in 0..<45 { model.step(dt: 1.0 / 90.0) }
            return model.pendulums[0].state.position.x
        }
        // Quarter of a period in, the fast clock has swung measurably
        // further back toward centre than the slow one.
        XCTAssertLessThan(swing(at: 2.0), swing(at: 0.5),
                          "twice the clock, more of the swing")
    }

    func testPausingStopsTimeAndResumingContinuesIt() {
        let model = PendulumsModel()
        let before = model.pendulums[0].state.position
        model.isPaused = true
        for _ in 0..<90 { model.step(dt: 1.0 / 90.0) }
        XCTAssertEqual(model.pendulums[0].state.position, before,
                       "paused is frozen, not slowed")

        model.isPaused = false
        for _ in 0..<90 { model.step(dt: 1.0 / 90.0) }
        XCTAssertNotEqual(model.pendulums[0].state.position, before)
    }

    // MARK: The switch bank

    /// Every plate the bank shows, and a reset that puts them all back —
    /// the bank reads its lamps from the model every frame, so a reset
    /// that missed one would leave a lit plate over a hidden layer.
    /// (Energy bars were the fifth until 2026-08-01, when the whole idea
    /// was deleted at the owner's request.)
    func testResetRestoresEveryLayerTheBankShows() {
        let model = PendulumsModel()
        model.showVelocity = false
        model.showAcceleration = true
        model.showForces = true
        model.frictionOn = false
        model.gravity = 1.62
        model.timeScale = 3.0

        model.reset()

        XCTAssertTrue(model.showVelocity)
        XCTAssertFalse(model.showAcceleration)
        XCTAssertFalse(model.showForces)
        XCTAssertTrue(model.frictionOn)
        XCTAssertEqual(model.gravity, 9.81, accuracy: 1e-9)
        XCTAssertEqual(model.timeScale, 1.0, accuracy: 1e-9)
        XCTAssertEqual(litWorld(model), "Earth")
    }

    // MARK: The length bead

    /// `setLength` goes to real trouble to re-project the bob onto the
    /// new sphere keeping its direction and speed, so that paying out
    /// cable changes the PERIOD without restarting the motion. Nothing
    /// asserted it, and it is the whole lesson of the grip.
    func testPayingOutCableChangesThePeriodWithoutStoppingTheSwing() {
        let model = PendulumsModel()
        model.frictionOn = false
        let first = model.pendulums[0]
        model.beginGrab(id: first.id)
        model.moveGrabbed(
            id: first.id,
            toWorld: first.pivot + SIMD3(0.30, -first.length * 0.85, 0))
        model.release(id: first.id, handVelocity: .zero)
        for _ in 0..<30 { model.step(dt: 1.0 / 90.0) }

        let movingBefore = simd_length(model.pendulums[0].state.velocity)
        XCTAssertGreaterThan(movingBefore, 0.05, "it should be mid-swing")
        let periodBefore = model.pendulums[0].period(gravity: model.gravity)

        model.setLength(id: first.id, 1.4)

        XCTAssertEqual(model.pendulums[0].length, 1.4, accuracy: 1e-9)
        XCTAssertEqual(simd_length(model.pendulums[0].state.position), 1.4,
                       accuracy: 1e-9, "the bob is back on the cable")
        XCTAssertEqual(simd_length(model.pendulums[0].state.velocity),
                       movingBefore, accuracy: 1e-9,
                       "speed survives the edit — the swing carries on")
        XCTAssertGreaterThan(
            model.pendulums[0].period(gravity: model.gravity), periodBefore,
            "a longer cable is a slower swing")
    }

    func testTheLengthBeadCannotLeaveItsRange() {
        let model = PendulumsModel()
        let id = model.pendulums[0].id
        model.setLength(id: id, 99)
        XCTAssertEqual(model.pendulums[0].length,
                       PendulumsModel.lengthRange.upperBound, accuracy: 1e-9)
        model.setLength(id: id, -5)
        XCTAssertEqual(model.pendulums[0].length,
                       PendulumsModel.lengthRange.lowerBound, accuracy: 1e-9)
    }

    // MARK: The physics the bench exists for

    /// T = 2π√(L/g), and the mass is NOT in it. The mass petal cycles
    /// light → medium → heavy precisely so you can watch the period not
    /// change; if it ever did, that petal would be teaching the opposite
    /// of the lesson it exists for.
    func testThePeriodFollowsRootLOverGAndIgnoresMass() {
        let model = PendulumsModel()
        let id = model.pendulums[0].id
        model.setLength(id: id, 1.0)

        let earth = model.pendulums[0].period(gravity: 9.81)
        XCTAssertEqual(earth, 2 * .pi * (1.0 / 9.81).squareRoot(), accuracy: 1e-9)

        // Quarter the gravity, double the period.
        XCTAssertEqual(model.pendulums[0].period(gravity: 9.81 / 4),
                       earth * 2, accuracy: 1e-9)
        // Quadruple the length, double the period.
        model.setLength(id: id, 4.0)   // clamps to 1.6
        model.setLength(id: id, 0.25)
        XCTAssertEqual(model.pendulums[0].period(gravity: 9.81),
                       earth / 2, accuracy: 1e-9)

        // And mass moves none of it.
        model.setLength(id: id, 1.0)
        for mass in [0.5, 1.5, 3.0] {
            model.setMass(id: id, mass)
            XCTAssertEqual(model.pendulums[0].period(gravity: 9.81),
                           earth, accuracy: 1e-9,
                           "mass \(mass) changed the period")
        }
    }

    /// A pivot dropped near the floor must be lifted so the bob cannot
    /// swing through it — the clamp is the cable's length plus clearance,
    /// not a fixed height, so it has to move when the cable does.
    func testAPivotIsLiftedSoTheBobClearsTheFloor() {
        let model = PendulumsModel()
        let id = model.pendulums[0].id
        model.setLength(id: id, 1.2)
        model.movePivot(id: id, to: SIMD3(0.2, 0.1, -1.0))

        XCTAssertGreaterThanOrEqual(
            model.pendulums[0].pivot.y,
            PendulumsModel.minimumPivotHeight + 1.2 - 1e-9,
            "the bob would have swung through the floor")
    }

    // MARK: Foucault

    /// Off means OFF: Ω is exactly zero, so `SphericalPendulum.step`
    /// reduces to the ordinary pendulum rather than to a very slow
    /// Foucault one. The core test pins that the reduction is bit-exact;
    /// this pins that the model actually hands it zero.
    func testEarthRotationIsZeroUntilSwitchedOn() {
        let model = PendulumsModel()
        XCTAssertFalse(model.foucaultOn)
        XCTAssertEqual(model.earthRotation, .zero)
        XCTAssertEqual(model.precessionRate, 0)

        model.foucaultOn = true
        XCTAssertGreaterThan(simd_length(model.earthRotation), 0)
        XCTAssertNotEqual(model.precessionRate, 0)
    }

    /// The panel quotes the TRUE rate, never the exaggerated one — that
    /// disclosure is what makes the exaggeration honest, so it must not
    /// move when the spin rail does.
    func testTheQuotedTrueRateIgnoresTheSpinExaggeration() {
        let model = PendulumsModel()
        model.foucaultOn = true
        model.latitudeDegrees = 48.8462          // Paris
        let quoted = model.truePrecessionDegreesPerHour
        let hours = model.truePrecessionHours

        model.earthSpin = PendulumsModel.spinRange.upperBound
        XCTAssertEqual(model.truePrecessionDegreesPerHour, quoted, accuracy: 1e-12,
                       "the disclosed rate followed the exaggeration")
        XCTAssertEqual(model.truePrecessionHours!, hours!, accuracy: 1e-12)
        // Paris really does turn 11.3° an hour, once round in ~31.8 h.
        XCTAssertEqual(abs(quoted), 11.30, accuracy: 0.05)
        XCTAssertEqual(hours!, 31.8, accuracy: 0.1)

        // …while what is SHOWN does scale with it.
        XCTAssertGreaterThan(abs(model.precessionRate),
                             abs(EarthRotation.precessionRate(
                                latitudeDegrees: 48.8462)) * 100)
    }

    /// The equator has no precession period, and the panel must be able
    /// to say so rather than print an enormous number.
    func testTheEquatorReportsNoTurnAtAll() {
        let model = PendulumsModel()
        model.foucaultOn = true
        model.latitudeDegrees = 0
        XCTAssertNil(model.truePrecessionHours)
        XCTAssertEqual(model.precessionRate, 0, accuracy: 1e-18)
    }

    /// The markers are the record: swinging at a latitude that precesses
    /// must fell some, and the equator must fell none. This drives the
    /// real integration rather than the closed form.
    func testTheRingRecordsThePrecessionAndTheEquatorFellsNothing() {
        func markersDown(latitude: Double) -> Int {
            let model = PendulumsModel()
            model.frictionOn = false
            model.foucaultOn = true
            model.earthSpin = PendulumsModel.spinRange.upperBound
            model.latitudeDegrees = latitude
            let first = model.pendulums[0]
            model.beginGrab(id: first.id)
            model.moveGrabbed(
                id: first.id,
                toWorld: first.pivot + SIMD3(0.30, -first.length * 0.85, 0))
            model.release(id: first.id, handVelocity: .zero)
            for _ in 0..<5_400 { model.step(dt: 1.0 / 90.0) }
            return model.markersFelled
        }
        XCTAssertGreaterThan(markersDown(latitude: 60), 0,
                             "the plane swept and nothing fell")
        XCTAssertEqual(markersDown(latitude: 0), 0,
                       "markers fell on the equator, where nothing turns")
    }

    /// Switching the effect on re-lays the ring, so the count always
    /// measures from where this run started rather than from a previous
    /// one.
    func testArmingTheEffectStandsEveryMarkerBackUp() {
        let model = PendulumsModel()
        model.foucaultOn = true
        XCTAssertEqual(model.standingMarkers.count, PendulumsModel.markerCount)
        XCTAssertEqual(model.markersFelled, 0)
    }

    func testResetPutsTheEarthBackAndStandsTheMarkersUp() {
        let model = PendulumsModel()
        model.foucaultOn = true
        model.latitudeDegrees = -72
        model.earthSpin = 15_000

        model.reset()

        XCTAssertFalse(model.foucaultOn)
        XCTAssertEqual(model.latitudeDegrees, 48.8462, accuracy: 1e-4)
        XCTAssertEqual(model.earthSpin, 3_000, accuracy: 1e-9)
        XCTAssertEqual(model.standingMarkers.count, PendulumsModel.markerCount)
        XCTAssertEqual(model.markersFelled, 0)
        XCTAssertEqual(model.earthRotation, .zero)
    }

    // MARK: The well

    func testTheWellRespectsThePendulumBudget() {
        let model = PendulumsModel()
        for step in 0..<20 {
            model.addPendulum(at: SIMD3(-0.6 + Double(step) * 0.1, 2.0, -1.1))
        }
        XCTAssertEqual(model.pendulums.count, PendulumsModel.pendulumBudget)
    }
}
