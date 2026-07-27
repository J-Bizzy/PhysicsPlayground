//
//  CurrentLoopTests.swift
//  PhysicsCoreTests
//
//  The coil-as-magnet identity is the bridge between the circuit bench
//  and the field bench, so it has to be exact — and the strongest check
//  available is that the loop's own exact on-axis field converges, far
//  away, onto the ideal-dipole field the rest of the module computes
//  from m = N·I·A. Two independent derivations meeting is worth more
//  than either one agreeing with itself.
//

import XCTest
import simd
@testable import PhysicsCore

final class CurrentLoopTests: XCTestCase {

    func testMomentIsTurnsTimesCurrentTimesArea() {
        let area = CurrentLoop.area(radius: 0.05)
        XCTAssertEqual(area, .pi * 0.0025, accuracy: 1e-15)
        XCTAssertEqual(
            CurrentLoop.momentMagnitude(turns: 200, current: 0.35, area: area),
            200 * 0.35 * area, accuracy: 1e-15)
    }

    /// Doubling any one factor doubles the moment.
    func testMomentIsLinearInEachFactor() {
        let base = CurrentLoop.momentMagnitude(turns: 100, current: 0.5, area: 0.01)
        XCTAssertEqual(CurrentLoop.momentMagnitude(turns: 200, current: 0.5, area: 0.01),
                       2 * base, accuracy: 1e-15)
        XCTAssertEqual(CurrentLoop.momentMagnitude(turns: 100, current: 1.0, area: 0.01),
                       2 * base, accuracy: 1e-15)
        XCTAssertEqual(CurrentLoop.momentMagnitude(turns: 100, current: 0.5, area: 0.02),
                       2 * base, accuracy: 1e-15)
    }

    /// Reversing the current reverses the magnet — flipping the battery
    /// really does swap the poles of an electromagnet.
    func testReversingCurrentReversesTheMoment() {
        let forward = CurrentLoop.magnet(
            at: .zero, axis: SIMD3(0, 1, 0), turns: 120, current: 0.4, radius: 0.04)
        let reverse = CurrentLoop.magnet(
            at: .zero, axis: SIMD3(0, 1, 0), turns: 120, current: -0.4, radius: 0.04)
        XCTAssertEqual(simd_length(forward.moment + reverse.moment), 0, accuracy: 1e-18)
    }

    /// Zero current is not a magnet at all — an open switch really does
    /// turn the electromagnet off.
    func testZeroCurrentGivesNoMoment() {
        let magnet = CurrentLoop.magnet(
            at: .zero, axis: SIMD3(1, 0, 0), turns: 500, current: 0, radius: 0.05)
        XCTAssertEqual(magnet.strength, 0, accuracy: 1e-18)
    }

    /// The memorised special case: B = μ₀NI/2a at the centre.
    func testCentreFieldMatchesTheAxialFormulaAtZero() {
        XCTAssertEqual(
            CurrentLoop.axialField(turns: 300, current: 0.6, radius: 0.05, distance: 0),
            CurrentLoop.centreField(turns: 300, current: 0.6, radius: 0.05),
            accuracy: 1e-18)
    }

    /// THE test: far along the axis, the exact Biot–Savart loop field and
    /// the ideal-dipole field built from m = N·I·A must agree. On axis
    /// the dipole field is μ₀·2m/(4π z³).
    func testFarFieldConvergesOnTheIdealDipole() {
        let turns = 250, current = 0.42, radius = 0.04
        let m = CurrentLoop.momentMagnitude(
            turns: turns, current: current, area: CurrentLoop.area(radius: radius))

        for (z, tolerance) in [(0.4, 2e-2), (1.0, 4e-3), (4.0, 3e-4)] {
            let exact = CurrentLoop.axialField(
                turns: turns, current: current, radius: radius, distance: z)
            let dipole = CurrentLoop.mu0 * 2 * m / (4 * .pi * z * z * z)
            XCTAssertEqual(exact / dipole, 1, accuracy: tolerance,
                           "at z = \(z) m the loop should look like a dipole")
        }
    }

    /// And the convergence is monotone — further away is a better match,
    /// which is what makes "far field" a meaningful phrase.
    func testTheDipoleApproximationImprovesWithDistance() {
        let turns = 100, current = 1.0, radius = 0.05
        let m = CurrentLoop.momentMagnitude(
            turns: turns, current: current, area: CurrentLoop.area(radius: radius))
        func error(_ z: Double) -> Double {
            let exact = CurrentLoop.axialField(
                turns: turns, current: current, radius: radius, distance: z)
            let dipole = CurrentLoop.mu0 * 2 * m / (4 * .pi * z * z * z)
            return abs(exact / dipole - 1)
        }
        XCTAssertLessThan(error(2.0), error(0.5))
        XCTAssertLessThan(error(0.5), error(0.15))
    }

    /// The coil hands off cleanly to the rest of the magnetism code: the
    /// dipole it produces exerts the forces and torques that module
    /// already knows how to compute.
    func testCoilMagnetWorksWithTheDipoleFieldCode() {
        let coil = CurrentLoop.magnet(
            at: .zero, axis: SIMD3(1, 0, 0), turns: 400, current: 0.8, radius: 0.05)
        let bar = BarMagnet(position: SIMD3(0.3, 0, 0), moment: SIMD3(5, 0, 0))
        // Head to tail along a common axis: they attract, so the force on
        // the far magnet points back toward the coil.
        let force = MagneticField.force(on: bar, dueTo: coil)
        XCTAssertLessThan(force.x, 0)
    }
}
