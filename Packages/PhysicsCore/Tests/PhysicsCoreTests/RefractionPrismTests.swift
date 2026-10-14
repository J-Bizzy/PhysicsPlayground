//
//  RefractionPrismTests.swift
//  PhysicsCoreTests
//
//  Snell's law, TIR, and the prism pinned to the textbook: exact
//  refraction angles, a razor-sharp critical angle, mirror-equal
//  reflection, Cauchy dispersion ordering, and — the flagship — a
//  symmetric prism passage producing exactly the minimum deviation
//  formula δ = 2·asin(n·sin(A/2)) − A out of the raw trace.
//

import XCTest
import simd
@testable import PhysicsCore

final class RefractionPrismTests: XCTestCase {

    /// Air → glass at 30°: sin θ₂ = sin 30°/1.5 = 1/3, exactly.
    func testSnellBendsExactly() {
        let incident = simd_normalize(SIMD3(sin(Double.pi / 6), -cos(Double.pi / 6), 0))
        let transmitted = Refraction.refract(
            direction: incident, normal: SIMD3(0, 1, 0), n1: 1.0, n2: 1.5)
        XCTAssertNotNil(transmitted)
        XCTAssertEqual(transmitted!.x, 1.0 / 3, accuracy: 1e-12, "sin of the refracted angle")
        XCTAssertEqual(transmitted!.y, -(1 - 1.0 / 9).squareRoot(), accuracy: 1e-12)
        XCTAssertEqual(simd_length(transmitted!), 1, accuracy: 1e-12)
    }

    /// The critical angle is a knife edge: glass → air transmits just
    /// below asin(1/1.5) and totally reflects just above it.
    func testTotalInternalReflectionThreshold() {
        let critical = Refraction.criticalAngle(n1: 1.5, n2: 1.0)!
        XCTAssertEqual(critical, asin(2.0 / 3), accuracy: 1e-15)

        func ray(_ angle: Double) -> SIMD3<Double> {
            SIMD3(sin(angle), -cos(angle), 0)
        }
        XCTAssertNotNil(Refraction.refract(
            direction: ray(critical - 1e-6), normal: SIMD3(0, 1, 0), n1: 1.5, n2: 1.0))
        XCTAssertNil(Refraction.refract(
            direction: ray(critical + 1e-6), normal: SIMD3(0, 1, 0), n1: 1.5, n2: 1.0),
                     "past the critical angle there is NO transmitted ray")
    }

    /// Reflection: normal component flips, tangential survives.
    func testReflectionEqualAngles() {
        let reflected = Refraction.reflect(
            direction: SIMD3(0.6, -0.8, 0), normal: SIMD3(0, 1, 0))
        XCTAssertEqual(reflected.x, 0.6, accuracy: 1e-12)
        XCTAssertEqual(reflected.y, 0.8, accuracy: 1e-12)
    }

    /// Cauchy: blue sees more glass than red.
    func testCauchyDispersionOrdering() {
        let blue = Refraction.cauchyIndex(wavelengthNanometers: 400)
        let red = Refraction.cauchyIndex(wavelengthNanometers: 700)
        XCTAssertEqual(blue, 1.5046 + 4200.0 / 160_000, accuracy: 1e-12)
        XCTAssertEqual(red, 1.5046 + 4200.0 / 490_000, accuracy: 1e-12)
        XCTAssertGreaterThan(blue, red)
    }

    /// Symmetric passage through a 60° prism at n = 1.5: the traced
    /// deviation equals 2·asin(n·sin 30°) − 60°, to a nano-radian.
    /// The formula is never used by the tracer — it emerges.
    func testSymmetricPassageHitsMinimumDeviation() {
        let apexAngle = Double.pi / 3
        let n = 1.5
        let geometry = Prism.Geometry(apex: SIMD2(0, 0), apexAngle: apexAngle)

        // Symmetric passage: the internal leg runs parallel to the
        // base, so the entry incidence is θ₁ = asin(n·sin(A/2)).
        let theta1 = asin(n * sin(apexAngle / 2))
        // Left-face inward normal is (cos(A/2), −sin(A/2)); rotate it
        // by +θ₁ to build the incident direction.
        let inward = SIMD2(cos(apexAngle / 2), -sin(apexAngle / 2))
        let incident = SIMD2(
            inward.x * cos(theta1) - inward.y * sin(theta1),
            inward.x * sin(theta1) + inward.y * cos(theta1))
        let target = (geometry.vertices[0] + geometry.vertices[1]) / 2
        let origin = target - incident * 0.3

        let line = Prism.trace(from: origin, direction: incident,
                               geometry: geometry, index: n)
        XCTAssertGreaterThanOrEqual(line.count, 4, "entered and exited")
        let exitDirection = simd_normalize(line[line.count - 1] - line[line.count - 2])
        let deviation = acos(max(-1, min(1, simd_dot(simd_normalize(incident), exitDirection))))
        let expected = Prism.minimumDeviation(apexAngle: apexAngle, index: n)
        XCTAssertEqual(deviation, expected, accuracy: 1e-9)

        // The internal leg really is parallel to the base.
        let internalLeg = simd_normalize(line[2] - line[1])
        XCTAssertEqual(abs(internalLeg.y), 0, accuracy: 1e-9)
    }

    /// White light fans out: blue deviates more than red through the
    /// same prism — dispersion from nothing but Snell + Cauchy.
    func testBlueDeviatesMoreThanRed() {
        let geometry = Prism.Geometry(apex: SIMD2(0, 0), apexAngle: .pi / 3)
        func deviation(_ nanometers: Double) -> Double {
            let n = Refraction.cauchyIndex(wavelengthNanometers: nanometers)
            let theta1 = asin(n * sin(geometry.apexAngle / 2))
            let inward = SIMD2(cos(geometry.apexAngle / 2), -sin(geometry.apexAngle / 2))
            let incident = SIMD2(
                inward.x * cos(theta1) - inward.y * sin(theta1),
                inward.x * sin(theta1) + inward.y * cos(theta1))
            let target = (geometry.vertices[0] + geometry.vertices[1]) / 2
            let line = Prism.trace(from: target - incident * 0.3, direction: incident,
                                   geometry: geometry, index: n)
            let exit = simd_normalize(line[line.count - 1] - line[line.count - 2])
            return acos(max(-1, min(1, simd_dot(simd_normalize(incident), exit))))
        }
        XCTAssertGreaterThan(deviation(450), deviation(650))
    }

    /// A steep prism turns its exit face into a mirror: the trace
    /// grows an internal-reflection vertex instead of passing through.
    func testSteepExitTotallyInternallyReflects() {
        let geometry = Prism.Geometry(apex: SIMD2(0, 0), apexAngle: 80 * .pi / 180)
        let n = 1.5
        // Gentle entry (20°) → internal angle at the exit face is
        // A − θ₂ ≈ 66.8°, far past the 41.8° critical angle.
        let theta1 = 20 * Double.pi / 180
        let half = geometry.apexAngle / 2
        let inward = SIMD2(cos(half), -sin(half))
        let incident = SIMD2(
            inward.x * cos(theta1) - inward.y * sin(theta1),
            inward.x * sin(theta1) + inward.y * cos(theta1))
        let target = (geometry.vertices[0] + geometry.vertices[1]) / 2
        let line = Prism.trace(from: target - incident * 0.3, direction: incident,
                               geometry: geometry, index: n)
        XCTAssertGreaterThanOrEqual(
            line.count, 5,
            "origin, entry, TIR bounce, exit, escape — the bounce is real")
    }

    /// A ray that misses the prism flies straight.
    func testMissFliesStraight() {
        let geometry = Prism.Geometry(apex: SIMD2(0, 0), apexAngle: .pi / 3)
        let line = Prism.trace(from: SIMD2(-0.5, 0.4), direction: SIMD2(1, 0),
                               geometry: geometry, index: 1.5)
        XCTAssertEqual(line.count, 2)
        XCTAssertEqual(line[1].y, 0.4, accuracy: 1e-12)
    }
}
