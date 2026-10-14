//
//  ShelfCrownPropTests.swift
//  Physics Playground — app tests
//
//  The parts shelf's crown, milled by `Tools/shelfcrown.py`: the asset
//  is in the bundle, lies across the shelf, is the size the Swift side
//  sizes its target and its turn from, and is centred on its axle.
//  Blender (x, y, z) → RealityKit (x, z, −y).
//

import XCTest
import RealityKit
import simd
@testable import PhysicsPlayground

@MainActor
final class ShelfCrownPropTests: XCTestCase {

    private func crown() throws -> Entity {
        try XCTUnwrap(try? Entity.load(named: "ShelfCrown"),
                      "ShelfCrown.usdz is not in the bundle — run Tools/shelfcrown.py")
    }

    /// The axle runs along x, across the shelf; the rim's diameter is
    /// what the other two extents measure, and the axle stands proud of
    /// the rim on both sides.
    func testTheCrownLiesAcrossTheShelfAtItsAuthoredSize() throws {
        let box = try crown().visualBounds(relativeTo: nil)
        XCTAssertEqual(box.extents.y, 2 * Well.Rack.crownRadius, accuracy: 0.002,
                       "the rim is not the radius `Well.Rack` turns it by")
        XCTAssertEqual(box.extents.z, 2 * Well.Rack.crownRadius, accuracy: 0.002)
        XCTAssertLessThan(box.extents.x, box.extents.y,
                          "the crown stands on end rather than lying across the shelf")
        XCTAssertGreaterThan(box.extents.x, Well.Rack.crownWidth + 0.010,
                             "the axle does not stand proud of the rim")
    }

    /// Centred on its axle, so the Swift side turns it about its own
    /// origin without measuring anything.
    func testTheCrownIsCentredOnItsAxle() throws {
        let box = try crown().visualBounds(relativeTo: nil)
        XCTAssertEqual(simd_length(box.center), 0, accuracy: 0.001,
                       "the crown's origin is \(box.center) off its axle")
    }

    /// The pinch target `Well` gives it is sized for this wheel: no
    /// larger than the collider rule's allowance on any axis, and never
    /// smaller than the wheel.
    func testTheCrownFitsItsPinchTarget() throws {
        let extents = try crown().visualBounds(relativeTo: nil).extents
        let target = Well.Rack.crownTarget
        for (axis, v, c) in [("x", extents.x, target.x), ("y", extents.y, target.y),
                             ("z", extents.z, target.z)] {
            XCTAssertLessThanOrEqual(c, max(v * 1.15, v + 0.03) + 1e-4,
                                     "the target is \(c) m on \(axis) for a \(v) m crown")
            XCTAssertGreaterThanOrEqual(c + 1e-4, v,
                                        "the target is smaller than the crown on \(axis)")
        }
    }
}
