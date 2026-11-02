//
//  OrbitalMechanicsModelTests.swift
//  Orbital Mechanics app state; the n-body math itself is covered in PhysicsCore's NBodyTests.
//

import XCTest
import PhysicsCore
import simd
@testable import PhysicsPlayground

@MainActor
final class OrbitalMechanicsModelTests: XCTestCase {

    /// `readout(for:)` is memoised — a memo outliving the state would report stale distance/energy forever.
    func testReadoutsFollowTheSystemForward() {
        let model = OrbitalMechanicsModel()
        guard let earth = model.bodies.first(where: { $0.body.name == "Earth" }) else {
            return XCTFail("Earth should be in the opening scene")
        }

        guard let first = model.readout(for: earth) else {
            return XCTFail("Earth orbits the Sun, so it has a readout")
        }
        XCTAssertEqual(model.readout(for: earth)?.distanceAU, first.distanceAU)

        model.timeScale = 40
        for _ in 0..<120 { model.step(dt: 1.0 / 60) }

        guard let moved = model.bodies.first(where: { $0.body.name == "Earth" }),
              let second = model.readout(for: moved) else {
            return XCTFail("Earth should still be present and bound")
        }
        XCTAssertNotEqual(second.distanceAU, first.distanceAU, accuracy: 0,
                          "A cached readout outlived the step that moved the planet")
        XCTAssertGreaterThan(abs(second.speedKmPerS - first.speedKmPerS), 0)
    }

    func testOpeningSceneIsSunAndEarthOnRealOrbit() {
        let model = OrbitalMechanicsModel()
        // The whole solar system opens live: Sun + 8 planets + a comet.
        XCTAssertEqual(model.bodies.count, 10)
        XCTAssertEqual(model.primaryBody?.body.name, "Sun")
        for name in ["Mercury", "Venus", "Earth", "Mars",
                     "Jupiter", "Saturn", "Uranus", "Neptune"] {
            XCTAssertTrue(model.bodies.contains { $0.body.name == name },
                          "\(name) missing from the opening system")
        }

        let earth = model.bodies.first { $0.body.name == "Earth" }!
        let readout = try! XCTUnwrap(model.readout(for: earth))
        XCTAssertEqual(readout.distanceAU, 1.0, accuracy: 1e-6)
        XCTAssertEqual(readout.speedKmPerS, 29.78, accuracy: 0.1)
        XCTAssertEqual(try! XCTUnwrap(readout.periodDays), 365.25, accuracy: 1.0)
        XCTAssertTrue(readout.isBound)
        XCTAssertLessThan(readout.totalEnergy, 0, "a bound orbit has negative total energy")
    }

    /// The comet must be genuinely out of the planets' plane, eccentric, and bound.
    func testOpeningSceneIncludesAnInclinedComet() {
        let model = OrbitalMechanicsModel()
        let comet = try! XCTUnwrap(model.bodies.first { $0.body.name == "Comet" })
        let sun = try! XCTUnwrap(model.bodies.first { $0.body.name == "Sun" })

        let h = simd_cross(comet.body.position - sun.body.position,
                           comet.body.velocity - sun.body.velocity)
        let tilt = acos(min(max(simd_dot(simd_normalize(h), SIMD3<Double>(0, 1, 0)), -1), 1))
        XCTAssertGreaterThan(tilt, 1.0,
                             "steeply inclined — it leaves the planets' plane")

        let readout = try! XCTUnwrap(model.readout(for: comet))
        XCTAssertTrue(readout.isBound, "a comet on a closed orbit, not an escapee")
        XCTAssertLessThan(readout.distanceAU, 1.0,
                          "starts at perihelion, inside Earth's orbit")

        for body in model.bodies where !["Sun", "Comet"].contains(body.body.name) {
            XCTAssertEqual(body.body.position.y, 0, accuracy: 1e-6)
        }
    }

    /// A held Earth must not move while everything else keeps simulating.
    func testHoldFreezesBodyWhileSystemEvolves() {
        let model = OrbitalMechanicsModel()
        let earth = model.bodies.first { $0.body.name == "Earth" }!
        let holdPoint = SIMD3<Double>(0.2, 0.1, -0.1)
        model.grab(id: earth.id, at: holdPoint, timestamp: 10)

        for _ in 0..<30 {
            model.step(dt: 1.0 / 90.0)
        }
        let held = model.bodies.first { $0.id == earth.id }!
        XCTAssertEqual(simd_distance(held.body.position,
                                     holdPoint * model.displayToSim),
                       0, accuracy: 1.0)
        XCTAssertEqual(held.body.velocity, .zero)
    }

    /// Release = the circular orbit at the release point + hand velocity × throwVelocityScale.
    func testReleaseLaysTheThrowOnTheCircularOrbit() {
        let model = OrbitalMechanicsModel()
        let earth = model.bodies.first { $0.body.name == "Earth" }!
        model.grab(id: earth.id, at: SIMD3(0.3, 0, 0), timestamp: 50)
        for sample in 1...9 {
            let t = Double(sample) / 90.0
            model.hold(id: earth.id, at: SIMD3(0.3, 0, -0.3 * t), timestamp: 50 + t)
        }
        model.release(id: earth.id, timestamp: 50 + 9.0 / 90.0)

        let released = model.bodies.first { $0.id == earth.id }!
        let sun = model.primaryBody!.body
        let circular = OrbitalMechanicsModel.circularVelocity(
            at: released.body.position, mass: released.body.mass, about: sun,
            gravitationalConstant: model.effectiveG) - sun.velocity
        let relative = released.body.velocity - sun.velocity
        XCTAssertEqual(relative.z - circular.z,
                       -0.3 * OrbitalMechanicsModel.throwVelocityScale, accuracy: 1.0)
        XCTAssertEqual(relative.x - circular.x, 0, accuracy: 1.0)
    }

    /// A still hand puts the body on the circular orbit where it was put —
    /// the way to place a planet. Releasing at the hand's speed alone
    /// dropped it into the Sun.
    func testAStillHandPlacesABodyOnACircularOrbit() {
        let model = OrbitalMechanicsModel()
        let earth = model.bodies.first { $0.body.name == "Earth" }!
        let point = SIMD3<Double>(0.45, 0.1, 0.2)
        model.grab(id: earth.id, at: point, timestamp: 10)
        for sample in 1...20 {
            model.hold(id: earth.id, at: point, timestamp: 10 + Double(sample) / 90.0)
        }
        model.release(id: earth.id, timestamp: 10 + 20.0 / 90.0)

        let elements = try! XCTUnwrap(model.orbitElements(for: earth.id))
        XCTAssertEqual(elements.eccentricity, 0, accuracy: 1e-6, "not the circular orbit")
        let readout = try! XCTUnwrap(model.readout(for: model.bodies.first { $0.id == earth.id }!))
        XCTAssertEqual(readout.distanceAU, simd_length(point) / OrbitalMechanicsModel.metersPerAU,
                       accuracy: 1e-6)
        XCTAssertTrue(readout.isBound)
        for _ in 0..<600 { model.step(dt: 1.0 / 90.0) }
        let later = try! XCTUnwrap(model.readout(for: model.bodies.first { $0.id == earth.id }!))
        XCTAssertEqual(later.distanceAU, readout.distanceAU, accuracy: readout.distanceAU * 0.01,
                       "the placed orbit did not hold")
    }

    /// Overlapping bodies merge: one fewer body, combined mass, momentum conserved.
    func testOverlappingBodiesMergeConservingMomentum() {
        let model = OrbitalMechanicsModel()
        let venusID = model.bodies.first { $0.body.name == "Venus" }!.id
        let earthID = model.bodies.first { $0.body.name == "Earth" }!.id

        let venusDisplay = model.bodies.first { $0.id == venusID }!.body.position * model.simToDisplay
        model.grab(id: earthID, at: venusDisplay, timestamp: 80)
        model.release(id: earthID, timestamp: 80.1)
        // Measured after the release: letting go settles the room's frame, and
        // the claim here is that the MERGE conserves what the pair carried in.
        let venus = model.bodies.first { $0.id == venusID }!
        let earth = model.bodies.first { $0.id == earthID }!
        let expectedMass = venus.body.mass + earth.body.mass
        let expectedMomentum = venus.body.mass * venus.body.velocity
            + earth.body.mass * earth.body.velocity
        model.step(dt: 1.0 / 90.0)

        XCTAssertEqual(model.bodies.count, 9, "ten bodies minus one merger")
        let merged = try! XCTUnwrap(model.bodies.first {
            abs($0.body.mass - expectedMass) < expectedMass * 1e-6
        }, "one body carries the combined Venus+Earth mass")
        XCTAssertEqual(merged.body.mass, expectedMass, accuracy: expectedMass * 1e-9)
        XCTAssertEqual(merged.body.mass * merged.body.velocity.z,
                       expectedMomentum.z,
                       accuracy: abs(expectedMomentum.z) * 1e-6)
    }

    /// Escape speed is √2 × circular speed at the same radius — pinned at the exact threshold via `addBody`.
    func testAWorldFromTheWellIsCircularAndEscapesAtRootTwo() {
        let model = OrbitalMechanicsModel()
        let distanceAU = 1.5
        let at = SIMD3(distanceAU * OrbitalMechanicsModel.metersPerAU, 0, 0)

        let circlerID = try! XCTUnwrap(model.addBody(at: at))
        let circler = model.bodies.first { $0.id == circlerID }!
        let readout = try! XCTUnwrap(model.readout(for: circler))
        XCTAssertTrue(readout.isBound, "born on a circular orbit, so bound")
        XCTAssertEqual(readout.distanceAU, distanceAU, accuracy: 1e-6)
        // Born circular reads back circular — guards the GM-vs-G(M+m) error in `onCircularOrbit`.
        XCTAssertEqual(try! XCTUnwrap(model.orbitElements(for: circlerID))
                           .eccentricity, 0, accuracy: 1e-6)

        XCTAssertEqual(readout.escapeSpeedKmPerS,
                       readout.speedKmPerS * 2.0.squareRoot(),
                       accuracy: readout.escapeSpeedKmPerS * 1e-6,
                       "escape speed is √2 × circular speed")
    }

    /// Throw a world hard enough and it stops coming back.
    func testAHardThrowUnbindsAWorld() {
        let model = OrbitalMechanicsModel()
        let at = SIMD3(1.5 * OrbitalMechanicsModel.metersPerAU, 0, 0)
        let id = try! XCTUnwrap(model.addBody(at: at))
        XCTAssertTrue(try! XCTUnwrap(
            model.readout(for: model.bodies.first { $0.id == id }!)).isBound)

        // 0.6 m/s hand × throwVelocityScale 8.6e4 ≈ 52 km/s on top of the 24 km/s circular orbit, over the ~34 km/s escape at 1.5 AU.
        model.grab(id: id, at: at, timestamp: 0)
        for sample in 1...9 {
            let t = Double(sample) / 90.0
            model.hold(id: id, at: at + SIMD3(0, 0, -0.6 * t), timestamp: t)
        }
        model.release(id: id, timestamp: 9.0 / 90.0)

        let thrown = model.bodies.first { $0.id == id }!
        XCTAssertFalse(try! XCTUnwrap(model.readout(for: thrown)).isBound,
                       "thrown past escape speed, it is leaving")
    }

    func testTimeScaleAndPause() {
        let model = OrbitalMechanicsModel()
        model.step(dt: 1.0 / 90.0)
        XCTAssertEqual(model.simulatedDays, 3.0 / 90.0, accuracy: 1e-9)

        model.timeScale = 100
        model.step(dt: 1.0 / 90.0)
        XCTAssertEqual(model.simulatedDays, 3.0 / 90.0 + 300.0 / 90.0, accuracy: 1e-9)

        model.isPaused = true
        let days = model.simulatedDays
        model.step(dt: 1.0 / 90.0)
        XCTAssertEqual(model.simulatedDays, days)
    }

    func testBodyBudgetIsEnforced() {
        let model = OrbitalMechanicsModel()
        for step in 0..<20 {
            // Spread out so the budget, not merging, is what stops this.
            let au = 1.5 + Double(step) * 0.4
            model.addBody(at: SIMD3(au * OrbitalMechanicsModel.metersPerAU, 0, 0))
        }
        XCTAssertEqual(model.bodies.count, OrbitalMechanicsModel.bodyBudget)
    }

    func testSunMassSliderRescalesLive() {
        let model = OrbitalMechanicsModel()
        model.sunMassMultiplier = 2.0
        XCTAssertEqual(model.primaryBody!.body.mass,
                       CelestialBody.sun.mass * 2, accuracy: 1e20)
        let earth = model.bodies.first { $0.body.name == "Earth" }!
        // Doubling the sun's mass grows escape speed at 1 AU by √2.
        let readout = try! XCTUnwrap(model.readout(for: earth))
        XCTAssertEqual(readout.escapeSpeedKmPerS, 42.1 * 2.0.squareRoot(), accuracy: 0.5)
    }

    /// Splitting the Sun into a binary conserves total mass and momentum; the pair is bound.
    func testMakeBinaryConservesMassAndMomentum() {
        let model = OrbitalMechanicsModel()
        let original = model.primaryBody!.body
        let originalMass = original.mass
        // In the barycentric frame the Sun is not at rest: it carries the
        // planets' momentum back. The pair must carry exactly that.
        let originalMomentum = original.mass * original.velocity

        model.makeBinary()

        let suns = model.bodies.filter { $0.body.name.hasPrefix("Sun") }
        XCTAssertEqual(suns.count, 2)
        XCTAssertEqual(suns.map(\.body.mass).reduce(0, +), originalMass, accuracy: 1e15)
        let momentum = suns.reduce(SIMD3<Double>.zero) { $0 + $1.body.mass * $1.body.velocity }
        XCTAssertEqual(simd_length(momentum - originalMomentum), 0,
                       accuracy: originalMass * 1e-9 + simd_length(originalMomentum) * 1e-9,
                       "the pair's total momentum matches the Sun it was split from")
        XCTAssertFalse(model.hasSingleSun)

        let pairEnergy = NBody.totalEnergy(bodies: suns.map(\.body))
        XCTAssertLessThan(pairEnergy, 0)

        // And it can't be split twice.
        let count = model.bodies.count
        model.makeBinary()
        XCTAssertEqual(model.bodies.count, count)
    }

    func testResetRestoresOpeningScene() {
        let model = OrbitalMechanicsModel()
        model.spawn(.mars)
        model.spawn(.jupiter)
        model.timeScale = 100
        model.gMultiplier = 3
        model.keplerSweepOn = true
        model.step(dt: 1)

        model.reset()

        XCTAssertEqual(model.bodies.count, 10)
        XCTAssertEqual(model.timeScale, 1)
        XCTAssertEqual(model.gMultiplier, 1)
        XCTAssertEqual(model.simulatedDays, 0)
        XCTAssertFalse(model.keplerSweepOn,
                       "the sweep waits behind the Show tab — off until asked for (2026-09-04)")
        XCTAssertNil(model.selectedBody, """
            nothing is selected on arrival: selection drives the ring, the \
            data card, the vectors and the sweep readout, and opening with \
            Earth selected stacked all four on the inner system at once
            """)
    }

    // MARK: The well's world

    /// A planet pulled from the well arrives in orbit — circular, at the radius the hand chose.
    func testAWorldFromTheWellArrivesOnACircularOrbit() {
        let model = OrbitalMechanicsModel()
        let id = model.addBody(at: SIMD3(0.45, 0, 0.18))!
        // Read after the spawn: adding a body settles the room's frame, which
        // moves every velocity by the same hair and none of the relative ones.
        let sun = model.primaryBody!.body
        let body = model.bodies.first { $0.id == id }!.body

        let offset = body.position - sun.position
        let relative = body.velocity - sun.velocity
        let distance = simd_length(offset)

        // M + m: the relative two-body orbit obeys r̈ = −G(M+m)r̂/r², used consistently in builders, readouts and ring.
        let expected = NBody.circularOrbitSpeed(
            centralMass: sun.mass + body.mass, distance: distance,
            gravitationalConstant: model.effectiveG)
        XCTAssertEqual(simd_length(relative), expected,
                       accuracy: expected * 1e-9,
                       "the new world is not moving at circular speed")
        // Circular means velocity ⟂ radius; anything else is an ellipse.
        XCTAssertEqual(simd_dot(simd_normalize(offset), simd_normalize(relative)),
                       0, accuracy: 1e-9,
                       "the new world's velocity is not perpendicular to its radius")
        XCTAssertEqual(relative.y, 0, accuracy: 1e-6,
                       "the new world was launched out of the plane")
        let existing = model.bodies.first {
            $0.id != id && $0.id != model.primaryBody?.id
        }!.body
        let newAngularMomentum = simd_cross(offset, relative)
        let oldAngularMomentum = simd_cross(existing.position - sun.position,
                                            existing.velocity - sun.velocity)
        XCTAssertGreaterThan(simd_dot(newAngularMomentum, oldAngularMomentum), 0,
                             "the new world orbits retrograde")
    }

    /// …and it stays on that orbit: same radius a simulated year later.
    func testAWorldFromTheWellHoldsItsRadius() {
        let model = OrbitalMechanicsModel()
        let sun = model.primaryBody!.body
        let id = model.addBody(at: SIMD3(0.45, 0, 0.18))!
        func radius() -> Double {
            let body = model.bodies.first { $0.id == id }!.body
            let primary = model.primaryBody!.body
            return simd_length(body.position - primary.position)
        }
        let start = radius()
        _ = sun
        for _ in 0..<2_000 { model.step(dt: 1.0 / 90.0) }
        XCTAssertEqual(radius(), start, accuracy: start * 0.02,
                       "the new world's orbit decayed or flew apart")
    }

    /// `addBody` respects the body budget — the renderer pools exactly `bodyBudget` spheres, so overflow would be invisible yet still gravitate.
    func testTheWellRespectsTheBodyBudget() {
        let model = OrbitalMechanicsModel()
        for index in 0..<20 {
            _ = model.addBody(at: SIMD3(0.4 + Double(index) * 0.01, 0, 0.2))
        }
        XCTAssertEqual(model.bodies.count, OrbitalMechanicsModel.bodyBudget)
    }


    // MARK: Reverse time

    /// The integrator is time-symmetric: run forward then back the same frames and the state returns.
    func testRunningTimeBackwardsRetracesTheSystem() {
        let model = OrbitalMechanicsModel()
        let id = model.bodies.first { $0.body.name == "Earth" }!.id
        func earth() -> CelestialBody { model.bodies.first { $0.id == id }!.body }

        let start = earth()
        for _ in 0..<600 { model.step(dt: 1.0 / 90.0) }
        let moved = earth()
        XCTAssertGreaterThan(
            simd_distance(moved.position, start.position),
            0.05 * CelestialBody.astronomicalUnit,
            "the system did not actually go anywhere")

        model.timeScale = -1
        for _ in 0..<600 { model.step(dt: 1.0 / 90.0) }
        let back = earth()

        let error = simd_distance(back.position, start.position)
            / CelestialBody.astronomicalUnit
        XCTAssertLessThan(error, 1e-6,
                          "time does not run backwards — the integrator is "
                          + "not reversible, or the substep count lost its sign")
        XCTAssertEqual(model.simulatedDays, 0, accuracy: 1e-9)
    }

    /// `ceil` of a negative substep count is <= 0 — reverse time must still substep, not leap once per frame.
    func testReverseTimeStillSubstepsInsteadOfLeaping() {
        let model = OrbitalMechanicsModel()
        let id = model.bodies.first { $0.body.name == "Mercury" }!.id
        model.timeScale = -20
        // At -20x a frame is 0.67 sim days of Mercury's 88-day year — an unsubstepped leap would show.
        for _ in 0..<400 { model.step(dt: 1.0 / 90.0) }
        let elements = model.orbitElements(for: id)!
        XCTAssertEqual(elements.eccentricity, 0, accuracy: 5e-3,
                       "Mercury's orbit decayed running backwards at 20x")
    }

    func testTheClockOffersReverseAndForward() {
        XCTAssertTrue(OrbitalMechanicsModel.timeScales.contains { $0 < 0 },
                      "the clock cannot run backwards")
        XCTAssertTrue(OrbitalMechanicsModel.timeScales.contains(1))
    }

    // MARK: The Lagrange layer

    /// The points belong to the selected planet against the primary.
    func testLagrangePointsFollowTheSelectedPlanet() {
        let model = OrbitalMechanicsModel()
        XCTAssertTrue(model.lagrangePoints.isEmpty, "shown without asking")

        model.showLagrangePoints = true
        let jupiter = model.bodies.first { $0.body.name == "Jupiter" }!
        model.select(id: jupiter.id)
        let points = model.lagrangePoints
        XCTAssertEqual(points.count, 5)
        XCTAssertEqual(Set(points.map(\.name)), ["L1", "L2", "L3", "L4", "L5"])

        // L4/L5 are equilateral: one orbital radius from both the Sun and the planet.
        let sun = model.primaryBody!.body.position
        let planet = jupiter.body.position
        let separation = simd_distance(sun, planet)
        for name in ["L4", "L5"] {
            let point = points.first { $0.name == name }!.position
            XCTAssertEqual(simd_distance(point, sun) / separation, 1, accuracy: 1e-6,
                           "\(name) is not equilateral with the Sun")
            XCTAssertEqual(simd_distance(point, planet) / separation, 1, accuracy: 1e-6,
                           "\(name) is not equilateral with the planet")
        }
        let l4 = points.first { $0.name == "L4" }!.position
        let l5 = points.first { $0.name == "L5" }!.position
        XCTAssertGreaterThan(simd_distance(l4, l5), separation)
    }

    /// Releasing a body onto a point matches it to the rotating frame.
    func testReleasingNearAPointInsertsItIntoTheRotatingFrame() {
        let model = OrbitalMechanicsModel()
        model.showLagrangePoints = true
        let jupiter = model.bodies.first { $0.body.name == "Jupiter" }!
        model.select(id: jupiter.id)
        let l4 = model.lagrangePoints.first { $0.name == "L4" }!.position

        let id = model.addBody(at: l4 * model.simToDisplay)!
        model.grab(id: id, at: l4 * model.simToDisplay, timestamp: 0)
        model.hold(id: id, at: l4 * model.simToDisplay, timestamp: 0)
        model.release(id: id, timestamp: 0.05)

        XCTAssertEqual(model.capturedPointName, "L4")
        let parked = model.bodies.first { $0.id == id }!.body
        XCTAssertEqual(simd_distance(parked.position, l4)
                       / CelestialBody.astronomicalUnit, 0, accuracy: 1e-9)
        // L4 is stable: still near the point much later.
        for _ in 0..<2_000 { model.step(dt: 1.0 / 90.0) }
        let now = model.bodies.first { $0.id == id }!.body.position
        let sun = model.primaryBody!.body.position
        let radius = simd_distance(now, sun)
        let jupiterRadius = simd_distance(
            model.bodies.first { $0.body.name == "Jupiter" }!.body.position, sun)
        XCTAssertEqual(radius / jupiterRadius, 1, accuracy: 0.05,
                       "the Trojan fell out of its orbit")
    }

    // MARK: Budget

    func testTheBudgetLeavesRoomToBuildSomething() {
        let model = OrbitalMechanicsModel()
        // reset() alone puts ten bodies in the scene.
        XCTAssertGreaterThanOrEqual(OrbitalMechanicsModel.bodyBudget,
                                    model.bodies.count + 4,
                                    "the opening scene leaves almost no room to add worlds")
    }

    // MARK: The frame

    private func momentum(_ model: OrbitalMechanicsModel) -> Double {
        simd_length(NBody.momentum(of: model.bodies.map(\.body)))
    }

    private func momentumScale(_ model: OrbitalMechanicsModel) -> Double {
        model.bodies.reduce(0) { $0 + $1.body.mass * simd_length($1.body.velocity) }
    }

    /// The system carries no net momentum and its barycentre stays at the
    /// origin, so nothing drifts across the room: the opening scene used to
    /// walk at 16 m/s (2.5 m of room per half hour at 100×).
    func testTheSystemHasNoNetMomentumAndItsBarycentreStaysPut() {
        let model = OrbitalMechanicsModel()
        XCTAssertLessThan(momentum(model), 1e-9 * momentumScale(model), "the opening scene drifts")
        // The Sun starts on the origin; the barycentre sits a few millimetres
        // of room away and must stay exactly there.
        let barycentre = NBody.barycentre(of: model.bodies.map(\.body))
        XCTAssertLessThan(simd_length(barycentre), 0.02 * CelestialBody.astronomicalUnit)

        model.timeScale = 100
        for _ in 0..<900 { model.step(dt: 1.0 / 90.0) }
        XCTAssertLessThan(simd_distance(NBody.barycentre(of: model.bodies.map(\.body)), barycentre),
                          1e-6 * CelestialBody.astronomicalUnit, "the barycentre moved")

        model.spawn(.jupiter)
        XCTAssertLessThan(momentum(model), 1e-9 * momentumScale(model), "spawning left a drift")
        let worldID = model.addBody(at: SIMD3(0.9, 0, 0.3))!
        XCTAssertLessThan(momentum(model), 1e-9 * momentumScale(model), "a new world left a drift")
        let earth = model.bodies.first { $0.body.name == "Earth" }!
        model.grab(id: earth.id, at: SIMD3(0.4, 0.1, 0.4), timestamp: 10)
        model.hold(id: earth.id, at: SIMD3(0.4, 0.1, 0.35), timestamp: 10.1)
        model.release(id: earth.id, timestamp: 10.1)
        XCTAssertLessThan(momentum(model), 1e-9 * momentumScale(model), "a throw left a drift")
        model.removeBody(id: worldID)
        XCTAssertLessThan(momentum(model), 1e-9 * momentumScale(model), "a deletion left a drift")
        model.setMass(id: earth.id, earths: 10)
        XCTAssertLessThan(momentum(model), 1e-9 * momentumScale(model), "a mass edit left a drift")
        model.makeBinary()
        XCTAssertLessThan(momentum(model), 1e-9 * momentumScale(model), "the binary left a drift")
    }

    /// The step follows the shortest timescale present: the default system
    /// keeps its 6 h step (14 substeps at 100×), a body dragged to 0.05 AU
    /// asks for far more and gets the frame budget, and 1× is one step.
    func testSubstepsFollowTheShortestTimescalePresent() {
        let model = OrbitalMechanicsModel()
        let g = model.effectiveG
        let frame = (1.0 / 90.0) * OrbitalMechanicsModel.daysPerSecond * 86_400
        let bodies = model.bodies.map(\.body)
        XCTAssertEqual(OrbitalMechanicsModel.substepCount(
            simDt: 100 * frame, bodies: bodies, gravitationalConstant: g), 14)
        XCTAssertEqual(OrbitalMechanicsModel.substepCount(
            simDt: frame, bodies: bodies, gravitationalConstant: g), 1)
        // A 90 Hz frame at −20× is 57 600 s: three steps of the 6 h cap, backwards.
        XCTAssertEqual(OrbitalMechanicsModel.substepCount(
            simDt: -20 * frame, bodies: bodies, gravitationalConstant: g), 3)

        let close = [CelestialBody.sun,
                     CelestialBody.mercury.onCircularOrbit(
                        of: .sun, distance: 0.05 * CelestialBody.astronomicalUnit)]
        XCTAssertEqual(OrbitalMechanicsModel.substepCount(
            simDt: 100 * frame, bodies: close, gravitationalConstant: g),
            OrbitalMechanicsModel.maxSubstepsPerFrame)
    }

    /// Merges are checked every substep: a world thrown at 140 km/s crosses
    /// 0.27 AU per frame at 100×, and used to skip a 0.1 AU merge sphere.
    func testAFastBodyCannotTunnelThroughAMerge() {
        let model = OrbitalMechanicsModel()
        let mars = model.bodies.first { $0.body.name == "Mars" }!
        let au = CelestialBody.astronomicalUnit
        let toDisplay = model.simToDisplay
        // Mars moves −z. Start the world 0.48 AU behind it on its track, and let
        // the hand carry it to 0.15 AU behind while building 1.63 m/s of throw.
        let start = (mars.body.position + SIMD3(0, 0, 0.48 * au)) * toDisplay
        let id = model.addBody(at: start)!
        model.grab(id: id, at: start, timestamp: 0)
        for sample in 1...9 {
            let t = Double(sample) / 90.0
            model.hold(id: id, at: start + SIMD3(0, 0, -1.63 * t), timestamp: t)
        }
        model.release(id: id, timestamp: 9.0 / 90.0)
        let thrown = model.bodies.first { $0.id == id }!
        XCTAssertGreaterThan(-thrown.body.velocity.z, 1.2e5, "the throw is not fast enough to tunnel")
        XCTAssertEqual(model.bodies.count, 11)

        model.timeScale = 100
        model.step(dt: 1.0 / 90.0)
        XCTAssertEqual(model.bodies.count, 10, "the world passed through Mars without merging")
    }

    /// Alone with the Sun, a planet's apse line holds: the visible creep of
    /// the beads is perturbation, never the integrator. Leapfrog at the
    /// app's ≥5× step turned Mercury 119″ per orbit, backwards.
    func testAnIsolatedPlanetDoesNotPrecessInTheModel() {
        let model = OrbitalMechanicsModel()
        let mercuryID = model.bodies.first { $0.body.name == "Mercury" }!.id
        let sunID = model.primaryBody!.id
        for body in model.bodies where body.id != mercuryID && body.id != sunID {
            model.removeBody(id: body.id)
        }
        XCTAssertEqual(model.bodies.count, 2)

        func eccentricityVector() -> (e: SIMD3<Double>, h: SIMD3<Double>) {
            let sun = model.bodies.first { $0.id == sunID }!.body
            let mercury = model.bodies.first { $0.id == mercuryID }!.body
            let r = mercury.position - sun.position, v = mercury.velocity - sun.velocity
            let h = simd_cross(r, v)
            let mu = model.effectiveG * (sun.mass + mercury.mass)
            return (simd_cross(v, h) / mu - simd_normalize(r), h)
        }
        // A circular seed has no apse line: give it Mercury's eccentricity by a
        // bead drag, then let go.
        XCTAssertTrue(model.beginOrbitEdit(bodyID: mercuryID, holding: .far))
        let sun = model.bodies.first { $0.id == sunID }!.body.position
        let mercury = model.bodies.first { $0.id == mercuryID }!.body.position
        let direction = simd_normalize(mercury - sun)
        // Periapsis stays at 0.387 AU; an apoapsis at 0.587 AU is e = 0.2056.
        let apoapsis: Double = 0.587 * CelestialBody.astronomicalUnit
        let farBead: SIMD3<Double> = sun + direction * apoapsis
        model.dragApsis(toDisplayPoint: farBead * model.simToDisplay)
        model.endOrbitEdit()
        let (e0, normal) = eccentricityVector()
        XCTAssertGreaterThan(simd_length(e0), 0.1, "the drag did not make an eccentric orbit")

        model.timeScale = 20
        let period = model.readout(for: model.bodies.first { $0.id == mercuryID }!)!.periodDays!
        let frames = Int((20 * period / (20 * OrbitalMechanicsModel.daysPerSecond / 90)).rounded())
        for _ in 0..<frames { model.step(dt: 1.0 / 90.0) }
        let (e1, _) = eccentricityVector()
        let turn = atan2(simd_dot(simd_cross(e0, e1), simd_normalize(normal)), simd_dot(e0, e1))
        let arcsecondsPerOrbit = turn * 180 / .pi * 3600 / 20
        XCTAssertLessThan(abs(arcsecondsPerOrbit), 0.5,
                          "an isolated orbit precessed \(arcsecondsPerOrbit)″ per orbit")
    }

    // MARK: Trails

    private func trailSpan(_ model: OrbitalMechanicsModel, _ name: String) -> Double {
        let body = model.bodies.first { $0.body.name == name }!
        return body.trail.angularSpan(about: model.primaryBody!.body.position)
    }

    /// Every body trails the same fraction of ITS OWN orbit, whatever its
    /// radius and whatever the clock: the same 1.9 m of ribbon for everyone
    /// gave Mercury 1.6 laps and Neptune a stub.
    func testEveryBodyTrailsTheSameFractionOfItsOwnOrbit() {
        let expected = OrbitTrail.fraction * 2 * Double.pi
        let model = OrbitalMechanicsModel()
        model.timeScale = 100
        for _ in 0..<600 { model.step(dt: 1.0 / 90.0) }   // 2 000 days
        for name in ["Mercury", "Venus", "Earth", "Mars"] {
            XCTAssertEqual(trailSpan(model, name), expected, accuracy: 0.06,
                           "\(name) trails \(trailSpan(model, name)) rad of its orbit at 100×")
        }
        // Jupiter's window (3 250 d) is still filling after 2 000 d.
        XCTAssertEqual(trailSpan(model, "Jupiter"), 2 * .pi * 2000 / 4333, accuracy: 0.06)

        let slow = OrbitalMechanicsModel()
        for _ in 0..<2100 { slow.step(dt: 1.0 / 90.0) }   // 70 days at 1×
        XCTAssertEqual(trailSpan(slow, "Mercury"), expected, accuracy: 0.06,
                       "Mercury trails \(trailSpan(slow, "Mercury")) rad of its orbit at 1×")
    }

    /// Samples are spaced by angle, so the path's density does not depend on
    /// how fast the clock runs.
    func testTrailSamplingIsUniformInAngleAtEveryClockSpeed() {
        func gaps(_ model: OrbitalMechanicsModel, _ name: String) -> (min: Double, max: Double) {
            let body = model.bodies.first { $0.body.name == name }!
            let centre = model.primaryBody!.body.position
            var smallest = Double.infinity, largest = 0.0
            for (a, b) in zip(body.trail.samples, body.trail.samples.dropFirst()) {
                let u = simd_normalize(a.position - centre), v = simd_normalize(b.position - centre)
                let gap = acos(min(max(simd_dot(u, v), -1), 1))
                smallest = min(smallest, gap); largest = max(largest, gap)
            }
            return (smallest, largest)
        }
        let fast = OrbitalMechanicsModel()
        fast.timeScale = 100
        for _ in 0..<600 { fast.step(dt: 1.0 / 90.0) }
        let slow = OrbitalMechanicsModel()
        for _ in 0..<2100 { slow.step(dt: 1.0 / 90.0) }
        for model in [fast, slow] {
            let earth = gaps(model, "Earth")
            XCTAssertLessThan(earth.max / earth.min, 1.5, "Earth's samples bunch: \(earth)")
            XCTAssertGreaterThanOrEqual(earth.min, OrbitTrail.angularStep * 0.99)
            XCTAssertLessThan(earth.max, OrbitTrail.angularStep * 2.5)
        }
    }

    /// A full trail keeps following its body — the old mesh froze in space
    /// once its point count stopped changing.
    func testASaturatedTrailKeepsFollowingTheBody() {
        let model = OrbitalMechanicsModel()
        model.timeScale = 100
        for _ in 0..<900 { model.step(dt: 1.0 / 90.0) }
        let now = model.simulatedSeconds
        let centre = model.primaryBody!.body.position
        for body in model.bodies where body.id != model.primaryBody!.id {
            let newest = body.trail.newest!
            let radius = simd_distance(body.body.position, centre)
            XCTAssertLessThan(simd_distance(newest.position, body.body.position), 0.05 * radius,
                              "\(body.body.name)'s trail ends \(simd_distance(newest.position, body.body.position) / radius) radii behind it")
            let window = model.trailWindow(for: body)
            XCTAssertGreaterThanOrEqual(body.trail.oldest!.time, now - window - 30 * 86_400,
                                        "\(body.body.name)'s trail reaches past its window")
        }
    }

    /// Running the clock backwards eats each trail from the body's end.
    func testReversingTimeUnwindsTheTrails() {
        let model = OrbitalMechanicsModel()
        for _ in 0..<300 { model.step(dt: 1.0 / 90.0) }
        let forward = trailSpan(model, "Mercury")
        XCTAssertGreaterThan(forward, 0.5)
        model.timeScale = -1
        for _ in 0..<150 { model.step(dt: 1.0 / 90.0) }
        XCTAssertEqual(trailSpan(model, "Mercury"), forward / 2, accuracy: forward * 0.15,
                       "half the frames back should leave half the trail")
        for _ in 0..<150 { model.step(dt: 1.0 / 90.0) }
        for body in model.bodies {
            XCTAssertTrue(body.trail.isEmpty, "\(body.body.name) still trails after a full rewind")
        }
    }

    /// A scrub rebuilds each trail to its own window at the restored instant:
    /// the old rebuild walked the whole recording and every trail changed length.
    func testScrubKeepsTheTrailWindow() {
        let model = OrbitalMechanicsModel()
        model.clearCapsule()
        model.timeScale = 100
        for _ in 0..<300 { model.step(dt: 1.0 / 90.0) }
        model.isPaused = true
        model.scrub(toOffset: 0.1)
        let now = model.simulatedSeconds
        let mercury = model.bodies.first { $0.body.name == "Mercury" }!
        let window = model.trailWindow(for: mercury)
        XCTAssertLessThanOrEqual(mercury.trail.newest!.time, now)
        XCTAssertGreaterThan(mercury.trail.newest!.time, now - 2 * 3.4 * 86_400,
                             "the scrubbed trail does not reach the body")
        XCTAssertGreaterThanOrEqual(mercury.trail.oldest!.time, now - window - 3.4 * 86_400)
        let span = trailSpan(model, "Mercury")
        let expected = OrbitTrail.fraction * 2 * Double.pi
        XCTAssertGreaterThan(span, expected - 0.3, "the scrubbed trail is short: \(span)")
        XCTAssertLessThan(span, expected + 0.06, "the scrubbed trail is long: \(span)")
    }

    /// A merge's survivor starts a fresh trail, and nothing carries the dead ids.
    func testAMergedBodyLeavesNoTrail() {
        let model = OrbitalMechanicsModel()
        for _ in 0..<200 { model.step(dt: 1.0 / 90.0) }
        let venusID = model.bodies.first { $0.body.name == "Venus" }!.id
        let earthID = model.bodies.first { $0.body.name == "Earth" }!.id
        let venusDisplay = model.bodies.first { $0.id == venusID }!.body.position * model.simToDisplay
        model.grab(id: earthID, at: venusDisplay, timestamp: 80)
        model.release(id: earthID, timestamp: 80.1)
        model.step(dt: 1.0 / 90.0)
        XCTAssertEqual(model.bodies.count, 9)
        XCTAssertFalse(model.bodies.contains { $0.id == venusID || $0.id == earthID })
        let survivor = model.bodies.first { $0.body.name == "Earth" }!
        XCTAssertLessThanOrEqual(survivor.trail.samples.count, 1, "the survivor inherited a trail")
    }

    // MARK: The fan

    /// Every world the fan offers survives its first frames: the Moon preset
    /// used to merge into Earth on frame one, and is gone.
    func testTheFanOffersOnlyWorldsTheScaleCanShow() {
        XCTAssertFalse(OrbitalMechanicsModel.Preset.allCases.contains { $0.rawValue == "moon" })
        XCTAssertEqual(OrbitalMechanicsModel.Preset.allCases.count, 9)
        for preset in OrbitalMechanicsModel.Preset.allCases {
            let model = OrbitalMechanicsModel()
            // The seeded planets have moved off their spawn points.
            model.timeScale = 100
            for _ in 0..<90 { model.step(dt: 1.0 / 90.0) }
            model.spawn(preset)
            XCTAssertEqual(model.bodies.count, 11, "\(preset) did not spawn")
            for _ in 0..<30 { model.step(dt: 1.0 / 90.0) }
            XCTAssertEqual(model.bodies.count, 11, "\(preset) merged within its first frames")
        }
    }

    /// A guess about a planet that is gone has nothing to resolve against:
    /// deleting the planet takes its ghost with it, rather than leaving a
    /// countdown over empty sky that ends in no verdict.
    func testThePredictionGoesWithItsPlanet() throws {
        let model = OrbitalMechanicsModel()
        let earth = try XCTUnwrap(model.bodies.first { $0.body.name == "Earth" })
        model.select(id: earth.id)
        model.armPrediction()
        XCTAssertEqual(model.prediction?.bodyID, earth.id)

        model.removeBody(id: earth.id)
        XCTAssertNil(model.prediction)
    }

    /// More's "Add a world" grid and Twin suns grey out exactly where the
    /// model would refuse them: at the body budget, where they once stayed
    /// lit and did nothing.
    func testTheAddControlsKnowWhenTheSystemIsFull() throws {
        let model = OrbitalMechanicsModel()
        XCTAssertTrue(model.hasRoomForABody)
        var radius = 0.6
        while model.bodies.count < OrbitalMechanicsModel.bodyBudget {
            _ = try XCTUnwrap(model.addBody(at: SIMD3(radius, 1.2, 0)))
            radius += 0.07
        }
        XCTAssertFalse(model.hasRoomForABody)

        let more = OrbitalMechanicsModule.more(model)
        let binary = try XCTUnwrap(more.first { $0.id == "binary" })
        guard case let .action(_, _, _, _, _, isEnabled, _) = binary else {
            return XCTFail("Twin suns is no longer an action")
        }
        XCTAssertFalse(isEnabled(), "Twin suns stayed lit with no room for a second sun")
        let worlds = try XCTUnwrap(more.first { $0.id == "worlds" })
        guard case let .verbs(_, _, _, gridEnabled, _) = worlds else {
            return XCTFail("Add a world is no longer a grid")
        }
        XCTAssertFalse(gridEnabled(), "Add a world stayed lit at the budget")
    }
}
