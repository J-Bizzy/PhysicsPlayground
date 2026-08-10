//
//  FadeTests.swift
//  PhysicsPlaygroundTests
//
//  `Fade.tick` never faded anything, and shipped that way.
//
//  Reported from the device 2026-08-09: turn on a vector arrow in
//  Pendulums and it appears; turn it off and it stays on screen, frozen
//  at the instant it was switched off. Both halves of that are the same
//  bug, and the "on" half is the one that explains why nobody caught it.
//
//  ── THE DEFECT ──
//
//  `tick` measures its own frame spacing from a `Clock` component it
//  keeps on the entity. It WRITES that clock every call — and then
//  removes it again whenever the ramp lands on 0 or 1. The first call
//  has no clock, so `dt` is 0, so the ramp does not move, so it lands on
//  the endpoint it started from, so the clock is removed. The next call
//  is a first call again. A settled entity can never begin a transition.
//
//  ── WHY IT LOOKED LIKE IT WORKED ──
//
//  Because `PendulumsRenderer.Arrow.update` sets `holder.isEnabled =
//  true` itself, and the renderer calls it whenever the layer is on. So
//  switching a vector ON enables the arrow directly and Fade's failure
//  is invisible. Switching it OFF stops calling `update`, and the only
//  thing left to hide the arrow is the mechanism that has never worked.
//
//  The blast radius is bigger than the bug report: thirteen call sites,
//  including every selection halo in the app (Circuits, Electric Fields,
//  Magnetism) and Gravity Lab's vector arrows.
//
//  ── WHAT THESE ASSERT ──
//
//  Not "the ramp is smooth" — that is a judgement for the device. Just
//  that a transition STARTS and that it FINISHES, which is the whole of
//  what a caller is promised and neither of which held.
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

    /// One tick toward hidden has to CHANGE something.
    ///
    /// It need not have arrived — 0.15 s is several frames — but after
    /// being told to hide, an entity that is still enabled with no
    /// opacity component is in exactly the state it started in, and the
    /// next call will be identical. That is the deadlock.
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

    /// The other direction, which the Pendulums arrows were hiding.
    ///
    /// `Arrow.update` enables its own holder, so showing appeared to
    /// work in that module no matter what `Fade` did. A selection halo
    /// has no such helper: if this fails, halos never appear at all.
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
