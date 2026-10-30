//
//  CircuitPropTests.swift
//  Physics Playground — app tests
//
//  The ten circuit parts milled by `Tools/circuitparts.py` as the Solid
//  Schematic (2026-10-30): every asset the bench asks for exists, lies along
//  X inside the element clamp with its live pieces as named children, and
//  every number the renderer shares with the script is the script's own
//  literal — read from the script, so the two cannot drift.
//  Blender (x, y, z) → RealityKit (x, z, −y).
//

import XCTest
import RealityKit
import simd
@testable import PhysicsPlayground

@MainActor
final class CircuitPropTests: XCTestCase {

    private func bounds(of name: String) throws -> BoundingBox {
        let loaded = try XCTUnwrap(try? Entity.load(named: name),
                                   "\(name).usdz is not in the bundle — run "
                                   + "Tools/circuitparts.py")
        let box = loaded.visualBounds(relativeTo: nil)
        XCTAssertGreaterThan(min(box.extents.x, min(box.extents.y, box.extents.z)), 0,
                             "\(name) has no thickness on some axis")
        return box
    }

    /// Every vertex of an asset, in the asset's frame.
    private func vertices(of name: String) throws -> [SIMD3<Float>] {
        let loaded = try XCTUnwrap(try? Entity.load(named: name))
        var points: [SIMD3<Float>] = []
        func walk(_ entity: Entity) {
            if let mesh = entity.components[ModelComponent.self]?.mesh {
                let toRoot = entity.transformMatrix(relativeTo: loaded)
                for instance in mesh.contents.instances {
                    guard let model = mesh.contents.models[instance.model] else { continue }
                    let transform = toRoot * instance.transform
                    for part in model.parts {
                        for local in part.positions.elements {
                            let p = transform * SIMD4(local, 1)
                            points.append(SIMD3(p.x, p.y, p.z))
                        }
                    }
                }
            }
            entity.children.forEach(walk)
        }
        walk(loaded)
        return points
    }

    // MARK: The script's literals

    /// `Tools/circuitparts.py`, read as text: its top-level literals are the
    /// contract's asset side.
    private func script() throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("Tools/circuitparts.py"), encoding: .utf8)
    }

    private func literal(_ name: String, in text: String) throws -> Double {
        let pattern = "\n\(name) = (-?[0-9.]+)"
        let range = try XCTUnwrap(text.range(of: pattern, options: .regularExpression), "\(name)")
        let line = String(text[range])
        return try XCTUnwrap(Double(line.split(separator: "=").last!.trimmingCharacters(in: .whitespaces)))
    }

    func testTheRendererSharesTheScriptsNumbers() throws {
        let text = try script()
        XCTAssertEqual(try literal("TERMINAL_OFFSET", in: text), CircuitsModel.terminalOffset)
        XCTAssertEqual(try literal("DOT_RADIUS", in: text), Double(CircuitsRenderer.contactRadius), accuracy: 1e-7)
        XCTAssertEqual(try literal("WIRE_CORE", in: text), Double(CircuitsRenderer.wireCoreRadius), accuracy: 1e-7)
        XCTAssertEqual(try literal("WIRE_JACKET", in: text), Double(CircuitsRenderer.wireJacketRadius),
                       accuracy: 1e-7)
        XCTAssertEqual(try literal("ELEMENT_CLAMP", in: text), Double(CircuitsRenderer.elementClamp),
                       accuracy: 1e-7)
        XCTAssertEqual(try literal("SWITCH_PIVOT_X", in: text), Double(CircuitsRenderer.switchPivot.x),
                       accuracy: 1e-7)
        XCTAssertEqual(try literal("SWITCH_OPEN_DEGREES", in: text),
                       Double(CircuitsRenderer.switchOpenAngle) * 180 / .pi, accuracy: 1e-4)
        XCTAssertEqual(try literal("MOTOR_INERTIA", in: text), CircuitsModel.motorInertia, accuracy: 1e-9,
                       "the flywheel milled is the inertia the model turns")
        // The element clamp is the carry box's: just inside a dot's target.
        XCTAssertEqual(CircuitsRenderer.elementClamp,
                       Float(CircuitsModel.terminalOffset) - CircuitsRenderer.terminalTargetRadius - 0.002,
                       accuracy: 1e-6)
        // Each lead's inner end, as LEAD_INNER lists it.
        for kind in CircuitsModel.ComponentKind.allCases {
            let ends = try XCTUnwrap(CircuitsRenderer.leadInner[kind], "\(kind)")
            let pattern = "\"\(kind.rawValue)\": \\((-?[0-9.]+), (-?[0-9.]+)\\)"
            let range = try XCTUnwrap(text.range(of: pattern, options: .regularExpression),
                                      "LEAD_INNER has no \(kind)")
            let numbers = String(text[range]).split(separator: "(").last!.dropLast()
                .split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            XCTAssertEqual(numbers.count, 2)
            XCTAssertEqual(numbers[0], Double(ends.x), accuracy: 1e-7, "\(kind)")
            XCTAssertEqual(numbers[1], Double(ends.y), accuracy: 1e-7, "\(kind)")
        }
    }

    // MARK: The assets

    /// Every part's element, the resistor's caps, the dot and the electron.
    /// A missing file falls back to a procedural body, which is the right
    /// behaviour and completely silent.
    func testEveryAssetTheBenchAsksForExists() throws {
        for name in CircuitsRenderer.bodyAssetNames.values.sorted()
            + [CircuitsRenderer.resistorCapsAssetName, CircuitsRenderer.dotAssetName,
               CircuitsRenderer.electronAssetName] {
            _ = try bounds(of: name)
        }
        XCTAssertNil(try? Entity.load(named: "CircuitCarrier"), "the carrier is retired")
    }

    /// The dot is the terminal, its radius the renderer's.
    func testTheDotIsTheContactsSize() throws {
        let dot = try bounds(of: CircuitsRenderer.dotAssetName)
        XCTAssertEqual(dot.extents.x, 2 * CircuitsRenderer.contactRadius, accuracy: 0.0005)
        XCTAssertEqual(simd_length(dot.center), 0, accuracy: 1e-4)
    }

    /// Every element lies along X inside the clamp, so a body pinch can
    /// never reach a dot's target, and its leads' inner ends lie on it.
    func testEveryElementStaysInsideTheClampAndMeetsItsLeads() throws {
        for kind in CircuitsModel.ComponentKind.allCases {
            let name = kind == .resistor ? CircuitsRenderer.resistorCapsAssetName
                : try XCTUnwrap(CircuitsRenderer.bodyAssetNames[kind])
            let box = try bounds(of: name)
            XCTAssertLessThan(box.max.x, CircuitsRenderer.elementClamp, "\(kind) reaches its +X dot")
            XCTAssertGreaterThan(box.min.x, -CircuitsRenderer.elementClamp, "\(kind) reaches its −X dot")
            let ends = try XCTUnwrap(CircuitsRenderer.leadInner[kind])
            XCTAssertGreaterThanOrEqual(ends.x, box.min.x - 0.002, "\(kind)'s left lead stops short")
            XCTAssertLessThanOrEqual(ends.y, box.max.x + 0.002, "\(kind)'s right lead stops short")
        }
    }

    /// The pieces Swift moves or lights are the asset's own named children.
    func testTheLivePiecesAreThere() {
        let expected: [(CircuitsModel.ComponentKind, (CircuitsRenderer.Module) -> Bool)] = [
            (.bulb, { $0.filament != nil }), (.led, { $0.ledCore != nil }),
            (.motor, { $0.rotor != nil && $0.rotorBlur != nil }), (.switcher, { $0.lever != nil }),
            (.fuse, { $0.fuseBridge != nil && $0.fuseGlass != nil }),
            (.capacitor, { $0.plates.count == 2 }), (.acSource, { $0.bead != nil }),
        ]
        for (kind, has) in expected {
            XCTAssertTrue(has(CircuitsRenderer.makeModule(kind: kind)), "\(kind) lost a live piece")
        }
        let blade = CircuitsRenderer.makeModule(kind: .switcher).lever
        XCTAssertEqual(blade.map { simd_distance($0.position, CircuitsRenderer.switchPivot) } ?? 1, 0,
                       accuracy: 1e-4, "the blade turns about the pivot")
        let rotor = CircuitsRenderer.makeModule(kind: .motor).rotor
        XCTAssertEqual(rotor.map { simd_length($0.position) } ?? 1, 0, accuracy: 1e-4,
                       "the flywheel turns about the hub")
    }

    /// Glass is see-through. Blender's USD exporter drops the Alpha socket
    /// and writes opacity as 1 − Transmission, so every glass part shipped
    /// opaque until 2026-10-18 and hid the filament a fuse exists to show.
    func testTheGlassPartsAreSeeThrough() throws {
        for name in ["CircuitBulb", "CircuitFuse", "CircuitLED", "CircuitACSource"] {
            let loaded = try XCTUnwrap(try? Entity.load(named: name))
            var transparent = 0
            func walk(_ entity: Entity) {
                for material in entity.components[ModelComponent.self]?.materials ?? [] {
                    if let pbr = material as? PhysicallyBasedMaterial,
                       case .transparent = pbr.blending {
                        transparent += 1
                    }
                }
                entity.children.forEach(walk)
            }
            walk(loaded)
            XCTAssertGreaterThan(transparent, 0, "\(name)'s glass came out opaque")
        }
    }

    /// The battery's long plate (+) is on the −X end — terminal 0, the
    /// nodeA convention the solver and the renderer share: the copper disc
    /// there reaches farther from the line than the zinc one.
    func testTheBatterysLongPlateIsTerminalZero() throws {
        let points = try vertices(of: "CircuitBattery").filter { abs($0.x) < 0.02 }
        func reach(_ side: (Float) -> Bool) -> Float {
            points.filter { side($0.x) && $0.y < 0.03 }.map { simd_length(SIMD2($0.y, $0.z)) }.max() ?? 0
        }
        XCTAssertGreaterThan(reach { $0 < -0.002 }, reach { $0 > 0.002 } + 0.01,
                             "the + plate should be the wider, at −X")
    }

    /// The LED's cone points from the anode (−X, terminal 0) to its bar: the
    /// shape says which way it conducts, as the solver's diode does.
    func testTheLEDsConePointsFromTheAnode() throws {
        let cone = try XCTUnwrap(CircuitsRenderer.makeModule(kind: .led).ledCore)
        let box = cone.visualBounds(relativeTo: nil)
        let points = try vertices(of: "CircuitLED").filter { $0.x >= box.min.x - 1e-4 && $0.x <= box.max.x + 1e-4 }
        let wide = points.filter { $0.x < box.center.x }.map { simd_length(SIMD2($0.y, $0.z)) }.max() ?? 0
        let narrow = points.filter { $0.x > box.max.x - 0.002 && $0.x <= box.max.x }
            .map { simd_length(SIMD2($0.y, $0.z)) }.min() ?? 1
        XCTAssertGreaterThan(wide, narrow, "the cone should be wide at −X and point +X")
    }

    /// The turntable under the floating circuit (2026-10-18): a deck and a
    /// rim, each centred on the axis with its top at y = 0, the rim's outer
    /// edge at `CircuitsModel.stageRadius`.
    func testTheTurntableIsMilledToTheStagesNumbers() throws {
        let deck = try bounds(of: "CircuitStageDeck")
        let rim = try bounds(of: "CircuitStageRim")
        let radius = Float(CircuitsModel.stageRadius)
        XCTAssertEqual(rim.extents.x, 2 * radius, accuracy: 0.003)
        XCTAssertEqual(rim.extents.z, 2 * radius, accuracy: 0.003)
        XCTAssertLessThan(deck.extents.x, rim.extents.x, "the deck runs past its rim")
        XCTAssertEqual(deck.max.y, 0, accuracy: 0.002, "the deck's top is not at y = 0")
        XCTAssertEqual(rim.max.y, 0, accuracy: 0.003)
        XCTAssertLessThan(deck.extents.y, 0.02, "a slim disc, not a drum")
        for box in [deck, rim] {
            XCTAssertEqual(box.center.x, 0, accuracy: 0.002)
            XCTAssertEqual(box.center.z, 0, accuracy: 0.002)
        }
    }
}
