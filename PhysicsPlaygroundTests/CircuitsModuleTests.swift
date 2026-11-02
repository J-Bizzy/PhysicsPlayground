//
//  CircuitsModuleTests.swift
//  PhysicsPlaygroundTests
//
//  Circuit Workshop's parts as the Solid Schematic (2026-10-30): the rule
//  that turns a part's face — the plane its symbol is drawn in — toward
//  the wearer, the number that is its only label, the states a part shows
//  on itself (a red LED, a fuse's broken filament, a capacitor's charged
//  plates, an AC bead at its phase, a bulb's warmth, a motor's blur, a
//  switch's blade), and a shelf preview that is the whole module and fits
//  its well.
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

    // MARK: Which way it faces

    /// A part lying along x, either way round, faces the wearer and keeps
    /// its +y to the sky.
    func testAPartLyingDownFacesTheFront() {
        for axis: SIMD3<Float> in [[1, 0, 0], [-1, 0, 0], [-0.999, 0.02, 0.03]] {
            let frame = CircuitsRenderer.moduleOrientation(axis: axis, front: front)
            assertClose(frame.act([1, 0, 0]), simd_normalize(axis), 1e-4, "axis")
            XCTAssertGreaterThan(frame.act([0, 0, 1]).z, 0.99, "\(axis) does not face the front")
            XCTAssertGreaterThan(abs(frame.act([0, 1, 0]).y), 0.99, "\(axis) is rolled")
        }
    }

    /// Anywhere short of pointing at the wearer, a part's face is the
    /// front's direction across its axis.
    func testATiltedPartsFaceIsTheFrontAcrossItsAxis() {
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<200 {
            let axis = simd_normalize(SIMD3<Float>(.random(in: -1...1, using: &generator),
                                                   .random(in: -1...1, using: &generator),
                                                   .random(in: -1...1, using: &generator)))
            let across = front - simd_dot(front, axis) * axis
            guard simd_length(across) >= CircuitsRenderer.faceThreshold else { continue }
            let frame = CircuitsRenderer.moduleOrientation(axis: axis, front: front)
            assertClose(frame.act([1, 0, 0]), axis, 1e-4)
            assertClose(frame.act([0, 0, 1]), simd_normalize(across), 1e-3)
        }
    }

    /// Turning the stage turns every part with it, rigidly.
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

    /// A part standing on end faces the wearer too — its symbol was edge-on
    /// under the lab kit's "top to the front" rule.
    func testAStandingPartFacesTheFront() {
        for axis: SIMD3<Float> in [[0, 1, 0], [0, -1, 0]] {
            let frame = CircuitsRenderer.moduleOrientation(axis: axis, front: front)
            assertClose(frame.act([0, 0, 1]), front, 1e-4)
        }
    }

    /// Pointing nearly at the wearer a hand's wobble must not wheel the part
    /// round its own axis: the frame moves no further than the axis did.
    func testAPartPointingAtTheWearerKeepsItsRollAsItWobbles() {
        var frame = CircuitsRenderer.moduleOrientation(axis: [0, 0, 1], front: front)
        var axis = SIMD3<Float>(0, 0, 1)
        for step in 0..<120 {
            let angle = Float(step) * 0.21
            let next = simd_normalize(SIMD3<Float>(0.12 * cos(angle), 0.12 * sin(angle), 1))
            let moved = acos(min(simd_dot(axis, next), 1))
            let nextFrame = CircuitsRenderer.moduleOrientation(axis: next, front: front, previous: frame)
            assertClose(nextFrame.act([1, 0, 0]), next, 1e-4)
            XCTAssertLessThan(CircuitsRenderer.angle(between: frame, and: nextFrame), moved + 1e-3,
                              "step \(step)")
            frame = nextFrame
            axis = next
        }
    }

    /// The value hangs below a part lying down, clear of the flywheel, and
    /// beside one standing up, where below would be its own lower dot.
    func testTheLabelHangsBelowOrBeside() {
        let lying = CircuitsRenderer.moduleOrientation(axis: [1, 0, 0], front: front)
        assertClose(CircuitsRenderer.labelOffset(for: lying), [0, -0.056, 0])
        let standing = CircuitsRenderer.moduleOrientation(axis: [0, 1, 0], front: front)
        let beside = CircuitsRenderer.labelOffset(for: standing)
        XCTAssertEqual(beside.y, 0, accuracy: 1e-4)
        XCTAssertEqual(beside.z, 0, accuracy: 1e-4, "beside, not in front of it")
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
        // The one authority, so the label and the bead agree: a 50 mA fuse's
        // label read "0.1 A" at one decimal until 2026-11-02.
        XCTAssertEqual(label(.fuse), "1.00 A")
        XCTAssertEqual(label(.fuse, failed: true), "1.00 A", "a blown fuse shows its broken filament")
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

    /// The first material on any mesh under `entity`.
    private func material(of entity: Entity) -> RealityKit.Material? {
        if let first = entity.components[ModelComponent.self]?.materials.first { return first }
        for child in entity.children {
            if let found = material(of: child) { return found }
        }
        return nil
    }

    private func rgb(_ material: RealityKit.Material?) -> (r: CGFloat, g: CGFloat, b: CGFloat)? {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        if let unlit = material as? UnlitMaterial {
            unlit.color.tint.getRed(&r, green: &g, blue: &b, alpha: &a)
        } else if let pbr = material as? PhysicallyBasedMaterial {
            pbr.baseColor.tint.getRed(&r, green: &g, blue: &b, alpha: &a)
        } else {
            return nil
        }
        return (r, g, b)
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
        XCTAssertTrue(material(of: core) is UnlitMaterial, "a forward-biased LED at 15 mA is lit")
        let lit = try XCTUnwrap(rgb(material(of: core)))
        XCTAssertGreaterThan(lit.r, 2 * lit.g, "the LED should glow red")
        XCTAssertGreaterThan(lit.r, 2 * lit.b)

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
        XCTAssertLessThan(try XCTUnwrap(rgb(material(of: dark))).r, 0.2)
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

    /// The capacitor's charge tints its plates — red on the one holding +Q,
    /// blue on the −Q facing it — by |V| against 24 V, deeper as it
    /// charges; the AC bead rides its sine at the source's phase.
    func testTheCapacitorsPlatesTakeTheChargeAndTheBeadRidesThePhase() throws {
        XCTAssertEqual(CircuitsRenderer.gaugeFill(volts: 12), 0.5, accuracy: 1e-12)
        XCTAssertEqual(CircuitsRenderer.gaugeFill(volts: -30), 1)
        XCTAssertEqual(CircuitsRenderer.chargeBucket(volts: 0), 0)
        XCTAssertEqual(CircuitsRenderer.chargeBucket(volts: 12), 3)
        XCTAssertEqual(CircuitsRenderer.chargeBucket(volts: -30), -7)
        assertClose(CircuitsRenderer.beadPosition(phase: 0),
                    [-CircuitsRenderer.acWaveHalfWidth, 0, CircuitsRenderer.acBeadZ], 1e-6)
        let crest = CircuitsRenderer.beadPosition(phase: .pi / 2)
        XCTAssertEqual(crest.y, CircuitsRenderer.acWaveAmplitude, accuracy: 1e-6, "it crests with the EMF")
        XCTAssertLessThan(CircuitsRenderer.beadPosition(phase: 3 * .pi / 2).y, 0)

        let model = CircuitsModel()
        model.loadPreset(.rcCharger)
        let renderer = CircuitsRenderer()
        run(model, renderer, frames: 180)
        let capacitor = try XCTUnwrap(model.components.first { $0.kind == .capacitor })
        let volts = try XCTUnwrap(model.readouts[capacitor.id]?.volts)
        XCTAssertGreaterThan(abs(volts), 0.5, "the capacitor should have charged")
        let plates = try [0, 1].map { try XCTUnwrap(entity(named: "capacitor-plate-\($0)", in: renderer)) }
        let colours = try plates.map { try XCTUnwrap(rgb(material(of: $0))) }
        let positive = volts > 0 ? colours[0] : colours[1]
        let negative = volts > 0 ? colours[1] : colours[0]
        XCTAssertGreaterThan(positive.r, positive.b, "the +Q plate should be red")
        XCTAssertGreaterThan(negative.b, negative.r, "the −Q plate should be blue")
    }

    /// A bulb's filament is the blackbody at its temperature: 2700 K at 3 W,
    /// T ∝ P^¼, warmer and brighter with every step up in power, dark below
    /// the first visible glow.
    func testTheFilamentWarmsWithItsPower() {
        XCTAssertEqual(CircuitsRenderer.filamentTemperature(watts: 3), 2700, accuracy: 1e-9)
        XCTAssertEqual(CircuitsRenderer.filamentTemperature(watts: 3.0 / 16),
                       1350, accuracy: 1e-6, "a sixteenth of the power is half the temperature")
        XCTAssertLessThanOrEqual(CircuitsRenderer.filamentTemperature(watts: 1000), 3200)
        XCTAssertEqual(CircuitsRenderer.filamentStep(watts: 0), -1)
        XCTAssertEqual(CircuitsRenderer.filamentStep(watts: 0.01), -1, "648 K does not glow")
        var lastStep = -1, lastBrightness = 0.0, lastBlueOverRed = 0.0
        for watts in stride(from: 0.05, through: 8, by: 0.05) {
            let step = CircuitsRenderer.filamentStep(watts: watts)
            XCTAssertGreaterThanOrEqual(step, lastStep, "\(watts) W")
            if step > lastStep, step >= 0 {
                let look = CircuitsRenderer.filamentLooks[step]
                XCTAssertGreaterThan(look.brightness, lastBrightness)
                XCTAssertGreaterThanOrEqual(look.colour.z / look.colour.x, lastBlueOverRed,
                                            "hotter is whiter")
                lastBrightness = look.brightness
                lastBlueOverRed = look.colour.z / look.colour.x
            }
            lastStep = step
        }
        let reference = CircuitsRenderer.filamentLooks[CircuitsRenderer.filamentStep(watts: 3)]
        XCTAssertEqual(reference.brightness, 1, accuracy: 0.15, "3 W is the reference filament")
        XCTAssertGreaterThan(reference.colour.x, reference.colour.z, "2700 K is warm")
    }

    /// The motor's one marker is drawn turning only while it passes fewer
    /// than 20 times a second — under half of 90 Hz, so the turn seen is the
    /// true one; faster, the marker is the smear the eye would see.
    func testTheMotorBlursWhereItWouldAlias() {
        let threshold = CircuitsRenderer.rotorBlurTurnsPerSecond
        XCTAssertLessThan(threshold, 45, "a one-marker turn above 45/s aliases at 90 Hz")
        XCTAssertFalse(CircuitsRenderer.rotorBlurred(motorSpeed: 2 * .pi * (threshold - 0.5)))
        XCTAssertTrue(CircuitsRenderer.rotorBlurred(motorSpeed: -2 * .pi * (threshold + 0.5)))
        // The default motor at 9 V turns 8.6 times a second: drawn turning.
        let k = CircuitsModel.motorTorqueConstant, b = CircuitsModel.motorFriction
        XCTAssertFalse(CircuitsRenderer.rotorBlurred(motorSpeed: k * 9 / (b * 8 + k * k)))
    }

    /// The switch's blade lies along the line closed and lifts to the
    /// symbol's 30° open, turning about the pivot.
    func testTheBladeShowsTheSwitch() throws {
        let model = CircuitsModel()
        model.clearBench()
        let id = try XCTUnwrap(model.add(.switcher, at: [0, 1.3, -0.85]))
        let renderer = CircuitsRenderer()
        run(model, renderer, frames: 2)
        let blade = try XCTUnwrap(entity(named: "k-\(id.uuidString)", in: renderer))
        XCTAssertEqual(blade.orientation.angle, 0, accuracy: 1e-4)
        model.toggleSwitch(id: id)
        run(model, renderer, frames: 60)
        XCTAssertEqual(blade.orientation.angle, CircuitsRenderer.switchOpenAngle, accuracy: 1e-3)
        XCTAssertGreaterThan(blade.orientation.act([1, 0, 0]).y, 0, "it lifts its free end")
    }

    /// Thrown closed, the drawn blade falls and reaches the contact on the
    /// frame the model closes the circuit — never sooner, never later — and
    /// its bounce never lifts it out of the contact.
    func testTheBladeLandsAsTheCircuitCloses() throws {
        let model = CircuitsModel()
        model.clearBench()
        let id = try XCTUnwrap(model.add(.switcher, at: [0, 1.3, -0.85]))
        let renderer = CircuitsRenderer()
        model.toggleSwitch(id: id)
        run(model, renderer, frames: 60)
        let blade = try XCTUnwrap(entity(named: "k-\(id.uuidString)", in: renderer))
        XCTAssertEqual(blade.orientation.angle, CircuitsRenderer.switchOpenAngle, accuracy: 1e-3)

        model.toggleSwitch(id: id)
        var landed = false
        var lastAngle = blade.orientation.angle
        for _ in 0..<40 {
            run(model, renderer, frames: 1)
            let closed = model.components.first { $0.id == id }!.isClosed
            let angle = blade.orientation.angle
            if !closed {
                XCTAssertGreaterThan(angle, 0, "drawn on the contact before the circuit closed")
                XCTAssertLessThanOrEqual(angle, lastAngle + 1e-5, "a falling blade only falls")
            } else {
                if !landed {
                    XCTAssertLessThanOrEqual(angle, CircuitsRenderer.bladeBounceLimit + 1e-4,
                                             "the circuit closed with the blade still in the air")
                    landed = true
                }
                XCTAssertLessThanOrEqual(angle, CircuitsRenderer.bladeBounceLimit + 1e-4,
                                         "the bounce left the contact")
            }
            lastAngle = angle
        }
        XCTAssertTrue(landed)
    }

    // MARK: The shelf

    /// A shelf preview is the whole module — element, leads and dots — and
    /// fits its well's mouth.
    func testEveryPreviewIsTheWholeModuleAndFitsItsWell() {
        let mouth = CircuitsPartsLayout.mouthHalfExtents
        for kind in CircuitsModel.ComponentKind.allCases {
            let preview = CircuitsRenderer.partPreview(for: kind)
            let half = preview.visualBounds(relativeTo: nil).extents / 2
            XCTAssertLessThanOrEqual(half.x, mouth.x, "\(kind) is wider than its well")
            XCTAssertLessThanOrEqual(half.y, mouth.y, "\(kind) is taller than its well")
            XCTAssertLessThanOrEqual(half.z, mouth.z, "\(kind) is deeper than its well")
            // The dots are in it: it spans dot to dot.
            let span = 2 * Float(CircuitsModel.terminalOffset) * CircuitsRenderer.shelfPreviewScale
            XCTAssertGreaterThan(2 * half.x, span, "\(kind)'s preview has no contacts")
        }
    }
}
