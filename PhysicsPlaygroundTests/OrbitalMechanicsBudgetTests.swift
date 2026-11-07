//
//  OrbitalMechanicsBudgetTests.swift
//  PhysicsPlaygroundTests
//
//  Orbital Mechanics' rendering budget, counted the way
//  `CircuitBudgetTests` counts (2026-11-06). The trails are one
//  `TrailRibbons` mesh, which the counter cannot read: it shows as one
//  unmeasured draw. Before this pass every body, the Sun's glow and the
//  hidden markers were 8 000-triangle `generateSphere`s.
//

import XCTest
import RealityKit
import PhysicsCore
@testable import PhysicsPlayground

@MainActor
final class OrbitalMechanicsBudgetTests: XCTestCase {

    /// The opening system a second in, its trails begun.
    func testTheOpeningSystemIsCheap() {
        let model = OrbitalMechanicsModel()
        let renderer = OrbitalMechanicsRenderer()
        for _ in 0..<90 {
            model.step(dt: 1.0 / 90.0)
            renderer.tick(model)
        }
        let cost = BudgetReport.log("Orbits opening", renderer.root)
        XCTAssertLessThanOrEqual(cost.unmeasured.count, 2, "\(cost.unmeasured)")
        // Measured 2026-11-06 after this pass: 54 078 triangles, 85 draws; it was 119 742.
        XCTAssertLessThanOrEqual(cost.draws, 110, "\(cost); heaviest: \(BudgetReport.heaviest(renderer.root))")
        XCTAssertLessThanOrEqual(cost.triangles, 70_000, "\(cost); heaviest: \(BudgetReport.heaviest(renderer.root))")
    }
}
