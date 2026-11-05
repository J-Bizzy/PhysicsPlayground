//
//  FieldBudgetTests.swift
//  PhysicsPlaygroundTests
//
//  Electric Fields' rendering budget, measured from what the renderer
//  builds (2026-11-03, the owner: "quite laggy"). Counted the way
//  `CircuitBudgetTests` counts: a draw is one mesh part of one enabled
//  entity, a triangle counted as often as it is drawn.
//
//  Before this pass the opening dipole was 184 000 triangles in 196 draws:
//  every arrowhead its own entity, every line point a ring of three tubes,
//  and each charge's sphere and sign strokes `generate*` meshes of 8 000 and
//  13 000 triangles. A test charge in flight added 190 trail beads, each a
//  transparent draw of an 8 000-triangle sphere.
//

import XCTest
import RealityKit
import RenderKit
import PhysicsCore
@testable import PhysicsPlayground

@MainActor
final class FieldBudgetTests: XCTestCase {

    /// The scene once the first trace has landed.
    private func settled(_ model: FieldModel, steps: Int = 0) async throws -> FieldRenderer {
        let renderer = FieldRenderer()
        for _ in 0..<steps {
            model.step(dt: 1.0 / 90.0)
            renderer.tick(model)
        }
        renderer.tick(model)
        for _ in 0..<100 {
            try await Task.sleep(for: .milliseconds(20))
            renderer.tick(model)
            if CircuitBudgetTests.cost(of: renderer.root).draws > 4 { break }
        }
        // A trail commits at most 30 times a second: let the last one land.
        try await Task.sleep(for: .milliseconds(120))
        renderer.tick(model)
        return renderer
    }

    /// Where a scene's triangles go, for a failure message to name.
    private func heaviest(_ root: Entity) -> String {
        var rows: [(String, Int)] = []
        func walk(_ entity: Entity) {
            guard entity.isEnabled else { return }
            if let model = entity.components[ModelComponent.self] {
                let triangles = CircuitBudgetTests.cost(of: model.mesh).triangles
                if triangles > 1_000 { rows.append((entity.name.isEmpty ? "?" : entity.name, triangles)) }
            }
            entity.children.forEach(walk)
        }
        walk(root)
        return rows.sorted { $0.1 > $1.1 }.prefix(6).map { "\($0.0) \($0.1)" }.joined(separator: ", ")
    }

    func testTheOpeningDipoleIsCheap() async throws {
        let renderer = try await settled(FieldModel())
        let cost = CircuitBudgetTests.cost(of: renderer.root)
        XCTAssertTrue(cost.unmeasured.isEmpty, "\(cost.unmeasured)")
        // Measured 2026-11-03 after this pass: 9 draws; it was 194.
        XCTAssertLessThanOrEqual(cost.draws, 16, "\(cost); heaviest: \(heaviest(renderer.root))")
        XCTAssertLessThanOrEqual(cost.triangles, 40_000, "\(cost); heaviest: \(heaviest(renderer.root))")
    }

    /// The arrowheads ride in the core line's own mesh: more lines, no more draws.
    func testArrowheadsAddNoDraws() async throws {
        let one = FieldModel()
        let few = try await settled(one)
        let more = FieldModel()
        _ = more.addCharge(positive: true, at: FieldModel.regionCenter + SIMD3(0, 0.3, 0))
        let many = try await settled(more)
        let fewCost = CircuitBudgetTests.cost(of: few.root)
        let manyCost = CircuitBudgetTests.cost(of: many.root)
        // A third charge adds its sphere and sign: a handful of draws, not its arrows.
        XCTAssertLessThanOrEqual(manyCost.draws - fewCost.draws, 4,
                                 "\(fewCost) → \(manyCost)")
    }

    /// A test charge circling in uniform B with its trail full.
    func testAFlyingTestChargeIsCheap() async throws {
        let model = FieldModel()
        model.magneticFieldOn = true
        model.dropProbe()
        let renderer = try await settled(model, steps: 900)
        XCTAssertGreaterThan(model.probeTrail.count, 50, "the trail should have grown")
        let cost = CircuitBudgetTests.cost(of: renderer.root)
        XCTAssertLessThanOrEqual(cost.draws, 40, "\(cost); heaviest: \(heaviest(renderer.root))")
        XCTAssertLessThanOrEqual(cost.triangles, 60_000, "\(cost); heaviest: \(heaviest(renderer.root))")
    }

    /// The three well mouths stand in the room the whole time.
    func testTheWellPreviewsAreCheap() {
        let previews = [FieldRenderer.chargePreview(isPositive: true),
                        FieldRenderer.chargePreview(isPositive: false),
                        FieldRenderer.probePreview(isPositive: true)]
        let triangles = previews.map { CircuitBudgetTests.cost(of: $0).triangles }.reduce(0, +)
        XCTAssertLessThanOrEqual(triangles, 6_000, "the three previews draw \(triangles)")
    }

    /// The faceted sphere and the flat bar are what they claim.
    func testTheCheapPrimitivesAreCheap() {
        XCTAssertLessThanOrEqual(
            CircuitBudgetTests.cost(of: Primitives.sphere(radius: 0.03, segments: 40)).triangles,
            1_600)
        XCTAssertLessThanOrEqual(
            CircuitBudgetTests.cost(of: Primitives.roundedBar(
                size: [0.024, 0.0062, 0.005], cornerRadius: 0.0022)).triangles,
            80)
    }
}
