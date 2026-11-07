//
//  PendulumBudgetTests.swift
//  PhysicsPlaygroundTests
//
//  Pendulums' rendering budget, counted the way `CircuitBudgetTests`
//  counts (2026-11-06). Before this pass every trail bead was an 8 000-
//  triangle `generateSphere` — about 56 live per swinging bob at 40 Hz
//  over 1.4 s — and so were the bobs and the wells' previews.
//

import XCTest
import RealityKit
import PhysicsCore
@testable import PhysicsPlayground

@MainActor
final class PendulumBudgetTests: XCTestCase {

    /// The opening cradle, as it hangs.
    func testTheOpeningCradleIsCheap() {
        let model = PendulumsModel()
        let renderer = PendulumsRenderer()
        renderer.tick(dt: 1.0 / 90.0, model: model)
        let cost = BudgetReport.log("Pendulums opening", renderer.root)
        XCTAssertTrue(cost.unmeasured.isEmpty, "\(cost.unmeasured)")
        // Measured 2026-11-06 after this pass: 10 544 triangles, 17 draws; it was 43 264.
        XCTAssertLessThanOrEqual(cost.draws, 24, "\(cost); heaviest: \(BudgetReport.heaviest(renderer.root))")
        XCTAssertLessThanOrEqual(cost.triangles, 16_000, "\(cost); heaviest: \(BudgetReport.heaviest(renderer.root))")
    }

    /// The cradle in motion with its trail full: an end bob thrown, two
    /// seconds at 90 Hz (the trail lives 1.4 s).
    func testASwingingCradleWithItsTrailIsCheap() throws {
        let model = PendulumsModel()
        let renderer = PendulumsRenderer()
        let end = try XCTUnwrap(model.pendulums.first)
        model.beginGrab(id: end.id)
        model.release(id: end.id, handVelocity: [-1.2, 0, 0])
        for _ in 0..<180 {
            model.step(dt: 1.0 / 90.0)
            renderer.tick(dt: 1.0 / 90.0, model: model)
        }
        XCTAssertGreaterThan(model.pendulums.map { simd_length($0.state.velocity) }.max() ?? 0, 0.1,
                             "the cradle should be swinging")
        let cost = BudgetReport.log("Pendulums swinging", renderer.root)
        // Measured 2026-11-06: 26 482 triangles, 128 draws; it was 813 882. The beads
        // stay one entity each, since each carries its own speed colour.
        XCTAssertLessThanOrEqual(cost.draws, 160, "\(cost); heaviest: \(BudgetReport.heaviest(renderer.root))")
        XCTAssertLessThanOrEqual(cost.triangles, 40_000, "\(cost); heaviest: \(BudgetReport.heaviest(renderer.root))")
    }

    /// The two well mouths stand in the room the whole time.
    func testTheWellPreviewsAreCheap() {
        let previews = [PendulumsRenderer.pendulumPreview(), PendulumsRenderer.doublePendulumPreview()]
        let triangles = previews.map { CircuitBudgetTests.cost(of: $0).triangles }.reduce(0, +)
        print("[budget] Pendulums previews: \(triangles) triangles")
        // Measured 2026-11-06: 3 296; it was 25 472.
        XCTAssertLessThanOrEqual(triangles, 5_000, "the two previews draw \(triangles)")
    }
}
