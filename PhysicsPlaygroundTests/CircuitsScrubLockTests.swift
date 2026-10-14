//
//  CircuitsScrubLockTests.swift
//  PhysicsPlaygroundTests
//
//  While the room is parked in its own past, the bench is read-only:
//  `restoreCapsuleSnapshot` overwrites the bench on every scrub change,
//  so an edit made while scrubbed would silently vanish. Looking around
//  the past stays legal: selection, the net highlight and the probes are
//  observations.
//

import XCTest
import simd
@testable import PhysicsPlayground

@MainActor
final class CircuitsScrubLockTests: XCTestCase {

    /// Every bench-mutating entry point refuses while scrubbed, and
    /// the bench comes out bit-identical.
    func testTheBenchIsReadOnlyWhileScrubbed() {
        let model = CircuitsModel()
        model.step(dt: 1.0 / 90.0)
        let components = model.components
        let wires = model.wires
        let anyPart = components[0]
        let anyWire = wires[0]
        model.scrubTime = 0.5

        XCTAssertNil(model.add(.resistor), "no new parts in the past")
        model.select(id: anyPart.id)
        model.removeComponent(id: anyPart.id)
        model.detachComponent(id: anyPart.id)
        model.deleteWire(id: anyWire.id)
        if let toggle = components.first(where: { $0.kind == .switcher }) {
            model.toggleSwitch(id: toggle.id)
        }
        model.setComponentValue(id: anyPart.id, 42)
        model.move(id: anyPart.id, to: anyPart.position + SIMD3(0.3, 0, 0))
        model.setAxis(id: anyPart.id, axis: SIMD3(0, 1, 0))
        model.release(id: anyPart.id)
        model.swing(id: anyPart.id, hand: anyPart.position + SIMD3(0, 0.2, 0))
        model.replaceFailed(id: anyPart.id)

        model.beginLeadPull(from: anyWire.from, hand: anyPart.position)
        XCTAssertNil(model.leadPull, "no lead comes off in the past")
        model.beginRewire(wire: anyWire.id, grabbing: 0, hand: anyPart.position)
        XCTAssertNil(model.leadPull, "no wire lifts in the past")
        _ = model.voiceOverWire(anyWire.from)
        XCTAssertNil(model.voiceWireSource, "the accessibility door is shut too")

        XCTAssertEqual(model.components, components,
                       "a scrubbed bench must come through untouched")
        XCTAssertEqual(model.wires, wires)
    }

    /// Observation stays live: a scrub is for looking around.
    func testSelectionAndHighlightStayLiveWhileScrubbed() {
        let model = CircuitsModel()
        model.step(dt: 1.0 / 90.0)
        model.scrubTime = 0.5

        let part = model.components[0]
        model.select(id: part.id)
        XCTAssertEqual(model.selectedID, part.id)

        let wire = model.wires[0]
        model.highlightNet(containing: wire.from)
        XCTAssertTrue(model.isHighlighted(wire: wire))
    }

    /// And the lock lifts with the scrub — this is a pause, not a
    /// padlock.
    func testTheBenchUnlocksWhenTheScrubEnds() {
        let model = CircuitsModel()
        model.step(dt: 1.0 / 90.0)
        model.scrubTime = 0.5
        XCTAssertNil(model.add(.resistor))
        model.scrubTime = nil
        XCTAssertNotNil(model.add(.resistor))
    }
}
