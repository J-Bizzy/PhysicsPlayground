//
//  PortalDoorTests.swift
//  PhysicsPlaygroundTests
//
//  The way into a lab: a pinch on a portal. The old door (carry an
//  exhibit to a pad, then press Load) was rebuilt four times; this one has
//  one step, so these assert that one step and the opening in front of it:
//  every portal enters its own lab, every portal is aimable, the opening
//  can always be skipped, and a walk back from a lab does not replay it.
//

import XCTest
import RealityKit
import RenderKit
@testable import PhysicsPlayground

@MainActor
final class PortalDoorTests: XCTestCase {

    private func builtScene(openingPlayed: Bool = true) -> (HubScene, [ModuleDescriptor]) {
        let modules = ModuleCatalog.all(appModel: AppModel())
        let scene = HubScene()
        scene.openingAlreadyPlayed = openingPlayed
        scene.build(modules: modules)
        return (scene, modules)
    }

    // MARK: The door

    /// Six portals, one per lab, in the catalog's arc order.
    func testThereIsOnePortalPerLabInArcOrder() {
        let (scene, modules) = builtScene()
        XCTAssertEqual(scene.portalIDs.count, modules.count)
        XCTAssertEqual(scene.portalIDs, HubDomain.arcOrder)
    }

    /// Operable, and it enters: the VoiceOver route and the pinch route
    /// meet in `onEnter`.
    func testActivatingAPortalEntersThatLab() throws {
        let (scene, modules) = builtScene()
        var entered: [String] = []
        scene.onEnter = { entered.append($0) }
        for module in modules {
            let portal = try XCTUnwrap(scene.portal(module.id))
            let action = try XCTUnwrap(portal.components[SpatialActionComponent.self],
                                       "\(module.id)'s portal publishes no action")
            action.activate?()
        }
        XCTAssertEqual(entered.sorted(), modules.map(\.id).sorted())
    }

    /// A tap anywhere on a portal — its rim, its preview, its name —
    /// resolves to that portal's lab.
    func testATapOnAnyPartOfAPortalFindsItsLab() throws {
        let (scene, modules) = builtScene()
        for module in modules {
            let portal = try XCTUnwrap(scene.portal(module.id))
            XCTAssertEqual(scene.moduleID(for: portal), module.id)
            for child in portal.children {
                XCTAssertEqual(scene.moduleID(for: child), module.id,
                               "a part of \(module.id)'s portal does not lead into it")
            }
        }
    }

    func testEveryPortalIsAimable() throws {
        let (scene, modules) = builtScene()
        for module in modules {
            let portal = try XCTUnwrap(scene.portal(module.id))
            XCTAssertNotNil(portal.components[InputTargetComponent.self])
            XCTAssertNotNil(portal.components[CollisionComponent.self])
            XCTAssertNotNil(portal.components[HoverEffectComponent.self],
                            "a portal must answer the eyes before the pinch")
        }
    }

    // MARK: The opening

    /// A first arrival plays the opening, and any pinch skips it: the
    /// shield that catches the pinch goes with it, and the particles too.
    func testAnyPinchSkipsTheOpening() throws {
        let (scene, _) = builtScene(openingPlayed: false)
        XCTAssertTrue(scene.isOpening)
        let shield = try XCTUnwrap(scene.root.children.first {
            $0.name == HubScene.skipShieldName })
        XCTAssertNil(scene.moduleID(for: shield),
                     "a pinch on the shield must skip, never enter a lab")

        var played = false
        scene.onOpeningPlayed = { played = true }
        scene.skipOpening()
        XCTAssertFalse(scene.isOpening)
        XCTAssertTrue(played, "a skipped opening must still count as seen")
        XCTAssertFalse(scene.root.children.contains { $0.name == HubScene.skipShieldName },
                       "the shield outlived the opening and would eat every pinch")
    }

    /// Walking back from a lab is not an arrival.
    func testAWalkBackDoesNotReplayTheOpening() {
        let (scene, _) = builtScene(openingPlayed: true)
        XCTAssertFalse(scene.isOpening)
        XCTAssertFalse(scene.root.children.contains { $0.name == HubScene.skipShieldName })
    }

    /// The opening runs to its end on its own and leaves nothing behind.
    func testTheOpeningEndsOnItsOwn() {
        let (scene, _) = builtScene(openingPlayed: false)
        var played = false
        scene.onOpeningPlayed = { played = true }
        var elapsed = 0.0
        while elapsed < Opening.duration + 0.5 {
            scene.animate(dt: 1.0 / 90.0)
            elapsed += 1.0 / 90.0
        }
        XCTAssertFalse(scene.isOpening)
        XCTAssertTrue(played)
        XCTAssertFalse(scene.root.children.contains { $0.name == HubScene.skipShieldName })
    }

    /// Entering is refused while the opening plays — the pinch skips it
    /// first — and allowed after.
    func testEnteringWaitsForTheOpening() {
        let (scene, _) = builtScene(openingPlayed: false)
        XCTAssertFalse(scene.beginEnterTransition(id: "circuits"))
        scene.skipOpening()
        XCTAssertTrue(scene.beginEnterTransition(id: "circuits"))
    }
}
