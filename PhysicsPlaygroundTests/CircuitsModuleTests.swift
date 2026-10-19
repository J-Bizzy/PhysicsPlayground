//
//  CircuitsModuleTests.swift
//  PhysicsPlaygroundTests
//
//  Circuit Workshop's parts as lab-kit modules (2026-10-18): the rule that
//  turns a part upright, the number that is its only label, the states a
//  part shows on itself (a red LED, a fuse's broken filament, a capacitor's
//  gauge, an AC dial's needle), and a shelf preview that is the whole
//  module and fits its well.
//

import XCTest
import RealityKit
import simd
@testable import PhysicsPlayground

@MainActor
final class CircuitsModuleTests: XCTestCase {

    private let front = SIMD3<Float>(0, 0, 1)

    private func assertClose(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ accuracy: Float = 1e-4,
                             _ message: String = "", line: UInt = #line) {
        XCTAssertLessThan(simd_distance(a, b), accuracy, "\(a) vs \(b) \(message)", line: line)
    }

    // MARK: Which way up

    /// A part lies along its axis with its carrier's top to the sky, either
    /// way round: one turned end-for-end shows its back chamfer rather than
    /// hanging upside down, which the shortest-arc rotation did to a part
    /// swung near −X.
    func testAPartLaidEitherWayRoundSitsUpright() {
        for axis: SIMD3<Float> in [[1, 0, 0], [-1, 0, 0], [-0.999, 0.02, 0.03], [0, 0, 1], [0, 0, -1]] {
            let frame = CircuitsRenderer.moduleOrientation(axis: axis, front: front)
            assertClose(frame.act([1, 0, 0]), simd_normalize(axis), 1e-4, "axis")
            XCTAssertGreaterThan(frame.act([0, 1, 0]).y, 0.99, "\(axis) is not upright")
        }
        let reversed = CircuitsRenderer.moduleOrientation(axis: [-1, 0, 0], front: front)
        assertClose(reversed.act([0, 0, 1]), [0, 0, -1], 1e-4, "the back chamfer faces the front")
    }

    /// Tilted anywhere short of the near-vertical cone, a part's top is the
    /// sky's direction across its axis: upright, never rolled.
    func testATiltedPartsTopIsAsHighAsItCanBe() {
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<200 {
            let axis = simd_normalize(SIMD3<Float>(.random(in: -1...1, using: &generator),
                                                   .random(in: -1...1, using: &generator),
                                                   .random(in: -1...1, using: &generator)))
            let up = SIMD3<Float>(0, 1, 0)
            let across = up - simd_dot(up, axis) * axis
            guard simd_length(across) >= CircuitsRenderer.uprightThreshold else { continue }
            let frame = CircuitsRenderer.moduleOrientation(axis: axis, front: front)
            assertClose(frame.act([1, 0, 0]), axis, 1e-4)
            assertClose(frame.act([0, 1, 0]), simd_normalize(across), 1e-3)
        }
    }

    /// Turning the stage turns every part with it, rigidly: the rule gives
    /// the turned part the turned frame, standing parts included.
    func testTheFrameTurnsWithTheStage() {
        let yaw: Float = 1.1
        let turn = simd_quatf(angle: yaw, axis: [0, 1, 0])
        let turnedFront = CircuitsRenderer.stageFront(yaw: Double(yaw))
        assertClose(turnedFront, turn.act(front), 1e-5)
        for axis: SIMD3<Float> in [[1, 0, 0], [0.3, 0.6, -0.2], [-0.5, -0.4, 0.7], [0, 1, 0]] {
            let before = CircuitsRenderer.moduleOrientation(axis: axis, front: front)
            let after = CircuitsRenderer.moduleOrientation(axis: turn.act(axis), front: turnedFront)
            XCTAssertLessThan(CircuitsRenderer.angle(between: after, and: turn * before), 1e-3,
                              "\(axis)")
        }
    }

    /// A part made standing on end turns its top to the stage's front.
    func testAStandingPartFacesTheFront() {
        for axis: SIMD3<Float> in [[0, 1, 0], [0, -1, 0]] {
            let frame = CircuitsRenderer.moduleOrientation(axis: axis, front: front)
            assertClose(frame.act([0, 1, 0]), front, 1e-4)
        }
    }

    /// Near vertical a hand's wobble must not wheel the part round its own
    /// axis: the frame moves no further than the axis did.
    func testANearlyStandingPartKeepsItsRollAsItWobbles() {
        var frame = CircuitsRenderer.moduleOrientation(axis: [0, 1, 0], front: front)
        var axis = SIMD3<Float>(0, 1, 0)
        for step in 0..<120 {
            let angle = Float(step) * 0.21
            let next = simd_normalize(SIMD3<Float>(0.12 * cos(angle), 1, 0.12 * sin(angle)))
            let moved = acos(min(simd_dot(axis, next), 1))
            let nextFrame = CircuitsRenderer.moduleOrientation(axis: next, front: front, previous: frame)
            assertClose(nextFrame.act([1, 0, 0]), next, 1e-4)
            XCTAssertLessThan(CircuitsRenderer.angle(between: frame, and: nextFrame), moved + 1e-3,
                              "step \(step)")
            frame = nextFrame
            axis = next
        }
    }

    /// The value hangs below a part lying down and beside one standing up,
    /// where below would be its own lower contact.
    func testTheLabelHangsBelowOrBeside() {
        let lying = CircuitsRenderer.moduleOrientation(axis: [1, 0, 0], front: front)
        assertClose(CircuitsRenderer.labelOffset(for: lying), [0, -0.050, 0])
        let standing = CircuitsRenderer.moduleOrientation(axis: [0, 1, 0], front: front)
        let beside = CircuitsRenderer.labelOffset(for: standing)
        XCTAssertEqual(beside.y, 0, accuracy: 1e-4)
        XCTAssertEqual(simd_length(beside), 0.060, accuracy: 1e-4)
    }

    // MARK: The label is the number

    func testTheLabelIsANumberOrNothing() {
        func label(_ kind: CircuitsModel.ComponentKind, failed: Bool = false,
                   closed: Bool = true) -> String {
            var component = CircuitsModel.Component(id: UUID(), kind: kind, position: .zero,
                                                    value: kind.defaultValue)
            component.failed = failed
            component.isClosed = closed
            return CircuitsRenderer.labelText(for: component)
        }
        XCTAssertEqual(label(.switcher), "")
        XCTAssertEqual(label(.switcher, closed: false), "")
        XCTAssertEqual(label(.led), "")
        XCTAssertEqual(label(.led, failed: true), "")
        XCTAssertEqual(label(.fuse), "1.0 A")
        XCTAssertEqual(label(.fuse, failed: true), "1.0 A", "a blown fuse shows its broken filament")
        XCTAssertEqual(label(.resistor, failed: true), label(.resistor),
                       "a scorched resistor shows its black ceramic")
        XCTAssertFalse(label(.acSource).contains("~"), "the dial carries the ~")
        for kind in CircuitsModel.ComponentKind.allCases {
            for text in [label(kind), label(kind, failed: true)] where !text.isEmpty {
                XCTAssertNotNil(text.rangeOfCharacter(from: .decimalDigits), "\(kind): \(text)")
                for word in ["open", "closed", "blown", "scorched", "burned", "LED", "fuse"] {
                    XCTAssertFalse(text.contains(word), "\(kind): \(text)")
                }
            }
        }
    }

    // MARK: States the part shows

    private func entity(named name: String, in renderer: CircuitsRenderer) -> Entity? {
        renderer.root.findEntity(named: name)
    }

    private func run(_ model: CircuitsModel, _ renderer: CircuitsRenderer, frames: Int) {
        for _ in 0..<frames {
            model.step(dt: 1 / 90)
            renderer.tick(dt: 1 / 90, model: model)
        }
    }

    /// 9 V through 470 Ω lights an LED red — 625 nm, a red LED's colour, not
    /// the bulb's yellow it used to borrow — and too much current leaves its
    /// die dark.
    func testAnLEDLightsRedAndBurnsOutDark() throws {
        let model = CircuitsModel()
        model.clearBench()
        let battery = try XCTUnwrap(model.add(.battery, at: [-0.35, 1.3, -0.85]))
        let resistor = try XCTUnwrap(model.add(.resistor, at: [0, 1.48, -0.85]))
        let led = try XCTUnwrap(model.add(.led, at: [0.35, 1.3, -0.85]))
        model.setComponentValue(id: resistor, 470)
        _ = model.connectTerminals(.init(componentID: battery, end: 0), .init(componentID: resistor, end: 0))
        _ = model.connectTerminals(.init(componentID: resistor, end: 1), .init(componentID: led, end: 0))
        _ = model.connectTerminals(.init(componentID: led, end: 1), .init(componentID: battery, end: 1))
        let renderer = CircuitsRenderer()
        run(model, renderer, frames: 4)

        let core = try XCTUnwrap(entity(named: "led-core", in: renderer))
        XCTAssertTrue(core.isEnabled, "a forward-biased LED at 15 mA is lit")
        let skin = try XCTUnwrap(core.children.first as? ModelEntity)
        let lit = try XCTUnwrap(skin.model?.materials.first as? UnlitMaterial)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        lit.color.tint.getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertGreaterThan(r, 2 * g, "the LED should glow red")
        XCTAssertGreaterThan(r, 2 * b)

        // Straight across the battery: far past 30 mA, and it burns out.
        model.clearBench()
        let cell = try XCTUnwrap(model.add(.battery, at: [-0.35, 1.3, -0.85]))
        let doomed = try XCTUnwrap(model.add(.led, at: [0.35, 1.3, -0.85]))
        _ = model.connectTerminals(.init(componentID: cell, end: 0), .init(componentID: doomed, end: 0))
        _ = model.connectTerminals(.init(componentID: doomed, end: 1), .init(componentID: cell, end: 1))
        run(model, renderer, frames: 4)
        XCTAssertTrue(model.components.first { $0.id == doomed }?.failed == true)
        let dark = try XCTUnwrap(entity(named: "led-core", in: renderer))
        XCTAssertTrue(dark.isEnabled, "a burned-out LED shows its dark die")
        let soot = try XCTUnwrap((dark.children.first as? ModelEntity)?.model?.materials.first
                                 as? UnlitMaterial)
        soot.color.tint.getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertLessThan(r, 0.2)
    }

    /// A fuse that blows loses the middle of its filament — the only sign
    /// of it on the bench, since its label is only ever its rating.
    func testABlownFuseLosesItsFilamentsMiddle() throws {
        let model = CircuitsModel()
        model.clearBench()
        let battery = try XCTUnwrap(model.add(.battery, at: [-0.35, 1.3, -0.85]))
        let fuse = try XCTUnwrap(model.add(.fuse, at: [0.35, 1.3, -0.85]))
        let renderer = CircuitsRenderer()
        run(model, renderer, frames: 2)
        XCTAssertTrue(try XCTUnwrap(entity(named: "fuse-bridge", in: renderer)).isEnabled)

        _ = model.connectTerminals(.init(componentID: battery, end: 0), .init(componentID: fuse, end: 0))
        _ = model.connectTerminals(.init(componentID: fuse, end: 1), .init(componentID: battery, end: 1))
        run(model, renderer, frames: 4)
        XCTAssertTrue(model.components.first { $0.id == fuse }?.failed == true)
        XCTAssertFalse(try XCTUnwrap(entity(named: "fuse-bridge", in: renderer)).isEnabled)
    }

    /// The capacitor's gauge reads |V| against 24 V, and fills as it
    /// charges; the AC dial's needle swings ±60° with the EMF.
    func testTheGaugeFillsAndTheNeedleSwings() throws {
        XCTAssertEqual(CircuitsRenderer.gaugeFill(volts: 12), 0.5, accuracy: 1e-12)
        XCTAssertEqual(CircuitsRenderer.gaugeFill(volts: -30), 1)
        XCTAssertEqual(CircuitsRenderer.needleAngle(phase: .pi / 2), .pi / 3, accuracy: 1e-6)
        XCTAssertEqual(CircuitsRenderer.needleAngle(phase: 0), 0, accuracy: 1e-6)

        let model = CircuitsModel()
        model.loadPreset(.rcCharger)
        let renderer = CircuitsRenderer()
        run(model, renderer, frames: 2)
        let gauge = try XCTUnwrap(entity(named: "capacitor-gauge", in: renderer))
        let early = gauge.isEnabled ? gauge.scale.x : 0
        run(model, renderer, frames: 180)
        XCTAssertTrue(gauge.isEnabled)
        XCTAssertGreaterThan(gauge.scale.x, early, "the gauge should fill as the capacitor charges")
        XCTAssertLessThanOrEqual(gauge.scale.x, CircuitsRenderer.gaugeLength + 1e-6)
    }

    // MARK: The shelf

    /// A shelf preview is the whole module — carrier and contacts — and fits
    /// its well's mouth.
    func testEveryPreviewIsTheWholeModuleAndFitsItsWell() {
        let mouth = CircuitsPartsLayout.mouthHalfExtents
        for kind in CircuitsModel.ComponentKind.allCases {
            let preview = CircuitsRenderer.partPreview(for: kind)
            let half = preview.visualBounds(relativeTo: nil).extents / 2
            XCTAssertLessThanOrEqual(half.x, mouth.x, "\(kind) is wider than its well")
            XCTAssertLessThanOrEqual(half.y, mouth.y, "\(kind) is taller than its well")
            XCTAssertLessThanOrEqual(half.z, mouth.z, "\(kind) is deeper than its well")
            // The contacts are in it: it spans contact to contact.
            let span = 2 * Float(CircuitsModel.terminalOffset) * CircuitsRenderer.shelfPreviewScale
            XCTAssertGreaterThan(2 * half.x, span, "\(kind)'s preview has no contacts")
        }
    }
}
