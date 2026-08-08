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
    /// Colliders skipped because their entity was folded away when the
    /// scene was measured. Reported, never silently dropped.
    private var unmeasured: [String] = []

    private func violations(under root: Entity, label: String) -> [Violation] {
        var found: [Violation] = []
        unmeasured = []

        func walk(_ entity: Entity, path: String) {
            if let collision = entity.components[CollisionComponent.self] {
                // IN WORLD METRES, not in the entity's own frame.
                //
                // Shielding is a property of the room, and the two
                // differ wherever an entity is scaled — which is exactly
                // where the pooled objects live. Gravity Lab's bodies
                // and Projectiles' balls carry ONE authored collider on
                // a sphere whose scale is set per instance, from 0.26×
                // for a comet to 2×+ for a star. Measured locally, a
                // single factor looks identical at every size; measured
                // in the room, the same factor is 2 mm of reach on the
                // comet and 10 cm of shielding on the star. The flat
                // 30 mm allowance only means anything in metres.
                let worldScale = entity.scale(relativeTo: nil)
                let visual = entity.visualBounds(relativeTo: entity)
                let visualExtents = visual.extents * worldScale

                // A FOLDED INSTRUMENT IS NOT MEASURABLE, AND SAYING SO
                // OUT LOUD IS THE POINT.
                //
                // The flat 30 mm allowance is in metres, so at a world
                // scale of 0.001 — which is exactly what
                // `FanLayout.placement` and `Bloom.layoutPetals` write
                // for a closed fan — it becomes a local allowance of
                // 30 m and the check passes whatever the collider is.
                // Every scene below is deliberately ticked open before
                // it is measured, so nothing currently hides here; this
                // records the hole rather than leaving a future caller
                // to measure a folded scene and read the silence as a
                // pass.
                if simd_reduce_min(worldScale) < 0.05 {
                    unmeasured.append(path)
                    for child in entity.children {
                        let name = child.name.isEmpty ? "·" : child.name
                        walk(child, path: "\(path)/\(name)")
                    }
                    return
                }
                // An entity with no mesh anywhere beneath it has nothing
                // to be measured against. That is its own smell, but it
                // is not this test's smell — a pure trigger volume is a
                // legitimate thing to build.
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

    /// THE QUESTION THE RULE IS ACTUALLY ABOUT: does this collider
    /// shield the thing next to it?
    ///
    /// Everything above measures a collider against its OWN entity, and
    /// that has a blind spot which is not theoretical — it shipped.
    /// `Grabbable.configureTouchTarget(_:matchingVisualBoundsOf:)`
    /// derives a box from an entity's visual bounds, so a test that
    /// measures that box against those same bounds passes by
    /// construction, whatever the bounds happen to contain. The gallery
    /// exhibit measured `pulser`, which contains the focus glow — a
    /// 0.40 m pool of light on the puck — and produced a 0.43 m target
    /// against a 0.36 m pitch: WIDER than the 0.19 m sphere it replaced,
    /// with every self-measuring assertion green.
    ///
    /// Six exhibits in a row, 0.36 m apart, is the one place in the app
    /// where identical grabbables stand at a known pitch, so it is the
    /// one place this can be asked directly. Overlap here means the
    /// exhibit you get is decided by hit order rather than by aim.
    func testGalleryExhibitTargetsDoNotOverlapEachOther() {
        let scene = HubScene()
        scene.build(modules: ModuleCatalog.all(appModel: AppModel()))

        // Every per-exhibit target in the gallery, as a world-space box:
        // the six exhibits AND the six ENTER plaques, which are new
        // objects at the same 0.36 m pitch and so are subject to exactly
        // the same question.
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
            for child in exhibit.children
            where child.name.hasPrefix(HubScene.enterPrefix) {
                collect(child, label: child.name)
            }
        }

        XCTAssertEqual(targets.count, 12,
                       "expected six exhibits and six ENTER plaques with targets; "
                       + "found \(targets.count) — if the gallery changed shape "
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

    /// THE PALETTE'S PETAL ROW, at every count it could plausibly reach.
    ///
    /// This is the clock-bank defect's other home. The row's width was a
    /// literal 0.22 m carrying a comment that it had been "widened from
    /// 0.17 when the fourth petal arrived" — hand-tuned for a count, in
    /// a list that grows. At 0.22 m a fifth petal pitches at 0.055 m and
    /// a sixth at 0.044 m, against a 0.068 m touch target: both
    /// unaimable, both looking perfectly reasonable in a screenshot.
    /// Two petals were added on 2026-08-07.
    func testThePetalRowFitsEveryCountItCouldReach() {
        for count in 2...10 {
            let span = Palette.petalRowSpan(count: count)
            let pitch = span / Float(count - 1)
            XCTAssertGreaterThan(
                pitch, Palette.petalColliderSpan,
                String(format: "%d petals pitch at %.4f m against a %.3f m touch "
                       + "target — adjacent petals cannot be told apart by a "
                       + "pinch.", count, pitch, Palette.petalColliderSpan))
        }
    }

    /// …and the row must stay reachable. A petal you have to walk to is
    /// not on a bead you are holding.
    func testThePetalRowStaysWithinArmsReach() {
        XCTAssertLessThan(Palette.petalRowSpan(count: 6), 0.60,
                          "six petals need a row wider than a comfortable "
                          + "two-handed sweep")
    }

    /// The placement puck is the object you move a whole lab with, and
    /// it stands among the lab's own apparatus.
    func testLabPlacementPuckCollidersFit() {
        let puck = LabAnchorView.makeAnchor(accent: .white)
        assertCollidersFit(puck, "LabPlacement")
    }
}
