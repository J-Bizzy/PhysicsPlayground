//
//  CircuitsWireFlowTests.swift
//  PhysicsPlaygroundTests
//
//  The current in each wire, which the nodal solve never states (wires are
//  its nodes): Kirchhoff divides each terminal's current among its wires
//  (`WireCurrents`, 2026-10-18). The electron dots ride it and the wire's
//  field is drawn from it, so the two agree in a parallel net — until now
//  each terminal's current was split evenly over its wires while the field
//  gave every wire its part's full current.
//

import XCTest
import PhysicsCore
import simd
@testable import PhysicsPlayground

@MainActor
final class CircuitsWireFlowTests: XCTestCase {

    private typealias Terminal = CircuitsModel.Terminal

    /// A battery and two different bulbs in parallel, the second bulb's
    /// leads wired to the first bulb's rather than back to the battery: the
    /// wire from the battery carries both bulbs, the one between the bulbs
    /// only the far bulb.
    private func chainedParallel() throws -> (CircuitsModel, near: UUID, far: UUID,
                                               feed: UUID, link: UUID) {
        let model = CircuitsModel()
        model.clearBench()
        let battery = try XCTUnwrap(model.add(.battery, at: SIMD3(-0.3, 1.1, -0.9)))
        let near = try XCTUnwrap(model.add(.bulb, at: SIMD3(0, 1.4, -0.9)))
        let far = try XCTUnwrap(model.add(.bulb, at: SIMD3(0.3, 1.4, -0.9)))
        model.setComponentValue(id: far, 48)
        model.connectTerminals(Terminal(componentID: battery, end: 1), Terminal(componentID: near, end: 0))
        model.connectTerminals(Terminal(componentID: near, end: 0), Terminal(componentID: far, end: 0))
        model.connectTerminals(Terminal(componentID: near, end: 1), Terminal(componentID: battery, end: 0))
        model.connectTerminals(Terminal(componentID: far, end: 1), Terminal(componentID: near, end: 1))
        XCTAssertEqual(model.wires.count, 4)
        model.step(dt: 1.0 / 90.0)
        let feed = try XCTUnwrap(model.wires.first {
            $0.from.componentID == battery || $0.to.componentID == battery
        }?.id)
        let link = try XCTUnwrap(model.wires.first {
            Set([$0.from.componentID, $0.to.componentID]) == [near, far]
                && $0.from.end == 0 && $0.to.end == 0
        }?.id)
        return (model, near, far, feed, link)
    }

    func testTheFeedCarriesBothBulbsAndTheLinkOnlyTheFar() throws {
        let (model, near, far, feed, link) = try chainedParallel()
        // Magnitudes: which way round a bulb's current is signed depends on
        // which lead faces the battery's +.
        let iNear = abs(try XCTUnwrap(model.readouts[near]?.amps))
        let iFar = abs(try XCTUnwrap(model.readouts[far]?.amps))
        XCTAssertGreaterThan(iNear, iFar, "the 24 Ω bulb draws more than the 48 Ω one")
        XCTAssertEqual(abs(try XCTUnwrap(model.wireFlows[feed])), iNear + iFar, accuracy: 1e-9)
        XCTAssertEqual(abs(try XCTUnwrap(model.wireFlows[link])), iFar, accuracy: 1e-9)
    }

    /// What every terminal's component pushes into the wiring leaves through
    /// its wires.
    func testCurrentBalancesAtEveryTerminal() throws {
        let (model, _, _, _, _) = try chainedParallel()
        for component in model.components {
            let amps = try XCTUnwrap(model.readouts[component.id]?.amps)
            for end in 0...1 {
                let terminal = Terminal(componentID: component.id, end: end)
                var leaving = 0.0
                for wire in model.wires {
                    let flow = model.wireFlows[wire.id] ?? 0
                    if wire.from == terminal { leaving += flow }
                    if wire.to == terminal { leaving -= flow }
                }
                let pushed = end == 1 ? amps : -amps
                XCTAssertEqual(leaving, pushed, accuracy: 1e-7,
                               "\(component.kind) terminal \(end)")
            }
        }
    }

    /// The field is drawn from the same currents the electrons ride.
    func testTheFieldAndTheElectronsAgree() throws {
        let (model, _, _, _, _) = try chainedParallel()
        for wire in model.wires {
            let flow = try XCTUnwrap(model.wireFlows[wire.id])
            let from = try XCTUnwrap(model.components.first { $0.id == wire.from.componentID })
            let a = from.terminalPosition(wire.from.end)
            let segment = model.currentSegments.first { simd_distance($0.a, a) < 1e-12 && abs($0.current) == abs(flow) }
            XCTAssertNotNil(segment, "the field drew this wire with another current")
        }
    }

    // MARK: A loaded bench is held to the live rules

    func testALoadedBenchLosesWhatTheLiveRulesRefuse() throws {
        let model = CircuitsModel()
        model.clearBench()
        let a = try XCTUnwrap(model.add(.resistor, at: SIMD3(-0.2, 1.2, -0.9)))
        let b = try XCTUnwrap(model.add(.resistor, at: SIMD3(0.2, 1.2, -0.9)))
        let tA0 = Terminal(componentID: a, end: 0), tA1 = Terminal(componentID: a, end: 1)
        let tB0 = Terminal(componentID: b, end: 0), tB1 = Terminal(componentID: b, end: 1)
        let ghost = Terminal(componentID: UUID(), end: 0)
        let wires: [CircuitsModel.Wire] = [
            .init(id: UUID(), from: tA1, to: tB0),
            .init(id: UUID(), from: tB0, to: tA1),   // the same pair again
            .init(id: UUID(), from: tA0, to: tA0),   // a terminal to itself
            .init(id: UUID(), from: tA0, to: ghost), // to a part that is not there
            .init(id: UUID(), from: tB1, to: tA0),
        ]
        var components = model.components
        components[0].position = SIMD3(0, -5, -0.9)   // under the floor
        let bench = CircuitsModel.sanitized(.init(components: components, wires: wires))
        XCTAssertEqual(bench.wires.map(\.id), [wires[0].id, wires[4].id])
        XCTAssertGreaterThanOrEqual(bench.components[0].position.y, CircuitsModel.floorMargin)
    }

    func testALoadedBenchKeepsNoMoreThanTheBudget() {
        let parts = (0..<CircuitsModel.componentBudget).map { index in
            CircuitsModel.Component(id: UUID(), kind: .resistor,
                                    position: SIMD3(Double(index) * 0.2 - 1.5, 1.2, -0.9),
                                    value: 100)
        }
        var wires: [CircuitsModel.Wire] = []
        // A tree of 31 links and then more, to overflow the 36.
        for index in 0..<(2 * parts.count - 1) {
            let from = Terminal(componentID: parts[index / 2].id, end: index % 2)
            let to = Terminal(componentID: parts[(index + 1) / 2].id, end: (index + 1) % 2)
            if from != to { wires.append(.init(id: UUID(), from: from, to: to)) }
        }
        let bench = CircuitsModel.sanitized(.init(components: parts, wires: wires))
        XCTAssertLessThanOrEqual(bench.wires.count, CircuitsModel.wireBudget)
    }

    /// Every authored bench is already legal: loading one changes nothing.
    func testThePresetsAndTheStarterLoopPassThroughUnchanged() {
        let model = CircuitsModel()
        model.reset()
        let starter = CircuitsModel.SavedBench(components: model.components, wires: model.wires)
        XCTAssertEqual(CircuitsModel.sanitized(starter).wires, starter.wires)
        for preset in CircuitsModel.Preset.allCases {
            model.loadPreset(preset)
            let bench = CircuitsModel.SavedBench(components: model.components, wires: model.wires)
            let clean = CircuitsModel.sanitized(bench)
            XCTAssertEqual(clean.wires, bench.wires, "\(preset) lost a wire")
            XCTAssertEqual(clean.components, bench.components, "\(preset) moved a part")
        }
    }
}
