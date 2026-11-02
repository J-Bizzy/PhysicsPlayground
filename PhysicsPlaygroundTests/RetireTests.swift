//
//  RetireTests.swift
//  PhysicsPlaygroundTests
//
//  Nothing pops while its neighbours fade (2026-11-02): an object the
//  model has dropped fades out of the room rather than vanishing in a
//  frame, and while it does nothing can take hold of it or find it by
//  name. A pooled slot leaves a fading copy and carries on.
//

import XCTest
import RealityKit
import RenderKit
@testable import PhysicsPlayground

@MainActor
final class RetireTests: XCTestCase {

    private func grabbable(named name: String) -> ModelEntity {
        let entity = ModelEntity(mesh: Primitives.box(size: [0.1, 0.1, 0.1], cornerRadius: 0),
                                 materials: [])
        entity.name = name
        entity.components.set(InputTargetComponent())
        entity.components.set(CollisionComponent(shapes: [Primitives.collisionBox(size: [0.1, 0.1, 0.1])]))
        return entity
    }

    /// Retired, it takes no hand and answers to no name at once, fades,
    /// and is gone once the fade is over.
    func testARetiredObjectFadesAndGoes() async throws {
        let room = Entity()
        let magnet = grabbable(named: "magnet")
        let pole = Entity()
        pole.name = "north"
        magnet.addChild(pole)
        room.addChild(magnet)

        Retire.entity(magnet)
        XCTAssertNil(room.findEntity(named: "magnet"), "still answers to its name")
        XCTAssertNil(room.findEntity(named: "north"), "a part of it still answers to its name")
        XCTAssertNil(magnet.components[InputTargetComponent.self], "a hand could still take it")
        XCTAssertNil(magnet.components[CollisionComponent.self])
        XCTAssertNotNil(magnet.components[OpacityComponent.self], "it should be fading")
        XCTAssertTrue(magnet.parent === room, "it vanished in one frame")

        try await Task.sleep(for: .seconds(Retire.duration + 0.15))
        XCTAssertNil(magnet.parent, "it should have gone once faded")
    }

    /// A pool's slot is handed straight on: a copy fades where it stood,
    /// and the slot itself is untouched.
    func testAPooledSlotLeavesAFadingCopy() {
        let room = Entity()
        let slot = grabbable(named: "ball")
        room.addChild(slot)

        Retire.copy(of: slot)
        XCTAssertEqual(room.children.count, 2)
        XCTAssertTrue(room.children.contains { $0.name == "ball" + Retire.suffix })
        XCTAssertNotNil(slot.components[InputTargetComponent.self], "the slot itself was disarmed")
        XCTAssertEqual(slot.name, "ball")

        slot.isEnabled = false
        Retire.copy(of: slot)
        XCTAssertEqual(room.children.count, 2, "a slot not drawn leaves nothing to fade")
    }

    /// The Time Capsule's plates fade with the tape. With `recedes` off the
    /// bank leaves its owner's fade alone, where the recession (no hand
    /// near: full strength) wiped it, and the plates popped.
    func testABankThatDoesNotRecedeKeepsItsOwnersFade() {
        let bank = SpatialActionBank(
            accent: .white,
            actions: [SpatialAction(id: "back", label: "Back a frame",
                                    symbol: "backward.frame.fill") {}])
        bank.recedes = false
        bank.root.components.set(OpacityComponent(opacity: 0.4))
        for _ in 0..<5 { bank.update(anchor: .zero, viewer: [0, 0, 1], dt: 1.0 / 90.0) }
        XCTAssertEqual(bank.root.components[OpacityComponent.self]?.opacity ?? 1, 0.4,
                       accuracy: 1e-6)
    }
}
