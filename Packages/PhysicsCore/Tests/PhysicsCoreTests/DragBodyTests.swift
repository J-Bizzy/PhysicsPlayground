//
//  DragBodyTests.swift
//  PhysicsCoreTests
//
//  The drag equation gives exact textbook numbers, the coefficient
//  table orders shapes the way wind tunnels do, and the obstacle field
//  respects the slip condition at surfaces while leaving distant flow
//  untouched.
//

import XCTest
import simd
@testable import PhysicsCore

final class DragBodyTests: XCTestCase {

    /// Textbook check: a 0.06 m-radius sphere at 10 m/s in sea-level
    /// air drags F = ½·1.225·100·0.47·π·0.0036 ≈ 0.3256 N.
    func testDragEquationExactValue() {
        let force = DragBody.dragForce(
            airDensity: 1.225, speed: 10,
            dragCoefficient: DragBody.sphere.dragCoefficient,
            frontalArea: DragBody.sphere.frontalArea(radius: 0.06))
        XCTAssertEqual(force, 0.5 * 1.225 * 100 * 0.47 * .pi * 0.0036, accuracy: 1e-12)
        XCTAssertEqual(force, 0.32564, accuracy: 5e-4)
    }

    /// The whole point of the exhibit: streamlining beats bluffness by
    /// an order of magnitude at equal frontal size.
    func testCoefficientOrdering() {
        XCTAssertLessThan(DragBody.teardrop.dragCoefficient,
                          DragBody.cone.dragCoefficient)
        XCTAssertLessThan(DragBody.cone.dragCoefficient,
                          DragBody.cube.dragCoefficient)
        XCTAssertLessThan(DragBody.sphere.dragCoefficient,
                          DragBody.cube.dragCoefficient)
        XCTAssertGreaterThan(DragBody.flatDisc.dragCoefficient / DragBody.teardrop.dragCoefficient,
                             25, "the disc drags >25× the teardrop")
        // The vehicles rank as every highway proves daily.
        XCTAssertLessThan(DragBody.plane.dragCoefficient, DragBody.car.dragCoefficient)
        XCTAssertLessThan(DragBody.car.dragCoefficient, DragBody.truck.dragCoefficient)
        XCTAssertLessThan(DragBody.truck.dragCoefficient, DragBody.flatDisc.dragCoefficient,
                          "even a box truck beats a flat plate")
    }

    /// Vehicle geometry: frontal areas follow the real silhouettes, and
    /// the shared size multiplier keeps display and physics in step.
    func testVehicleGeometry() {
        XCTAssertEqual(DragBody.car.frontalArea(radius: 0.1), 2 * 0.1 * 1.57 * 0.1, accuracy: 1e-12)
        XCTAssertEqual(DragBody.truck.frontalArea(radius: 0.1), 2 * 0.1 * 3.1 * 0.1, accuracy: 1e-12)
        XCTAssertEqual(DragBody.plane.frontalArea(radius: 0.1), .pi * 0.04 * 0.04, accuracy: 1e-12)
        for body in DragBody.allCases {
            XCTAssertEqual(body.sizeMultiplier, body.isVehicle ? 2.2 : 1)
        }
    }

    /// The sphere silhouettes match each body's story: none for the
    /// cylinder (exact solution), one exact sphere for the sphere, a
    /// cabin-high taper for the car, near-constant girth for the truck,
    /// and a slender fuselage for the plane — all scaling with size.
    func testObstacleSilhouettes() {
        XCTAssertTrue(DragBody.cylinder.obstacleSpheres(center: .zero, halfWidth: 0.1).isEmpty)

        let ball = DragBody.sphere.obstacleSpheres(center: SIMD3(1, 2, 3), halfWidth: 0.1)
        XCTAssertEqual(ball.count, 1)
        XCTAssertEqual(ball[0].radius, 0.1, accuracy: 1e-12)
        XCTAssertEqual(ball[0].center, SIMD3(1, 2, 3))

        let car = DragBody.car.obstacleSpheres(center: .zero, halfWidth: 0.1)
        let biggest = car.max(by: { $0.radius < $1.radius })!
        XCTAssertGreaterThan(biggest.radius, car.first!.radius, "cabin above the nose")
        XCTAssertGreaterThan(biggest.radius, car.last!.radius, "cabin above the tail")

        let truck = DragBody.truck.obstacleSpheres(center: .zero, halfWidth: 0.1)
        let plane = DragBody.plane.obstacleSpheres(center: .zero, halfWidth: 0.1)
        XCTAssertGreaterThan(truck.map(\.radius).max()!, 3 * plane.map(\.radius).max()!,
                             "the truck shoulders far more air than the fuselage")

        // Radii scale linearly with the body's half-width.
        let doubled = DragBody.car.obstacleSpheres(center: .zero, halfWidth: 0.2)
        XCTAssertEqual(doubled[0].radius, 2 * car[0].radius, accuracy: 1e-12)
    }

    /// Drag grows with the square of speed — doubling wind quadruples force.
    func testQuadraticSpeedScaling() {
        func f(_ v: Double) -> Double {
            DragBody.dragForce(airDensity: 1.225, speed: v,
                               dragCoefficient: 1.0, frontalArea: 0.01)
        }
        XCTAssertEqual(f(8) / f(4), 4, accuracy: 1e-12)
    }

    /// Far from every obstacle the field is untouched; at a surface the
    /// into-surface component is gone (slip); inside, flow points out.
    func testObstacleFieldSlipCondition() {
        let field = ObstacleField(spheres: [
            .init(center: SIMD3(0, 0, 0), radius: 0.1),
        ])
        let wind = SIMD3(1.0, 0, 0)

        // Far away: unchanged.
        let far = field.deflected(wind, at: SIMD3(0, 0, 5))
        XCTAssertEqual(simd_distance(far, wind), 0, accuracy: 1e-12)

        // Head-on at the upstream surface: the into-surface (x)
        // component is fully removed.
        let atSurface = field.deflected(wind, at: SIMD3(-0.1, 0, 0))
        XCTAssertEqual(atSurface.x, 0, accuracy: 1e-9)

        // Inside: pushed outward, never inward.
        let inside = field.deflected(wind, at: SIMD3(-0.05, 0, 0))
        XCTAssertLessThan(inside.x, 0, "flow inside the sphere points back out")

        // Grazing flow (tangential) at the side is preserved.
        let grazing = field.deflected(wind, at: SIMD3(0, 0.1, 0))
        XCTAssertEqual(simd_distance(grazing, wind), 0, accuracy: 1e-9,
                       "tangential flow feels no obstacle")
    }
}
