//
//  OpticsModelTests.swift
//  PhysicsPlaygroundTests
//
//  The optical bench's app state: the welcome lens focuses the beam,
//  the point-source prediction matches the trace, and edits behave.
//

import XCTest
import PhysicsCore
import simd
@testable import PhysicsPlayground

@MainActor
final class OpticsModelTests: XCTestCase {

    /// Opens with one converging lens at the bench center; parallel
    /// rays all cross the axis at exactly one focal length past it.
    func testWelcomeBeamFocusesAtTheFocalPoint() {
        let model = OpticsModel()
        XCTAssertEqual(model.elements.count, 1)
        let lens = model.elements[0]
        XCTAssertEqual(lens.kind, .convergingLens)

        for ray in model.tracedRays {
            // Segment after the lens: find where it crosses y = 0.
            let a = ray[ray.count - 2], b = ray[ray.count - 1]
            guard abs(b.y - a.y) > 1e-12 else { continue }  // axial ray
            let t = -a.y / (b.y - a.y)
            let crossX = a.x + t * (b.x - a.x)
            XCTAssertEqual(crossX, lens.x + lens.focal, accuracy: 1e-9,
                           "every parallel ray crosses at the focal point")
        }
    }

    /// Point source: the prediction card equals the thin-lens equation,
    /// and the traced rays cross exactly there.
    func testPointSourceImageMatchesPrediction() {
        let model = OpticsModel()
        model.sourceMode = .point
        let lens = model.elements[0]
        let prediction = try! XCTUnwrap(model.imagePrediction)
        let objectDistance = lens.x - OpticsModel.sourceX
        XCTAssertEqual(prediction.imageDistance,
                       RayOptics.imageDistance(objectDistance: objectDistance,
                                               focalLength: lens.focal),
                       accuracy: 1e-12)

        // Two non-axial traced rays cross at the predicted x.
        let rays = model.tracedRays.filter { ray in
            abs(ray.last!.y - ray[ray.count - 2].y) > 1e-9
        }
        let a = rays.first!, b = rays.last!
        func exit(_ ray: [SIMD2<Double>]) -> RayOptics.BenchRay {
            let p = ray[ray.count - 2], q = ray[ray.count - 1]
            return RayOptics.BenchRay(x: p.x, y: p.y, slope: (q.y - p.y) / (q.x - p.x))
        }
        let crossing = try! XCTUnwrap(RayOptics.crossing(of: exit(a), and: exit(b)))
        XCTAssertEqual(crossing, prediction.x, accuracy: 1e-9,
                       "the gold marker sits on the real crossing")
    }

    /// Element moves clamp to the bench and removal clears cleanly.
    func testElementEditing() {
        let model = OpticsModel()
        let id = model.elements[0].id
        model.moveElement(id: id, toX: 10)
        XCTAssertLessThanOrEqual(model.elements[0].x, OpticsModel.railHalf)
        model.setFocal(id: id, 5)
        XCTAssertEqual(model.elements[0].focal, OpticsModel.focalRange.upperBound)
        model.removeSelected()
        XCTAssertTrue(model.elements.isEmpty)
    }
}
