//
//  RayOpticsTests.swift
//  PhysicsCoreTests
//
//  Optics against the textbook: Snell's numbers, the critical angle,
//  mirror reflection, and — the important one — the thin-lens equation
//  EMERGING from traced rays crossing where 1/f = 1/do + 1/di says.
//

import XCTest
import simd
@testable import PhysicsCore

final class RayOpticsTests: XCTestCase {

    /// Air→glass at 30°: sin θ₂ = sin 30°/1.5 → θ₂ = 19.47°.
    func testSnellRefractionExactAngle() {
        let incident = SIMD3(sin(Double.pi / 6), -cos(Double.pi / 6), 0)
        let normal = SIMD3(0.0, 1.0, 0.0)
        let refracted = try! XCTUnwrap(RayOptics.refract(
            incident, normal: normal, n1: 1.0, n2: 1.5))
        let angle = asin(abs(refracted.x))
        XCTAssertEqual(angle, asin(sin(.pi / 6) / 1.5), accuracy: 1e-12)
        XCTAssertEqual(simd_length(refracted), 1, accuracy: 1e-12)
    }

    /// Glass→air: 41.8° critical angle; beyond it, TIR (nil).
    func testTotalInternalReflection() {
        let critical = try! XCTUnwrap(RayOptics.criticalAngle(n1: 1.5, n2: 1.0))
        XCTAssertEqual(critical, asin(1 / 1.5), accuracy: 1e-12)
        let steep = SIMD3(sin(critical + 0.02), -cos(critical + 0.02), 0)
        XCTAssertNil(RayOptics.refract(steep, normal: SIMD3(0, 1, 0), n1: 1.5, n2: 1.0))
    }

    /// Reflection: angle in = angle out, in vector form.
    func testMirrorReflection() {
        let incident = simd_normalize(SIMD3(1.0, -1.0, 0))
        let reflected = RayOptics.reflect(incident, normal: SIMD3(0, 1, 0))
        XCTAssertEqual(simd_distance(reflected, simd_normalize(SIMD3(1.0, 1.0, 0))), 0,
                       accuracy: 1e-12)
    }

    /// The showcase: two rays from a point object 0.4 m before an
    /// f = 0.25 m lens cross exactly at di = 1/(1/0.25 − 1/0.4) ≈ 0.667 m
    /// past the lens — the thin-lens equation emerging from the trace.
    func testTracedRaysFormTheThinLensImage() {
        let objectX = -0.4
        let elements: [RayOptics.BenchElement] = [.lens(x: 0, focalLength: 0.25)]
        let bounds = -0.6...1.2

        func exitRay(slope: Double) -> RayOptics.BenchRay {
            let points = RayOptics.trace(
                RayOptics.BenchRay(x: objectX, y: 0, slope: slope),
                elements: elements, bounds: bounds)
            // Reconstruct the exit ray from the last two points.
            let a = points[points.count - 2], b = points[points.count - 1]
            return RayOptics.BenchRay(
                x: a.x, y: a.y, slope: (b.y - a.y) / (b.x - a.x))
        }

        let crossing = try! XCTUnwrap(RayOptics.crossing(
            of: exitRay(slope: 0.15), and: exitRay(slope: -0.1)))
        let predicted = RayOptics.imageDistance(objectDistance: 0.4, focalLength: 0.25)
        XCTAssertEqual(crossing, predicted, accuracy: 1e-9,
                       "the image forms where 1/f = 1/do + 1/di says")
        XCTAssertEqual(predicted, 2.0 / 3.0, accuracy: 1e-9)
    }

    /// A mirror sends the ray back across the bench.
    func testMirrorTurnsTheTraceAround() {
        let points = RayOptics.trace(
            RayOptics.BenchRay(x: -0.5, y: 0.1, slope: 0),
            elements: [.mirror(x: 0.4)], bounds: -0.6...0.6)
        XCTAssertEqual(points.last!.x, -0.6, accuracy: 1e-12,
                       "the ray returns to the left edge")
    }
}
