//
//  ColliderCriterionTests.swift
//  PhysicsPlaygroundTests
//
//  THE COLLIDER RULE, ENFORCED BY A TEST INSTEAD OF BY ATTENTION.
//
//  `DESIGN_SYSTEM.md` calls it absolute: *"A collider must never be
//  larger than the thing it represents… an app-wide input outage was
//  traced to one region-sized sphere."* The rule was written in
//  2026-07-29 after that outage, restated in DECISIONS.md, quoted in
//  `Well.makeSource`'s own comment — and violated at a dozen sites in
//  every module, including a 52 cm sphere on a 12 mm plate that made
//  the entire interior of the capacitor unpinchable.
//
//  It was violated everywhere because it was enforced nowhere. Every
//  site is a hand-typed radius next to a hand-typed mesh, in a different
//  file, written on a different day. A test that LISTED the sites would
//  be the same act of attention that mis-sized them, so this one
//  reflects: it builds a scene from each module and every design-system
//  primitive, walks every `CollisionComponent` in it, and measures each
//  shape against the visual bounds of the entity carrying it. Add a
//  grabbable tomorrow and it is covered tomorrow.
//
//  THE MARGIN, and why it is two numbers rather than one.
//
//      allowed = max(visual × 1.15, visual + 0.03 m)
//
//  15% is the proportional allowance: a target you reach for should
//  forgive a near miss. But 15% of a 13 mm circuit terminal is 2 mm,
//  which is not a forgiving target, it is a smaller one — and the rule
//  exists to stop colliders SHIELDING their neighbours, which a target
//  the size of a fingertip does not do. So there is also a flat 30 mm
//  (15 mm of reach per side), which is what `Well.makeSource` had
//  already chosen for itself by hand, and the site gets whichever is
//  kinder. The failure the rule is about — a sphere that swallows the
//  object next to it — is orders of magnitude outside both.
//
//  WHAT THIS TEST CANNOT SEE. It measures a collider against its OWN
//  entity, not against its neighbours, because spacing is a layout
//  property and layout is what `FanLayoutTests` and the placement tests
//  cover. A collider inside this margin can still overlap a neighbour
//  that is genuinely touching it — Newton's cradle balls touch, so their
//  colliders must. What it rules out is the case that broke things: a
//  collider that reaches PAST a neighbour's centre.
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

    /// Walks `root` and measures every collider against the visual
    /// bounds of the entity that carries it.
    private func violations(under root: Entity, label: String) -> [Violation] {
        var found: [Violation] = []

        func walk(_ entity: Entity, path: String) {
            if let collision = entity.components[CollisionComponent.self] {
                let visual = entity.visualBounds(relativeTo: entity)
                let visualExtents = visual.extents
                // An entity with no mesh anywhere beneath it has nothing
                // to be measured against. That is its own smell, but it
                // is not this test's smell — a pure trigger volume is a
                // legitimate thing to build.
                let hasVisual = visualExtents.x.isFinite && visualExtents.y.isFinite
                    && visualExtents.z.isFinite
                    && simd_length(visualExtents) > 1e-5

                if hasVisual {
                    for shape in collision.shapes {
                        let extents = shape.bounds.extents
                        for (axis, v, c) in [("x", visualExtents.x, extents.x),
                                             ("y", visualExtents.y, extents.y),
                                             ("z", visualExtents.z, extents.z)] {
                            let allowed = max(v * proportionalMargin, v + flatMargin)
                            // A tenth of a millimetre of slop. A target
                            // sized to exactly `visual + reach` — which
                            // is what `matchingVisualBoundsOf:` builds —
                            // must not fail on the last bit of a Float.
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

    /// The criterion must be able to fail. A scene built deliberately
    /// wrong — the exact shape of the capacitor plate defect, a 0.26 m
    /// sphere on a thin slab — has to be caught, or every green run
    /// below means nothing.
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
        let bank = SpatialLayerBank(accent: .white, layers: [
            LayerSwitch(id: "lines", label: "Field lines", isOn: { true }, toggle: {}),
            LayerSwitch(id: "grid", label: "Grid", isOn: { false }, toggle: {}),
        ])
        for _ in 0..<40 { bank.update(anchor: .zero, viewer: [0, 0, 1], dt: 1 / 90) }
        assertCollidersFit(bank.root, "SpatialLayerBank")

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

    func testGravityLabCollidersFit() {
        let model = GravityLabModel()
        let renderer = GravityLabRenderer()
        for _ in 0..<3 { renderer.tick(model) }
        assertCollidersFit(renderer.root, "GravityLab")
    }

    func testProjectilesCollidersFit() {
        let model = KinematicsModel()
        let renderer = KinematicsRenderer()
        for _ in 0..<3 { renderer.tick(model) }
        assertCollidersFit(renderer.root, "Projectiles")
    }

    func testMagnetismCollidersFit() {
        let model = MagnetismModel()
        let renderer = MagnetismRenderer()
        for _ in 0..<3 { renderer.tick(model) }
        assertCollidersFit(renderer.root, "Magnetism")
    }

    func testCircuitsCollidersFit() {
        let model = CircuitsModel()
        let renderer = CircuitsRenderer()
        for _ in 0..<3 { renderer.tick(dt: 1 / 90, model: model) }
        assertCollidersFit(renderer.root, "Circuits")
    }

    // MARK: The gallery and the shell

    /// The first surface every user sees, and the one the audit found a
    /// 0.38 m sphere on: exhibits stand 0.36 m apart, so each one's
    /// target reached 2 cm into its neighbour's.
    func testGalleryCollidersFit() {
        let scene = HubScene()
        scene.build(modules: ModuleCatalog.all(appModel: AppModel()))
        assertCollidersFit(scene.root, "Gallery")
    }

    /// The placement puck is the object you move a whole lab with, and
    /// it stands among the lab's own apparatus.
    func testLabPlacementPuckCollidersFit() {
        let puck = LabAnchorView.makeAnchor(accent: .white)
        assertCollidersFit(puck, "LabPlacement")
    }
}
