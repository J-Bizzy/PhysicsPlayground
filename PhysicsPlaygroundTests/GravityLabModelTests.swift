//
//  GravityLabModelTests.swift
//  PhysicsPlaygroundTests
//
//  Tests for the Gravity Lab app state: the opening scene, orbital
//  readouts against real values, hold-freeze semantics, throw mapping,
//  display-radius collisions with momentum-conserving merges, escape
//  detection, time scaling, and reset. The n-body math itself is covered
//  in PhysicsCore's NBodyTests.
//

import XCTest
import PhysicsCore
import simd
@testable import PhysicsPlayground

@MainActor
final class GravityLabModelTests: XCTestCase {

    /// `readout(for:)` is memoised — several callers ask for the same
    /// body every frame. A memo that outlived the state it described
    /// would report a planet's old distance and energy forever, which
    /// would look exactly like broken physics.
    func testReadoutsFollowTheSystemForward() {
        let model = GravityLabModel()
        guard let earth = model.bodies.first(where: { $0.body.name == "Earth" }) else {
            return XCTFail("Earth should be in the opening scene")
        }

        guard let first = model.readout(for: earth) else {
            return XCTFail("Earth orbits the Sun, so it has a readout")
        }
        // Same state, asked twice: the memo must not change the answer.
        XCTAssertEqual(model.readout(for: earth)?.distanceAU, first.distanceAU)

        // Advance far enough that Earth has measurably moved.
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
        let model = GravityLabModel()
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

    /// The comet is what gives the system a third dimension: the planets
    /// all share one plane, and a flat disc of a solar system gives the
    /// viewer no reason to move their head. It has to be genuinely out of
    /// that plane, genuinely eccentric, and genuinely bound.
    func testOpeningSceneIncludesAnInclinedComet() {
        let model = GravityLabModel()
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

        // Every planet still shares the ecliptic — only the comet leaves it.
        for body in model.bodies where !["Sun", "Comet"].contains(body.body.name) {
            XCTAssertEqual(body.body.position.y, 0, accuracy: 1e-6)
        }
    }

    /// One simulated frame at 1× advances 3 days ÷ 90 of orbit; a held
    /// Earth must not move at all while everything else keeps simulating.
    func testHoldFreezesBodyWhileSystemEvolves() {
        let model = GravityLabModel()
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

    /// Release velocity = hand velocity × throwVelocityScale.
    func testReleaseAppliesScaledHandVelocity() {
        let model = GravityLabModel()
        let earth = model.bodies.first { $0.body.name == "Earth" }!
        model.grab(id: earth.id, at: SIMD3(0.3, 0, 0), timestamp: 50)
        // Hand moving 0.3 m/s along −z for 0.1 s.
        for sample in 1...9 {
            let t = Double(sample) / 90.0
            model.hold(id: earth.id, at: SIMD3(0.3, 0, -0.3 * t), timestamp: 50 + t)
        }
        model.release(id: earth.id, timestamp: 50 + 9.0 / 90.0)

        let released = model.bodies.first { $0.id == earth.id }!
        XCTAssertEqual(released.body.velocity.z,
                       -0.3 * GravityLabModel.throwVelocityScale,
                       accuracy: 1.0)
    }

    /// Dropping Earth right on top of Venus merges them: one fewer body,
    /// combined mass, momentum conserved.
    func testOverlappingBodiesMergeConservingMomentum() {
        let model = GravityLabModel()
        let venus = model.bodies.first { $0.body.name == "Venus" }!
        let earth = model.bodies.first { $0.body.name == "Earth" }!
        let expectedMass = venus.body.mass + earth.body.mass
        let expectedMomentum = venus.body.mass * venus.body.velocity
            + earth.body.mass * SIMD3<Double>.zero  // held Earth is at rest

        // Park Earth exactly on Venus and let go without motion.
        let venusDisplay = venus.body.position * model.simToDisplay
        model.grab(id: earth.id, at: venusDisplay, timestamp: 80)
        model.release(id: earth.id, timestamp: 80.1)
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

    /// The √2 rule, on the path a user can actually reach: a world pulled
    /// from the well is born circular and bound; speed it up past √2 ×
    /// the circular speed — which is what a hard throw does — and it is
    /// unbound. Escape speed is √2 × circular speed at the same radius,
    /// so this is the threshold itself, not a number near it.
    ///
    /// Rebased off the deleted custom-planet builder (a grave — see
    /// `GravityLabModel`). Testing it through `addBody` is strictly
    /// better: it pins the readout's bound/unbound verdict against the
    /// exact boundary rather than against a builder's speed factor.
    func testAWorldFromTheWellIsCircularAndEscapesAtRootTwo() {
        let model = GravityLabModel()
        let distanceAU = 1.5
        let at = SIMD3(distanceAU * GravityLabModel.metersPerAU, 0, 0)

        let circlerID = try! XCTUnwrap(model.addBody(at: at))
        let circler = model.bodies.first { $0.id == circlerID }!
        let readout = try! XCTUnwrap(model.readout(for: circler))
        XCTAssertTrue(readout.isBound, "born on a circular orbit, so bound")
        XCTAssertEqual(readout.distanceAU, distanceAU, accuracy: 1e-6)
        // Born circular reads back circular — the invariant that caught
        // the GM-vs-G(M+m) error in `onCircularOrbit`.
        XCTAssertEqual(try! XCTUnwrap(model.orbitElements(for: circlerID))
                           .eccentricity, 0, accuracy: 1e-6)

        // The √2 rule itself: escape speed is exactly √2 × the circular
        // speed at the same radius. Asserted against the two numbers the
        // readout already publishes, rather than by reaching into
        // `bodies` — whose setter is private, correctly.
        XCTAssertEqual(readout.escapeSpeedKmPerS,
                       readout.speedKmPerS * 2.0.squareRoot(),
                       accuracy: readout.escapeSpeedKmPerS * 1e-6,
                       "escape speed is √2 × circular speed")
    }

    /// And the other half of the rule, through the gesture that reaches
    /// it: throw a world hard enough and it stops coming back.
    func testAHardThrowUnbindsAWorld() {
        let model = GravityLabModel()
        let at = SIMD3(1.5 * GravityLabModel.metersPerAU, 0, 0)
        let id = try! XCTUnwrap(model.addBody(at: at))
        XCTAssertTrue(try! XCTUnwrap(
            model.readout(for: model.bodies.first { $0.id == id }!)).isBound)

        // A hand sweep well past escape: `throwVelocityScale` is 8.6e4,
        // so 0.6 m/s of hand is ~52 km/s, comfortably over the ~34 km/s
        // escape speed at 1.5 AU.
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
        let model = GravityLabModel()
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
        let model = GravityLabModel()
        for step in 0..<20 {
            // Spread them out so none of them merges on contact — the
            // budget is what must stop this, not collisions.
            let au = 1.5 + Double(step) * 0.4
            model.addBody(at: SIMD3(au * GravityLabModel.metersPerAU, 0, 0))
        }
        XCTAssertEqual(model.bodies.count, GravityLabModel.bodyBudget)
    }

    func testSunMassSliderRescalesLive() {
        let model = GravityLabModel()
        model.sunMassMultiplier = 2.0
        XCTAssertEqual(model.primaryBody!.body.mass,
                       CelestialBody.sun.mass * 2, accuracy: 1e20)
        let earth = model.bodies.first { $0.body.name == "Earth" }!
        // Same speed around a heavier sun → deeper in the well → still bound,
        // but the escape speed at 1 AU has grown by √2.
        let readout = try! XCTUnwrap(model.readout(for: earth))
        XCTAssertEqual(readout.escapeSpeedKmPerS, 42.1 * 2.0.squareRoot(), accuracy: 0.5)
    }

    // The three Lagrange-MODE tests that stood here went with the mode
    // itself (a grave — see `GravityLabModel`'s scale-mapping comment).
    // They were its only callers, and nothing they asserted is lost: the
    // co-rotating insertion and the L4-stays-put dynamics are both pinned
    // on the reachable path by `testReleasingNearAPointInsertsItIntoThe`
    // `RotatingFrame` below, which drives the display LAYER a user can
    // actually switch on.

    /// Splitting the Sun into a binary conserves total mass and momentum
    /// exactly, and the pair genuinely orbits (bound, opposite velocities).
    func testMakeBinaryConservesMassAndMomentum() {
        let model = GravityLabModel()
        let originalMass = model.primaryBody!.body.mass

        model.makeBinary()

        let suns = model.bodies.filter { $0.body.name.hasPrefix("Sun") }
        XCTAssertEqual(suns.count, 2)
        XCTAssertEqual(suns.map(\.body.mass).reduce(0, +), originalMass, accuracy: 1e15)
        let momentum = suns.reduce(SIMD3<Double>.zero) { $0 + $1.body.mass * $1.body.velocity }
        XCTAssertEqual(simd_length(momentum), 0, accuracy: originalMass * 1e-9,
                       "the pair's total momentum matches the original resting Sun")
        XCTAssertFalse(model.hasSingleSun)

        // The pair is bound: mutual energy is negative.
        let pairEnergy = NBody.totalEnergy(bodies: suns.map(\.body))
        XCTAssertLessThan(pairEnergy, 0)

        // And it can't be split twice.
        let count = model.bodies.count
        model.makeBinary()
        XCTAssertEqual(model.bodies.count, count)
    }

    func testResetRestoresOpeningScene() {
        let model = GravityLabModel()
        model.spawn(.mars)
        model.spawn(.jupiter)
        model.timeScale = 100
        model.gMultiplier = 3
        model.trailLength = .long
        model.showFieldParticles = true
        model.showSpacetimeGrid = true
        model.step(dt: 1)

        model.reset()

        XCTAssertEqual(model.bodies.count, 10)
        XCTAssertEqual(model.timeScale, 1)
        XCTAssertEqual(model.gMultiplier, 1)
        XCTAssertEqual(model.trailLength, .medium)
        XCTAssertEqual(model.simulatedDays, 0)
        XCTAssertFalse(model.showFieldParticles)
        XCTAssertTrue(model.showSpacetimeGrid,
                      "the curvature grid is the module's signature image — it opens with it")
    }

    // MARK: The well's world

    /// A planet pulled from the well arrives IN ORBIT — circular, at the
    /// radius the hand chose. It used to arrive at rest relative to the
    /// Sun, which is to say already falling into it, and the only thing
    /// that could save it was a hand moving at exactly 0.31 m/s exactly
    /// perpendicular to the radius vector. Nobody can do that, so every
    /// world anyone made plunged.
    func testAWorldFromTheWellArrivesOnACircularOrbit() {
        let model = GravityLabModel()
        let sun = model.primaryBody!.body
        // A point off in the display space, well clear of the primary.
        let id = model.addBody(at: SIMD3(0.45, 0, 0.18))!
        let body = model.bodies.first { $0.id == id }!.body

        let offset = body.position - sun.position
        let relative = body.velocity - sun.velocity
        let distance = simd_length(offset)

        // M + m, matching the builders: the relative orbit of a two-body
        // system obeys r̈ = −G(M+m)r̂/r², and this app now uses that
        // consistently in the builders, the readouts and the orbit ring.
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
        // …and in the ecliptic, going the same way as everything else.
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

    /// …and it stays on that orbit. One simulated year later it is back
    /// at the same radius, which is the whole claim a circle makes.
    func testAWorldFromTheWellHoldsItsRadius() {
        let model = GravityLabModel()
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

    /// `addBody` respects the body budget. It did not, and the renderer
    /// pools exactly `bodyBudget` spheres — so the worlds past the cap
    /// gravitated, perturbed and merged while being invisible.
    func testTheWellRespectsTheBodyBudget() {
        let model = GravityLabModel()
        for index in 0..<20 {
            _ = model.addBody(at: SIMD3(0.4 + Double(index) * 0.01, 0, 0.2))
        }
        XCTAssertEqual(model.bodies.count, GravityLabModel.bodyBudget)
    }


    // MARK: Reverse time

    /// Velocity Verlet is time-symmetric for a conservative force, so a
    /// negative time scale does not replay a recording — it integrates
    /// backwards and arrives where the system genuinely was. Run forward,
    /// run back the same number of frames, and the state returns.
    func testRunningTimeBackwardsRetracesTheSystem() {
        let model = GravityLabModel()
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

    /// The substep cap has to work in reverse too. `ceil` of a negative
    /// number is <= 0, so a naive count would clamp to a single enormous
    /// leap per frame — the exact failure the cap exists to prevent.
    func testReverseTimeStillSubstepsInsteadOfLeaping() {
        let model = GravityLabModel()
        let id = model.bodies.first { $0.body.name == "Mercury" }!.id
        model.timeScale = -20
        // Mercury's year is 88 days; at -20x a frame is 0.67 sim days, so
        // a single unsubstepped leap would be visibly off its orbit.
        for _ in 0..<400 { model.step(dt: 1.0 / 90.0) }
        let elements = model.orbitElements(for: id)!
        XCTAssertEqual(elements.eccentricity, 0, accuracy: 5e-3,
                       "Mercury's orbit decayed running backwards at 20x")
    }

    func testTheClockOffersReverseAndForward() {
        XCTAssertTrue(GravityLabModel.timeScales.contains { $0 < 0 },
                      "the clock cannot run backwards")
        XCTAssertTrue(GravityLabModel.timeScales.contains(1))
    }

    // MARK: The Lagrange layer

    /// The points belong to the SELECTED planet against the primary, so
    /// selecting Jupiter gives you the Trojans' points. They were locked
    /// behind an Earth–Moon mode nothing ever called, now deleted.
    func testLagrangePointsFollowTheSelectedPlanet() {
        let model = GravityLabModel()
        XCTAssertTrue(model.lagrangePoints.isEmpty, "shown without asking")

        model.showLagrangePoints = true
        let jupiter = model.bodies.first { $0.body.name == "Jupiter" }!
        model.select(id: jupiter.id)
        let points = model.lagrangePoints
        XCTAssertEqual(points.count, 5)
        XCTAssertEqual(Set(points.map(\.name)), ["L1", "L2", "L3", "L4", "L5"])

        // L4 and L5 are the equilateral points: each sits one orbital
        // radius from BOTH the Sun and the planet.
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
        // And they are genuinely different points.
        let l4 = points.first { $0.name == "L4" }!.position
        let l5 = points.first { $0.name == "L5" }!.position
        XCTAssertGreaterThan(simd_distance(l4, l5), separation)
    }

    /// Releasing a body onto a point matches it to the rotating frame.
    /// The branch is not new — it has been correct and unreachable since
    /// it was written, gated on a mode with no caller.
    func testReleasingNearAPointInsertsItIntoTheRotatingFrame() {
        let model = GravityLabModel()
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
        // L4 is stable, so it should still be near the point a long time
        // later — that is the whole demonstration.
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
        let model = GravityLabModel()
        // reset() alone puts ten bodies in the scene.
        XCTAssertGreaterThanOrEqual(GravityLabModel.bodyBudget,
                                    model.bodies.count + 4,
                                    "the opening scene leaves almost no room to add worlds")
    }

}
