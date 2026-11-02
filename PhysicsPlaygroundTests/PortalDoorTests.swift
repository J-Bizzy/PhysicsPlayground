//
//  PortalDoorTests.swift
//  PhysicsPlaygroundTests
//
//  The way into a lab: a pinch on a portal. The old door (carry an
//  exhibit to a pad, then press Load) was rebuilt four times; this one has
//  one step, so these assert that one step and the arrival in front of it:
//  every portal enters its own lab, every portal is aimable — even while
//  the labs are still rising — and a walk back from a lab does not replay
//  the arrival.
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

    // MARK: The arrival

    /// A first arrival brings the labs up with nothing else in the room:
    /// no star, no night, no wall that eats a pinch (the opening's, until
    /// 2026-10-21).
    func testTheArrivalBringsOnlyTheLabs() {
        let (scene, _) = builtScene(openingPlayed: false)
        XCTAssertTrue(scene.isOpening)
        for name in ["opening", "opening-night", "opening-skip"] {
            XCTAssertNil(scene.root.findEntity(named: name), "\(name) is back")
        }
    }

    /// Walking back from a lab is not an arrival.
    func testAWalkBackDoesNotReplayTheArrival() {
        let (scene, _) = builtScene(openingPlayed: true)
        XCTAssertFalse(scene.isOpening)
    }

    /// The arrival runs to its end on its own, counts as seen, and leaves
    /// every lab exactly in its place at its size.
    func testTheArrivalEndsOnItsOwnWithEveryLabInPlace() throws {
        let (scene, _) = builtScene(openingPlayed: false)
        var played = false
        scene.onOpeningPlayed = { played = true }
        var elapsed = 0.0
        // The clean frames that settle the scene, then the arrival.
        while elapsed < 0.2 + Opening.duration + 0.5 {
            scene.animate(dt: 1.0 / 90.0)
            elapsed += 1.0 / 90.0
        }
        XCTAssertFalse(scene.isOpening)
        XCTAssertTrue(played)
        for id in scene.portalIDs {
            let anchor = try XCTUnwrap(scene.portal(id))
            XCTAssertNil(anchor.components[OpacityComponent.self], "\(id) is still fading")
            let body = try XCTUnwrap(anchor.findEntity(named: "portal-body"))
            XCTAssertEqual(body.scale, .one, "\(id) is not at its size")
            XCTAssertLessThan(abs(body.position.y), 0.005, "\(id) is not in its place")
        }
    }

    /// While they arrive the labs start low and small, the leftmost ahead.
    func testTheLabsRiseIntoPlace() throws {
        let (scene, _) = builtScene(openingPlayed: false)
        // Settled, then a few frames in.
        for _ in 0..<(Settle.cleanFrames + 12) { scene.animate(dt: 1.0 / 90.0) }
        let first = try XCTUnwrap(scene.portal(scene.portalIDs[0])?.findEntity(named: "portal-body"))
        let last = try XCTUnwrap(scene.portal(scene.portalIDs[6])?.findEntity(named: "portal-body"))
        XCTAssertLessThan(first.position.y, -0.005, "the first lab is not rising")
        XCTAssertLessThan(first.scale.x, 1)
        XCTAssertLessThan(last.position.y, first.position.y, "the last lab is ahead of the first")
    }

    /// A pinch on a lab enters it at once, even while the labs are rising.
    func testEnteringNeverWaits() {
        let (scene, _) = builtScene(openingPlayed: false)
        XCTAssertTrue(scene.isOpening)
        XCTAssertTrue(scene.beginEnterTransition(id: "circuits"))
    }

    /// Entering, the chosen lab stays while the rest of the home fades: it
    /// is what the wearer looks at while its lab settles out of sight, and
    /// the room is never empty between them. Then, told to leave, the home
    /// goes in one cross-fade.
    func testTheChosenPortalStaysWhileTheRestFades() throws {
        let (scene, _) = builtScene(openingPlayed: true)
        // Settled, and faded fully in (a walk back's fade is τ 0.18 s).
        for _ in 0..<(Settle.cleanFrames + 120) { scene.animate(dt: 1.0 / 90.0) }
        XCTAssertTrue(scene.beginEnterTransition(id: "circuits"))
        for _ in 0..<90 { scene.animate(dt: 1.0 / 90.0) }

        let chosen = try XCTUnwrap(scene.portal("circuits"))
        let other = try XCTUnwrap(scene.portal("optics"))
        XCTAssertEqual(chosen.components[OpacityComponent.self]?.opacity ?? 1, 1,
                       "the chosen lab faded with the rest")
        XCTAssertLessThan(other.components[OpacityComponent.self]?.opacity ?? 1, 0.02)
        XCTAssertEqual(scene.root.components[OpacityComponent.self]?.opacity ?? 1, 1,
                       "the home is still there, holding the door")

        scene.leaving = true
        for _ in 0..<Int((AppModel.departure * 90).rounded(.up)) + 1 {
            scene.animate(dt: 1.0 / 90.0)
        }
        XCTAssertEqual(scene.root.components[OpacityComponent.self]?.opacity ?? 1, 0,
                       accuracy: 1e-6, "gone within the cross-fade")
    }

    /// One door at a time: a second pinch while the first portal swells
    /// enters nothing, where it once entered a second lab straight after.
    func testASecondPinchMidSwellEntersNothing() {
        let (scene, _) = builtScene(openingPlayed: true)
        XCTAssertTrue(scene.beginEnterTransition(id: "circuits"))
        XCTAssertFalse(scene.beginEnterTransition(id: "optics"))
        XCTAssertFalse(scene.beginEnterTransition(id: "circuits"))
        XCTAssertEqual(scene.enteringID, "circuits")
    }
}
