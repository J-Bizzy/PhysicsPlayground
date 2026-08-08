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
        // A SOLITARY pendulum, not the opening scene's first bob.
        //
        // The module opens with Newton's cradle now (2026-08-02), and a
        // ball in a cradle is supposed to lose its swing — it hands the
        // whole of it to the next ball along. This test is about
        // DAMPING, so it needs a pendulum with nothing to collide with;
        // asserting the old way would have been asserting that a cradle
        // does not work.
        let model = PendulumsModel()
        model.frictionOn = false
        for pendulum in model.pendulums { model.removePendulum(id: pendulum.id) }
        guard let id = model.addPendulum(),
              let first = model.pendulums.first(where: { $0.id == id }) else {
            return XCTFail("could not hang a solitary pendulum")
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

    // MARK: Hand-spawned pendulums start still; cables do not stretch

    /// A pendulum pulled from the well hangs plumb and at rest until a
    /// hand swings it — the drawn-back birth is the cradle cold-open's,
    /// not the well's (owner, 2026-08-03).
    func testAHandSpawnedPendulumHangsStillUntilSwung() {
        let model = PendulumsModel()
        for pendulum in model.pendulums { model.removePendulum(id: pendulum.id) }
        guard let id = model.addPendulum(angle: 0),
              let index = model.pendulums.firstIndex(where: { $0.id == id }) else {
            return XCTFail("could not hang a pendulum")
        }

        for _ in 0..<450 { model.step(dt: 1.0 / 90.0) }
        let state = model.pendulums[index].state
        XCTAssertEqual(simd_length(state.velocity), 0, accuracy: 1e-9,
                       "a plumb pendulum found a velocity from nowhere")
        XCTAssertEqual(state.position.x, 0, accuracy: 1e-9)
        XCTAssertEqual(state.position.z, 0, accuracy: 1e-9)
    }

    /// The cable is inextensible under the hand: however far the hand
    /// pulls, the bob stays exactly L from the pivot. Only the length
    /// bead changes L.
    func testGrabbingABobNeverStretchesTheCable() {
        let model = PendulumsModel()
        for pendulum in model.pendulums { model.removePendulum(id: pendulum.id) }
        guard let id = model.addPendulum(),
              let first = model.pendulums.first(where: { $0.id == id }) else {
            return XCTFail("could not hang a pendulum")
        }

        model.beginGrab(id: id)
        // Pull to twice the cable length, then to a tenth of it: the
        // stored bob must sit on the sphere both times.
        for reach in [2.0, 0.1, 5.0] {
            let hand = first.pivot + SIMD3(0.3, -0.5, 0.2) * (first.length * reach)
            model.moveGrabbed(id: id, toWorld: hand)
            let held = model.pendulums.first { $0.id == id }!
            XCTAssertEqual(simd_length(held.state.position), held.length,
                           accuracy: 1e-9,
                           "the cable stretched to \(reach)× under the hand")
        }
        model.release(id: id, handVelocity: .zero)
        let released = model.pendulums.first { $0.id == id }!
        XCTAssertEqual(simd_length(released.state.position), released.length,
                       accuracy: 1e-9)
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

    // (The Foucault suite stood here until 2026-08-03, when the feature
    // was removed at the owner's direction. Its sine-law recovery tests
    // live on in git history alongside the physics they guarded.)

    // MARK: The well

    func testTheWellRespectsThePendulumBudget() {
        let model = PendulumsModel()
        for step in 0..<20 {
            model.addPendulum(at: SIMD3(-0.6 + Double(step) * 0.1, 2.0, -1.1))
        }
        XCTAssertEqual(model.pendulums.count, PendulumsModel.pendulumBudget)
    }

    // MARK: The cradle and the chaotic one

    /// The module's cold open IS a cradle: five identical bobs, touching,
    /// with the first drawn back.
    @MainActor
    func testTheModuleOpensWithNewtonsCradle() {
        let model = PendulumsModel()
        XCTAssertEqual(model.pendulums.count, 5)
        XCTAssertTrue(model.pendulums.allSatisfy { $0.kind == .simple })

        let masses = Set(model.pendulums.map(\.mass))
        XCTAssertEqual(masses.count, 1, """
            a cradle of mismatched balls does something much less tidy — \
            equal masses swap velocities exactly, and that IS the mechanism
            """)

        // Exactly one is lifted; the rest hang plumb and touching.
        let swinging = model.pendulums.filter { abs($0.state.position.x) > 0.01 }
        XCTAssertEqual(swinging.count, 1)
    }

    /// One ball in, one ball out — through the real model, not through
    /// `BobCollision` in isolation.
    ///
    /// Measured as peak DISPLACEMENT from plumb over the whole run, not
    /// as a speed at some instant. My first attempt sampled speed at 1.2 s
    /// and failed on a cradle that was working perfectly: the far ball
    /// was at the top of its swing, which is exactly where its speed is
    /// zero. Displacement has no such phase to get unlucky with — the
    /// middle balls never leave plumb no matter when you look.
    ///
    /// This is the end-to-end version of
    /// `BobCollisionTests.testOneBallInSendsExactlyOneBallOut`, and it
    /// checks the two things that test cannot see: the projection onto
    /// the line of centres, and the write-back into `state.velocity`.
    @MainActor
    func testTheCradlePassesTheSwingAcrossToTheFarBall() {
        let model = PendulumsModel()
        model.frictionOn = false
        var peak = [Double](repeating: 0, count: model.pendulums.count)
        for _ in 0..<Int(2.5 * 90) {
            model.step(dt: 1.0 / 90)
            for (index, pendulum) in model.pendulums.enumerated() {
                peak[index] = max(peak[index], abs(pendulum.state.position.x))
            }
        }

        let ends = max(peak[0], peak[peak.count - 1])
        let middle = peak[1..<(peak.count - 1)].max() ?? 0
        XCTAssertGreaterThan(ends, 0.1,
                             "neither end ball ever swung; peaks were \(peak)")
        XCTAssertLessThan(middle, ends * 0.25, """
            the middle balls should barely leave plumb — the impulse passes \
            THROUGH them. Peaks were \(peak)
            """)
    }

    /// A double pendulum is a different rig, not a mode: it has a second
    /// rod, a second mass, and a two-angle state the simple one has no
    /// slot for.
    @MainActor
    func testADoublePendulumHangsWithBothRods() throws {
        let model = PendulumsModel()
        let id = try XCTUnwrap(model.addDoublePendulum())
        let pendulum = try XCTUnwrap(model.pendulums.first { $0.id == id })

        XCTAssertEqual(pendulum.kind, .double)
        XCTAssertNotNil(pendulum.doubleState)
        let elbow = try XCTUnwrap(pendulum.upperBobWorld)
        let bob = try XCTUnwrap(pendulum.lowerBobWorld)

        // Both rods are the length they claim to be, which is the whole
        // constraint the Lagrangian is written under.
        XCTAssertEqual(simd_distance(pendulum.pivot, elbow), pendulum.length,
                       accuracy: 1e-9)
        XCTAssertEqual(simd_distance(elbow, bob), pendulum.length2, accuracy: 1e-9)
        XCTAssertEqual(pendulum.bobWorld, bob, "the grabbable bob is the LOWER one")
    }

    /// …and it keeps both rods rigid as it runs. A constraint that drifts
    /// is the classic failure of integrating angles rather than positions.
    @MainActor
    func testTheDoublePendulumsRodsStayRigidThroughChaos() throws {
        let model = PendulumsModel()
        model.frictionOn = false
        let id = try XCTUnwrap(model.addDoublePendulum())
        for _ in 0..<(90 * 15) { model.step(dt: 1.0 / 90) }

        let pendulum = try XCTUnwrap(model.pendulums.first { $0.id == id })
        let elbow = try XCTUnwrap(pendulum.upperBobWorld)
        let bob = try XCTUnwrap(pendulum.lowerBobWorld)
        XCTAssertEqual(simd_distance(pendulum.pivot, elbow), pendulum.length,
                       accuracy: 1e-9)
        XCTAssertEqual(simd_distance(elbow, bob), pendulum.length2, accuracy: 1e-9)
    }

    /// Deleting a pendulum removes it and everything that referred to
    /// it, whichever end it was thrown away from.
    ///
    /// The pivot's ring grew a trash petal on 2026-08-02, matching every
    /// other module — so deleting from the TOP is now the usual path,
    /// and a stale `selectedID` left behind by it would leave the info
    /// card describing a rig that is not there.
    @MainActor
    func testDeletingAPendulumClearsEverythingThatPointedAtIt() throws {
        let model = PendulumsModel()
        let id = try XCTUnwrap(model.addPendulum())
        model.select(id: id)
        XCTAssertEqual(model.selectedID, id)

        let before = model.pendulums.count
        model.removePendulum(id: id)

        XCTAssertEqual(model.pendulums.count, before - 1)
        XCTAssertFalse(model.pendulums.contains { $0.id == id })
        XCTAssertNotEqual(model.selectedID, id,
                          "the selection still points at a deleted rig")
    }

    /// A double pendulum deletes the same way a simple one does — one
    /// rig, one id, whichever kind it is.
    @MainActor
    func testDeletingADoublePendulumWorksToo() throws {
        let model = PendulumsModel()
        let id = try XCTUnwrap(model.addDoublePendulum())
        model.removePendulum(id: id)
        XCTAssertFalse(model.pendulums.contains { $0.id == id })
    }

    // MARK: The double's readouts

    /// EVERY READOUT ABOUT THE DOUBLE PENDULUM USED TO LIE, and they all
    /// lied for one reason: `step` wrote `doubleState` and never wrote
    /// `state`, which is what the renderer, the card, the notebook and
    /// the freeze sculpt all read.
    ///
    /// So `state.position` stayed a plumb bob at rest and
    /// `state.velocity` was identically zero forever. The trail's
    /// `speed > 0.02` gate never passed, so the chaotic trace the rig
    /// exists for could not be drawn at all; the force arrows drew a
    /// constant mg on a bob accelerating hard; the card read
    /// `v 0.00 m/s` permanently.
    ///
    /// This asserts the mirror rather than any particular trajectory —
    /// chaos makes a stored reference untestable, as this file's own
    /// header explains, but "the two representations agree" is true on
    /// every step of every trajectory.
    func testTheDoublesStateTracksItsLowerBob() throws {
        let model = PendulumsModel()
        for existing in model.pendulums { model.removePendulum(id: existing.id) }
        let id = try XCTUnwrap(model.addDoublePendulum())

        var sawMotion = false
        for _ in 0..<400 {
            model.step(dt: 1.0 / 90)
            let pendulum = try XCTUnwrap(model.pendulums.first { $0.id == id })
            let double = try XCTUnwrap(pendulum.doubleState)
            let lower = try XCTUnwrap(pendulum.lowerBobWorld)

            // `state.position` is relative to the pivot; `lowerBobWorld`
            // is the same point lifted into the room.
            let fromState = pendulum.pivot + pendulum.state.position
            XCTAssertEqual(simd_distance(fromState, lower), 0, accuracy: 1e-9,
                           "state.position is not the lower bob")

            // And the speed must match the double's own derivative.
            let planar = double.lowerBobVelocity(rig: pendulum.doubleRig)
            XCTAssertEqual(simd_length(pendulum.state.velocity),
                           simd_length(planar), accuracy: 1e-9,
                           "state.velocity is not the lower bob's speed")

            if simd_length(pendulum.state.velocity) > 0.02 { sawMotion = true }
        }

        XCTAssertTrue(sawMotion,
                      "the lower bob never exceeded the trail's own "
                      + "`speed > 0.02` gate, so the chaotic trace would "
                      + "still be undrawable")
    }

    /// A NEW double must not inherit the last one's speed.
    ///
    /// The mirror above writes `state` from the double's own solution
    /// every step, so a fresh rig reports a fresh velocity — but the
    /// first version of this test asserted the wrong thing (that a new
    /// double is at rest a step later), which is false: it is released
    /// from θ₁ = 2.2 rad and gravity has it moving inside one frame.
    /// What is actually worth pinning is that the number describes THIS
    /// pendulum rather than the one whose slot it took.
    func testANewDoubleDoesNotInheritTheLastOnesSpeed() throws {
        let model = PendulumsModel()
        for existing in model.pendulums { model.removePendulum(id: existing.id) }

        let first = try XCTUnwrap(model.addDoublePendulum())
        for _ in 0..<300 { model.step(dt: 1.0 / 90) }
        let fast = try XCTUnwrap(model.pendulums.first { $0.id == first })
        XCTAssertGreaterThan(simd_length(fast.state.velocity), 0.2,
                             "the fixture never got moving, so this proves nothing")
        model.removePendulum(id: first)

        _ = try XCTUnwrap(model.addDoublePendulum())
        let fresh = try XCTUnwrap(model.pendulums.first)
        XCTAssertEqual(simd_length(fresh.state.velocity), 0, accuracy: 1e-12,
                       "a brand-new double is released from rest")

        // And one step later it is moving at roughly free-fall speed,
        // not at whatever the deleted one was doing.
        model.step(dt: 1.0 / 90)
        let stepped = try XCTUnwrap(model.pendulums.first)
        XCTAssertLessThan(simd_length(stepped.state.velocity), 0.3)
    }

    // MARK: Bobs that meet

    /// Mechanical energy of every simple pendulum on the bench, with the
    /// pivot as datum. Frictionless, this may fall (a collision with
    /// restitution < 1 removes some) but must never RISE.
    private func benchEnergy(_ model: PendulumsModel) -> Double {
        model.pendulums.filter { $0.kind == .simple }.reduce(0) { total, p in
            let speed = simd_length(p.state.velocity)
            let height = p.state.position.y      // negative, below the pivot
            return total + 0.5 * p.mass * speed * speed
                + p.mass * model.gravity * height
        }
    }

    /// A FRICTIONLESS BENCH MUST NOT MAKE ENERGY — an invariant worth
    /// pinning, and NOT evidence for the claim it was written to test.
    ///
    /// Audit P1-25 says off-axis bobs gain energy on every contact,
    /// because the exchange is applied along the line of centres rather
    /// than along each bob's own constraint tangent. The reasoning is
    /// plausible; the effect is not there. Measured on this fixture —
    /// two bobs whose lengths differ by 0.04 m, tilting the contact
    /// normal ~34° off tangent while staying inside the 0.07 m contact
    /// distance, so they genuinely collide — total energy moves by
    /// 3.6e-15 J over 1800 steps, with and without the projection the
    /// claim asks for. That fix was written and reverted; the reasoning
    /// is at the call site in `PendulumsModel`.
    ///
    /// So this test does NOT discriminate between the two
    /// implementations, and saying so is the point: two earlier versions
    /// of it were vacuous in ways that were not obvious (the first hung
    /// the bobs 25 cm apart, where they never touched at all), and a
    /// test whose green nobody has interrogated is how this arc's worst
    /// defects shipped. What it does buy is a real guard against a
    /// FUTURE collision change that does inject energy.
    func testAFrictionlessBenchNeverGainsEnergyThroughCollisions() throws {
        let model = PendulumsModel()
        for existing in model.pendulums { model.removePendulum(id: existing.id) }
        model.frictionOn = false

        // Two pendulums whose bobs CAN meet but do not meet level.
        //
        // The lengths differ by 0.04 m — enough to tilt the contact
        // normal about 34° off the horizontal, and still inside the
        // 0.07 m sum of the two bob radii, so they genuinely touch. The
        // first version of this test used 0.80 and 0.55, which hangs the
        // bobs 25 cm apart: they never collided at all and the test
        // passed against the unfixed code, which is the only kind of
        // green worth being suspicious of.
        let pivot = PendulumsModel.defaultPivot
        _ = try XCTUnwrap(model.addPendulum(length: 0.80, angle: 0.9, at: pivot))
        _ = try XCTUnwrap(model.addPendulum(length: 0.76, angle: -0.9,
                                            at: pivot + SIMD3(0.06, 0, 0)))

        let start = benchEnergy(model)
        var peak = start
        var closestApproach = Double.infinity
        for _ in 0..<(90 * 20) {
            model.step(dt: 1.0 / 90)
            peak = max(peak, benchEnergy(model))
            if model.pendulums.count == 2 {
                closestApproach = min(closestApproach,
                                      simd_distance(model.pendulums[0].bobWorld,
                                                    model.pendulums[1].bobWorld))
            }
        }

        // A small tolerance for the integrator itself; the defect was
        // not small — it compounded until the bobs flew.
        // The measured figure is ~4e-15 J, so the tolerance is generous
        // by twelve orders of magnitude and still catches anything that
        // pumps the bench.
        XCTAssertLessThan(
            peak, start + 0.02,
            "the bench gained \(peak - start) J across 20 s of off-axis "
            + "collisions — a frictionless bench may lose energy, never make it")

        // And the bobs must actually have COLLIDED, or the assertion
        // above is about a bench where nothing ever happened. This is
        // the check the first two versions of this test lacked.
        let a = try XCTUnwrap(model.pendulums.first)
        let b = try XCTUnwrap(model.pendulums.last)
        XCTAssertLessThan(closestApproach, a.bobRadius + b.bobRadius,
                          "the bobs never came within contact distance, so this "
                          + "test exercised no collision at all")
    }

    /// COLLISIONS USED TO SWITCH OFF FOR THE WHOLE BENCH IF TWO PIVOTS
    /// COINCIDED.
    ///
    /// The sweep is ordered along the line from the first movable pivot
    /// to the last — ARRAY order, not spatial order — and a zero-length
    /// axis returned early out of the entire resolution. Pull two
    /// pendulums from the well without moving either and both land on
    /// `defaultPivot`, so nothing in the room collided with anything
    /// from then on, including a cradle standing beside them.
    func testTwoPendulumsOnOnePivotDoNotDisableTheWholeBench() throws {
        let model = PendulumsModel()
        for existing in model.pendulums { model.removePendulum(id: existing.id) }
        model.frictionOn = false

        // THE STACKED PAIR GOES AT THE ENDS OF THE ARRAY, because the
        // old axis was `movable.first.pivot` to `movable.last.pivot` in
        // ARRAY order — that is the whole bug, and a fixture with the
        // pair in the middle would leave the axis non-zero and prove
        // nothing.
        _ = try XCTUnwrap(model.addPendulum(length: 0.8, angle: 0.2))

        // A cradle-like pair that WILL touch, well away from the origin.
        let rail = PendulumsModel.defaultPivot + SIMD3(0.9, 0, 0)
        _ = try XCTUnwrap(model.addPendulum(length: 0.8, angle: 0.6, at: rail))
        _ = try XCTUnwrap(model.addPendulum(length: 0.8, angle: 0,
                                            at: rail + SIMD3(0.07, 0, 0)))

        // …and the second of the stacked pair, which is what the well
        // produces if you pull twice and move neither.
        _ = try XCTUnwrap(model.addPendulum(length: 0.8, angle: 0.2))
        XCTAssertEqual(model.pendulums.first?.pivot, model.pendulums.last?.pivot,
                       "the fixture must have the coinciding pair at the ENDS")

        // The struck bob starts at rest; if collisions run at all, it
        // must be moving before the swinging one could reach it by any
        // other means.
        let strickenID = model.pendulums[2].id
        var sawTransfer = false
        for _ in 0..<(90 * 4) {
            model.step(dt: 1.0 / 90)
            let struck = try XCTUnwrap(model.pendulums.first { $0.id == strickenID })
            if simd_length(struck.state.velocity) > 0.05 { sawTransfer = true; break }
        }

        XCTAssertTrue(sawTransfer,
                      "no momentum ever reached the second bob — two pendulums "
                      + "sharing a pivot elsewhere on the bench switched "
                      + "collisions off for everything")
    }
}
