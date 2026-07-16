//
//  CircuitsModel.swift
//  Physics Playground — Circuits module
//
//  App state for the build-your-own-circuit lab. Components float
//  anywhere in the room (positions are immersive-space coordinates,
//  clamped only by a generous 3 m build sphere); every component has
//  two terminals, and wiring is tap–tap: pinch one terminal, pinch
//  another, and a wire joins them.
//
//  The electrical truth comes from PhysicsCore's CircuitSolver every
//  frame: wires merge terminals into nodes (union–find), each
//  component stamps its Norton companion, and the nodal solve returns
//  every voltage, current, and power — so bulb brightness, electron
//  drift, and the readouts all agree with Kirchhoff by construction.
//  Capacitors integrate through time (real RC transients); pause
//  freezes their state.
//

import Foundation
import Observation
import PhysicsCore
import simd

@MainActor
@Observable
final class CircuitsModel {
    // MARK: Build volume & budgets

    nonisolated static let buildCenter = SIMD3<Double>(0, 1.25, -0.9)
    /// The only restriction: a generous reach from the build center.
    nonisolated static let buildRadius = 3.0
    nonisolated static let floorMargin = 0.2
    nonisolated static let componentBudget = 16
    nonisolated static let wireBudget = 36
    /// Batteries are honest: a small internal resistance, so even a
    /// dead-short misbehaves physically instead of exploding the math.
    nonisolated static let batteryInternalResistance = 0.05
    /// Terminals sit at ±x on every component.
    nonisolated static let terminalOffset = 0.085

    // MARK: Components

    enum ComponentKind: String, CaseIterable, Identifiable {
        case battery, resistor, bulb, capacitor, switcher

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .battery: "Battery"
            case .resistor: "Resistor"
            case .bulb: "Bulb"
            case .capacitor: "Capacitor"
            case .switcher: "Switch"
            }
        }

        var defaultValue: Double {
            switch self {
            case .battery: 9.0        // V
            case .resistor: 470.0     // Ω
            case .bulb: 24.0          // Ω
            case .capacitor: 2.2e-3   // F
            case .switcher: 0
            }
        }
    }

    struct Terminal: Equatable, Hashable {
        var componentID: UUID
        var end: Int  // 0 = left (battery +), 1 = right
    }

    struct Component: Identifiable, Equatable {
        let id: UUID
        let kind: ComponentKind
        var position: SIMD3<Double>
        /// Volts, ohms, or farads depending on kind.
        var value: Double
        /// Switches only.
        var isClosed = true
        /// Capacitors only: the integrated state.
        var capacitorVoltage = 0.0

        func terminalPosition(_ end: Int) -> SIMD3<Double> {
            position + SIMD3(end == 0 ? -CircuitsModel.terminalOffset
                                      : CircuitsModel.terminalOffset, 0, 0)
        }
    }

    struct Wire: Identifiable, Equatable {
        let id: UUID
        let from: Terminal
        let to: Terminal
    }

    private(set) var components: [Component] = []
    private(set) var wires: [Wire] = []
    private(set) var selectedID: UUID?
    /// The half-made connection: first terminal tapped, awaiting its mate.
    private(set) var pendingTerminal: Terminal?

    var selectedComponent: Component? {
        guard let selectedID else { return nil }
        return components.first { $0.id == selectedID }
    }

    // MARK: Display & time

    var showElectronFlow = true
    var isPaused = false

    // MARK: Live electrical state (rebuilt every step)

    struct Readout: Equatable {
        /// Across the component, V (terminal 0 minus terminal 1).
        var volts: Double
        /// Through the component, A (positive terminal 0 → 1).
        var amps: Double
        /// Dissipated (positive) or delivered (negative), W.
        var watts: Double
    }

    private(set) var readouts: [UUID: Readout] = [:]
    /// Estimated current in each wire (for the electron flow), A.
    private(set) var wireFlows: [UUID: Double] = [:]
    /// Power delivered by all sources, W.
    private(set) var totalSourcePower = 0.0

    // MARK: Sounds

    private(set) var soundEvent: SpatialSoundEvent?
    private var soundCounter = 0

    private func emitSound(_ kind: SoundPalette.Sound, at position: SIMD3<Double>, volume: Double) {
        soundCounter += 1
        soundEvent = SpatialSoundEvent(id: soundCounter, kind: kind,
                                       position: position, volume: volume)
    }

    // MARK: Editing

    func add(_ kind: ComponentKind) {
        guard components.count < Self.componentBudget else { return }
        let angle = Double(components.count) * 2.4
        let position = clamp(Self.buildCenter
            + SIMD3(cos(angle) * 0.35, Double(components.count % 3) * 0.15 - 0.1, sin(angle) * 0.25))
        let component = Component(id: UUID(), kind: kind, position: position,
                                  value: kind.defaultValue)
        components.append(component)
        selectedID = component.id
        emitSound(.pop, at: position, volume: 0.6)
    }

    func removeSelected() {
        guard let selectedID,
              let component = components.first(where: { $0.id == selectedID }) else { return }
        wires.removeAll { $0.from.componentID == selectedID || $0.to.componentID == selectedID }
        components.removeAll { $0.id == selectedID }
        if pendingTerminal?.componentID == selectedID { pendingTerminal = nil }
        self.selectedID = components.last?.id
        emitSound(.thud, at: component.position, volume: 0.4)
    }

    func select(id: UUID) {
        guard components.contains(where: { $0.id == id }) else { return }
        selectedID = id
    }

    func move(id: UUID, to point: SIMD3<Double>) {
        guard let index = components.firstIndex(where: { $0.id == id }) else { return }
        components[index].position = clamp(point)
    }

    private func clamp(_ point: SIMD3<Double>) -> SIMD3<Double> {
        var clamped = point
        let offset = clamped - Self.buildCenter
        let distance = simd_length(offset)
        if distance > Self.buildRadius {
            clamped = Self.buildCenter + offset * (Self.buildRadius / distance)
        }
        clamped.y = max(clamped.y, Self.floorMargin)
        return clamped
    }

    // MARK: Wiring (tap one terminal, then another)

    func tapTerminal(_ terminal: Terminal) {
        guard components.contains(where: { $0.id == terminal.componentID }) else { return }
        guard let pending = pendingTerminal else {
            pendingTerminal = terminal
            return
        }
        defer { pendingTerminal = nil }
        guard pending != terminal else { return }  // tapped again: cancel
        // No duplicate wires between the same two terminals.
        let exists = wires.contains {
            ($0.from == pending && $0.to == terminal) || ($0.from == terminal && $0.to == pending)
        }
        guard !exists, wires.count < Self.wireBudget else { return }
        wires.append(Wire(id: UUID(), from: pending, to: terminal))
        if let component = components.first(where: { $0.id == terminal.componentID }) {
            emitSound(.pop, at: component.terminalPosition(terminal.end), volume: 0.8)
        }
    }

    func deleteWire(id: UUID) {
        guard let wire = wires.first(where: { $0.id == id }) else { return }
        wires.removeAll { $0.id == id }
        if let component = components.first(where: { $0.id == wire.from.componentID }) {
            emitSound(.thud, at: component.terminalPosition(wire.from.end), volume: 0.3)
        }
    }

    func toggleSwitch(id: UUID) {
        guard let index = components.firstIndex(where: { $0.id == id }),
              components[index].kind == .switcher else { return }
        components[index].isClosed.toggle()
        selectedID = id
        emitSound(.thud, at: components[index].position, volume: 0.5)
    }

    // MARK: Selected-component value editing

    var selectedValue: Double {
        get { selectedComponent?.value ?? 0 }
        set {
            guard let index = components.firstIndex(where: { $0.id == selectedID }) else { return }
            components[index].value = newValue
        }
    }

    var selectedIsClosed: Bool {
        get { selectedComponent?.isClosed ?? true }
        set {
            guard let index = components.firstIndex(where: { $0.id == selectedID }),
                  components[index].kind == .switcher else { return }
            components[index].isClosed = newValue
        }
    }

    // MARK: The solve (every frame)

    func step(dt: Double) {
        guard !components.isEmpty else {
            readouts = [:]
            wireFlows = [:]
            totalSourcePower = 0
            return
        }
        let timeStep = min(max(dt, 1e-4), 1.0 / 30.0)

        // 1. Union–find terminals into nodes across the wires.
        var terminalIndex: [Terminal: Int] = [:]
        var parents: [Int] = []
        for component in components {
            for end in 0...1 {
                terminalIndex[Terminal(componentID: component.id, end: end)] = parents.count
                parents.append(parents.count)
            }
        }
        func find(_ i: Int) -> Int {
            var root = i
            while parents[root] != root { root = parents[root] }
            var current = i
            while parents[current] != root {
                let next = parents[current]
                parents[current] = root
                current = next
            }
            return root
        }
        for wire in wires {
            guard let a = terminalIndex[wire.from], let b = terminalIndex[wire.to] else { continue }
            parents[find(a)] = find(b)
        }

        // 2. Compact node numbering, ground = the first battery's − end
        // (or the first terminal if there's no battery).
        let groundTerminal = components.first { $0.kind == .battery }
            .map { Terminal(componentID: $0.id, end: 1) }
            ?? Terminal(componentID: components[0].id, end: 0)
        var nodeOf: [Int: Int] = [:]
        let groundRoot = find(terminalIndex[groundTerminal]!)
        nodeOf[groundRoot] = 0
        var nodeCount = 1
        for index in parents.indices {
            let root = find(index)
            if nodeOf[root] == nil {
                nodeOf[root] = nodeCount
                nodeCount += 1
            }
        }
        func node(_ terminal: Terminal) -> Int {
            nodeOf[find(terminalIndex[terminal]!)]!
        }

        // 3. Stamp one element per component and solve.
        let elements = components.map { component -> CircuitElement in
            let a = node(Terminal(componentID: component.id, end: 0))
            let b = node(Terminal(componentID: component.id, end: 1))
            let kind: CircuitElement.Kind = switch component.kind {
            case .battery:
                .battery(volts: component.value,
                         internalResistance: Self.batteryInternalResistance)
            case .resistor, .bulb:
                .resistor(ohms: component.value)
            case .capacitor:
                .capacitor(farads: component.value,
                           previousVoltage: component.capacitorVoltage)
            case .switcher:
                component.isClosed ? .conductor : .open
            }
            return CircuitElement(nodeA: a, nodeB: b, kind: kind)
        }
        let solution = CircuitSolver.solve(
            elements: elements, nodeCount: nodeCount, timeStep: timeStep)

        // 4. Publish readouts; advance capacitor state (unless frozen).
        var newReadouts: [UUID: Readout] = [:]
        var sourcePower = 0.0
        for (index, component) in components.enumerated() {
            newReadouts[component.id] = Readout(
                volts: solution.voltages[index],
                amps: solution.currents[index],
                watts: solution.powers[index]
            )
            if solution.powers[index] < 0 { sourcePower -= solution.powers[index] }
            if component.kind == .capacitor, !isPaused {
                components[index].capacitorVoltage = solution.voltages[index]
            }
        }
        readouts = newReadouts
        totalSourcePower = sourcePower

        // 5. Wire currents for the electron flow: each terminal's element
        // current fans out evenly over its wires (a visualization choice;
        // parallel wires between the same nodes share indistinguishably).
        var flows: [UUID: Double] = [:]
        for wire in wires {
            func outflow(_ terminal: Terminal) -> Double {
                guard let index = components.firstIndex(where: { $0.id == terminal.componentID })
                else { return 0 }
                let current = solution.currents[index]
                let directed = terminal.end == 1 ? current : -current
                let fan = wires.filter { $0.from == terminal || $0.to == terminal }.count
                return directed / Double(max(fan, 1))
            }
            flows[wire.id] = (outflow(wire.from) - outflow(wire.to)) / 2
        }
        wireFlows = flows
    }

    // MARK: Reset

    /// The opening scene: a lit loop — battery, switch, bulb — begging
    /// to be tapped open.
    func reset() {
        components = []
        wires = []
        pendingTerminal = nil
        showElectronFlow = true
        isPaused = false
        readouts = [:]
        wireFlows = [:]
        totalSourcePower = 0

        let battery = Component(id: UUID(), kind: .battery,
                                position: Self.buildCenter + SIMD3(-0.4, -0.1, 0), value: 9)
        let bulb = Component(id: UUID(), kind: .bulb,
                             position: Self.buildCenter + SIMD3(0.4, -0.1, 0), value: 24)
        let toggle = Component(id: UUID(), kind: .switcher,
                               position: Self.buildCenter + SIMD3(0, 0.25, 0), value: 0)
        components = [battery, bulb, toggle]
        selectedID = bulb.id

        func terminal(_ component: Component, _ end: Int) -> Terminal {
            Terminal(componentID: component.id, end: end)
        }
        wires = [
            Wire(id: UUID(), from: terminal(battery, 0), to: terminal(toggle, 0)),
            Wire(id: UUID(), from: terminal(toggle, 1), to: terminal(bulb, 0)),
            Wire(id: UUID(), from: terminal(bulb, 1), to: terminal(battery, 1)),
        ]
        step(dt: 1.0 / 90.0)
    }

    init() {
        reset()
    }
}
