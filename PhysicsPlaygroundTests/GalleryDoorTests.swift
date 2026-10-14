//
//  GalleryDoorTests.swift
//  PhysicsPlaygroundTests
//
//  The way into a lab. The door has been rebuilt four times and two of
//  those rebuilds shipped broken with every test green, so these assert
//  the door's behaviour rather than any object that implements it: a
//  tap on any exhibit puts that lab on the pad; the pad holds one lab; a
//  tap on the docked lab does not re-fly it; a tap during a carry does
//  not fight the hand; and operating an exhibit enters that lab (the
//  VoiceOver route, which skips the pad).
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

    /// The exhibit entity for a module, found the way the tap handler finds
    /// it rather than by name.
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

    /// One pad, one lab. The evicted exhibit has to be sent home, or two
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

    /// A tap on the lab already on the pad is not a second door: re-flying
    /// an object to where it already is reads as a glitch.
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

    /// Operable, and it enters. The exhibit is what a VoiceOver sweep
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

    /// No two translucent discs may share a plane: the focus pool's three
    /// discs were built coplanar and shimmered as the depth buffer picked a
    /// winner per pixel. Checked against each other, and scoped by name,
    /// because Orbital Mechanics' miniature draws two orbit rings that share a
    /// plane and overlap nowhere.
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

    /// The pad's teach card is not coming back by accident: it hung inside
    /// the volume the carry drag sweeps through.
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
            // The gallery's grab bar lives under the pad on purpose and
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
