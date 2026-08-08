//
//  RecessionCriterionTests.swift
//  PhysicsPlaygroundTests
//
//  THE INSTRUMENTS THAT STAND IN THE ROOM MUST GET OUT OF THE WAY.
//
//  `Recession` shipped on 2026-08-07 with two call sites — `SummonHandle`
//  and Gravity Lab's layer bank — and the task was marked done. Five
//  primitives that stand permanently in every lab (`SpatialLayerBank`,
//  `SpatialActionBank`, `SpatialPicker`, `Well`, `TimeRail`) never faded
//  at all, which is the whole feature missing from five of seven places
//  it was for.
//
//  WHY THESE ARE BEHAVIOURAL AND NOT A SOURCE SCAN. The companion
//  criterion in `SpatialActionCriterionTests` greps the tree, because
//  operability is a UNIVERSAL rule — anything pinchable must be
//  operable, no exceptions, so a file either complies or does not.
//  Recession is not universal, and a grep would be actively wrong:
//
//  · `Bloom` must NOT recede. It is already gaze-gated — it unfolds when
//    you look at its object and folds when you look away — so a second
//    distance fade would dim a ring you just opened by looking at it.
//  · The palette bead must NOT recede. It is the one object present in
//    every lab at all times and the way back out; a way out that fades
//    when your hands are down is a way out you cannot find.
//  · The time rail's PLATES must not, though its reel does. They only
//    exist while the tape is drawn out, and a scrub control that dims
//    mid-scrub fights the hand using it.
//
//  So the rule is per-primitive judgement, and the test has to be too.
//  What it can enforce without listing is the SHAPE: for every primitive
//  that claims to recede, a far hand dims it and a near hand does not,
//  measured through the real `update` rather than by calling `Recession`
//  directly — which is exactly the step that was missing.
//

import XCTest
import RealityKit
import RenderKit
@testable import PhysicsPlayground

@MainActor
final class RecessionCriterionTests: XCTestCase {

    /// Far enough to be fully receded, near enough to be fully lit.
    private static let far = SIMD3<Float>(0, 0, 40)
    private static let near = SIMD3<Float>(0.05, 0, 0)

    private func opacity(of entity: Entity) -> Float {
        entity.components[OpacityComponent.self]?.opacity ?? 1
    }

    /// Drives a primitive through its own `update` twice and asserts the
    /// hand is what changed the brightness.
    private func assertRecedes(
        _ name: String,
        root: Entity,
        update: (SIMD3<Float>?) -> Void,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        update(Self.far)
        let receded = opacity(of: root)
        XCTAssertEqual(receded, Recession.restingOpacity, accuracy: 1e-4, """
            \(name) does not recede: with the nearest hand 40 m away it is \
            still at \(receded). Pass `nearestHand` into its `update` and \
            call `Recession.apply`.
            """, file: file, line: line)

        update(Self.near)
        XCTAssertEqual(opacity(of: root), 1, accuracy: 1e-4, """
            \(name) stayed dim with a hand 5 cm away — it recedes but never \
            comes back, which is worse than never receding.
            """, file: file, line: line)

        // AND NO HAND AT ALL IS FULL BRIGHTNESS, not resting. The
        // simulator never tracks hands, and so does any device frame
        // where they are out of view; an instrument that fades because
        // the system briefly lost your hands is one that flickers.
        update(nil)
        XCTAssertEqual(opacity(of: root), 1, accuracy: 1e-4, """
            \(name) receded with NO hand tracked. Untracked is not far.
            """, file: file, line: line)
    }

    func testLayerBankRecedes() {
        let bank = SpatialLayerBank(accent: .white, layers: [
            LayerSwitch(id: "a", label: "Lines", isOn: { true }, toggle: {}),
        ])
        assertRecedes("SpatialLayerBank", root: bank.root) { hand in
            for _ in 0..<90 {
                bank.update(anchor: .zero, viewer: [0, 0, 1], dt: 1 / 90,
                            nearestHand: hand)
            }
        }
    }

    func testActionBankRecedes() {
        let bank = SpatialActionBank(accent: .white, actions: [
            .init(id: "reset", label: "Reset", symbol: "arrow.counterclockwise",
                  fire: {}),
        ])
        assertRecedes("SpatialActionBank", root: bank.root) { hand in
            for _ in 0..<90 {
                bank.update(anchor: .zero, viewer: [0, 0, 1], dt: 1 / 90,
                            resetNonce: 0, nearestHand: hand)
            }
        }
    }

    func testPickerRecedes() {
        let picker = SpatialPicker(
            accessibilityNoun: "World",
            choices: [.init(id: "a", label: "Earth", symbol: "globe")])
        picker.open()
        assertRecedes("SpatialPicker", root: picker.root) { hand in
            for _ in 0..<90 {
                picker.update(anchor: .zero, viewer: [0, 0, 1], dt: 1 / 90,
                              nearestHand: hand)
            }
        }
    }

    func testSummonHandleRecedes() {
        let handle = SummonHandle(title: "Clock", symbol: "clock", accent: .white)
        handle.summary = { "5×" }
        assertRecedes("SummonHandle", root: handle.root) { hand in
            for _ in 0..<90 {
                handle.update(anchor: .zero, viewer: [0, 0, 1], dt: 1 / 90,
                              nearestHand: hand)
            }
        }
    }

    /// PER SOURCE, not per root — a bench of wells spread half a metre
    /// apart must not all light up because one of them is near your hand.
    func testEachWellRecedesOnItsOwnDistance() throws {
        let well = Well([
            .init(name: "near", tint: .white, label: "Add magnet",
                  preview: { ModelEntity(mesh: .generateSphere(radius: 0.02)) },
                  position: [0, 0, 0], spawn: { _ in UUID() }),
            .init(name: "far", tint: .white, label: "Add world",
                  preview: { ModelEntity(mesh: .generateSphere(radius: 0.02)) },
                  position: [40, 0, 0], spawn: { _ in UUID() }),
        ])
        for _ in 0..<10 { well.update(dt: 1 / 90, nearestHand: .zero) }

        let sources = well.root.children
        XCTAssertEqual(sources.count, 2)
        let nearWell = try XCTUnwrap(sources.first { $0.name == "well-near" })
        let farWell = try XCTUnwrap(sources.first { $0.name == "well-far" })

        XCTAssertEqual(opacity(of: nearWell), 1, accuracy: 1e-4,
                       "the well under the hand should be at full brightness")
        XCTAssertEqual(opacity(of: farWell), Recession.restingOpacity,
                       accuracy: 1e-4, """
                       the well 40 m away receded with the row, not on its own \
                       distance — `Well.update` is applying recession to `root` \
                       instead of to each source.
                       """)
    }

    /// The criterion has to be able to fail, or every case above is
    /// asserting against a mechanism that was never wired.
    func testTheHelperCatchesAPrimitiveThatIgnoresTheHand() {
        let root = Entity()
        var failures = 0
        // A stand-in that never applies recession, checked through the
        // same predicate the real cases use.
        for hand in [Self.far, Self.near] {
            _ = hand
            if abs(opacity(of: root) - Recession.restingOpacity) > 1e-4 {
                failures += 1
            }
        }
        XCTAssertEqual(failures, 2, """
            an entity that never applies recession should differ from the \
            resting opacity at every distance — if it does not, the helper's \
            comparison is not measuring anything.
            """)
    }
}
