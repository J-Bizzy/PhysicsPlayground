//
//  VignettePropTests.swift
//  Physics Playground — app tests
//
//  The props the home's dioramas load, against the numbers the Swift side
//  places them by. The cradle is placed at its AUTHORED size and origin
//  (`HubVignettes.placed`), not recentred, so a Blender script that drifts
//  from `HubDioramas` would stand it off its stage or hang the balls off
//  their rails — and still load without a word. The exporter maps Blender
//  (x, y, z) → RealityKit (x, z, −y).
//

import XCTest
import RealityKit
import simd
@testable import PhysicsPlayground

@MainActor
final class VignettePropTests: XCTestCase {

    private func bounds(of name: String) throws -> BoundingBox {
        let loaded = try XCTUnwrap(try? Entity.load(named: name),
                                   "\(name).usdz is not in the bundle — run Tools/hubdioramas.py")
        return loaded.visualBounds(relativeTo: nil)
    }

    /// Everything the dioramas load, loads. A diorama falls back to
    /// primitives when an asset is missing, which is the right behaviour
    /// and also completely silent — so the only way a dropped file gets
    /// noticed is here.
    func testEveryPropTheDioramasAskForExists() throws {
        for name in ["HubCradle", "PickupCoil", "LauncherBarrel",
                     "CircuitBattery", "CircuitBulb", "CircuitSwitch"] {
            let box = try bounds(of: name)
            XCTAssertGreaterThan(min(box.extents.x, min(box.extents.y, box.extents.z)), 0,
                                 "\(name) has no thickness on some axis")
        }
    }

    /// The cradle's rails stand where the balls hang from, and the frame
    /// stands inside the stage.
    func testTheCradleHangsFromItsRails() throws {
        let box = try bounds(of: "HubCradle")
        let foot = HubVignettes.cradleFootRadius
        XCTAssertEqual(box.max.y, HubVignettes.cradleRailHeight + 0.0024, accuracy: 0.001)
        XCTAssertEqual(box.max.z, HubVignettes.cradleRailOffset + foot, accuracy: 0.001)
        XCTAssertEqual(box.max.x, HubVignettes.cradleRailHalf + foot, accuracy: 0.001)
        XCTAssertEqual(box.min.y, 0, accuracy: 0.001, "the frame does not stand on the stage")
        // The feet are round: the farthest point of one is its centre's
        // distance plus its radius.
        let reach = simd_length(SIMD2(HubVignettes.cradleRailHalf, HubVignettes.cradleRailOffset)) + foot
        XCTAssertLessThan(reach, HubVignettes.stageRadius, "the frame's feet hang off the stage")
    }

    /// The end ball's 0.55 rad release clears the frame's legs.
    func testTheReleasedBallClearsTheFrame() {
        let swing = HubVignettes.cradleSwing
        let length = HubVignettes.cradleRailHeight - HubVignettes.cradleRestHeight
        let rest = 2 * 2 * HubVignettes.cradleBallRadius
        let outermost = rest + length * Float(sin(swing.amplitude)) + HubVignettes.cradleBallRadius
        XCTAssertLessThanOrEqual(outermost, HubVignettes.cradleRailHalf + 0.001)
    }
}
