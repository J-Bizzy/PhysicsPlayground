//
//  EnterPlaqueTests.swift
//  PhysicsPlaygroundTests
//
//  THE SECOND WAY INTO A LAB, WHICH NOTHING WAS WATCHING.
//
//  Until 2026-08-04 the only way from the gallery into a lab was a ~1.1 m
//  pinch-drag onto a 0.105 m pad. The ENTER plaque is the answer to that
//  — a small machined slab on each puck you can look at and pinch, or
//  activate with VoiceOver — and it is the front door this whole arc is
//  named for.
//
//  It had ZERO tests. On 2026-08-09 a placement change moved it 37 mm
//  down, into the terrace slab it rests on, and EVERY ENTER PLAQUE IN THE
//  GALLERY DISAPPEARED. 605 tests stayed green. It was caught by looking
//  at a screenshot, four pictures into an unrelated change.
//
//  A door with no test is a door that opens until the day it doesn't. So:
//
//  1. Every module has one, by count — not "the gallery has some".
//  2. It is pinchable AND operable, and activating it enters THAT lab.
//  3. IT IS ABOVE THE SURFACE IT STANDS ON. This is the one that would
//     have caught the regression, and it is the one a spacing change can
//     break without touching anything named "enter". Asserted against the
//     terrace the plaque sits on rather than against the number −0.160,
//     because a test that repeats the constant only proves the constant
//     was not edited.
//

import XCTest
import RealityKit
import RenderKit
@testable import PhysicsPlayground

@MainActor
final class EnterPlaqueTests: XCTestCase {

    private func builtScene() -> (HubScene, [ModuleDescriptor]) {
        let modules = ModuleCatalog.all(appModel: AppModel())
        let scene = HubScene()
        scene.build(modules: modules)
        return (scene, modules)
    }

    private func plaques(in scene: HubScene) -> [Entity] {
        var found: [Entity] = []
        func walk(_ entity: Entity) {
            if entity.name.hasPrefix(HubScene.enterPrefix) { found.append(entity) }
            entity.children.forEach(walk)
        }
        walk(scene.root)
        return found
    }

    func testEveryLabHasAnEnterPlaque() {
        let (scene, modules) = builtScene()
        let found = plaques(in: scene)
        XCTAssertEqual(found.count, modules.count, """
            \(found.count) ENTER plaques for \(modules.count) labs. This is \
            the reachable way in; a missing one is a lab you can only get \
            to by dragging it 1.1 m onto a 0.105 m pad.
            """)
        for module in modules {
            XCTAssertTrue(
                found.contains { $0.name == "\(HubScene.enterPrefix)\(module.id)" },
                "\(module.id) has no ENTER plaque")
        }
    }

    /// PINCHABLE AND OPERABLE. The plaque is the accessibility answer to
    /// the drag, so a plaque VoiceOver can find and not use is no answer.
    func testEveryPlaqueIsAimableAndOperable() throws {
        let (scene, _) = builtScene()
        for plaque in plaques(in: scene) {
            let targets = Self.descendants(of: plaque) {
                $0.components[InputTargetComponent.self] != nil
            }
            XCTAssertFalse(targets.isEmpty,
                           "\(plaque.name) cannot be aimed at")
            XCTAssertNotNil(plaque.components[SpatialActionComponent.self],
                            "\(plaque.name) publishes no action")
        }
    }

    func testActivatingAPlaqueEntersThatLab() throws {
        let (scene, modules) = builtScene()
        var entered: [String] = []
        scene.onEnter = { entered.append($0) }

        for module in modules {
            let plaque = try XCTUnwrap(plaques(in: scene).first {
                $0.name == "\(HubScene.enterPrefix)\(module.id)"
            })
            let action = try XCTUnwrap(plaque.components[SpatialActionComponent.self])
            action.activate?()
        }
        XCTAssertEqual(entered.sorted(), modules.map(\.id).sorted(), """
            activating the plaques entered \(entered), not every lab once. \
            A plaque wired to the wrong id sends you into someone else's lab.
            """)
    }

    /// …AND IT IS NOT BURIED IN THE FURNITURE.
    ///
    /// The regression that prompted this file: the plaque moved down into
    /// the terrace it rests on, so it was still built, still named, still
    /// operable, and invisible. Every assertion above would have passed.
    func testEveryPlaqueStandsProudOfItsTerrace() throws {
        let (scene, _) = builtScene()
        for plaque in plaques(in: scene) {
            // ITS TOP, not its bottom. The plaque rests at the terrace's
            // front lip and straddles the slab's top face by about a
            // centimetre — by design, it is a label on the front of a
            // plinth. A first version of this asserted the BOTTOM cleared
            // the slab and failed all six while the screenshot showed
            // them plainly, which is the third time in this session an
            // assertion about a 3-D arrangement measured a relationship
            // that was not the one in the picture.
            //
            // "Stands proud" is the claim, and it is the one the
            // regression broke: sunk 37 mm, the whole plaque was under
            // the slab's top and invisible.
            let plaqueTop = plaque.visualBounds(relativeTo: nil).max.y
            // The terrace slab under this plaque: the nearest ancestor
            // geometry that is not part of the exhibit itself.
            let terraceTop = try XCTUnwrap(
                Self.terraceTop(under: plaque, in: scene),
                "\(plaque.name) has no terrace beneath it to stand on")
            XCTAssertGreaterThan(plaqueTop, terraceTop, """
                \(plaque.name) reaches \(plaqueTop) and the terrace top is \
                \(terraceTop) — no part of the plaque is above the slab it \
                stands on, so it cannot be seen. It is still named, still \
                operable, and still invisible, which is exactly how this \
                shipped once already with 605 tests green.
                """)
        }
    }

    // MARK: Helpers

    private static func descendants(of root: Entity,
                                    where predicate: (Entity) -> Bool) -> [Entity] {
        var found: [Entity] = []
        func walk(_ entity: Entity) {
            if predicate(entity) { found.append(entity) }
            entity.children.forEach(walk)
        }
        walk(root)
        return found
    }

    /// The top of the widest slab whose footprint contains this plaque —
    /// the terrace, without needing to know what it is called.
    private static func terraceTop(under plaque: Entity, in scene: HubScene) -> Float? {
        let at = plaque.position(relativeTo: nil)
        var best: Float?
        func walk(_ entity: Entity) {
            defer { entity.children.forEach(walk) }
            guard let model = entity as? ModelEntity,
                  let mesh = model.model?.mesh else { return }
            let bounds = mesh.bounds.extents
            // A terrace is wide, shallow and long; an exhibit is not.
            guard bounds.x > 0.8, bounds.y < 0.2 else { return }
            let box = model.visualBounds(relativeTo: nil)
            guard at.x >= box.min.x, at.x <= box.max.x,
                  at.z >= box.min.z, at.z <= box.max.z else { return }
            best = max(best ?? -.greatestFiniteMagnitude, box.max.y)
        }
        walk(scene.root)
        return best
    }
}
