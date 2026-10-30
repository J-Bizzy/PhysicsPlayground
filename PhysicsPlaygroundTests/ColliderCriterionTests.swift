//
//  ColliderCriterionTests.swift
//  PhysicsPlaygroundTests
//
//  The collider rule, enforced by a test instead of by attention: an
//  input-targetable collider must never be larger than the thing it
//  represents, because hit-testing uses colliders and an oversized one
//  shields its neighbours. This reflects over every module and every
//  primitive, walking every `CollisionComponent` and measuring it
//  against the visual bounds of the entity that carries it, with
//  allowed = max(visual × 1.15, visual + 0.03 m). It measures a collider
//  against its own entity, not its neighbours; spacing is a layout
//  property covered elsewhere.
//

import XCTest
import RealityKit
import RenderKit
import simd
@testable import PhysicsPlayground

@MainActor
final class ColliderCriterionTests: XCTestCase {

    /// Proportional allowance over the visual bounds.
    private let proportionalMargin: Float = 1.15
    /// Flat allowance, total across an axis — 15 mm of reach per side.
    private let flatMargin: Float = 0.03

    // MARK: The criterion

    private struct Violation {
        let path: String
        let axis: String
        let visual: Float
        let collider: Float
        let allowed: Float
    }

    /// Colliders skipped because their entity was folded away when the
    /// scene was measured. Reported, never silently dropped.
    private var unmeasured: [String] = []

    private func violations(under root: Entity, label: String) -> [Violation] {
        var found: [Violation] = []
        unmeasured = []

        func walk(_ entity: Entity, path: String) {
            if let collision = entity.components[CollisionComponent.self] {
                // In world metres, not the entity's frame: pooled objects carry one
                // authored collider on a per-instance scale, and the flat 30 mm
                // allowance only means anything in metres.
                let worldScale = entity.scale(relativeTo: nil)
                let visual = entity.visualBounds(relativeTo: entity)
                let visualExtents = visual.extents * worldScale

                // A folded instrument is not measurable: at a world scale of 0.001 the
                // flat allowance becomes 30 m locally. Every scene below is ticked open
                // before it is measured; this records the hole rather than passing.
                if simd_reduce_min(worldScale) < 0.05 {
                    unmeasured.append(path)
                    for child in entity.children {
                        let name = child.name.isEmpty ? "·" : child.name
                        walk(child, path: "\(path)/\(name)")
                    }
                    return
                }
                // An entity with no mesh beneath it has nothing to be measured
                // against; a pure trigger volume is legitimate.
                let hasVisual = visualExtents.x.isFinite && visualExtents.y.isFinite
                    && visualExtents.z.isFinite
                    && simd_length(visualExtents) > 1e-5

                if hasVisual {
                    for shape in collision.shapes {
                        let extents = shape.bounds.extents * worldScale
                        for (axis, v, c) in [("x", visualExtents.x, extents.x),
                                             ("y", visualExtents.y, extents.y),
                                             ("z", visualExtents.z, extents.z)] {
                            let allowed = max(v * proportionalMargin, v + flatMargin)
                            // A tenth of a millimetre of slop, so a target sized to exactly
                            // `visual + reach` does not fail on the last bit of a Float.
                            if c > allowed + 1e-4 {
                                found.append(Violation(path: path, axis: axis,
                                                       visual: v, collider: c,
                                                       allowed: allowed))
                            }
                        }
                    }
                }
            }
            for child in entity.children {
                let name = child.name.isEmpty ? "·" : child.name
                walk(child, path: "\(path)/\(name)")
            }
        }

        walk(root, path: label)
        return found
    }

    private func assertCollidersFit(_ root: Entity, _ label: String,
                                    file: StaticString = #filePath, line: UInt = #line) {
        let found = violations(under: root, label: label)
        XCTAssertTrue(
            unmeasured.isEmpty,
            "\(unmeasured.count) collider(s) in \(label) were folded away when "
            + "the scene was measured, so nothing was checked: "
            + "\(unmeasured.joined(separator: ", ")). Tick the instrument open "
            + "before asserting, or this test is reporting a pass it did not "
            + "earn.", file: file, line: line)
        guard !found.isEmpty else { return }
        let report = found
            .sorted { $0.collider / max($0.allowed, 1e-6) > $1.collider / max($1.allowed, 1e-6) }
            .map { v in
                String(format: "  %@ [%@]: collider %.4f m vs visual %.4f m "
                       + "(allowed %.4f m, over by %.1f×)",
                       v.path, v.axis, v.collider, v.visual, v.allowed,
                       v.collider / max(v.allowed, 1e-6))
            }
            .joined(separator: "\n")
        XCTFail("\(found.count) collider(s) larger than the thing they represent "
                + "in \(label):\n\(report)", file: file, line: line)
    }

    /// The criterion must be able to fail: the exact shape of the capacitor
    /// plate defect, a 0.26 m sphere on a thin slab, has to be caught.
    func testTheCriterionCatchesTheDefectItWasWrittenFor() {
        let plate = ModelEntity(mesh: .generateBox(size: [0.012, 0.5, 0.5]),
                                materials: [UnlitMaterial(color: .white)])
        plate.name = "plate"
        Grabbable.configureTouchTarget(plate, collisionRadius: 0.26)

        let found = violations(under: plate, label: "fixture")
        XCTAssertFalse(found.isEmpty,
                       "the criterion did not catch a 0.52 m sphere on a 12 mm plate")
        XCTAssertTrue(found.contains { $0.axis == "x" },
                      "the thin axis is the one that shields the room, and it was missed")
    }

    /// …and must not fire on a target sized the way the rule asks.
    func testTheCriterionPassesATargetSizedToItsObject() {
        let bob = ModelEntity(mesh: .generateSphere(radius: 0.035),
                              materials: [UnlitMaterial(color: .white)])
        bob.name = "bob"
        Grabbable.configureTouchTarget(bob, collisionRadius: 0.048)
        XCTAssertTrue(violations(under: bob, label: "fixture").isEmpty)
    }

    // MARK: The design-system primitives

    func testDesignSystemPrimitiveCollidersFit() {
        let actions = SpatialActionBank(accent: .white, actions: [
            .init(id: "clear", label: "Clear", symbol: "trash", confirms: true, fire: {}),
        ])
        for _ in 0..<40 {
            actions.update(anchor: .zero, viewer: [0, 0, 1], dt: 1 / 90, resetNonce: 0)
        }
        assertCollidersFit(actions.root, "SpatialActionBank")

        let picker = SpatialPicker(
            accessibilityNoun: "Speed",
            choices: (0..<4).map { .init(id: "\($0)", label: "\($0)×") },
            staysOpen: true)
        for _ in 0..<40 { picker.update(anchor: .zero, viewer: [0, 0, 1], dt: 1 / 90) }
        assertCollidersFit(picker.root, "SpatialPicker")
    }

    // MARK: The modules

    func testPendulumsCollidersFit() {
        let model = PendulumsModel()
        let renderer = PendulumsRenderer()
        for _ in 0..<3 { renderer.tick(dt: 1 / 90, model: model) }
        assertCollidersFit(renderer.root, "Pendulums")
    }

    func testElectricFieldsCollidersFit() {
        let model = FieldModel()
        model.capacitorOn = true
        let renderer = FieldRenderer()
        for _ in 0..<3 { renderer.tick(model) }
        assertCollidersFit(renderer.root, "ElectricFields")
    }

    func testOrbitalMechanicsCollidersFit() {
        let model = OrbitalMechanicsModel()
        let renderer = OrbitalMechanicsRenderer()
        for _ in 0..<3 { renderer.tick(model) }
        assertCollidersFit(renderer.root, "OrbitalMechanics")
    }

    func testProjectilesCollidersFit() {
        let model = KinematicsModel()
        let renderer = KinematicsRenderer()
        for _ in 0..<3 { renderer.tick(model) }
        assertCollidersFit(renderer.root, "Projectiles")
    }

    func testMagnetismCollidersFit() {
        let model = MagnetismModel()
        // With a coil out of the well, selected, so its halo stands too.
        model.addCoil(at: SIMD3(0, 1.3, -0.5))
        let renderer = MagnetismRenderer()
        for _ in 0..<3 { renderer.tick(model) }
        assertCollidersFit(renderer.root, "Magnetism")
    }

    func testOpticsCollidersFit() {
        let model = OpticsModel()
        // Selected, so the aim bead stands and is measured too.
        model.select(id: model.pieces.first?.id)
        let renderer = OpticsRenderer()
        for _ in 0..<3 { renderer.tick(model) }
        assertCollidersFit(renderer.root, "Light & Optics")
    }

    func testCircuitsCollidersFit() {
        let model = CircuitsModel()
        let renderer = CircuitsRenderer()
        for _ in 0..<3 { renderer.tick(dt: 1 / 90, model: model) }
        assertCollidersFit(renderer.root, "Circuits")
    }

    /// A joint: two parts snapped nose-to-tail, the junction dot's sphere the one
    /// target where their leads meet.
    func testCircuitsJointCollidersFit() {
        let model = CircuitsModel()
        model.clearBench()
        guard let battery = model.add(.battery, at: CircuitsModel.buildCenter),
              let part = model.components.first(where: { $0.id == battery }) else {
            return XCTFail("no battery")
        }
        let landing = part.terminalPosition(1) + SIMD3(0.03 + CircuitsModel.terminalOffset, 0.02, 0)
        if let bulb = model.add(.bulb, at: landing) { model.release(id: bulb) }
        XCTAssertEqual(model.wires.count, 1)
        let renderer = CircuitsRenderer()
        for _ in 0..<3 { renderer.tick(dt: 1 / 90, model: model) }
        assertCollidersFit(renderer.root, "Circuits, a joint")
    }

    /// Every kind of part, not just the starter loop's three: each module's
    /// contacts, carry box and (on the switch) blade are measured.
    func testCircuitsCollidersFitEveryKind() {
        let model = CircuitsModel()
        model.clearBench()
        for (index, kind) in CircuitsModel.ComponentKind.allCases.enumerated() {
            model.add(kind, at: SIMD3(-0.48 + Double(index % 5) * 0.24,
                                      1.42 - Double(index / 5) * 0.24, -0.85))
        }
        let renderer = CircuitsRenderer()
        for _ in 0..<3 { renderer.tick(dt: 1 / 90, model: model) }
        assertCollidersFit(renderer.root, "Circuits, every kind")
    }

    // MARK: The home and the shell

    /// The first surface every user sees. Each lab moves — the magnet
    /// through its coil, the cradle's balls, the slow turn — and its target
    /// covers the whole motion, as the plinth under it did until 2026-10-21:
    /// so a portal is measured against everything it drew over its longest
    /// loop, not one pose. Everything else in the home is measured as it
    /// stands.
    func testHomeCollidersFit() {
        let scene = HubScene()
        scene.openingAlreadyPlayed = true
        scene.build(modules: ModuleCatalog.all(appModel: AppModel()))
        let ids = scene.portalIDs
        for child in scene.root.children where !ids.contains(child.name) {
            assertCollidersFit(child, "Home")
        }

        // Twelve seconds, past the longest loop (the light bench's ten), a
        // pose every quarter-second.
        var swept: [String: BoundingBox] = [:]
        for _ in 0..<48 {
            for _ in 0..<8 { scene.animate(dt: 1.0 / 30.0) }
            for id in ids {
                guard let anchor = scene.portal(id) else { continue }
                let bounds = anchor.visualBounds(relativeTo: anchor)
                swept[id] = swept[id].map { $0.union(bounds) } ?? bounds
            }
        }
        for id in ids {
            guard let anchor = scene.portal(id),
                  let shape = anchor.components[CollisionComponent.self]?.shapes.first,
                  let visual = swept[id] else {
                XCTFail("Home/\(id) has no target to measure")
                continue
            }
            for (axis, v, c) in [("x", visual.extents.x, shape.bounds.extents.x),
                                 ("y", visual.extents.y, shape.bounds.extents.y),
                                 ("z", visual.extents.z, shape.bounds.extents.z)] {
                let allowed = max(v * proportionalMargin, v + flatMargin)
                XCTAssertLessThanOrEqual(c, allowed + 1e-4,
                                         "Home/\(id) [\(axis)]: target \(c) m over a lab that sweeps \(v) m")
            }
        }
    }

    /// Does this collider shield the thing next to it? A target derived
    /// from an entity's visual bounds passes a self-measuring test by
    /// construction, whatever those bounds contain; the home's six
    /// portals at a known pitch are the one place the question can be
    /// asked directly.
    func testPortalTargetsDoNotOverlapEachOther() {
        let scene = HubScene()
        scene.openingAlreadyPlayed = true
        scene.build(modules: ModuleCatalog.all(appModel: AppModel()))

        // Every portal's target, as a world-space box.
        let moduleIDs = Set(ModuleCatalog.all(appModel: AppModel()).map(\.id))
        var targets: [(id: String, min: SIMD3<Float>, max: SIMD3<Float>)] = []

        func collect(_ entity: Entity, label: String) {
            guard let collision = entity.components[CollisionComponent.self],
                  let shape = collision.shapes.first else { return }
            let centre = entity.position(relativeTo: nil) + shape.bounds.center
            let half = shape.bounds.extents / 2
            targets.append((label, centre - half, centre + half))
        }

        for exhibit in scene.root.children where moduleIDs.contains(exhibit.name) {
            collect(exhibit, label: exhibit.name)
        }

        XCTAssertEqual(targets.count, moduleIDs.count,
                       "expected one target per portal; "
                       + "found \(targets.count) — if the home changed shape "
                       + "this test is measuring the wrong thing")

        for (index, a) in targets.enumerated() {
            for b in targets[(index + 1)...] {
                let overlaps = a.min.x < b.max.x && b.min.x < a.max.x
                    && a.min.y < b.max.y && b.min.y < a.max.y
                    && a.min.z < b.max.z && b.min.z < a.max.z
                XCTAssertFalse(
                    overlaps,
                    String(format: "%@ and %@ have overlapping touch targets — "
                           + "which one a pinch selects is decided by hit order.\n"
                           + "  %@  x[%.3f…%.3f] y[%.3f…%.3f] z[%.3f…%.3f]\n"
                           + "  %@  x[%.3f…%.3f] y[%.3f…%.3f] z[%.3f…%.3f]\n"
                           + "  separate on ANY one axis and they no longer clash.",
                           a.id, b.id,
                           a.id, a.min.x, a.max.x, a.min.y, a.max.y, a.min.z, a.max.z,
                           b.id, b.min.x, b.max.x, b.min.y, b.max.y, b.min.z, b.max.z))
            }
        }
    }



    /// The placement puck is the object you move a whole lab with, and
    /// it stands among the lab's own apparatus.
    func testLabPlacementPuckCollidersFit() {
        let puck = LabAnchorView.makeAnchor(accent: .white)
        assertCollidersFit(puck, "LabPlacement")
    }
}
