//
//  CircuitPropTests.swift
//  Physics Playground — app tests
//
//  The ten circuit parts milled by `Tools/circuitparts.py` (2026-09-02),
//  and the contract the renderer has with them: every asset the bench
//  asks for exists, lies along X, and stays inside the carry box's clamp
//  at the leads' inner edge — because `CircuitsAlignmentTests` and
//  `ColliderCriterionTests` measure the bench on the assumption that a
//  body never reaches its own terminals. Same axis mapping as
//  `VignettePropTests`: Blender (x, y, z) -> RealityKit (x, z, -y).
//

import XCTest
import RealityKit
import simd
@testable import PhysicsPlayground

@MainActor
final class CircuitPropTests: XCTestCase {

    /// The inner edge of a lead, from `CircuitsSpaceView`'s carry box.
    private static let leadClamp: Float = 0.059

    private func bounds(of name: String) throws -> BoundingBox {
        let loaded = try XCTUnwrap(try? Entity.load(named: name),
                                   "\(name).usdz is not in the bundle — run "
                                   + "Tools/circuitparts.py")
        let box = loaded.visualBounds(relativeTo: nil)
        XCTAssertGreaterThan(min(box.extents.x, min(box.extents.y, box.extents.z)), 0,
                             "\(name) has no thickness on some axis")
        return box
    }

    /// Every kind the renderer maps to an asset has one, plus the
    /// resistor's caps. A missing file falls back to a procedural body,
    /// which is the right behaviour and completely silent.
    func testEveryPartTheBenchAsksForExists() throws {
        for name in CircuitsRenderer.bodyAssetNames.values.sorted()
            + [CircuitsRenderer.resistorCapsAssetName] {
            _ = try bounds(of: name)
        }
    }

    /// A body never reaches its own leads: the whole model sits inside
    /// |x| < 0.059, and the ones that are longer than they are tall lie
    /// ALONG X rather than standing on end.
    func testEveryBodyStaysInsideTheLeadClampAndLiesAlongX() throws {
        for name in CircuitsRenderer.bodyAssetNames.values.sorted()
            + [CircuitsRenderer.resistorCapsAssetName] {
            let box = try bounds(of: name)
            XCTAssertLessThan(box.max.x, Self.leadClamp, "\(name) reaches its +X lead")
            XCTAssertGreaterThan(box.min.x, -Self.leadClamp, "\(name) reaches its −X lead")
        }
        for name in ["CircuitBattery", "CircuitCapacitor", "CircuitInductor",
                     "CircuitMotor", "CircuitFuse", "CircuitSwitch",
                     "CircuitResistorCaps"] {
            let box = try bounds(of: name)
            XCTAssertGreaterThan(box.extents.x, box.extents.y,
                                 "\(name) should lie along X, not stand on end")
        }
    }

    /// The bulb's envelope rises above its base, where the renderer hangs
    /// the filament (+y 0.012); the LED's dome likewise.
    func testTheBulbAndTheLEDStandUp() throws {
        for name in ["CircuitBulb", "CircuitLED"] {
            let box = try bounds(of: name)
            XCTAssertGreaterThan(box.max.y, 0.02, "\(name)'s glass should rise above its base")
            XCTAssertGreaterThan(box.extents.y, box.extents.x,
                                 "\(name) stands up rather than lying along X")
        }
    }

    /// The motor's shaft end is +X, where the renderer mounts the rotor
    /// (+0.05): the model reaches farther that way than the other.
    func testTheMotorsShaftIsOnThePlusXEnd() throws {
        let box = try bounds(of: "CircuitMotor")
        XCTAssertGreaterThan(box.max.x, -box.min.x + 0.005,
                             "the shaft stub should make +X the longer end")
    }

    /// The battery's positive nipple is on the −X end — terminal 0, the
    /// nodeA convention the solver and the renderer share.
    func testTheBatterysNippleIsOnTheMinusXEnd() throws {
        let box = try bounds(of: "CircuitBattery")
        XCTAssertGreaterThan(-box.min.x, box.max.x + 0.002,
                             "the nipple should make −X the longer end")
    }
}
