//
//  HubBudgetTests.swift
//  PhysicsPlaygroundTests
//
//  The home's rendering budget, counted the way `CircuitBudgetTests`
//  counts (2026-11-06): seven miniatures animated every frame under the
//  wordmark, the first thing every wearer sees. Before this pass the
//  miniatures were built from the labs' own 8 000-triangle spheres and
//  13 000-triangle rounded boxes — a strobe of fifteen dots alone was
//  120 000 — and the optics bench kept 32 beam cylinders drawn at a scale
//  of 1e-5.
//

import XCTest
import RealityKit
@testable import PhysicsPlayground

@MainActor
final class HubBudgetTests: XCTestCase {

    /// The home at its heaviest frame over eight seconds of its cycles.
    func testTheHomeIsWithinBudget() {
        let scene = HubScene()
        scene.openingAlreadyPlayed = true
        scene.build(modules: ModuleCatalog.all(appModel: AppModel()))
        var worst = CircuitBudgetTests.Cost()
        var worstFrame = 0
        for frame in 0..<240 {
            scene.animate(dt: 1.0 / 30.0)
            let cost = CircuitBudgetTests.cost(of: scene.root)
            if cost.triangles > worst.triangles { worst = cost; worstFrame = frame }
        }
        for _ in 0..<worstFrame { scene.animate(dt: 1.0 / 30.0) }
        print("[budget] Home worst frame \(worstFrame): \(worst); heaviest: \(BudgetReport.heaviest(scene.root, top: 12))")
        // Measured 2026-11-06 after this pass: 191 132 triangles, 223 draws; it was
        // 607 644. Apple's figure for the Shared Space is 250 000 and 250.
        XCTAssertLessThanOrEqual(worst.draws, 240, "\(worst); heaviest: \(BudgetReport.heaviest(scene.root))")
        XCTAssertLessThanOrEqual(worst.triangles, 230_000, "\(worst); heaviest: \(BudgetReport.heaviest(scene.root))")
    }
}
