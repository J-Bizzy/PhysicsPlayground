//
//  SpatialActionCriterionTests.swift
//  PhysicsPlaygroundTests
//
//  ANNOUNCED, READABLE, AND IMPOSSIBLE TO OPERATE.
//
//  `grep -rn "systemActions\|AccessibilityEvents"` returned ZERO matches
//  across this project. Twenty files set `isAccessibilityElement` and
//  populate `label` and `value` — so every plate, petal, disc, rail,
//  well and grip in six labs was spoken correctly and could not be
//  pressed. And because `makeControls` and the six `*ControlsPanel`
//  files were deleted on 2026-08-01, `ARCHITECTURE.md` states there is
//  no fallback surface: for a VoiceOver user this app was six rooms of
//  readouts with no controls in them at all.
//
//  It happened the way every defect in this arc happened — not by a
//  decision, but because nothing asked. Each primitive was written on a
//  different day and each author set the two properties they could see
//  in the autocomplete.
//
//  THE CRITERION, and why it is this one. The tempting test is "every
//  primitive declares `systemActions`", which is a listing test wearing
//  a criterion's clothes: it passes the moment somebody writes
//  `systemActions = []`. This asserts the thing that actually matters —
//  **an entity that is hit-testable and announces itself must be
//  operable without hands** — over every entity in a built scene. An
//  entity carrying `InputTargetComponent` and an accessibility label is
//  by definition a control somebody can aim at; if it cannot also be
//  activated or adjusted, it is a control only some people have.
//

import XCTest
import RealityKit
import RenderKit
@testable import PhysicsPlayground

@MainActor
final class SpatialActionCriterionTests: XCTestCase {

    private struct Unreachable {
        let path: String
        let label: String
    }

    /// Walks a built scene for controls a hand can reach and VoiceOver
    /// cannot.
    private func unreachable(under root: Entity, label: String) -> [Unreachable] {
        var found: [Unreachable] = []

        func walk(_ entity: Entity, path: String) {
            let accessibility = entity.components[AccessibilityComponent.self]
            let isTargetable = entity.components[InputTargetComponent.self] != nil
            if isTargetable, let accessibility, accessibility.isAccessibilityElement {
                let action = entity.components[SpatialActionComponent.self]
                let operable = action?.activate != nil || action?.adjust != nil
                if !operable {
                    found.append(Unreachable(
                        path: path,
                        label: accessibility.label.map(String.init(localized:)) ?? "—"))
                }
            }
            for child in entity.children {
                walk(child, path: "\(path)/\(child.name.isEmpty ? "·" : child.name)")
            }
        }

        walk(root, path: label)
        return found
    }

    private func assertOperable(_ root: Entity, _ label: String,
                                file: StaticString = #filePath, line: UInt = #line) {
        let found = unreachable(under: root, label: label)
        guard !found.isEmpty else { return }
        let report = found.map { "  \($0.path) — spoken as \"\($0.label)\"" }
            .joined(separator: "\n")
        XCTFail("""
            \(found.count) control(s) in \(label) can be pinched but not \
            operated without hands. Attach `SpatialActions.attach` (or a \
            `SpatialActionComponent`) so VoiceOver's Activate reaches the same \
            code the tap does:
            \(report)
            """, file: file, line: line)
    }

    /// The criterion has to be able to fail, or every green run below
    /// means nothing.
    func testTheCriterionCatchesAControlItCannotOperate() {
        let plate = ModelEntity(mesh: .generateBox(size: [0.05, 0.05, 0.01]),
                                materials: [UnlitMaterial(color: .white)])
        plate.name = "mute-plate"
        plate.components.set(InputTargetComponent())
        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = "Field lines"
        plate.components.set(accessibility)

        XCTAssertEqual(unreachable(under: plate, label: "fixture").count, 1)
    }

    /// …and must accept one that is wired.
    func testTheCriterionAcceptsAnOperableControl() {
        let plate = ModelEntity(mesh: .generateBox(size: [0.05, 0.05, 0.01]),
                                materials: [UnlitMaterial(color: .white)])
        plate.components.set(InputTargetComponent())
        SpatialActions.attach(to: plate, label: "Field lines", value: "showing",
                              activate: {})
        XCTAssertTrue(unreachable(under: plate, label: "fixture").isEmpty)
    }

    // MARK: The primitives

    func testLayerBankPlatesCanBeOperatedWithoutHands() {
        var flipped: [String] = []
        let bank = SpatialLayerBank(accent: .white, layers: [
            LayerSwitch(id: "lines", label: "Field lines", isOn: { true },
                        toggle: { flipped.append("lines") }),
            LayerSwitch(id: "grid", label: "Grid", isOn: { false },
                        toggle: { flipped.append("grid") }),
        ])
        for _ in 0..<40 { bank.update(anchor: .zero, viewer: [0, 0, 1], dt: 1 / 90) }
        assertOperable(bank.root, "SpatialLayerBank")

        // And the action must reach the SAME closure a tap does.
        let plate = try? XCTUnwrap(bank.root.children.first { $0.name == "layer-grid" })
        XCTAssertTrue(SpatialActions.activate(plate ?? Entity()))
        XCTAssertEqual(flipped, ["grid"])
    }

    func testActionBankPlatesCanBeOperatedWithoutHands() {
        var fired = 0
        let bank = SpatialActionBank(accent: .white, actions: [
            .init(id: "reset", label: "Reset", symbol: "arrow.counterclockwise",
                  fire: { fired += 1 }),
        ])
        for _ in 0..<40 {
            bank.update(anchor: .zero, viewer: [0, 0, 1], dt: 1 / 90, resetNonce: 0)
        }
        assertOperable(bank.root, "SpatialActionBank")
    }

    /// A DESTRUCTIVE plate must still confirm. Routing VoiceOver
    /// straight at `fire` would hand the one user who cannot see the
    /// plate light up a single-tap way to wipe a bench.
    func testADestructivePlateStillConfirmsForVoiceOver() throws {
        var fired = 0
        let bank = SpatialActionBank(accent: .white, actions: [
            .init(id: "clear", label: "Clear", symbol: "trash",
                  confirms: true, fire: { fired += 1 }),
        ])
        for _ in 0..<40 {
            bank.update(anchor: .zero, viewer: [0, 0, 1], dt: 1 / 90, resetNonce: 0)
        }
        let plate = try XCTUnwrap(bank.root.children.first {
            $0.components[SpatialActionComponent.self] != nil
        })

        XCTAssertTrue(SpatialActions.activate(plate))
        XCTAssertEqual(fired, 0, "one activation fired a destructive verb")
        XCTAssertTrue(SpatialActions.activate(plate))
        XCTAssertEqual(fired, 1, "the second activation should confirm it")
    }

    func testSummonHandleCanBeOperatedWithoutHands() {
        let handle = SummonHandle(title: "Analysis", symbol: "chart.xyaxis.line",
                                  accent: .white)
        handle.summary = { "off" }
        for _ in 0..<40 {
            handle.update(anchor: .zero, viewer: [0, 0, 1], dt: 1 / 90)
        }
        assertOperable(handle.root, "SummonHandle")
    }
}
