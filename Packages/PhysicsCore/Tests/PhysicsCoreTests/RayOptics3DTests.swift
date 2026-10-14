//
//  RayOptics3DTests.swift
//  PhysicsCoreTests
//
//  The 3D ideal-lens law reproduces the textbook exactly, in full 3D:
//  a parallel cone of rays meets the focal point, a point source
//  images at the thin-lens distance with the right magnification, a
//  diverging lens traces back to its virtual focus, and mirrors fold
//  the bench. The image emerges from the trace — never painted on.
//

import XCTest
import simd
@testable import PhysicsCore

final class RayOptics3DTests: XCTestCase {

    private let axis = SIMD3<Double>(0, 1.35, -0.9)

    /// Every ray of a circular parallel beam passes through the focal
    /// point, to numerical exactness — the 3D generalization the 2D
    /// bench could only show in one plane.
    func testParallelBeamMeetsTheFocalPointExactly() {
        let lens = RayOptics3D.Element(x: 0, kind: .lens(focalLength: 0.3))
        let rays = RayOptics3D.parallelBeam(
            fromX: -0.5, center: axis, radius: 0.12, rings: 3, spokes: 8)
        let lines = RayOptics3D.trace(
            rays: rays, elements: [lens], axisCenter: axis, bounds: -0.5...0.8)
        XCTAssertEqual(lines.count, 25)
        for line in lines {
            let at = RayOptics3D.lateralPoint(of: line, atX: 0.3)
            XCTAssertNotNil(at)
            XCTAssertEqual(at!.y, axis.y, accuracy: 1e-9)
            XCTAssertEqual(at!.z, axis.z, accuracy: 1e-9)
        }
    }

    /// A point source at 2f re-converges at 2f on the far side (the
    /// classic unit-magnification conjugates), for every cone ray.
    func testPointSourceAtTwoFImagesAtTwoF() {
        let lens = RayOptics3D.Element(x: 0, kind: .lens(focalLength: 0.25))
        let source = SIMD3(-0.5, axis.y, axis.z)
        let rays = RayOptics3D.pointCone(from: source, halfAngle: 0.25, rings: 3, spokes: 8)
        let lines = RayOptics3D.trace(
            rays: rays, elements: [lens], axisCenter: axis, bounds: -0.5...1.0)
        for line in lines {
            let at = RayOptics3D.lateralPoint(of: line, atX: 0.5)
            XCTAssertNotNil(at)
            XCTAssertEqual(at!.y, axis.y, accuracy: 1e-9)
            XCTAssertEqual(at!.z, axis.z, accuracy: 1e-9)
        }
    }

    /// An off-axis point source images with the thin-lens
    /// magnification −dᵢ/dₒ, in both lateral dimensions.
    func testOffAxisImageObeysMagnification() {
        let lens = RayOptics3D.Element(x: 0, kind: .lens(focalLength: 0.2))
        // dₒ = 0.3 → dᵢ = 1/(1/0.2 − 1/0.3) = 0.6, m = −2.
        let source = SIMD3(-0.3, axis.y + 0.02, axis.z - 0.015)
        let rays = RayOptics3D.pointCone(from: source, halfAngle: 0.2, rings: 2, spokes: 6)
        // Aim the cone roughly at the lens center so rays actually hit it.
        let lines = RayOptics3D.trace(
            rays: rays, elements: [lens], axisCenter: axis, bounds: -0.3...1.0)
        for line in lines where line.count >= 3 {
            let at = RayOptics3D.lateralPoint(of: line, atX: 0.6)
            XCTAssertNotNil(at)
            XCTAssertEqual(at!.y, axis.y - 0.04, accuracy: 1e-9, "m = −2 in y")
            XCTAssertEqual(at!.z, axis.z + 0.03, accuracy: 1e-9, "m = −2 in z")
        }
    }

    /// Diverging lens: parallel rays fan out as if from the virtual
    /// focus a distance f in front of the lens.
    func testDivergingLensTracesBackToVirtualFocus() {
        let lens = RayOptics3D.Element(x: 0, kind: .lens(focalLength: -0.25))
        let rays = RayOptics3D.parallelBeam(
            fromX: -0.4, center: axis, radius: 0.1, rings: 2, spokes: 6)
        let lines = RayOptics3D.trace(
            rays: rays, elements: [lens], axisCenter: axis, bounds: -0.4...0.6)
        for line in lines {
            // Take the outgoing segment and extrapolate backward.
            guard line.count >= 3 else { continue }
            let a = line[line.count - 2]
            let b = line[line.count - 1]
            let direction = (b - a) / simd_length(b - a)
            let t = (-0.25 - a.x) / direction.x
            let virtualPoint = a + t * direction
            XCTAssertEqual(virtualPoint.y, axis.y, accuracy: 1e-9)
            XCTAssertEqual(virtualPoint.z, axis.z, accuracy: 1e-9)
        }
    }

    /// The mirror folds the axial direction and preserves the lateral.
    func testMirrorFoldsTheBench() {
        let mirror = RayOptics3D.Element(x: 0.4, kind: .mirror)
        let ray = RayOptics3D.Ray(
            origin: SIMD3(-0.2, axis.y + 0.05, axis.z),
            direction: SIMD3(1, 0.02, -0.01))
        let line = RayOptics3D.trace(
            ray: ray, elements: [mirror], axisCenter: axis, bounds: -0.5...0.6)
        XCTAssertEqual(line.last!.x, -0.5, accuracy: 1e-9, "came back out the left")
        // Lateral motion continues unflipped.
        XCTAssertGreaterThan(line.last!.y, axis.y + 0.05)
    }

    /// The screen absorbs: the polyline ends on the screen plane.
    func testScreenAbsorbs() {
        let screen = RayOptics3D.Element(x: 0.3, kind: .screen)
        let ray = RayOptics3D.Ray(
            origin: SIMD3(-0.2, axis.y, axis.z), direction: SIMD3(1, 0, 0))
        let line = RayOptics3D.trace(
            ray: ray, elements: [screen], axisCenter: axis, bounds: -0.5...0.9)
        XCTAssertEqual(line.last!.x, 0.3, accuracy: 1e-12)
    }
}
