//
//  MagnetismBudgetTests.swift
//  PhysicsPlaygroundTests
//
//  Magnetism's rendering budget, counted the way `CircuitBudgetTests`
//  counts (2026-11-06). Before this pass every arrowhead on a field line
//  was its own entity (a pool of 600), each magnet three 13 000-triangle
//  rounded boxes with four extruded letters built uncached, and the
//  compass another 40 000. The three line tubes are `LiveTube` meshes,
//  which the counter cannot read: they show as unmeasured draws.
//

import XCTest
import RealityKit
import PhysicsCore
@testable import PhysicsPlayground

@MainActor
final class MagnetismBudgetTests: XCTestCase {

    /// The bench once its first trace has landed (the lines are computed
    /// off the main thread and applied at most 30 times a second).
    private func settled(_ model: MagnetismModel) async throws -> MagnetismRenderer {
        let renderer = MagnetismRenderer()
        renderer.tick(model)
        let first = CircuitBudgetTests.cost(of: renderer.root)
        for _ in 0..<150 {
            try await Task.sleep(for: .milliseconds(20))
            renderer.tick(model)
            if CircuitBudgetTests.cost(of: renderer.root) != first { break }
        }
        try await Task.sleep(for: .milliseconds(150))
        renderer.tick(model)
        return renderer
    }

    /// Two magnets, their lines and the compass.
    func testTheOpeningBenchIsCheap() async throws {
        let renderer = try await settled(MagnetismModel())
        let cost = BudgetReport.log("Magnetism opening", renderer.root)
        XCTAssertLessThanOrEqual(cost.unmeasured.count, 3, "only the three line tubes: \(cost.unmeasured)")
        // Measured 2026-11-06 after this pass: 89 248 triangles, 35 draws; it was
        // 258 772 in 332. Three quarters of what is left is the three line tubes.
        XCTAssertLessThanOrEqual(cost.draws, 48, "\(cost); heaviest: \(BudgetReport.heaviest(renderer.root))")
        XCTAssertLessThanOrEqual(cost.triangles, 120_000, "\(cost); heaviest: \(BudgetReport.heaviest(renderer.root))")
    }

    /// The arrowheads ride in the lines' own mesh: the lines layer costs
    /// its three tubes and nothing per arrow.
    func testTheLinesAddOnlyTheirTubes() async throws {
        let bare = MagnetismModel()
        bare.showFieldLines = false
        let without = try await settled(bare)
        let with = try await settled(MagnetismModel())
        let a = CircuitBudgetTests.cost(of: without.root)
        let b = CircuitBudgetTests.cost(of: with.root)
        print("[budget] Magnetism lines off \(a) → on \(b)")
        // Measured 2026-11-06: +3 draws; it was +300.
        XCTAssertLessThanOrEqual(b.draws - a.draws, 6, "\(a) → \(b)")
    }

    /// The two well mouths stand in the room the whole time.
    func testTheWellPreviewsAreCheap() {
        let previews = [MagnetismRenderer.magnetPreview(), MagnetismRenderer.coilPreview()]
        let triangles = previews.map { CircuitBudgetTests.cost(of: $0).triangles }.reduce(0, +)
        print("[budget] Magnetism previews: \(triangles) triangles; heaviest: \(previews.map { BudgetReport.heaviest($0) })")
        // Measured 2026-11-06: 42 844, most of it the milled coil; it was 147 284.
        XCTAssertLessThanOrEqual(triangles, 60_000, "the two previews draw \(triangles)")
    }
}
