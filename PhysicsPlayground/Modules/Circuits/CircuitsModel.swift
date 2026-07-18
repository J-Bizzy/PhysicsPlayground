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
        case battery, resistor, bulb, capacitor, switcher, wire

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .battery: "Battery"
            case .resistor: "Resistor"
            case .bulb: "Bulb"
            case .capacitor: "Capacitor"
            case .switcher: "Switch"
            case .wire: "Wire"
            }
        }

        var defaultValue: Double {
            switch self {
            case .battery: 9.0        // V
            case .resistor: 470.0     // Ω
            case .bulb: 24.0          // Ω
            case .capacitor: 2.2e-3   // F
            case .switcher: 0
            case .wire: 0.25          // m — a wire's value is its length
            }
        }
    }

    /// Real 1 mm² copper: R = ρL/A with ρ = 1.68×10⁻⁸ Ω·m, so a wire's
    /// resistance honestly grows with the length the user gives it
    /// (~17 mΩ per meter — negligible next to a bulb, but not zero).
    nonisolated static let wireOhmsPerMeter = 1.68e-8 / 1e-6

    /// How long a wire is allowed to be, whether set by slider or by
    /// pulling its end grips.
    nonisolated static let wireLengthRange = 0.1...2.0

    /// How far beyond a terminal its orange end grip sits.
    nonisolated static let endGripOffset = 0.03

    /// Terminals this close when a part is released connect themselves.
    nonisolated static let snapDistance = 0.08

    nonisolated static func wireResistance(length: Double) -> Double {
        max(length, 0.01) * wireOhmsPerMeter
    }

    struct Terminal: Equatable, Hashable {
        var componentID: UUID
        var end: Int  // 0 = left (battery +), 1 = right
    }

    struct Component: Identifiable, Equatable {
        let id: UUID
        let kind: ComponentKind
        var position: SIMD3<Double>
        /// Volts, ohms, farads — or meters of length for a wire.
        var value: Double
        /// Unit direction from terminal 0 toward terminal 1. Parts are
        /// aimed anywhere in space by pulling their end grips.
        var axis = SIMD3<Double>(1, 0, 0)
        /// Switches only.
        var isClosed = true
        /// Capacitors only: the integrated state.
        var capacitorVoltage = 0.0

        /// Half the distance between the two terminals — a wire spans
        /// its own adjustable length; every other part has the
        /// standard-size body.
        var terminalHalfSpan: Double {
            kind == .wire ? value / 2 : CircuitsModel.terminalOffset
        }

        func terminalPosition(_ end: Int) -> SIMD3<Double> {
            position + (end == 0 ? -terminalHalfSpan : terminalHalfSpan) * axis
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
    /// The contextual one-liner shown after loading a premade circuit.
    private(set) var insightText = ""

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

    /// Adds a part — at `point` when it comes off the tray, otherwise on
    /// a spawn ring at the build center. Returns the new part's id (nil
    /// when the component budget is full).
    @discardableResult
    func add(_ kind: ComponentKind, at point: SIMD3<Double>? = nil) -> UUID? {
        guard components.count < Self.componentBudget else { return nil }
        let angle = Double(components.count) * 2.4
        let fallback = Self.buildCenter
            + SIMD3(cos(angle) * 0.35, Double(components.count % 3) * 0.15 - 0.1, sin(angle) * 0.25)
        let position = clamp(point ?? fallback)
        let component = Component(id: UUID(), kind: kind, position: position,
                                  value: kind.defaultValue)
        components.append(component)
        selectedID = component.id
        emitSound(.pop, at: position, volume: 0.6)
        return component.id
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

    /// Live length while a wire's end grip is being pulled. Clamped to
    /// the same range as the panel slider; ignores non-wires.
    func setWireLength(id: UUID, length: Double) {
        guard let index = components.firstIndex(where: { $0.id == id }),
              components[index].kind == .wire else { return }
        components[index].value = min(max(length, Self.wireLengthRange.lowerBound),
                                      Self.wireLengthRange.upperBound)
    }

    /// Magnetic connections: when a part is released, any of its
    /// terminals sitting within snapDistance of another part's free-ish
    /// terminal wires itself up — bring parts together and they connect.
    func autoConnect(id: UUID) {
        guard let component = components.first(where: { $0.id == id }) else { return }
        var connected = false
        for end in 0...1 {
            let mine = Terminal(componentID: id, end: end)
            let minePosition = component.terminalPosition(end)
            var best: (terminal: Terminal, distance: Double)?
            for other in components where other.id != id {
                for otherEnd in 0...1 {
                    let theirs = Terminal(componentID: other.id, end: otherEnd)
                    let distance = simd_distance(minePosition, other.terminalPosition(otherEnd))
                    guard distance < Self.snapDistance else { continue }
                    let already = wires.contains {
                        ($0.from == mine && $0.to == theirs) || ($0.from == theirs && $0.to == mine)
                    }
                    guard !already else { continue }
                    if best == nil || distance < best!.distance {
                        best = (theirs, distance)
                    }
                }
            }
            if let best {
                wires.append(Wire(id: UUID(), from: mine, to: best.terminal))
                connected = true
            }
        }
        if connected {
            emitSound(.chime, at: component.position, volume: 0.5)
        }
    }

    /// Adopt the aim a carry left the part with (the hand can twist a
    /// held part). Ignores degenerate axes; normalizes the rest.
    func setAxis(id: UUID, axis: SIMD3<Double>) {
        guard let index = components.firstIndex(where: { $0.id == id }) else { return }
        let length = simd_length(axis)
        guard length > 1e-6 else { return }
        components[index].axis = axis / length
    }

    /// True while any battery is pushing more current than a healthy
    /// circuit would draw — i.e. the load is (nearly) a dead short and
    /// the battery's internal resistance is doing all the limiting.
    var hasOverloadedBattery: Bool {
        components.contains { component in
            component.kind == .battery
                && abs(readouts[component.id]?.amps ?? 0) > Self.overloadAmps
        }
    }

    /// A bulb draws ~0.4 A; a dead short through a 9 V battery draws
    /// ~150 A. Anything past this is a wiring mistake, not a load.
    nonisolated static let overloadAmps = 2.0

    /// Swing a part by one of its end grips: the opposite end stays
    /// pinned at `pivot`, the grabbed end chases the hand, and the part
    /// re-aims along the line between them. Wires also take their new
    /// length from the hand's reach.
    func dragEnd(id: UUID, grabbedEnd: Int, pivot: SIMD3<Double>, hand: SIMD3<Double>) {
        guard let index = components.firstIndex(where: { $0.id == id }) else { return }
        var direction = hand - pivot
        let reach = simd_length(direction)
        guard reach > 1e-4 else { return }
        direction /= reach
        setWireLength(id: id, length: reach - Self.endGripOffset)
        let halfSpan = components[index].terminalHalfSpan
        components[index].axis = grabbedEnd == 1 ? direction : -direction
        components[index].position = clamp(pivot + direction * halfSpan)
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
            case .wire:
                .resistor(ohms: Self.wireResistance(length: component.value))
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

    // MARK: Premade circuits

    /// The classic teaching circuits, laid out ready-made — and built
    /// from ordinary parts, so every one can be rewired, re-valued,
    /// aimed, and torn apart afterward.
    enum Preset: String, CaseIterable, Identifiable {
        case series, parallel, divider, rcCharger, shortCircuit
        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .series: "Series bulbs"
            case .parallel: "Parallel bulbs"
            case .divider: "Voltage divider"
            case .rcCharger: "RC charger"
            case .shortCircuit: "Short circuit"
            }
        }
    }

    /// Places a part directly (no spawn sound), returning its id.
    @discardableResult
    private func place(_ kind: ComponentKind, at position: SIMD3<Double>,
                       axis: SIMD3<Double> = SIMD3(1, 0, 0),
                       value: Double? = nil) -> UUID {
        var component = Component(id: UUID(), kind: kind, position: position,
                                  value: value ?? kind.defaultValue)
        component.axis = axis
        components.append(component)
        return component.id
    }

    private func connect(_ a: (UUID, Int), _ b: (UUID, Int)) {
        wires.append(Wire(id: UUID(),
                          from: Terminal(componentID: a.0, end: a.1),
                          to: Terminal(componentID: b.0, end: b.1)))
    }

    func loadPreset(_ preset: Preset) {
        clearBench()
        showElectronFlow = true
        isPaused = false
        let up = SIMD3<Double>(0, 1, 0)

        switch preset {
        case .series:
            let battery = place(.battery, at: SIMD3(0, 1.12, -0.9))
            let bulb1 = place(.bulb, at: SIMD3(-0.22, 1.5, -0.9))
            let bulb2 = place(.bulb, at: SIMD3(0.22, 1.5, -0.9))
            let toggle = place(.switcher, at: SIMD3(0.34, 1.31, -0.9), axis: up)
            connect((battery, 1), (toggle, 0))
            connect((toggle, 1), (bulb2, 1))
            connect((bulb2, 0), (bulb1, 1))
            connect((bulb1, 0), (battery, 0))
            insightText = "Series: ONE path, so the same current threads both bulbs — each gets half the voltage and glows dimmer than it would alone. Unscrew either and the whole loop dies."
        case .parallel:
            let battery = place(.battery, at: SIMD3(0, 1.12, -0.9))
            let bulb1 = place(.bulb, at: SIMD3(-0.18, 1.45, -0.9))
            let bulb2 = place(.bulb, at: SIMD3(0.18, 1.58, -0.9))
            connect((battery, 1), (bulb1, 1))
            connect((battery, 1), (bulb2, 1))
            connect((bulb1, 0), (battery, 0))
            connect((bulb2, 0), (battery, 0))
            insightText = "Parallel: each bulb gets the FULL 9 V, so both burn at full brightness — and the battery pays for it, pushing double the current. Select the battery and compare its mA to one bulb's."
        case .divider:
            let battery = place(.battery, at: SIMD3(0, 1.12, -0.9))
            let r1 = place(.resistor, at: SIMD3(-0.2, 1.5, -0.9), value: 470)
            let r2 = place(.resistor, at: SIMD3(0.2, 1.5, -0.9), value: 1000)
            connect((battery, 1), (r2, 1))
            connect((r2, 0), (r1, 1))
            connect((r1, 0), (battery, 0))
            insightText = "A voltage divider: the 9 V splits in proportion to resistance — select each resistor and read ~2.9 V across 470 Ω and ~6.1 V across 1 kΩ. Slide either value and watch the split follow."
        case .rcCharger:
            let battery = place(.battery, at: SIMD3(0, 1.12, -0.9))
            let resistor = place(.resistor, at: SIMD3(-0.3, 1.31, -0.9), axis: up, value: 1000)
            let capacitor = place(.capacitor, at: SIMD3(0, 1.5, -0.9))
            let toggle = place(.switcher, at: SIMD3(0.3, 1.31, -0.9), axis: up)
            connect((battery, 1), (toggle, 0))
            connect((toggle, 1), (capacitor, 1))
            connect((capacitor, 0), (resistor, 1))
            connect((resistor, 0), (battery, 0))
            insightText = "RC charging: the capacitor fills toward 9 V with time constant τ = RC ≈ 2.2 s — select it and watch the charge curve slow as it approaches full. Flip the switch to pause the flow mid-charge."
        case .shortCircuit:
            let battery = place(.battery, at: SIMD3(0, 1.12, -0.9))
            let jumper = place(.wire, at: SIMD3(0, 1.45, -0.9), value: 0.4)
            connect((battery, 1), (jumper, 1))
            connect((jumper, 0), (battery, 0))
            insightText = "A dead short: nothing limits the current but the battery's own 50 mΩ — about 150 A, the red warning, and in real life a very hot battery. Add a bulb into the loop to tame it."
        }
        selectedID = components.first?.id
        step(dt: 1.0 / 90.0)
    }

    // MARK: Reset

    /// Empties the bench completely — the blank-slate path behind the
    /// quick panel's Clear bench button.
    func clearBench() {
        components = []
        wires = []
        selectedID = nil
        pendingTerminal = nil
        insightText = ""
        readouts = [:]
        wireFlows = [:]
        totalSourcePower = 0
    }

    /// The opening scene: a battery–switch–bulb loop already flowing, so
    /// the room shows live current the moment the lab appears — flip the
    /// switch, pull it apart, or Clear bench and build from nothing.
    func reset() {
        clearBench()
        showElectronFlow = true
        isPaused = false
        seedStarterLoop()
    }

    private func seedStarterLoop() {
        // A clean rectangle: battery along the bottom, bulb along the
        // top, the switch standing upright on the right edge, and the
        // bulb→battery wire closing the left edge dead vertical.
        let battery = Component(
            id: UUID(), kind: .battery,
            position: SIMD3(0, 1.12, -0.9),
            value: ComponentKind.battery.defaultValue)
        let switcher = Component(
            id: UUID(), kind: .switcher,
            position: SIMD3(0.30, 1.31, -0.9),
            value: ComponentKind.switcher.defaultValue,
            axis: SIMD3(0, 1, 0))
        let bulb = Component(
            id: UUID(), kind: .bulb,
            position: SIMD3(0, 1.5, -0.9),
            value: ComponentKind.bulb.defaultValue)
        components = [battery, switcher, bulb]
        wires = [
            Wire(id: UUID(),
                 from: Terminal(componentID: battery.id, end: 1),
                 to: Terminal(componentID: switcher.id, end: 0)),
            Wire(id: UUID(),
                 from: Terminal(componentID: switcher.id, end: 1),
                 to: Terminal(componentID: bulb.id, end: 1)),
            Wire(id: UUID(),
                 from: Terminal(componentID: bulb.id, end: 0),
                 to: Terminal(componentID: battery.id, end: 0)),
        ]
        // Solve once immediately so the bulb opens lit, not one frame dark.
        step(dt: 1.0 / 90.0)
    }

    init() {
        reset()
    }
}
