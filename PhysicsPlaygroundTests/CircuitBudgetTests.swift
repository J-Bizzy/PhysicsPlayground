//
//  CircuitBudgetTests.swift
//  PhysicsPlaygroundTests
//
//  Circuit Workshop's rendering budget, measured from what the renderer
//  actually builds (contract "Budget, defended", 2026-10-30). Apple's figure
//  for the Shared Space is under 250 draw calls and 250k triangles; the
//  bench was 682k triangles in Electron View on the starter loop alone, and
//  a full pool of electron dots was 400 draws by itself. A draw here is one
//  mesh part of one enabled entity — instanced copies would share theirs —
//  and a triangle is counted as often as it is drawn.
//

import XCTest
import RealityKit
@testable import PhysicsPlayground

@MainActor
final class CircuitBudgetTests: XCTestCase {

    struct Cost: Equatable, CustomStringConvertible {
        var triangles = 0
        var draws = 0
        /// Meshes with no triangles to read (a LowLevelMesh, say): counted
        /// as draws but not as triangles, so the tests insist there are none.
        var unmeasured: [String] = []

        static func + (a: Cost, b: Cost) -> Cost {
            Cost(triangles: a.triangles + b.triangles, draws: a.draws + b.draws,
                 unmeasured: a.unmeasured + b.unmeasured)
        }
        static func - (a: Cost, b: Cost) -> Cost {
            Cost(triangles: a.triangles - b.triangles, draws: a.draws - b.draws)
        }
        var description: String { "\(triangles) triangles, \(draws) draws" }
    }

    static func cost(of mesh: MeshResource) -> Cost {
        let contents = mesh.contents
        var cost = Cost()
        func add(_ model: MeshResource.Model) {
            for part in model.parts {
                cost.draws += 1
                cost.triangles += (part.triangleIndices?.count ?? 0) / 3
            }
        }
        if contents.instances.isEmpty {
            contents.models.forEach(add)
        } else {
            for instance in contents.instances {
                if let model = contents.models[instance.model] { add(model) }
            }
        }
        return cost
    }

    /// What an entity tree draws as it stands: disabled subtrees cost
    /// nothing, an instanced mesh costs its parts once and its triangles
    /// once per copy.
    static func cost(of entity: Entity) -> Cost {
        guard entity.isEnabled else { return Cost() }
        var total = Cost()
        if let model = entity.components[ModelComponent.self] {
            var mesh = cost(of: model.mesh)
            if mesh.triangles == 0 { mesh.unmeasured = [entity.name] }
            if let part = entity.components[MeshInstancesComponent.self]?[partIndex: 0] {
                mesh.triangles *= part.data.instanceCount
            }
            total = total + mesh
        }
        return entity.children.reduce(total) { $0 + cost(of: $1) }
    }

    /// Where a bench's triangles go, by the zoom rig's children, for a
    /// failure message to name.
    static func breakdown(_ renderer: CircuitsRenderer) -> String {
        renderer.viewRoot.children.map { child in
            let name = child.name.isEmpty ? "\(type(of: child))" : String(child.name.prefix(14))
            return "\(name) \(cost(of: child).triangles)"
        }.joined(separator: ", ")
    }

    private func tick(_ renderer: CircuitsRenderer, _ model: CircuitsModel, frames: Int) {
        for _ in 0..<frames { renderer.tick(dt: 1 / 90, model: model) }
    }

    // MARK: Per part

    /// Each part's element — the milled asset, its moving pieces included —
    /// stays under 8k triangles (the bulb's glass, under 14k) and six draws;
    /// the dots and leads Swift adds stay under 2.5k and eight. (The contract
    /// said five draws; the bulb's filament and the motor's rotor each carry
    /// their own material, and the bench totals below are the budget that
    /// binds.)
    func testEachPartIsWithinItsBudget() {
        for kind in CircuitsModel.ComponentKind.allCases {
            let module = CircuitsRenderer.makeModule(kind: kind)
            let element = Self.cost(of: module.body)
            let added = Self.cost(of: module.root) - element
            XCTAssertEqual(element.unmeasured, [], "\(kind)")
            XCTAssertGreaterThan(element.triangles, 0, "\(kind)'s element drew nothing")
            XCTAssertLessThanOrEqual(element.triangles, kind == .bulb ? 14_000 : 8_000, "\(kind): \(element)")
            XCTAssertLessThanOrEqual(element.draws, 6, "\(kind): \(element)")
            XCTAssertLessThanOrEqual(added.triangles, 2_500, "\(kind): \(added) added")
            XCTAssertLessThanOrEqual(added.draws, 8, "\(kind): \(added) added")
        }
    }

    /// The electron dot is the milled low-poly pair, not two 8k spheres.
    func testTheElectronDotIsLowPoly() {
        let (core, halo) = CircuitsRenderer.electronMeshes()
        XCTAssertLessThanOrEqual(Self.cost(of: core).triangles + Self.cost(of: halo).triangles, 400)
    }

    // MARK: The bench

    /// The lab's opening, the starter loop, with the skyline standing and
    /// the zoom at 4× — Electron View, where the dots multiply.
    func testTheStarterLoopAtFourTimesIsWithinBudget() {
        let model = CircuitsModel()
        model.showVoltageHeights = true
        let renderer = CircuitsRenderer()
        renderer.handZoom = 4
        tick(renderer, model, frames: 240)
        XCTAssertFalse(renderer.electronDots.positions.isEmpty, "the loop should be conducting")
        let bench = Self.cost(of: renderer.root)
        XCTAssertEqual(bench.unmeasured, [])
        XCTAssertLessThanOrEqual(bench.triangles, 70_000, "\(bench): \(Self.breakdown(renderer))")
        XCTAssertLessThanOrEqual(bench.draws, 120, "\(bench)")
        print("[budget] starter loop at 4×: \(bench) — \(Self.breakdown(renderer))")
    }

    /// The worst a bench gets: all ten parts wired in one loop, the skyline
    /// up, Electron View, and every dot in the pool in the air.
    func testAllTenPartsWithAFullPoolAreWithinBudget() {
        let model = CircuitsModel()
        model.clearBench()
        let kinds = CircuitsModel.ComponentKind.allCases
        var ids: [UUID] = []
        for (index, kind) in kinds.enumerated() {
            let angle = Double(index) / Double(kinds.count) * 2 * .pi
            let position = CircuitsModel.buildCenter + SIMD3(0.42 * cos(angle), 0.30 * sin(angle), 0)
            ids.append(model.add(kind, at: position)!)
        }
        for index in ids.indices {
            model.connectTerminals(
                .init(componentID: ids[index], end: 1),
                .init(componentID: ids[(index + 1) % ids.count], end: 0))
        }
        XCTAssertEqual(model.wires.count, kinds.count)
        model.showVoltageHeights = true
        let renderer = CircuitsRenderer()
        renderer.handZoom = 4
        tick(renderer, model, frames: 240)
        renderer.electronDots.show(Array(repeating: SIMD3<Float>(CircuitsModel.buildCenter),
                                         count: CircuitsRenderer.electronBudget))
        XCTAssertEqual(renderer.electronDots.positions.count, CircuitsRenderer.electronBudget)
        let bench = Self.cost(of: renderer.root)
        XCTAssertEqual(bench.unmeasured, [])
        XCTAssertLessThanOrEqual(bench.triangles, 250_000, "\(bench)")
        XCTAssertLessThanOrEqual(bench.draws, 400, "\(bench)")
        print("[budget] ten parts, a full pool, at 4×: \(bench)")
    }

    // MARK: The dots

    /// A dot is one draw, a bead wide enough to stand proud of the jacket
    /// it rides inside, and a hidden one costs nothing.
    func testEachDotIsOneDrawStandingProudOfTheJacket() {
        XCTAssertGreaterThan(ElectronDots.beadRadius, CircuitsRenderer.wireJacketRadius)
        let dots = ElectronDots(capacity: CircuitsRenderer.electronBudget)
        dots.show([[0, 1, -1]])
        let one = Self.cost(of: dots.root)
        XCTAssertEqual(one.draws, 1)
        dots.show((0..<300).map { SIMD3(Float($0) * 0.001, 1, -1) })
        XCTAssertEqual(dots.positions.count, CircuitsRenderer.electronBudget)
        XCTAssertEqual(Self.cost(of: dots.root).draws, CircuitsRenderer.electronBudget)
        dots.show([])
        XCTAssertEqual(Self.cost(of: dots.root), Cost())
    }

    /// When a bench wants more dots than the pool holds, every conducting
    /// wire keeps at least two and the rest are shared in proportion — no
    /// wire that carries current is drawn as if it carried none.
    func testThePoolIsSharedNotStarved() {
        XCTAssertEqual(CircuitsRenderer.shareDots([10, 20], capacity: 120), [10, 20])
        let wanted = [36, 36, 36, 36, 36, 8, 2]
        let shared = CircuitsRenderer.shareDots(wanted, capacity: 120)
        XCTAssertLessThanOrEqual(shared.reduce(0, +), 120)
        XCTAssertGreaterThan(shared.reduce(0, +), 110, "the pool should be nearly all used")
        XCTAssertTrue(shared.allSatisfy { $0 >= 2 })
        XCTAssertEqual(shared.last, 2)
        XCTAssertGreaterThan(shared[0], shared[5])
    }

    /// The dots ride the wires — every one lies on a wire's straight run —
    /// and go when Electron flow is switched off.
    func testTheDotsRideTheWiresAndGoWhenSwitchedOff() {
        let model = CircuitsModel()
        let renderer = CircuitsRenderer()
        tick(renderer, model, frames: 3)
        let dots = renderer.electronDots.positions
        XCTAssertFalse(dots.isEmpty)
        func end(_ terminal: CircuitsModel.Terminal) -> SIMD3<Float>? {
            model.components.first { $0.id == terminal.componentID }
                .map { SIMD3<Float>($0.terminalPosition(terminal.end)) }
        }
        let runs = model.wires.compactMap { wire -> (SIMD3<Float>, SIMD3<Float>)? in
            guard let a = end(wire.from), let b = end(wire.to) else { return nil }
            return (a, b)
        }
        for dot in dots {
            let nearest = runs.map { a, b -> Float in
                let t = simd_clamp(simd_dot(dot - a, b - a) / simd_length_squared(b - a), 0, 1)
                return simd_distance(dot, a + (b - a) * t)
            }.min() ?? .infinity
            XCTAssertLessThan(nearest, 1e-4, "a dot off every wire")
        }

        model.showElectronFlow = false
        tick(renderer, model, frames: 1)
        XCTAssertTrue(renderer.electronDots.positions.isEmpty)
        XCTAssertEqual(Self.cost(of: renderer.electronDots.root), Cost())
    }
}
