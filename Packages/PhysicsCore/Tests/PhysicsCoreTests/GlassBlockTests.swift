//
//  GlassBlockTests.swift
//  PhysicsCoreTests
//
//  The slab pinned to the textbook: a ray leaves a parallel-faced
//  block traveling exactly parallel to how it arrived, displaced by
//  exactly t·sin(θ₁−θ₂)/cos(θ₂); a steep entry turns the slab into a
//  light pipe (TIR bounces down its length); a miss flies straight.
//

import XCTest
import simd
@testable import PhysicsCore

final class GlassBlockTests: XCTestCase {

    private let center = SIMD3<Double>(0, 0, 0)
    private let half = SIMD3<Double>(0.15, 0.1, 0.05)
    private let n = 1.5

    /// The parallel-shift law, both parts exact.
    func testSlabPassesTheRayParallelWithExactShift() {
        // Hit the +z face (thickness 0.1) at 40° in the x–z plane.
        let theta1 = 40 * Double.pi / 180
        let d = SIMD3(sin(theta1), 0, -cos(theta1))
        let origin = SIMD3<Double>(-0.12, 0, 0.3)
        let line = GlassBlock.trace(from: origin, direction: d,
                                    center: center, halfExtents: half, index: n)
        guard line.count == 4 else {
            return XCTFail("expected origin, entry, exit, escape — got \(line.count) points")
        }

        // Exit direction parallel to the entry direction.
        let exit = simd_normalize(line[3] - line[2])
        XCTAssertEqual(exit.x, d.x, accuracy: 1e-12)
        XCTAssertEqual(exit.y, d.y, accuracy: 1e-12)
        XCTAssertEqual(exit.z, d.z, accuracy: 1e-12)

        // Lateral displacement: t·sin(θ₁−θ₂)/cos(θ₂), t = 0.1.
        let theta2 = asin(sin(theta1) / n)
        let expected = 0.1 * sin(theta1 - theta2) / cos(theta2)
        // Displacement = distance between entry and exit projected
        // perpendicular to the travel direction.
        let across = line[2] - line[1]
        let lateral = across - simd_dot(across, d) * d
        XCTAssertEqual(simd_length(lateral), expected, accuracy: 1e-9)
    }

    /// Enter through the small end of the long block at a shallow
    /// angle: the internal ray meets the long faces past the critical
    /// angle and bounces down the slab — a light pipe.
    func testSteepEntryBecomesALightPipe() {
        // A long slab, entered through the -x end, angled slightly
        // toward +z: after refraction the ray runs nearly along +x,
        // striking the z faces far past the 41.8° critical angle.
        let pipeHalf = SIMD3<Double>(0.45, 0.1, 0.05)
        let d = simd_normalize(SIMD3(1.0, 0, 0.35))
        let origin = SIMD3<Double>(-0.7, 0, -0.09)
        let line = GlassBlock.trace(from: origin, direction: d,
                                    center: center, halfExtents: pipeHalf, index: n)
        // Origin, entry, at least two internal bounces, exit, escape.
        XCTAssertGreaterThanOrEqual(line.count, 6, "bounced along the pipe")
        // Every internal vertex sits on the box surface, inside bounds.
        for vertex in line.dropFirst(2).dropLast(2) {
            let onSurface = abs(abs(vertex.x) - pipeHalf.x) < 1e-9
                || abs(abs(vertex.y) - pipeHalf.y) < 1e-9
                || abs(abs(vertex.z) - pipeHalf.z) < 1e-9
            XCTAssertTrue(onSurface)
            XCTAssertLessThanOrEqual(abs(vertex.x), pipeHalf.x + 1e-9)
            XCTAssertLessThanOrEqual(abs(vertex.z), pipeHalf.z + 1e-9)
        }
    }

    /// Normal incidence: straight through, no bend, no shift.
    func testNormalIncidenceGoesStraight() {
        let line = GlassBlock.trace(from: SIMD3(0, 0, 0.4), direction: SIMD3(0, 0, -1),
                                    center: center, halfExtents: half, index: n)
        XCTAssertEqual(line.count, 4)
        for vertex in line {
            XCTAssertEqual(vertex.x, 0, accuracy: 1e-12)
            XCTAssertEqual(vertex.y, 0, accuracy: 1e-12)
        }
    }

    /// A miss flies straight through empty air.
    func testMissFliesStraight() {
        let line = GlassBlock.trace(from: SIMD3(0, 0.5, 0.4), direction: SIMD3(0, 0, -1),
                                    center: center, halfExtents: half, index: n)
        XCTAssertEqual(line.count, 2)
    }
}
