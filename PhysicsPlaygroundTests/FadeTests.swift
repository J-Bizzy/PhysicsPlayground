//
//  FadeTests.swift
//  PhysicsPlaygroundTests
//
//  `Fade.tick` measures its own frame spacing from a clock component it
//  keeps on the entity, and it once removed that clock whenever the ramp
//  landed — so a settled entity could never begin a transition. These
//  assert that a transition starts and that it finishes, which is the
//  whole of what a caller is promised.
//

import XCTest
import RealityKit
import UIKit
import RenderKit

@MainActor
final class FadeTests: XCTestCase {

    /// A settled, fully-visible entity — what a caller hands to `tick`
    /// on the frame it decides to hide something.
    private func settledVisibleEntity() -> Entity {
        let entity = Entity()
        entity.isEnabled = true
        entity.components.remove(OpacityComponent.self)
        return entity
    }

    private func isSettledVisible(_ entity: Entity) -> Bool {
        entity.isEnabled && entity.components[OpacityComponent.self] == nil
    }

    override func setUp() async throws {
        try XCTSkipIf(UIAccessibility.isReduceMotionEnabled,
                      "Reduce Motion snaps instead of ramping; these test the ramp")
    }

    /// One tick toward hidden has to change something: an entity still
    /// enabled with no opacity component is in the state it started in, and
    /// the next call would be identical.
    func testHidingASettledEntityStartsTheRamp() {
        let entity = settledVisibleEntity()
        Fade.tick(entity, visible: false)
        XCTAssertFalse(isSettledVisible(entity), """
            after one tick toward hidden, the entity is still fully visible \
            with no opacity component — bit for bit the state it was in \
            before the call.

            Nothing distinguishes the next call from this one, so the ramp \
            never starts and the entity never disappears. This is the \
            Pendulums arrow that will not switch off.
            """)
    }

    /// And it has to finish.
    func testAHiddenEntityEventuallyDisappears() {
        let entity = settledVisibleEntity()
        // Well past `Fade.duration` (0.15 s), at a plausible frame rate.
        for _ in 0..<40 {
            Fade.tick(entity, visible: false)
            Thread.sleep(forTimeInterval: 1.0 / 90.0)
        }
        XCTAssertFalse(entity.isEnabled, """
            still enabled after ~0.44 s of ticking toward hidden, against a \
            \(Fade.duration) s ramp.
            """)
    }

    /// The other direction. A selection halo has no helper enabling it, so
    /// if this fails halos never appear at all.
    func testShowingAHiddenEntityStartsTheRamp() {
        let entity = Entity()
        entity.isEnabled = false
        Fade.tick(entity, visible: true)
        XCTAssertFalse(!entity.isEnabled && entity.components[OpacityComponent.self] == nil, """
            after one tick toward shown, the entity is still disabled with no \
            opacity component — the state it started in.

            Nothing in the app enables a selection halo except this call, so \
            a halo in this state never appears.
            """)
    }

    func testAShownEntityEventuallyArrivesFullyOpaque() {
        let entity = Entity()
        entity.isEnabled = false
        for _ in 0..<40 {
            Fade.tick(entity, visible: true)
            Thread.sleep(forTimeInterval: 1.0 / 90.0)
        }
        XCTAssertTrue(entity.isEnabled, "never became enabled")
        XCTAssertNil(entity.components[OpacityComponent.self], """
            arrived, but kept an OpacityComponent. `tick`'s own contract is \
            that a settled entity drops it so it renders on the fast path.
            """)
    }

    /// Already-correct states must stay free.
    func testTickingAnAlreadySettledEntityIsANoOp() {
        let visible = settledVisibleEntity()
        Fade.tick(visible, visible: true)
        XCTAssertTrue(isSettledVisible(visible),
                      "a settled visible entity was disturbed by being told to stay")

        let hidden = Entity()
        hidden.isEnabled = false
        Fade.tick(hidden, visible: false)
        XCTAssertFalse(hidden.isEnabled)
        XCTAssertNil(hidden.components[OpacityComponent.self])
    }
}
