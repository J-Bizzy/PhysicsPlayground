//
//  PickupCoilPropTests.swift
//  PhysicsPlaygroundTests
//
//  The milled coil is the coil the physics traces: its flanges are the
//  radius `MagnetismModel` draws a halo round, its length is the winding
//  plus the bobbin, and its bore runs along +x, the axis the renderer
//  turns onto the coil's own. A prop scaled by eye is a prop a magnet
//  passes through the copper of.
//

import XCTest
import RealityKit
@testable import PhysicsPlayground

@MainActor
final class PickupCoilPropTests: XCTestCase {

    func testTheMilledCoilMatchesThePhysics() throws {
        let coil = try XCTUnwrap(PropCache.prototype(named: "PickupCoil"),
                                 "PickupCoil.usdz did not load — run Tools/pickupcoil.py")
        let box = coil.visualBounds(relativeTo: nil)
        // Along the bore: the winding, two flanges and the sleeve's lips.
        XCTAssertEqual(box.extents.x, Float(MagnetismModel.coilLength) + 0.016, accuracy: 0.0015)
        // Across it, the flanges' diameter, both ways the bore is not.
        XCTAssertEqual(box.extents.z, 2 * Float(MagnetismModel.coilFlangeRadius), accuracy: 0.0015)
        XCTAssertGreaterThan(box.extents.y, box.extents.z, "the terminal block should stand above the flanges")
        // Centred on the bore, so the renderer's turn turns it about its axis.
        XCTAssertEqual(box.center.x, 0, accuracy: 0.001)
        XCTAssertEqual(box.center.z, 0, accuracy: 0.001)
    }

    /// The LED's seat is the top of the milled socket: the dome sits on it,
    /// not inside the block or floating above it.
    func testTheLEDSitsInItsSocket() throws {
        let coil = try XCTUnwrap(PropCache.prototype(named: "PickupCoil"))
        let top = coil.visualBounds(relativeTo: nil).max.y
        XCTAssertEqual(top, MagnetismRenderer.ledSeat, accuracy: 0.001)
    }
}
