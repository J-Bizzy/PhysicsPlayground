//
//  GalleryDoorTests.swift
//  PhysicsPlaygroundTests
//
//  THE WAY INTO A LAB, WHICH NOTHING WAS WATCHING FOR MOST OF ITS LIFE.
//
//  This file is the successor to `EnterPlaqueTests`, and it inherits that
//  file's reason for existing. The gallery's door has now been rebuilt
//  four times — a bare tap (cut 2026-07-29), a focus panel's Load button
//  (deleted 2026-08-04), an ENTER plaque on every puck (2026-08-07 to
//  08-09), and now a tap that sends the lab to the pad. Three of those
//  four transitions broke the door, and TWO OF THEM SHIPPED:
//
//  · 2026-08-04 → 08-07, the only way in was a sustained ~1.1 m
//    pinch-drag onto a 0.105 m plate. Nothing failed.
//  · 2026-08-09, a spacing change sank every ENTER plaque into the
//    terrace slab. Still built, still named, still operable, invisible.
//    605 tests stayed green; a screenshot caught it.
//
//  So the assertions here are about the DOOR's behaviour rather than
//  about any object that currently implements it:
//
//  1. A tap on any exhibit puts THAT lab on the pad — all six, by id.
//  2. The pad holds one lab: docking evicts whatever was standing there.
//  3. A tap on the lab already on the pad does not re-fly it.
//  4. A tap during a carry does not fight the hand.
//  5. The exhibit is operable, and operating it enters THAT lab — the
//     VoiceOver route, which deliberately skips the pad entirely.
//

import XCTest
import RealityKit
import RenderKit
@testable import PhysicsPlayground

@MainActor
final class GalleryDoorTests: XCTestCase {

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

    private func builtScene() -> (HubScene, [ModuleDescriptor]) {
        let modules = ModuleCatalog.all(appModel: AppModel())
        let scene = HubScene()
        scene.build(modules: modules)
        return (scene, modules)
    }

    /// The exhibit entity for a module — the thing a pinch actually lands
    /// on, found the way the tap handler finds it rather than by name, so
    /// a rename cannot make this test pass while the door breaks.
    private func exhibit(_ id: String, in scene: HubScene) throws -> Entity {
        try XCTUnwrap(scene.root.children.first { $0.name == id },
                      "no exhibit entity for \(id)")
    }

    // MARK: The tap

    func testTappingAnyExhibitSendsThatLabToThePad() throws {
        let (scene, modules) = builtScene()
        for module in modules {
            let entity = try exhibit(module.id, in: scene)
            let id = try XCTUnwrap(scene.moduleID(for: entity), """
                a pinch on \(module.id)'s exhibit resolves to no module, so \
                the tap handler would return without doing anything. This is \
                the door: it opens for every lab or the gallery has holes.
                """)
            scene.sendToPad(id: id)
            XCTAssertEqual(scene.dockedModuleID, module.id, """
                tapping \(module.id) left \(scene.dockedModuleID ?? "nothing") \
                on the pad. A tap wired to the wrong id sends you to \
                someone else's lab.
                """)
        }
    }

    /// ONE PAD, ONE LAB. The evicted exhibit has to be sent home, or two
    /// miniatures occupy the same 10 cm plate and the Load button names
    /// only one of them.
    func testDockingASecondLabEvictsTheFirst() throws {
        let (scene, modules) = builtScene()
        let first = modules[0].id, second = modules[1].id

        scene.sendToPad(id: first)
        XCTAssertEqual(scene.dockedModuleID, first)

        scene.sendToPad(id: second)
        XCTAssertEqual(scene.dockedModuleID, second, """
            the pad still holds \(scene.dockedModuleID ?? "nothing") after \
            \(second) was sent to it.
            """)
    }

    /// A tap on the lab that is ALREADY there is not a second door. It
    /// used to be impossible to express — you cannot drag something onto
    /// the spot it occupies — and a tap can, so it needs saying: re-flying
    /// an object to where it already is reads as a glitch, and the Load
    /// button is sitting over it waiting for the real pinch.
    func testTappingTheDockedLabIsIgnored() throws {
        let (scene, modules) = builtScene()
        let id = modules[0].id
        scene.sendToPad(id: id)

        let seated = try exhibit(id, in: scene).position
        scene.sendToPad(id: id)

        XCTAssertEqual(scene.dockedModuleID, id, "the pad let go of its lab")
        XCTAssertEqual(try exhibit(id, in: scene).position, seated,
                       "the docked lab moved when it was tapped again")
    }

    /// The hand wins. `sendToPad` fires from a tap recogniser that runs
    /// alongside the drag one, so a carry in progress must not have its
    /// exhibit flown out from under it.
    func testATapDuringACarryIsIgnored() throws {
        let (scene, modules) = builtScene()
        let carried = modules[0].id
        let entity = try exhibit(carried, in: scene)

        XCTAssertTrue(scene.beginExhibitDrag(entity: entity,
                                             world: entity.position(relativeTo: nil)),
                      "the carry did not start, so this test proves nothing")
        scene.sendToPad(id: modules[1].id)

        XCTAssertNil(scene.dockedModuleID, """
            a lab was docked while another was in the hand. The carry's own \
            release decides where its exhibit lands.
            """)
        scene.cancelExhibitDrag()
    }

    // MARK: The VoiceOver route

    /// OPERABLE, AND IT ENTERS. The exhibit is what a VoiceOver sweep
    /// lands on, and it goes straight into the lab rather than through
    /// the pad — the ceremony's whole payload is visual.
    func testActivatingAnExhibitEntersThatLab() throws {
        let (scene, modules) = builtScene()
        var entered: [String] = []
        scene.onEnter = { entered.append($0) }

        for module in modules {
            let entity = try exhibit(module.id, in: scene)
            let action = try XCTUnwrap(
                entity.components[SpatialActionComponent.self],
                "\(module.id)'s exhibit publishes no action, so VoiceOver "
                + "can announce it and not open it")
            action.activate?()
        }

        XCTAssertEqual(entered.sorted(), modules.map(\.id).sorted(), """
            activating the exhibits entered \(entered), not every lab once.
            """)
    }

    func testEveryExhibitIsAimable() throws {
        let (scene, modules) = builtScene()
        for module in modules {
            let entity = try exhibit(module.id, in: scene)
            XCTAssertNotNil(entity.components[InputTargetComponent.self],
                            "\(module.id)'s exhibit cannot be aimed at")
            XCTAssertNotNil(entity.components[CollisionComponent.self],
                            "\(module.id)'s exhibit has no collider to pinch")
        }
    }

    // MARK: Stacked glass

    /// NO TWO TRANSLUCENT DISCS MAY SHARE A PLANE.
    ///
    /// The focus pool under each exhibit is three flat discs of the
    /// module's accent at falling opacity, and all three were built at
    /// the same y — coplanar to the micron. The depth buffer then picks
    /// a winner per pixel per frame, so the pool shimmered whenever the
    /// head moved, worst of all on the pad where a docked lab holds
    /// still and gives the eye time to watch it.
    ///
    /// Reported from a headset, not caught here, because nothing was
    /// asserting it: every disc was the right size, the right colour and
    /// in the right place. Coplanarity is invisible to any test that
    /// checks parts individually, so this one checks them against EACH
    /// OTHER — which is the only way this class of defect is visible.
    ///
    /// SCOPED BY NAME, not by shape. The first version of this looked
    /// for anything flat, wide and translucent anywhere in an exhibit,
    /// and failed on Gravity Lab — whose miniature draws two orbit
    /// TRACKS, rings at different radii sharing the orbital plane and
    /// overlapping nowhere. A rule that cannot tell a ring from a filled
    /// disc reports correct geometry as broken, which is how a criterion
    /// test gets switched off.
    @MainActor
    func testNoTwoDiscsInAFocusPoolShareAPlane() throws {
        let (scene, modules) = builtScene()

        for module in modules {
            let entity = try exhibit(module.id, in: scene)
            let pool = try XCTUnwrap(
                Self.descendants(of: entity) {
                    $0.name == HubScene.focusPoolName
                }.first,
                "\(module.id) has no focus pool — it is what shows which "
                + "exhibit you are facing, so a missing one is a defect too")

            let levels = pool.children.compactMap { child -> Float? in
                guard let model = child as? ModelEntity,
                      model.model?.mesh.bounds != nil else { return nil }
                return child.position.y
            }
            XCTAssertGreaterThan(levels.count, 1,
                                 "\(module.id)'s pool has nothing to stack")

            let sorted = levels.sorted()
            for (lower, upper) in zip(sorted, sorted.dropFirst()) {
                XCTAssertGreaterThan(upper - lower, 0.0002, """
                    \(module.id)'s focus pool draws two discs \(upper - lower) \
                    m apart at y \(lower). They are concentric and they \
                    overlap, so at the same depth the renderer picks a winner \
                    per pixel and the pool flickers as the head moves.
                    """)
            }
        }
    }

    // MARK: The furniture that is gone

    /// THE PAD'S TEACH CARD IS NOT COMING BACK by accident. "Or carry a
    /// lab to the pad" hung at the plate's rim — inside the volume the
    /// carry drag sweeps through, so the sentence describing the gesture
    /// stood in the way of performing it. If a future pass re-adds a
    /// billboarded card there, this catches it.
    func testNothingHangsAtThePadsRim() {
        let (scene, _) = builtScene()
        let pad = scene.podiumTop
        var offenders: [String] = []

        func walk(_ entity: Entity) {
            defer { entity.children.forEach(walk) }
            guard entity.components[InputTargetComponent.self] != nil else { return }
            let at = entity.position(relativeTo: nil)
            // The rim: below the pad's top, within a hand's width of it.
            guard simd_distance(at, pad) < 0.25, at.y < pad.y else { return }
            // The gallery's grab bar lives under the pad ON PURPOSE and
            // is the one thing there a pinch is meant to find.
            guard !HubScene.isGalleryBar(entity) else { return }
            offenders.append(entity.name.isEmpty ? "<unnamed>" : entity.name)
        }
        walk(scene.root)

        XCTAssertTrue(offenders.isEmpty, """
            \(offenders) sit at the pad's rim with a touch target. That is \
            the volume a carry sweeps through on its way in, and anything \
            standing in it intercepts the gesture it is next to.
            """)
    }
}
