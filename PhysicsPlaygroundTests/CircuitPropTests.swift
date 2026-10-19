//
//  CircuitPropTests.swift
//  Physics Playground — app tests
//
//  The ten circuit parts milled by `Tools/circuitparts.py` as lab-kit
//  modules (2026-10-18): every asset the bench asks for exists, sits on
//  the shared carrier, lies along X, and stays inside the carry box's
//  clamp at the contacts' inner edge; the carrier runs to the contacts.
//  Blender (x, y, z) → RealityKit (x, z, −y).
//

import XCTest
import RealityKit
import simd
@testable import PhysicsPlayground

@MainActor
final class CircuitPropTests: XCTestCase {

    /// The inner edge of a lead, from `CircuitsSpaceView`'s carry box.
    private static let leadClamp: Float = 0.059

    private func bounds(of name: String) throws -> BoundingBox {
        let loaded = try XCTUnwrap(try? Entity.load(named: name),
                                   "\(name).usdz is not in the bundle — run "
                                   + "Tools/circuitparts.py")
        let box = loaded.visualBounds(relativeTo: nil)
        XCTAssertGreaterThan(min(box.extents.x, min(box.extents.y, box.extents.z)), 0,
                             "\(name) has no thickness on some axis")
        return box
    }

    /// Every kind the renderer maps to an asset has one, plus the
    /// resistor's caps and the carrier. A missing file falls back to a
    /// procedural body, which is the right behaviour and completely silent.
    func testEveryPartTheBenchAsksForExists() throws {
        for name in CircuitsRenderer.bodyAssetNames.values.sorted()
            + [CircuitsRenderer.resistorCapsAssetName, CircuitsRenderer.carrierAssetName] {
            _ = try bounds(of: name)
        }
    }

    /// The carrier every part is mounted on runs from contact to contact —
    /// so two parts snapped nose-to-tail butt their carriers at the joint —
    /// with its top where every body sits and its underside where the
    /// home's diorama stands it.
    func testTheCarrierRunsToTheContactsUnderEveryPart() throws {
        let carrier = try bounds(of: CircuitsRenderer.carrierAssetName)
        let contact = Float(CircuitsModel.terminalOffset)
        XCTAssertEqual(carrier.max.x, contact, accuracy: 0.0015)
        XCTAssertEqual(carrier.min.x, -contact, accuracy: 0.0015)
        XCTAssertEqual(carrier.min.y, CircuitsRenderer.carrierBottom, accuracy: 0.001)
        // The traces and rivets stand a hair proud of the top face.
        XCTAssertGreaterThan(carrier.max.y, CircuitsRenderer.carrierTop)
        XCTAssertLessThan(carrier.max.y, CircuitsRenderer.carrierTop + 0.004)
        // A contact sits on its trace: the ball's underside is the top face.
        XCTAssertEqual(-CircuitsRenderer.contactRadius, CircuitsRenderer.carrierTop, accuracy: 1e-6)
        for name in CircuitsRenderer.bodyAssetNames.values.sorted()
            + [CircuitsRenderer.resistorCapsAssetName] {
            let box = try bounds(of: name)
            XCTAssertGreaterThanOrEqual(box.min.y, CircuitsRenderer.carrierBottom - 0.001,
                                        "\(name) hangs below its carrier")
            XCTAssertLessThanOrEqual(abs(box.center.z), 0.004, "\(name) is off the carrier's centre line")
        }
    }

    /// Glass is see-through. Blender's USD exporter drops the Alpha socket
    /// and writes opacity as 1 − Transmission, so every glass part shipped
    /// opaque until 2026-10-18 and hid the filament a fuse exists to show.
    func testTheGlassPartsAreSeeThrough() throws {
        for name in ["CircuitBulb", "CircuitFuse", "CircuitLED"] {
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

    /// A body never reaches its own leads: the whole model sits inside
    /// |x| < 0.059, and the ones that are longer than they are tall lie
    /// Along X rather than standing on end.
    func testEveryBodyStaysInsideTheLeadClampAndLiesAlongX() throws {
        for name in CircuitsRenderer.bodyAssetNames.values.sorted()
            + [CircuitsRenderer.resistorCapsAssetName] {
            let box = try bounds(of: name)
            XCTAssertLessThan(box.max.x, Self.leadClamp, "\(name) reaches its +X lead")
            XCTAssertGreaterThan(box.min.x, -Self.leadClamp, "\(name) reaches its −X lead")
        }
        for name in ["CircuitBattery", "CircuitInductor",
                     "CircuitMotor", "CircuitFuse", "CircuitSwitch",
                     "CircuitResistorCaps"] {
            let box = try bounds(of: name)
            XCTAssertGreaterThan(box.extents.x, box.extents.y,
                                 "\(name) should lie along X, not stand on end")
        }
    }

    /// The bulb's envelope stands round the place the renderer hangs its
    /// filament, and the LED's lens over the place it lights its die, and
    /// the capacitor's can stands up off the carrier.
    func testTheBulbTheLEDAndTheCapacitorStandUp() throws {
        let bulb = try bounds(of: "CircuitBulb")
        XCTAssertGreaterThan(bulb.max.y, CircuitsRenderer.bulbCentre + 0.015,
                             "the bulb's glass should close over its filament")
        let led = try bounds(of: "CircuitLED")
        XCTAssertGreaterThan(led.max.y, CircuitsRenderer.ledGlowHeight + 0.004,
                             "the LED's lens should rise over its die")
        let capacitor = try bounds(of: "CircuitCapacitor")
        XCTAssertGreaterThan(capacitor.max.y, CircuitsRenderer.carrierTop + 0.035,
                             "the capacitor's can should stand on end")
    }

    /// The motor's shaft end is +X, where the renderer mounts the rotor
    /// (+0.05): the model reaches farther that way than the other.
    func testTheMotorsShaftIsOnThePlusXEnd() throws {
        let box = try bounds(of: "CircuitMotor")
        XCTAssertGreaterThan(box.max.x, -box.min.x + 0.005,
                             "the shaft stub should make +X the longer end")
    }

    /// The battery's positive nipple is on the −X end — terminal 0, the
    /// nodeA convention the solver and the renderer share. Measured over
    /// what stands above the carrier: the symbols on the chamfers below it
    /// are wider than the cell and symmetric.
    func testTheBatterysNippleIsOnTheMinusXEnd() throws {
        let loaded = try XCTUnwrap(try? Entity.load(named: "CircuitBattery"))
        var lowest = Float.infinity, highest = -Float.infinity
        func walk(_ entity: Entity) {
            if let mesh = entity.components[ModelComponent.self]?.mesh {
                let toRoot = entity.transformMatrix(relativeTo: loaded)
                for instance in mesh.contents.instances {
                    guard let model = mesh.contents.models[instance.model] else { continue }
                    let transform = toRoot * instance.transform
                    for part in model.parts {
                        for local in part.positions.elements {
                            let point = transform * SIMD4(local, 1)
                            guard point.y > CircuitsRenderer.carrierTop + 0.004 else { continue }
                            lowest = min(lowest, point.x)
                            highest = max(highest, point.x)
                        }
                    }
                }
            }
            entity.children.forEach(walk)
        }
        walk(loaded)
        XCTAssertGreaterThan(-lowest, highest + 0.001, "the nipple should make −X the longer end")
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
