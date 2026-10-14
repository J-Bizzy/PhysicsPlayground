//
//  OrbitalMechanicsRendererTests.swift
//  PhysicsPlaygroundTests
//
//  The trail ribbons: one per body, keyed by the body's id so a merge
//  frees the dead body's ribbon; a tube 1.2 mm thick in the room at any
//  zoom; and the fade material's ramp actually arriving.
//

import XCTest
import PhysicsCore
import RealityKit
import RenderKit
import simd
@testable import PhysicsPlayground

@MainActor
final class OrbitalMechanicsRendererTests: XCTestCase {

    /// The old slots were positional: a merge shifted every later body
    /// down one and a slot could keep drawing a dead body's path in its
    /// colour. Ribbons follow identity.
    func testTrailSlotsFollowBodyIdentityThroughAMerge() {
        let model = OrbitalMechanicsModel()
        let renderer = OrbitalMechanicsRenderer()
        for _ in 0..<120 { model.step(dt: 1.0 / 90.0) }
        renderer.tick(model)
        let venusID = model.bodies.first { $0.body.name == "Venus" }!.id
        let earthID = model.bodies.first { $0.body.name == "Earth" }!.id
        XCTAssertNotNil(renderer.trailSlot(for: venusID))
        XCTAssertNotNil(renderer.trailSlot(for: earthID))
        XCTAssertEqual(renderer.liveTrailRibbons, model.bodies.count,
                       "every body trails — the Sun's is its wobble about the barycentre")

        let venusDisplay = model.bodies.first { $0.id == venusID }!.body.position * model.simToDisplay
        model.grab(id: earthID, at: venusDisplay, timestamp: 80)
        model.release(id: earthID, timestamp: 80.1)
        model.step(dt: 1.0 / 90.0)
        XCTAssertEqual(model.bodies.count, 9)
        renderer.tick(model)

        XCTAssertNil(renderer.trailSlot(for: venusID), "the dead Venus kept a ribbon")
        XCTAssertNil(renderer.trailSlot(for: earthID), "the dead Earth kept a ribbon")
        for body in model.bodies {
            XCTAssertNotNil(renderer.trailSlot(for: body.id), "\(body.body.name) lost its ribbon")
        }
        XCTAssertLessThanOrEqual(renderer.liveTrailRibbons, model.bodies.count)
    }

    /// 1.2 mm in the room at 1× and at 9×: the radius in display units is
    /// divided by the rig, bucketed so a zoom does not rewrite every frame.
    func testTrailRadiusIsConstantInTheRoom() {
        for rig: Float in [0.4, 1, 2.5, 4, 9] {
            let room = OrbitalMechanicsRenderer.trailRadius(rigScale: rig) * rig
            XCTAssertEqual(room, 0.0012, accuracy: 0.0012 * 0.12, "\(rig)× draws a \(room) m tube")
        }
        XCTAssertEqual(OrbitalMechanicsRenderer.rigBucket(1.0), OrbitalMechanicsRenderer.rigBucket(1.05),
                       "a 5 % zoom jitter changed the bucket")
    }

    /// The ribbon is a real mesh with a real vertex budget.
    func testARibbonHoldsACapacityOfSamplesAndEmptiesBelowTwo() {
        let ribbon = try! XCTUnwrap(TrailRibbon(capacity: OrbitTrail.capacity),
                                    "the GPU refused the ribbon's buffers")
        XCTAssertTrue(ribbon.isEmpty)
        let capacity = OrbitTrail.capacity
        var points: [SIMD3<Float>] = []
        var ages: [Float] = []
        for i in 0..<capacity {
            let angle = Float(i) * 0.01
            points.append(SIMD3<Float>(cos(angle), 0, sin(angle)))
            ages.append(Float(i) / Float(capacity))
        }
        ribbon.update(points: points, ages: ages, radius: 0.0012)
        XCTAssertFalse(ribbon.isEmpty)
        XCTAssertTrue(ribbon.entity.isEnabled)
        ribbon.update(points: [points[0]], ages: [1], radius: 0.0012)
        XCTAssertTrue(ribbon.isEmpty, "one point is not a path")
        XCTAssertFalse(ribbon.entity.isEnabled)
    }

    /// The fade is a texture the loader delivers; a ribbon wears a flat
    /// colour until then, and forever if this fails.
    func testTheFadeRampLoads() async {
        let ramp = await Materials.fadeRamp()
        XCTAssertNotNil(ramp, "no ramp: every trail stays a flat 0.6 opacity")
        if let ramp {
            let faded = Materials.fadedLine(.systemBlue, ramp: ramp)
            XCTAssertNotNil(faded.blending)
        }
    }
}
