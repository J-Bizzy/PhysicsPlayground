//
//  VignettePropTests.swift
//  Physics Playground — app tests
//
//  The props the home's dioramas load: every one of them is in the bundle
//  and solid. A diorama falls back to primitives when a file is missing,
//  silently, so this is where a dropped file is noticed. (The cradle's
//  milled frame was measured here until 2026-10-26, when the miniature
//  became the lab's own frameless cradle.)
//

import XCTest
import RealityKit
import simd
@testable import PhysicsPlayground

@MainActor
final class VignettePropTests: XCTestCase {

    private func bounds(of name: String) throws -> BoundingBox {
        let loaded = try XCTUnwrap(try? Entity.load(named: name),
                                   "\(name).usdz is not in the bundle")
        return loaded.visualBounds(relativeTo: nil)
    }

    /// Everything the dioramas load, loads. A diorama falls back to
    /// primitives when an asset is missing, which is the right behaviour
    /// and also completely silent — so the only way a dropped file gets
    /// noticed is here.
    func testEveryPropTheDioramasAskForExists() throws {
        for name in ["PickupCoil", "LauncherBarrel",
                     "CircuitBattery", "CircuitBulb", "CircuitSwitch"] {
            let box = try bounds(of: name)
            XCTAssertGreaterThan(min(box.extents.x, min(box.extents.y, box.extents.z)), 0,
                                 "\(name) has no thickness on some axis")
        }
    }
}
