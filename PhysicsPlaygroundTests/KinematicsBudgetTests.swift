//
//  KinematicsBudgetTests.swift
//  PhysicsPlaygroundTests
//
//  Projectiles' rendering budget, counted the way `CircuitBudgetTests`
//  counts (2026-11-06). Before this pass every strobe dot was an 8 000-
//  triangle `generateSphere`, forty to a flight, and so were the balls,
//  the launcher, the aim bead and the waiting ball.
//

import XCTest
import RealityKit
import PhysicsCore
@testable import PhysicsPlayground

@MainActor
final class KinematicsBudgetTests: XCTestCase {

    /// The quiet room: the launcher, its bead and shaft, the waiting ball.
    func testTheQuietRoomIsCheap() {
        let model = KinematicsModel()
        let renderer = KinematicsRenderer()
        renderer.tick(model)
        let cost = BudgetReport.log("Projectiles opening", renderer.root)
        // Measured 2026-11-06 after this pass: 4 264 triangles, 6 draws; it was 17 912.
        XCTAssertLessThanOrEqual(cost.draws, 12, "\(cost); heaviest: \(BudgetReport.heaviest(renderer.root))")
        XCTAssertLessThanOrEqual(cost.triangles, 8_000, "\(cost); heaviest: \(BudgetReport.heaviest(renderer.root))")
    }

    /// One shot 0.8 s into its flight, its strobe behind it.
    func testABallInFlightWithItsStrobeIsCheap() throws {
        let model = KinematicsModel()
        let renderer = KinematicsRenderer()
        model.fire()
        for _ in 0..<72 {
            model.step(dt: 1.0 / 90.0)
            renderer.tick(model)
        }
        XCTAssertEqual(model.flights.first?.status, .flying)
        let cost = BudgetReport.log("Projectiles in flight", renderer.root)
        // Measured 2026-11-06: 8 048 triangles, 19 draws; it was 114 936. A full
        // forty-dot strobe adds about 8 000 more.
        XCTAssertLessThanOrEqual(cost.draws, 60, "\(cost); heaviest: \(BudgetReport.heaviest(renderer.root))")
        XCTAssertLessThanOrEqual(cost.triangles, 20_000, "\(cost); heaviest: \(BudgetReport.heaviest(renderer.root))")
    }

    /// The hoop well's preview and the waiting ball stand in the room the
    /// whole time.
    func testTheWellPreviewsAreCheap() {
        let renderer = KinematicsRenderer()
        let triangles = [KinematicsRenderer.hoopPreview(), renderer.readyBall]
            .map { CircuitBudgetTests.cost(of: $0).triangles }.reduce(0, +)
        print("[budget] Projectiles previews: \(triangles) triangles")
        // Measured 2026-11-06: 2 032; it was 8 576.
        XCTAssertLessThanOrEqual(triangles, 3_000, "the previews draw \(triangles)")
    }
}
