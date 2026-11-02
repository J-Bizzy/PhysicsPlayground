//
//  GraspTests.swift
//  PhysicsPlaygroundTests
//
//  Every grab answers (2026-11-02): the objects that took a hand in
//  silence — a part fresh off the shelf, a hoop, a plate, the stage, a
//  lead pulled from nothing — now glow and tick as everything else does,
//  and the ring, the halo and the card name one part.
//

import XCTest
import RealityKit
import RenderKit
@testable import PhysicsPlayground

@MainActor
final class GraspTests: XCTestCase {

    // MARK: Carried by name

    /// A well's object has no entity until its renderer next draws: the
    /// carry waits for it by name, glows it once found, and lets go when
    /// the hand does.
    func testACarriedObjectGlowsOnceItIsDrawnAndLetsGoAfter() {
        let root = Entity()
        let carried = Grasp.Carried()
        carried.carry("hoop", fromWell: true)
        carried.find(under: root)

        // Something with bounds: the aura is sized from them.
        let hoop = ModelEntity(mesh: Primitives.box(size: [0.1, 0.1, 0.1], cornerRadius: 0),
                               materials: [])
        hoop.name = "hoop"
        root.addChild(hoop)
        carried.find(under: root)
        XCTAssertTrue(LiveGlow.isLive(hoop), "found, and wearing the glow")

        carried.carry(nil)
        XCTAssertFalse(LiveGlow.isLive(hoop), "let go, and the glow leaves")
    }

    // MARK: Circuits

    /// The stage says yes and no aloud: a tick as a hand takes the rim of
    /// a circuit, a thud for an empty stage there is nothing on to turn.
    func testTheStageAnswersAHandEitherWay() {
        let model = CircuitsModel()
        let rim = SIMD3(model.stage.center.x + 0.4, model.stage.top, model.stage.center.y)
        XCTAssertTrue(model.beginSpin(hand: rim, at: 0))
        XCTAssertEqual(model.soundEvent?.kind, .grabTick)
        model.endSpin(coasts: false, at: 0.1)
        XCTAssertEqual(model.soundEvent?.kind, .releaseTick)

        model.clearBench()
        XCTAssertFalse(model.beginSpin(hand: rim, at: 1))
        XCTAssertEqual(model.soundEvent?.kind, .thud, "an empty stage refused in silence")
    }

    /// A lead pulled fresh from a terminal ticks, as lifting an existing
    /// wire's end always did.
    func testAFreshLeadPullTicks() throws {
        let model = CircuitsModel()
        let battery = try XCTUnwrap(model.components.first { $0.kind == .battery })
        let lead = CircuitsModel.Terminal(componentID: battery.id, end: 0)
        model.beginLeadPull(from: lead, hand: battery.terminalPosition(0) + SIMD3(0, 0.05, 0))
        XCTAssertEqual(model.soundEvent?.kind, .grabTick)
    }

    /// Deleting the selected part selects nothing: the halo and the card
    /// used to jump to whichever part had been added last.
    func testDeletingTheSelectedPartSelectsNothing() throws {
        let model = CircuitsModel()
        let bulb = try XCTUnwrap(model.components.first { $0.kind == .bulb })
        model.select(id: bulb.id)
        model.removeComponent(id: bulb.id)
        XCTAssertNil(model.selectedID)
    }

    /// While a part's ring is open its card stands aside, up and to the
    /// viewer's left, where the petals no longer land on it; folded, it
    /// comes back over the part.
    func testTheCardStandsAsideWhileTheRingIsOpen() throws {
        let model = CircuitsModel()
        let renderer = CircuitsRenderer()
        let card = Entity()
        renderer.selectedAnchor.addChild(card)
        let battery = try XCTUnwrap(model.components.first { $0.kind == .battery })
        model.select(id: battery.id)

        renderer.ringPartID = battery.id
        for _ in 0..<90 { renderer.tick(dt: 1 / 90, model: model) }
        XCTAssertLessThan(simd_distance(card.position, CircuitsRenderer.readoutAside), 1e-3)

        renderer.ringPartID = nil
        for _ in 0..<90 { renderer.tick(dt: 1 / 90, model: model) }
        XCTAssertLessThan(simd_length(card.position), 1e-3)
    }
}
