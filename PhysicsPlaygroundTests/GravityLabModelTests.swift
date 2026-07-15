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

    func testOpeningSceneIsSunAndEarthOnRealOrbit() {
        let model = GravityLabModel()
        XCTAssertEqual(model.bodies.count, 2)
        XCTAssertEqual(model.primaryBody?.body.name, "Sun")

        let earth = model.bodies.first { $0.body.name == "Earth" }!
        let readout = try! XCTUnwrap(model.readout(for: earth))
        XCTAssertEqual(readout.distanceAU, 1.0, accuracy: 1e-6)
        XCTAssertEqual(readout.speedKmPerS, 29.78, accuracy: 0.1)
        XCTAssertEqual(try! XCTUnwrap(readout.periodDays), 365.25, accuracy: 1.0)
        XCTAssertTrue(readout.isBound)
        XCTAssertLessThan(readout.totalEnergy, 0, "a bound orbit has negative total energy")
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
                       -0.3 * model.throwVelocityScale,
                       accuracy: 1.0)
    }

    /// Dropping Earth right on top of Venus merges them: one fewer body,
    /// combined mass, momentum conserved.
    func testOverlappingBodiesMergeConservingMomentum() {
        let model = GravityLabModel()
        model.spawn(.venus)
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

        XCTAssertEqual(model.bodies.count, 2, "Sun + merged body")
        let merged = model.bodies.first { $0.body.name != "Sun" }!
        XCTAssertEqual(merged.body.mass, expectedMass, accuracy: expectedMass * 1e-9)
        XCTAssertEqual(merged.body.mass * merged.body.velocity.z,
                       expectedMomentum.z,
                       accuracy: abs(expectedMomentum.z) * 1e-6)
    }

    /// The custom builder's √2 rule: ×1.5 circular speed is unbound,
    /// ×1.0 is a circle.
    func testCustomPlanetEscapeBoundary() {
        let model = GravityLabModel()
        model.customSpeedFactor = 1.5
        model.spawnCustom()
        let flyer = model.selectedBody!
        XCTAssertFalse(try! XCTUnwrap(model.readout(for: flyer)).isBound)

        model.customSpeedFactor = 1.0
        model.spawnCustom()
        let circler = model.selectedBody!
        let readout = try! XCTUnwrap(model.readout(for: circler))
        XCTAssertTrue(readout.isBound)
        XCTAssertEqual(readout.distanceAU, model.customDistanceAU, accuracy: 1e-6)
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
        for _ in 0..<20 {
            model.spawnCustom()
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

    // MARK: Lagrange mode

    func testLagrangeModeSetsUpEarthMoonSatelliteAtNewScale() {
        let model = GravityLabModel()
        model.enterLagrangeMode()

        XCTAssertEqual(model.mode, .lagrange)
        XCTAssertEqual(model.bodies.count, 3)
        XCTAssertEqual(model.primaryBody?.body.name, "Earth")
        XCTAssertEqual(model.displayToSim,
                       GravityLabModel.earthMoonSeparation / GravityLabModel.metersPerEarthMoon,
                       accuracy: 1)
        XCTAssertEqual(model.lagrangePoints.count, 5)
    }

    /// Dropping the satellite on L4 inserts it with the co-rotating
    /// velocity — and it then genuinely stays near the moving L4.
    func testSatelliteDroppedOnL4IsCapturedAndStays() {
        let model = GravityLabModel()
        model.enterLagrangeMode()
        let satellite = model.bodies.first { $0.body.name == "Satellite" }!
        let l4 = model.lagrangePoints.first { $0.name == "L4" }!.position

        model.grab(id: satellite.id, at: l4 * model.simToDisplay, timestamp: 300)
        model.release(id: satellite.id, timestamp: 300.1)

        XCTAssertEqual(model.capturedPointName, "L4")
        let inserted = model.bodies.first { $0.id == satellite.id }!
        XCTAssertGreaterThan(simd_length(inserted.body.velocity), 1,
                             "co-rotating insertion is not zero velocity")

        // A simulated week: the satellite must track the moving L4.
        for _ in 0..<200 {
            model.step(dt: 1.0 / 90.0)
        }
        let currentL4 = model.lagrangePoints.first { $0.name == "L4" }!.position
        let now = model.bodies.first { $0.id == satellite.id }!
        let separation = GravityLabModel.earthMoonSeparation
        XCTAssertLessThan(simd_distance(now.body.position, currentL4), 0.1 * separation)
    }

    func testLagrangeSpawnsAreBlockedAndExitRestoresSolarSystem() {
        let model = GravityLabModel()
        model.enterLagrangeMode()
        model.exitLagrangeMode()

        XCTAssertEqual(model.mode, .solarSystem)
        XCTAssertEqual(model.bodies.count, 2)
        XCTAssertEqual(model.primaryBody?.body.name, "Sun")
        XCTAssertEqual(model.displayToSim,
                       CelestialBody.astronomicalUnit / GravityLabModel.metersPerAU,
                       accuracy: 1)
        XCTAssertNil(model.capturedPointName)
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

        XCTAssertEqual(model.bodies.count, 2)
        XCTAssertEqual(model.timeScale, 1)
        XCTAssertEqual(model.gMultiplier, 1)
        XCTAssertEqual(model.trailLength, .medium)
        XCTAssertEqual(model.simulatedDays, 0)
        XCTAssertFalse(model.showFieldParticles)
        XCTAssertFalse(model.showSpacetimeGrid)
    }
}
