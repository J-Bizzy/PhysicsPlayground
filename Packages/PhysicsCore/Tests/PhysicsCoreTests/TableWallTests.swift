//
//  TableWallTests.swift
//  PhysicsCoreTests
//
//  A table is a finite horizontal wall (Projectiles, 2026-09-02): the
//  strike law was written for vertical rectangles and the ceiling, and
//  these pin that it is genuinely normal-agnostic — a drop onto a table
//  top bounces, a drop beside it falls past, and the underside is a
//  surface too.
//

import XCTest
import simd
@testable import PhysicsCore

final class TableWallTests: XCTestCase {

    private let table = RoomWalls.Wall(
        center: SIMD3(0, 0.70, 0), normal: SIMD3(0, 1, 0),
        uAxis: SIMD3(1, 0, 0), vAxis: SIMD3(0, 0, 1), halfU: 0.40, halfV: 0.30)

    func testADropOntoTheTableTopBounces() throws {
        let hit = try XCTUnwrap(RoomWalls.strike(
            previous: SIMD3(0.1, 1.0, 0.1), current: SIMD3(0.1, 0.6, 0.1),
            velocity: SIMD3(0, -3, 0), radius: 0.05, restitution: 0.8, walls: [table]))
        XCTAssertEqual(hit.position.y, 0.75, accuracy: 1e-9, "the ball's surface meets the top")
        XCTAssertEqual(hit.velocity.y, 2.4, accuracy: 1e-9)
        XCTAssertEqual(hit.impactSpeed, 3, accuracy: 1e-9)
    }

    func testADropBesideTheTableFallsPast() {
        XCTAssertNil(RoomWalls.strike(
            previous: SIMD3(0.6, 1.0, 0), current: SIMD3(0.6, 0.6, 0),
            velocity: SIMD3(0, -3, 0), radius: 0.05, restitution: 0.8, walls: [table]))
    }

    func testTheUndersideIsASurfaceToo() throws {
        let hit = try XCTUnwrap(RoomWalls.strike(
            previous: SIMD3(0, 0.40, 0), current: SIMD3(0, 0.80, 0),
            velocity: SIMD3(0, 3, 0), radius: 0.05, restitution: 0.8, walls: [table]))
        XCTAssertEqual(hit.position.y, 0.65, accuracy: 1e-9)
        XCTAssertLessThan(hit.velocity.y, 0)
    }
}
