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
    /// The bench's walls, as a half-size about `buildCenter`.
    ///
    /// This was a 3 m *sphere* — "the only restriction: a generous reach
    /// from the build center" — which was true and harmless while the
    /// bench owned the room — a 3 m reach means a resistor can be parked
    /// most of the way across it. A box rather than a sphere because
    /// that is what `CircuitsModelTests.assertOnTheBench` checks.
    ///
    /// Sized about the build centre (z = −0.9), slightly shallower in
    /// z than the bench's visual footprint about its pivot (z = −0.85).
    nonisolated static let buildHalfExtents = SIMD3<Double>(0.70, 0.48, 0.33)
    nonisolated static let floorMargin = 0.2
    nonisolated static let componentBudget = 16
    nonisolated static let wireBudget = 36
    /// Batteries are honest: a small internal resistance, so even a
    /// dead-short misbehaves physically instead of exploding the math.
    nonisolated static let batteryInternalResistance = 0.05
    /// Terminals sit at ±x on every component.
    nonisolated static let terminalOffset = 0.085

    // MARK: Components

    enum ComponentKind: String, CaseIterable, Identifiable, Codable {
        // Declaration order is drawer order: power, passives, outputs,
        // control, wire.
        case battery, acSource, resistor, capacitor, inductor
        case bulb, led, motor, fuse, switcher, wire

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .battery: "Battery"
            case .acSource: "AC Source"
            case .resistor: "Resistor"
            case .capacitor: "Capacitor"
            case .inductor: "Inductor"
            case .bulb: "Bulb"
            case .led: "LED"
            case .motor: "Motor"
            case .fuse: "Fuse"
            case .switcher: "Switch"
            case .wire: "Wire"
            }
        }

        var defaultValue: Double {
            switch self {
            case .battery: 9.0        // V
            case .acSource: 6.0       // V amplitude (0.5 Hz)
            case .resistor: 470.0     // Ω
            case .capacitor: 2.2e-3   // F
            case .inductor: 0.5       // H
            case .bulb: 24.0          // Ω
            case .led: 0              // fixed 2 V drop, 12 Ω on
            case .motor: 8.0          // Ω coil resistance
            case .fuse: 1.0           // A rating
            case .switcher: 0
            case .wire: 0.25          // m — a wire's value is its length
            }
        }
    }

    // LED physics: a red LED's forward drop and on-resistance, and the
    // current beyond which it burns out (real 5 mm LEDs die ~30 mA+).
    nonisolated static let ledForwardDrop = 2.0
    nonisolated static let ledOnResistance = 12.0
    nonisolated static let ledMaxAmps = 0.03
    /// The AC source's fixed frequency — slow enough to watch.
    nonisolated static let acFrequency = 0.5

    // A real DC motor: back-EMF and torque share the constant k (V·s/rad
    // = N·m/A). The coil resistance is the component's value. Steady
    // speed with no load settles at ω = kV/(bR + k²) — proportional to
    // the applied voltage, the property the tests pin.
    nonisolated static let motorTorqueConstant = 0.06
    nonisolated static let motorFriction = 0.0008
    nonisolated static let motorInertia = 0.0009

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
    /// How near two terminals must come to snap together — generous so
    /// bringing parts close is enough (they magnetise).
    nonisolated static let snapDistance = 0.13
    /// Carry a part until a snapped connection stretches past this and
    /// it pops off — the same magnet, in reverse.
    nonisolated static let breakDistance = 0.3

    nonisolated static func wireResistance(length: Double) -> Double {
        max(length, 0.01) * wireOhmsPerMeter
    }

    struct Terminal: Equatable, Hashable, Codable {
        var componentID: UUID
        var end: Int  // 0 = left (battery +), 1 = right
    }

    struct Component: Identifiable, Equatable, Codable {
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
        /// Failure simulation (burned LED, blown fuse) — transient,
        /// never persisted; Replace on the readout clears it.
        var failed = false
        /// Inductors only: the integrated state — transient.
        var inductorCurrent = 0.0
        /// Motors only: the spin speed (rad/s) — transient, integrated
        /// each step from torque against back-EMF and friction.
        var motorSpeed = 0.0

        private enum CodingKeys: String, CodingKey {
            case id, kind, position, value, axis, isClosed, capacitorVoltage
        }

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

    struct Wire: Identifiable, Equatable, Codable {
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

    // MARK: True speed — the thirteen orders of magnitude

    /// Shows the drift at its REAL relative rate: electrons frozen,
    /// the field front racing. Every circuit animation ever drawn —
    /// including this app's default — marches the dots along at a
    /// speed chosen to look good, which teaches the exact opposite of
    /// the truth. This mode tells it.
    var trueSpeedMode = false

    /// A conventional hookup wire: 1 mm radius copper.
    nonisolated static let wireRadius = 1e-3

    /// Largest current anywhere in the circuit, amps — what the drift
    /// readout describes.
    var peakCurrent: Double {
        let wireMax = wireFlows.values.map(abs).max() ?? 0
        let partMax = readouts.values.map { abs($0.amps) }.max() ?? 0
        return max(wireMax, partMax)
    }

    /// Drift speed of the electrons at that current, m/s.
    var driftSpeed: Double {
        ChargeTransport.driftSpeed(current: peakCurrent, wireRadius: Self.wireRadius)
    }

    /// The loop an electron would have to walk, metres — the summed
    /// length of every carrying wire, in the bench's own display
    /// metres, which is what the user is actually looking at.
    var conductingPathLength: Double {
        var total = 0.0
        for wire in wires where abs(wireFlows[wire.id] ?? 0) > 5e-4 {
            guard let a = terminalWorldPosition(wire.from),
                  let b = terminalWorldPosition(wire.to) else { continue }
            total += simd_distance(a, b)
        }
        return total
    }

    /// How long one electron takes to go round, seconds, and how long
    /// the field takes over the same path. The two numbers whose
    /// ratio is the whole lesson.
    var driftLapTime: Double {
        ChargeTransport.traversalTime(length: conductingPathLength, speed: driftSpeed)
    }

    var signalLapTime: Double {
        ChargeTransport.traversalTime(length: conductingPathLength,
                                      speed: ChargeTransport.signalSpeed())
    }
    var isPaused = false
    /// The contextual one-liner shown after loading a premade circuit.

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
        persistSoon()
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
        persistSoon()
    }

    func select(id: UUID) {
        if id != selectedID { scopeSamples = [] }
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

    /// The pairs a release right now would wire up — the renderer draws
    /// these as ghost wires while a part is carried, so the release
    /// never surprises: what you preview is what you get.
    func autoConnectCandidates(id: UUID) -> [(from: Terminal, to: Terminal)] {
        guard let component = components.first(where: { $0.id == id }) else { return [] }
        var pairs: [(from: Terminal, to: Terminal)] = []
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
                pairs.append((mine, best.terminal))
            }
        }
        return pairs
    }

    /// Magnetic connections: when a part is released, any of its
    /// terminals sitting within snapDistance of another part's free-ish
    /// terminal wires itself up — bring parts together and they connect.
    func autoConnect(id: UUID) {
        let pairs = autoConnectCandidates(id: id)
        guard !pairs.isEmpty,
              let component = components.first(where: { $0.id == id }) else { return }
        for pair in pairs {
            wires.append(Wire(id: UUID(), from: pair.from, to: pair.to))
        }
        emitSound(.chime, at: component.position, volume: 0.5)
        persistSoon()
    }

    // MARK: Pull-apart detach (the magnet, in reverse)

    /// Wires short enough at grab time to count as "snapped contacts"
    /// — only these pop when stretched, so a deliberately long span
    /// wire is never yanked off by moving a neighbour.
    private var poppableWires: Set<UUID> = []

    private func terminalWorldPosition(_ terminal: Terminal) -> SIMD3<Double>? {
        components.first { $0.id == terminal.componentID }?
            .terminalPosition(terminal.end)
    }

    /// The current end-to-end length of a wire in the room.
    func wireLength(_ wire: Wire) -> Double {
        guard let a = terminalWorldPosition(wire.from),
              let b = terminalWorldPosition(wire.to) else { return 0 }
        return simd_distance(a, b)
    }

    /// Call when a part starts being carried or stretched: remember
    /// which of its connections are short contacts (poppable).
    func beginCarry(id: UUID) {
        poppableWires = Set(wires.filter { wire in
            (wire.from.componentID == id || wire.to.componentID == id)
                && wireLength(wire) < Self.breakDistance
        }.map(\.id))
    }

    /// Call while carrying: any poppable contact stretched past the
    /// break distance snaps off, with a thunk. Bring the part back and
    /// it re-snaps on release.
    func breakOverstretchedWires(id: UUID) {
        guard !poppableWires.isEmpty else { return }
        let snapped = wires.filter {
            poppableWires.contains($0.id) && wireLength($0) > Self.breakDistance
        }
        guard !snapped.isEmpty else { return }
        for wire in snapped {
            wires.removeAll { $0.id == wire.id }
            poppableWires.remove(wire.id)
        }
        if let component = components.first(where: { $0.id == id }) {
            emitSound(.thud, at: component.position, volume: 0.5)
        }
        persistSoon()
    }

    func endCarry() { poppableWires.removeAll() }

    /// Detach a whole component at once — every wire touching it drops.
    /// The clean "take it out of the circuit" action for the readout.
    func detachComponent(id: UUID) {
        let touching = wires.filter {
            $0.from.componentID == id || $0.to.componentID == id
        }
        guard !touching.isEmpty else { return }
        wires.removeAll { wire in touching.contains { $0.id == wire.id } }
        if let component = components.first(where: { $0.id == id }) {
            emitSound(.thud, at: component.position, volume: 0.5)
        }
        persistSoon()
    }

    /// Direct terminal-to-terminal wiring — the drag-to-wire gesture's
    /// landing. Same rules as tap-tap: no self-wires, no duplicates.
    func connectTerminals(_ a: Terminal, _ b: Terminal) {
        guard a != b,
              components.contains(where: { $0.id == a.componentID }),
              let target = components.first(where: { $0.id == b.componentID })
        else { return }
        let exists = wires.contains {
            ($0.from == a && $0.to == b) || ($0.from == b && $0.to == a)
        }
        guard !exists, wires.count < Self.wireBudget else { return }
        wires.append(Wire(id: UUID(), from: a, to: b))
        pendingTerminal = nil
        emitSound(.pop, at: target.terminalPosition(b.end), volume: 0.8)
        persistSoon()
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

    nonisolated static func clampToBench(
        _ point: SIMD3<Double>
    ) -> SIMD3<Double> {
        var clamped = simd_clamp(point,
                                 buildCenter - buildHalfExtents,
                                 buildCenter + buildHalfExtents)
        clamped.y = max(clamped.y, floorMargin)
        return clamped
    }

    private func clamp(_ point: SIMD3<Double>) -> SIMD3<Double> {
        Self.clampToBench(point)
    }

    // MARK: Wiring (tap one terminal, then another)

    func tapTerminal(_ terminal: Terminal) {
        guard components.contains(where: { $0.id == terminal.componentID }) else { return }
        guard let pending = pendingTerminal else {
            pendingTerminal = terminal
            return
        }
        defer { pendingTerminal = nil }
        // The PENDING end is re-validated too, not just the new one.
        // Belt and braces against the zombie wire above: `removeComponent`
        // clears the arming, and this refuses to build a wire onto a
        // part that has gone however it went.
        guard components.contains(where: { $0.id == pending.componentID }) else { return }
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
        persistSoon()
    }

    func deleteWire(id: UUID) {
        guard let wire = wires.first(where: { $0.id == id }) else { return }
        wires.removeAll { $0.id == id }
        if let component = components.first(where: { $0.id == wire.from.componentID }) {
            emitSound(.thud, at: component.terminalPosition(wire.from.end), volume: 0.3)
        }
        persistSoon()
    }

    func toggleSwitch(id: UUID) {
        guard let index = components.firstIndex(where: { $0.id == id }),
              components[index].kind == .switcher else { return }
        components[index].isClosed.toggle()
        selectedID = id
        emitSound(.thud, at: components[index].position, volume: 0.5)
        persistSoon()
    }

    /// True when the part has at least one wire on it.
    func isWired(id: UUID) -> Bool {
        wires.contains {
            $0.from.componentID == id || $0.to.componentID == id
        }
    }

    // MARK: Per-component edits — what the Bloom calls

    /// The range a part's value may be pulled across, and the unit it
    /// reads in. A component's value has no size of its own, so the
    /// grip's honesty comes from the CONSEQUENCE: pull a bulb's
    /// resistance up and it visibly dims, pull a battery's volts up and
    /// the electron drift quickens. You watch the circuit answer.
    static func valueRange(for kind: ComponentKind) -> ClosedRange<Double> {
        switch kind {
        case .battery, .acSource: 1.0...24.0        // V
        case .resistor: 10.0...4700.0               // Ω
        case .capacitor: 1e-4...1e-2                // F
        case .inductor: 0.05...5.0                  // H
        case .bulb: 4.0...240.0                     // Ω
        case .motor: 1.0...60.0                     // Ω
        case .fuse: 0.05...5.0                      // A
        case .wire: 0.08...0.9                      // m
        case .led, .switcher: 0...0
        }
    }

    static func formatValue(_ value: Double, for kind: ComponentKind) -> String {
        switch kind {
        case .battery, .acSource: PhysicsFormat.measurement(value, "V", decimals: 1)
        case .resistor, .bulb, .motor: value >= 1000
            ? PhysicsFormat.measurement(value / 1000, "k\u{03A9}", decimals: 1)
            : PhysicsFormat.measurement(value, "\u{03A9}", decimals: 0)
        // THIS PRINTED "0 mF" AT THE BOTTOM OF THE CAPACITOR'S OWN RAIL
        // while the bench label beside it said "100 µF".
        //
        // `%.0f` of `value * 1000` for a 100 µF part is 0.1 rounded to
        // zero, and the whole usable range of this component — the rail
        // spans microfarads — rounds to the same "0 mF". So the one
        // readout telling you what you had just dialled in was a
        // constant, and it disagreed with the label on the part.
        // `PhysicsFormat.metric` picks the prefix from the magnitude,
        // which is what the rest of the app already does.
        case .capacitor: PhysicsFormat.metric(value, "F", decimals: 0)
        case .inductor: PhysicsFormat.measurement(value, "H", decimals: 2)
        case .fuse: PhysicsFormat.measurement(value, "A", decimals: 2)
        case .wire: PhysicsFormat.measurement(value * 100, "cm", decimals: 0)
        case .led, .switcher: ""
        }
    }

    func componentValue(id: UUID) -> Double {
        components.first(where: { $0.id == id })?.value ?? 0
    }

    func setComponentValue(id: UUID, _ value: Double) {
        guard let index = components.firstIndex(where: { $0.id == id }) else { return }
        let range = Self.valueRange(for: components[index].kind)
        guard range.upperBound > range.lowerBound else { return }
        components[index].value = min(max(value, range.lowerBound), range.upperBound)
        persistSoon()
    }

    func removeComponent(id: UUID) {
        components.removeAll { $0.id == id }
        wires.removeAll { $0.from.componentID == id || $0.to.componentID == id }
        if selectedID == id { selectedID = components.last?.id }
        // A HALF-DRAWN WIRE CANNOT SURVIVE ITS OWN PART.
        //
        // Pinch a terminal (which arms it), open that part's ring, tap
        // Delete: `pendingTerminal` still named the destroyed part, and
        // the next terminal tap anywhere on the bench appended a `Wire`
        // whose `from` component does not exist. It is invisible
        // (`isEnabled = false`), therefore un-pinchable and impossible
        // to remove, permanently consumes one of the 36 budget slots,
        // and is written straight to `UserDefaults` — so it survives
        // relaunches. `connectTerminals` validated both ends; this, the
        // path the Bloom's Delete petal actually calls, cleared neither.
        if pendingTerminal?.componentID == id { pendingTerminal = nil }
        persistSoon()
    }

    // MARK: Selected-component value editing

    var selectedValue: Double {
        get { selectedComponent?.value ?? 0 }
        set {
            guard let index = components.firstIndex(where: { $0.id == selectedID }) else { return }
            components[index].value = newValue
            persistSoon()
        }
    }

    // `selectedIsWired` and `selectedIsClosed` were deleted 2026-08-09.
    // Both were read only by `CircuitsInsightCard`, which the owner
    // deleted the same week under the rule that a paragraph is the
    // wrong shape for this room. `isWired(id:)` above is the live form
    // and the Bloom asks it about the part in your hand; a switch's
    // state is read off the switch, which is a thing on the bench with
    // a lever, not a property of "the selection".

    // MARK: The solve (every frame)

    /// One frame of the wearer's experience: solve, then record.
    ///
    /// This model is the odd one out twice over. Its solve runs every
    /// frame even while paused, so a frozen bench still shows honest
    /// readouts — so only unpaused frames belong in the recording. And
    /// it solves ONCE IMMEDIATELY whenever the bench changes (seeding,
    /// restoring a saved bench, loading a demo), so the first frame is
    /// never dark; those priming solves call `solve` directly and are
    /// deliberately not recorded, because nobody watched them happen.
    func step(dt: Double) {
        let isRecordingFrame = !isPaused
        solve(dt: dt)
        if isRecordingFrame {
            recordCapsuleFrame(dt: min(max(dt, 1e-4), 1.0 / 30.0))
        }
    }

    private func solve(dt: Double) {
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
        if !isPaused { simTime += timeStep }
        let elements = components.map { component -> CircuitElement in
            let a = node(Terminal(componentID: component.id, end: 0))
            let b = node(Terminal(componentID: component.id, end: 1))
            let kind: CircuitElement.Kind = switch component.kind {
            case .battery:
                .battery(volts: component.value,
                         internalResistance: Self.batteryInternalResistance)
            case .acSource:
                .battery(volts: component.value
                            * sin(2 * .pi * Self.acFrequency * simTime),
                         internalResistance: Self.batteryInternalResistance)
            case .resistor, .bulb:
                .resistor(ohms: component.value)
            case .capacitor:
                .capacitor(farads: component.value,
                           previousVoltage: component.capacitorVoltage)
            case .inductor:
                .inductor(henries: component.value,
                          previousCurrent: component.inductorCurrent)
            case .motor:
                // The coil (its value) in series with a back-EMF source
                // of k·ω opposing the drive — a battery companion whose
                // EMF is the motor's own spin (from the last step).
                .battery(volts: Self.motorTorqueConstant * component.motorSpeed,
                         internalResistance: max(component.value, 0.1))
            case .led:
                component.failed
                    ? .open
                    : .diode(forwardDrop: Self.ledForwardDrop,
                             onResistance: Self.ledOnResistance,
                             isConducting: false)
            case .fuse:
                component.failed ? .open : .resistor(ohms: 0.001)
            case .switcher:
                component.isClosed ? .conductor : .open
            case .wire:
                .resistor(ohms: Self.wireResistance(length: component.value))
            }
            return CircuitElement(nodeA: a, nodeB: b, kind: kind)
        }
        // 3b. THE METER, AS AN ELEMENT. Until 2026-08-08 A⎓ read the
        // current of whichever component the probes bracketed, which is
        // the opposite of what an ammeter does: put it across a broken
        // switch — the correct placement, the loop deliberately open —
        // and it reported the switch's own current, exactly 0.000 A. The
        // meter was never in the network, and no current can flow
        // through a meter that is not there.
        //
        // It is stamped only in A⎓ and only across two DIFFERENT nodes.
        // In V⎓ an ammeter's shunt would short whatever it was measuring,
        // and across one node it would be a loop of itself.
        var meterElementIndex: Int?
        var stamped = elements
        if multimeterArmed, meterMode == .ampsDC,
           let probeA, let probeB {
            let a = node(probeA), b = node(probeB)
            if a != b {
                meterElementIndex = stamped.count
                stamped.append(CircuitElement(
                    nodeA: a, nodeB: b,
                    kind: .resistor(ohms: Self.ammeterShuntOhms)))
            }
        }
        let solution = CircuitSolver.solveWithDiodes(
            elements: stamped, nodeCount: nodeCount, timeStep: timeStep).solution
        meterCurrent = meterElementIndex.map { solution.currents[$0] }

        // Terminal voltages for the warm↔cool gradient the renderer
        // paints across the bench.
        var terminalVolts: [Terminal: Double] = [:]
        for component in components {
            for end in 0...1 {
                let terminal = Terminal(componentID: component.id, end: end)
                terminalVolts[terminal] = solution.nodeVoltages[node(terminal)]
            }
        }
        terminalVoltages = terminalVolts
        let span = solution.nodeVoltages.dropFirst()
        voltageSpan = (min(span.min() ?? 0, 0), max(span.max() ?? 0, 0))

        // Node potentials with a representative position (the centroid
        // of the node's terminals) — the voltage skyline reads these:
        // each node's potential becomes a height you can compare, so
        // Kirchhoff's loop law becomes a walk over the terrain.
        var nodeAccum: [Int: (sum: SIMD3<Double>, count: Int)] = [:]
        for component in components {
            for end in 0...1 {
                let nd = node(Terminal(componentID: component.id, end: end))
                let pos = component.terminalPosition(end)
                let current = nodeAccum[nd] ?? (.zero, 0)
                nodeAccum[nd] = (current.sum + pos, current.count + 1)
            }
        }
        nodePotentials = nodeAccum.map { (nd, acc) in
            NodePotential(position: acc.sum / Double(acc.count),
                          voltage: solution.nodeVoltages[nd])
        }

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
            if component.kind == .inductor, !isPaused {
                components[index].inductorCurrent = solution.currents[index]
            }
            if component.kind == .motor, !isPaused {
                // Torque from the coil current spins the rotor up against
                // friction; the resulting speed feeds back as next step's
                // back-EMF. τ = kI − bω,  ω += τ/J · dt.
                let current = solution.currents[index]
                let torque = Self.motorTorqueConstant * current
                    - Self.motorFriction * components[index].motorSpeed
                components[index].motorSpeed += torque / Self.motorInertia * timeStep
            }
            if !isPaused, !component.failed {
                let amps = abs(solution.currents[index])
                if component.kind == .led, amps > Self.ledMaxAmps {
                    components[index].failed = true
                    emitSound(.boom, at: component.position, volume: 0.35)
                } else if component.kind == .fuse, amps > component.value {
                    components[index].failed = true
                    emitSound(.pop, at: component.position, volume: 0.8)
                }
            }
        }
        readouts = newReadouts
        totalSourcePower = sourcePower
        if !isPaused, let selectedID, let readout = newReadouts[selectedID],
           simTime - lastScopeSample >= 1.0 / 60.0 {
            lastScopeSample = simTime
            scopeSamples.append((simTime, readout.volts, readout.amps))
            if scopeSamples.count > Self.scopeCapacity {
                scopeSamples.removeFirst(scopeSamples.count - Self.scopeCapacity)
            }
        }

        // 5. Wire currents for the electron flow: each terminal's element
        // current fans out evenly over its wires (a visualization choice;
        // parallel wires between the same nodes share indistinguishably).
        // TWO LOOKUP TABLES, BUILT ONCE, instead of two linear scans per
        // terminal per wire.
        //
        // `outflow` used to call `components.firstIndex(where:)` and
        // `wires.filter { … }.count` — and it is called twice per wire,
        // so the fan-out alone was O(W²) with a fresh array allocated
        // for every one of those counts. All of it inside `solve`,
        // which runs every frame INCLUDING while paused, by design, so
        // a frozen bench paid it too.
        //
        // Both answers are facts about the bench GRAPH, and the graph is
        // the same for every wire in a given solve.
        var componentIndex: [UUID: Int] = [:]
        componentIndex.reserveCapacity(components.count)
        for (index, component) in components.enumerated() {
            componentIndex[component.id] = index
        }
        var fanOut: [Terminal: Int] = [:]
        fanOut.reserveCapacity(wires.count * 2)
        for wire in wires {
            fanOut[wire.from, default: 0] += 1
            fanOut[wire.to, default: 0] += 1
        }

        var flows: [UUID: Double] = [:]
        flows.reserveCapacity(wires.count)
        for wire in wires {
            func outflow(_ terminal: Terminal) -> Double {
                guard let index = componentIndex[terminal.componentID] else { return 0 }
                let current = solution.currents[index]
                let directed = terminal.end == 1 ? current : -current
                return directed / Double(max(fanOut[terminal] ?? 1, 1))
            }
            flows[wire.id] = (outflow(wire.from) - outflow(wire.to)) / 2
        }
        wireFlows = flows
    }

    // MARK: Instruments

    /// Oscilloscope: a scrolling window of the selected part's voltage
    /// and current, sampled at 60 Hz of simulated time.
    private(set) var scopeSamples: [(time: Double, volts: Double, amps: Double)] = []
    private var lastScopeSample = -1.0
    nonisolated static let scopeCapacity = 300   // 5 s at 60 Hz

    /// Multimeter: arm it, then tap any two terminals. Red probe first.
    var multimeterArmed = false {
        didSet { if !multimeterArmed { probeA = nil; probeB = nil } }
    }
    /// THE AMMETER'S OWN RESISTANCE, stamped into the network so that
    /// current can flow THROUGH it.
    ///
    /// A real bench ammeter is a shunt of a few milliohms — low enough
    /// not to disturb the circuit it measures, high enough to be a real
    /// element. 1 mΩ against this bench's smallest other resistance
    /// (`wireResistance`, tens of mΩ) changes the loop current by well
    /// under a percent, which is the whole design requirement for an
    /// ammeter.
    ///
    /// NOT `.conductor`: a perfect short carries a current the solver
    /// reports through whichever parallel path it likes, and the meter
    /// would read an arbitrary share of it. A resistance makes the
    /// answer unique.
    static let ammeterShuntOhms = 0.001


    /// What the meter measured on the last step, amps — `nil` unless it
    /// was actually in the network.
    private(set) var meterCurrent: Double?

    private(set) var probeA: Terminal?
    private(set) var probeB: Terminal?

    /// Which lead. Red is A, black is B — the convention every meter
    /// prints on its own jacks, and the reason a voltage reads positive
    /// when red is on the higher potential.
    enum ProbeSlot { case red, black }

    /// Parks a probe on a terminal, or lifts it off with nil.
    ///
    /// This is how the PROBES set the measurement now: you carry a probe
    /// to a terminal and its tip latches on. `probeTap` below survives
    /// for the accessibility path, where there is no hand to carry
    /// anything with.
    func setProbe(_ slot: ProbeSlot, to terminal: Terminal?) {
        switch slot {
        case .red:
            guard probeA != terminal else { return }
            probeA = terminal
        case .black:
            guard probeB != terminal else { return }
            probeB = terminal
        }
        if let terminal,
           let component = components.first(where: { $0.id == terminal.componentID }) {
            emitSound(.pop, at: component.terminalPosition(terminal.end), volume: 0.4)
        }
    }

    /// The terminal nearest `point`, if one is within `radius`.
    func nearestTerminal(to point: SIMD3<Double>,
                         within radius: Double) -> Terminal? {
        var best: (terminal: Terminal, distance: Double)?
        for component in components {
            for end in 0...1 {
                let distance = simd_distance(point, component.terminalPosition(end))
                guard distance <= radius else { continue }
                if best == nil || distance < best!.distance {
                    best = (Terminal(componentID: component.id, end: end), distance)
                }
            }
        }
        return best?.terminal
    }

    /// A tap while the meter is armed lands a probe (A, then B, then
    /// back to A — walk the probes around the circuit freely).
    func probeTap(_ terminal: Terminal) {
        if probeA == nil || probeB != nil {
            probeA = terminal
            probeB = nil
        } else if terminal != probeA {
            probeB = terminal
        }
        if let component = components.first(where: { $0.id == terminal.componentID }) {
            emitSound(.pop, at: component.terminalPosition(terminal.end), volume: 0.5)
        }
    }

    /// What the dial is pointing at.
    ///
    /// Four positions, which is what a meter of this class actually has.
    /// They are genuinely different measurements rather than four
    /// formats of one number — and one of them, current, cannot honestly
    /// be taken the way the other three can. See `MultimeterReading`.
    enum MeterMode: String, CaseIterable, Codable {
        case voltsDC
        case ampsDC
        case ohms
        case continuity

        var label: String {
            switch self {
            case .voltsDC: "V⎓"
            case .ampsDC: "A⎓"
            case .ohms: "Ω"
            case .continuity: "•)))"
            }
        }

        var longLabel: String {
            switch self {
            case .voltsDC: "DC volts"
            case .ampsDC: "DC current"
            case .ohms: "Resistance"
            case .continuity: "Continuity"
            }
        }
    }

    var meterMode: MeterMode = .voltsDC

    struct MultimeterReading {
        /// What the display shows, already formatted and ranged.
        var display: String
        /// The one line under it — a unit, or the reason there is no
        /// number. This is where the instrument is honest about itself.
        var note: String
        /// Continuity mode only: whether it should be beeping.
        var beeping: Bool = false
        /// True when the meter is being asked to do something a real one
        /// would object to. Drives the display's colour.
        var fault: Bool = false
    }

    /// Everything the meter can say, by mode.
    ///
    /// THE AMMETER IS THE HONEST ONE, and it is the reason this is four
    /// modes rather than one readout. A voltmeter goes ACROSS a
    /// component and barely disturbs it; an ammeter has to go IN SERIES,
    /// because the current it reports is the current flowing THROUGH it.
    /// Touching an ammeter's probes across a component that is already
    /// carrying current puts a near-zero resistance in parallel with it —
    /// a short, and in a real lab a blown fuse. That mistake is one of
    /// the most common in an introductory lab, and a simulated meter
    /// that silently printed the right number for it would be teaching
    /// the mistake.
    ///
    /// So: A⎓ reports a current only when the probes bracket a component
    /// whose circuit is otherwise BROKEN — the meter completing the loop
    /// is the meter being in series. Across a live component it says so
    /// instead of answering.
    var multimeterReading: MultimeterReading? {
        guard let probeA, let probeB else { return nil }
        guard let vA = terminalVoltages[probeA],
              let vB = terminalVoltages[probeB] else { return nil }

        let bracketsOneComponent = probeA.componentID == probeB.componentID
            && probeA.end != probeB.end
        let component = components.first { $0.id == probeA.componentID }
        let sameNode = abs(vA - vB) < 1e-3 && isProbePairConnected(probeA, probeB)

        switch meterMode {
        case .voltsDC:
            return MultimeterReading(
                display: Self.autoRange(vA - vB, unit: "V"),
                note: bracketsOneComponent && component != nil
                    ? "across the \(component!.kind.displayName)"
                    : "between the probes")

        case .ampsDC:
            // READ THE METER, NOT THE COMPONENT. This branch used to
            // return `readouts[probed component].amps`, which is the
            // opposite of what an ammeter does — put it across a broken
            // switch, the correct placement with the loop deliberately
            // open, and it reported the switch's own current: exactly
            // 0.000 A, every time. Audit P1-20 called that "two
            // reachable outputs, FUSE and zero" and blamed a threshold;
            // the threshold was innocent and the meter simply was not in
            // the circuit. It is stamped as a real shunt now (see
            // `ammeterShuntOhms`) and this reads what flows through it.
            // THE GUARD COMES FIRST, AND IT DOES NOT USE THE STAMP.
            //
            // Whether the probes are bracketing something live is a
            // question about the COMPONENT, answerable the instant a
            // probe lands. The stamped current only exists after a
            // solve, so a guard that waited for it would print "— — —"
            // for a frame — and, worse, would answer wrongly for any
            // caller reading this property without stepping first.
            // Making the guard depend on the stamp broke
            // `testAmpsModeRefusesToBePutAcrossALiveComponent` on the
            // first run, which is precisely what that test is for.
            let bracketed = bracketsOneComponent
                ? readouts[probeA.componentID]?.amps : nil
            if bracketsOneComponent, let component, let bracketed,
               abs(bracketed) > CircuitSolver.liveCurrentThreshold(volts: vA - vB) {
                return MultimeterReading(
                    display: "FUSE",
                    note: "the \(component.kind.displayName) is live — probes "
                        + "across it would short it. Break the loop first.",
                    fault: true)
            }
            // AND THE READING IS THE METER'S OWN CURRENT — the half that
            // actually changed. Nil means the probes are not across two
            // different nodes, so there is nothing for a series meter to
            // be in.
            guard let amps = meterCurrent else {
                return MultimeterReading(
                    display: "— — —",
                    note: "an ammeter goes IN SERIES: break the loop and "
                        + "put both probes across the gap",
                    fault: true)
            }
            return MultimeterReading(
                display: Self.autoRange(amps, unit: "A"),
                note: bracketsOneComponent && component != nil
                    ? "in series with the \(component!.kind.displayName)"
                    : "in series, between the probes")

        case .ohms:
            guard bracketsOneComponent, let component else {
                return MultimeterReading(
                    display: "— — —",
                    note: "put both probes across one component",
                    fault: true)
            }
            if abs(totalSourcePower) > 1e-6 {
                return MultimeterReading(
                    display: "— — —",
                    note: "the circuit is live: an ohmmeter drives its own "
                        + "current, so switch the source off first",
                    fault: true)
            }
            guard let ohms = Self.resistance(of: component) else {
                return MultimeterReading(
                    display: "OL",
                    note: "no resistive path across the "
                        + "\(component.kind.displayName)")
            }
            return MultimeterReading(
                display: Self.autoRange(ohms, unit: "Ω"),
                note: "across the \(component.kind.displayName)")

        case .continuity:
            // A real meter beeps below a few tens of ohms. Same node
            // through copper is zero, which is what a bench beeps at.
            let ohms = bracketsOneComponent
                ? (component.flatMap(Self.resistance) ?? .infinity) : .infinity
            let connected = sameNode || ohms < Self.continuityThreshold
            return MultimeterReading(
                display: connected ? "•)))" : "OL",
                note: connected ? "connected" : "open",
                beeping: connected)
        }
    }

    /// A meter beeps below this. Real ones sit between 20 and 50 Ω.
    nonisolated static let continuityThreshold = 50.0

    /// The resistance a component presents, ohms — nil where the idea
    /// does not apply.
    ///
    /// A capacitor is deliberately absent rather than infinite: its
    /// opposition to current is a REACTANCE that depends on frequency,
    /// and calling it a resistance would be the kind of quiet
    /// simplification this app exists not to make.
    nonisolated static func resistance(of component: Component) -> Double? {
        switch component.kind {
        case .resistor: component.value
        case .bulb, .led, .motor: component.value
        case .wire: wireResistance(length: component.value)
        case .switcher: component.isClosed ? 0.001 : nil
        case .fuse: component.failed ? nil : 0.001
        case .battery, .acSource: nil
        case .capacitor, .inductor: nil
        }
    }

    /// Auto-ranging, the way a real display does it: milli, then unit,
    /// then kilo, always three significant figures.
    nonisolated static func autoRange(_ value: Double, unit: String) -> String {
        // GRAVE, 2026-08-08: this was a fourth hand-rolled SI prefixer —
        // milli below 1, base to 999.5, kilo above — sitting beside the
        // three the app had already consolidated into
        // `PhysicsFormat.metric`. Its bands were the same bands and its
        // rounding was its own, which is how "the same quantity spelled
        // two ways in the same module" happens.
        //
        // The one behaviour worth keeping is the zero: a meter reading
        // "0 A" and one reading nothing are different claims, and this
        // one says the reading IS zero.
        guard abs(value) > 1e-9 else { return "0.000 " + unit }
        // THREE DECIMALS IN EVERY BAND, where the hand-rolled version
        // used one for milli, three for the base unit and two for kilo.
        // No bench meter does that: a 3½-digit DMM shows the same
        // resolution wherever the range lands, which is the whole point
        // of auto-ranging. So this is a small display change and a
        // correction — "4.200 mA" rather than "4.2 mA".
        return PhysicsFormat.metric(value, unit, decimals: 3)
    }

    /// True when the two probes share a node through wires alone.
    private func isProbePairConnected(_ a: Terminal, _ b: Terminal) -> Bool {
        var frontier = [a]
        var seen: Set<Terminal> = [a]
        while let current = frontier.popLast() {
            if current == b { return true }
            for wire in wires {
                let next: Terminal?
                if wire.from == current { next = wire.to }
                else if wire.to == current { next = wire.from }
                else { next = nil }
                if let next, !seen.contains(next) {
                    seen.insert(next)
                    frontier.append(next)
                }
            }
        }
        return false
    }

    // MARK: Workshop state

    /// The AC sources' shared clock.
    private(set) var simTime = 0.0

    // MARK: Time Capsule

    @ObservationIgnored var capsule = TimeCapsule<CapsuleSnapshot>()
    @ObservationIgnored var capsuleClock = 0.0
    var scrubTime: Double?
    var scrubNonce = 0
    /// Live node voltages by terminal, for the voltage-gradient wires.
    private(set) var terminalVoltages: [Terminal: Double] = [:]
    private(set) var voltageSpan: (min: Double, max: Double) = (0, 0)

    /// A circuit node's potential and where it sits — the voltage
    /// skyline draws a tower of this height at this spot.
    struct NodePotential: Equatable {
        var position: SIMD3<Double>
        var voltage: Double
    }
    private(set) var nodePotentials: [NodePotential] = []
    /// The signature 3-D view: raise every node to a height equal to
    /// its voltage, so potential becomes terrain.
    var showVoltageHeights = false

    /// Draw the magnetic field the bench's own current makes.
    ///
    /// This is what replaced the electromagnet annex (2026-08-02). The
    /// annex answered "a current is a magnet" by standing a SECOND
    /// apparatus in the room and cabling to it; this answers the same
    /// question with the bench you already built, which is both the
    /// smaller claim and the truer one — every wire here has a field
    /// around it, not just the one wound into a coil.
    var showMagneticField = false
    /// The Electron View toggle: the whole bench swells around the user.
    var electronView = false
    /// The latest failure explanation (shown until the part is replaced).

    /// Puts a burned/blown part back in service.
    func replaceFailed(id: UUID) {
        guard let index = components.firstIndex(where: { $0.id == id }) else { return }
        components[index].failed = false
        emitSound(.chime, at: components[index].position, volume: 0.5)
    }

    // THE RUNNING COMMENTARY IS GONE (owner, 2026-08-09).
    //
    // `insightText` was set in twelve places — the capacitor's charge
    // percentage, whichever component was dissipating the most power,
    // what Electron View is really showing, why a fuse blew, and a
    // paragraph for each of the five presets — and drawn on a dark card
    // floating above the bench. `insightClock`, `insightHoldUntil`, the
    // twelve-second `hold` that stopped the live line overwriting an
    // authored one, and `failureNote` were all machinery for that one
    // surface, and they go with it.
    //
    // It had a real argument for existing: unlike the first-run hint it
    // said something DIFFERENT each time, about the circuit you had just
    // built, and it vanished when there was nothing to say. Its own
    // header set the condition for its removal — "if it ever repeats
    // itself it is behaving like the hint and should go the same way" —
    // and the owner's call is that a paragraph hanging over the bench is
    // the wrong shape for this app whether or not it repeats. The
    // readouts on the parts say what the circuit is doing; they are
    // attached to the thing they describe, which the card never was.

    // MARK: Persistence (the bench survives relaunch)

    private struct SavedBench: Codable {
        var components: [Component]
        var wires: [Wire]
    }

    nonisolated static let saveKey = "circuits.savedBench.v1"
    private var persistTask: Task<Void, Never>?

    /// Debounced save: edits within a second collapse into one write.
    private func persistSoon() {
        persistTask?.cancel()
        persistTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.persistNow()
        }
    }

    /// Immediate save (internal so tests can force it).
    func persistNow() {
        // Never save a scrubbed bench. While the room is frozen in its
        // own past, `components` and `wires` hold a RECORDED topology —
        // saving it would let a rewind you were only inspecting become
        // the bench you find on next launch.
        guard scrubTime == nil else { return }
        let bench = SavedBench(components: components, wires: wires)
        if let data = try? JSONEncoder().encode(bench) {
            UserDefaults.standard.set(data, forKey: Self.saveKey)
        }
    }

    /// Installs a decoded bench after sanity checks: budget respected,
    /// orphaned wires dropped.
    @discardableResult
    private func apply(_ bench: SavedBench) -> Bool {
        guard !bench.components.isEmpty,
              bench.components.count <= Self.componentBudget else { return false }
        components = bench.components
        wires = bench.wires.filter { wire in
            bench.components.contains { $0.id == wire.from.componentID }
                && bench.components.contains { $0.id == wire.to.componentID }
        }
        selectedID = nil
        pendingTerminal = nil
        solve(dt: 1.0 / 90.0)
        return true
    }

    /// Restores the auto-saved bench if one exists.
    private func restoreSavedBench() -> Bool {
        guard let data = UserDefaults.standard.data(forKey: Self.saveKey),
              let bench = try? JSONDecoder().decode(SavedBench.self, from: data)
        else { return false }
        return apply(bench)
    }

    // MARK: Named save slots

    nonisolated static let slotsKey = "circuits.saveSlots.v1"
    nonisolated static let slotBudget = 8

    /// The saved circuit names, sorted — observable for the panel list.
    private(set) var slotNames: [String] = []

    private func readSlots() -> [String: Data] {
        UserDefaults.standard.dictionary(forKey: Self.slotsKey) as? [String: Data] ?? [:]
    }

    private func writeSlots(_ slots: [String: Data]) {
        UserDefaults.standard.set(slots, forKey: Self.slotsKey)
        slotNames = slots.keys.sorted()
    }

    func refreshSlotNames() {
        slotNames = readSlots().keys.sorted()
    }

    /// Saves the current bench under `name` (overwrites an existing
    /// slot; new slots respect the budget). Returns success.
    @discardableResult
    func saveSlot(named rawName: String) -> Bool {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !components.isEmpty else { return false }
        var slots = readSlots()
        guard slots[name] != nil || slots.count < Self.slotBudget else { return false }
        guard let data = try? JSONEncoder().encode(
            SavedBench(components: components, wires: wires)) else { return false }
        slots[name] = data
        writeSlots(slots)
        return true
    }

    @discardableResult
    func loadSlot(named name: String) -> Bool {
        guard let data = readSlots()[name],
              let bench = try? JSONDecoder().decode(SavedBench.self, from: data),
              apply(bench) else { return false }
        persistSoon()
        return true
    }

    func deleteSlot(named name: String) {
        var slots = readSlots()
        slots.removeValue(forKey: name)
        writeSlots(slots)
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
        case .parallel:
            let battery = place(.battery, at: SIMD3(0, 1.12, -0.9))
            let bulb1 = place(.bulb, at: SIMD3(-0.18, 1.45, -0.9))
            let bulb2 = place(.bulb, at: SIMD3(0.18, 1.58, -0.9))
            connect((battery, 1), (bulb1, 1))
            connect((battery, 1), (bulb2, 1))
            connect((bulb1, 0), (battery, 0))
            connect((bulb2, 0), (battery, 0))
        case .divider:
            let battery = place(.battery, at: SIMD3(0, 1.12, -0.9))
            let r1 = place(.resistor, at: SIMD3(-0.2, 1.5, -0.9), value: 470)
            let r2 = place(.resistor, at: SIMD3(0.2, 1.5, -0.9), value: 1000)
            connect((battery, 1), (r2, 1))
            connect((r2, 0), (r1, 1))
            connect((r1, 0), (battery, 0))
        case .rcCharger:
            let battery = place(.battery, at: SIMD3(0, 1.12, -0.9))
            let resistor = place(.resistor, at: SIMD3(-0.3, 1.31, -0.9), axis: up, value: 1000)
            let capacitor = place(.capacitor, at: SIMD3(0, 1.5, -0.9))
            let toggle = place(.switcher, at: SIMD3(0.3, 1.31, -0.9), axis: up)
            connect((battery, 1), (toggle, 0))
            connect((toggle, 1), (capacitor, 1))
            connect((capacitor, 0), (resistor, 1))
            connect((resistor, 0), (battery, 0))
        case .shortCircuit:
            let battery = place(.battery, at: SIMD3(0, 1.12, -0.9))
            let jumper = place(.wire, at: SIMD3(0, 1.45, -0.9), value: 0.4)
            connect((battery, 1), (jumper, 1))
            connect((jumper, 0), (battery, 0))
        }
        selectedID = components.first?.id
        solve(dt: 1.0 / 90.0)
    }

    // MARK: The bench's own magnetic field

    /// Every current-carrying straight run on the bench, for
    /// `WireField`.
    ///
    /// Two kinds of segment, and both are needed for the field to close
    /// the way a real loop's does:
    ///
    /// - each COMPONENT, from its terminal 0 to its terminal 1, carrying
    ///   the current the solver put through it;
    /// - each WIRE, carrying the current of the component it leaves.
    ///
    /// The wire's current is read from the component at its `from` end
    /// because a wire is not an element in the nodal solve — it is a
    /// short, so whatever flows into it flows out, and that is the
    /// current of the branch it belongs to. In a series loop every
    /// segment then carries the same amps, which is exactly what makes
    /// the field around a loop look like a loop's.
    ///
    /// SIGNED, and the sign is the direction of flow: a segment written
    /// terminal-0-to-terminal-1 with negative amps is current running the
    /// other way, and `WireField` reverses the field for it. Take the
    /// signs out and a loop's two sides would reinforce instead of
    /// opposing, which is the one error that would look plausible.
    var currentSegments: [WireField.Segment] {
        var segments: [WireField.Segment] = []
        segments.reserveCapacity(components.count + wires.count)

        for component in components {
            guard let amps = readouts[component.id]?.amps, amps != 0 else { continue }
            segments.append(.init(a: component.terminalPosition(0),
                                  b: component.terminalPosition(1),
                                  current: amps))
        }
        for wire in wires {
            guard let amps = readouts[wire.from.componentID]?.amps,
                  amps != 0 else { continue }
            guard let from = components.first(where: { $0.id == wire.from.componentID }),
                  let to = components.first(where: { $0.id == wire.to.componentID })
            else { continue }
            // A wire leaving terminal 1 carries the branch current in the
            // same sense the component does; leaving terminal 0 it is
            // running back into it, so the sign flips.
            segments.append(.init(a: from.terminalPosition(wire.from.end),
                                  b: to.terminalPosition(wire.to.end),
                                  current: wire.from.end == 1 ? amps : -amps))
        }
        return segments
    }

    /// B at a point in the room, tesla — the bench's field and nothing
    /// else. Earth's field is Magnetism's business, not this bench's.
    func magneticField(at point: SIMD3<Double>) -> SIMD3<Double> {
        WireField.field(at: point, segments: currentSegments)
    }

    // MARK: Inductor current

    /// The current through the bench's inductor, in amps.
    ///
    /// Sums every inductor on the bench, so two coils in series read as
    /// the current they share and a second parallel branch adds to it.
    var inductorCurrent: Double {
        components
            .filter { $0.kind == .inductor }
            .compactMap { readouts[$0.id]?.amps }
            .reduce(0, +)
    }

    // MARK: Reset

    /// Empties the bench completely — the blank-slate path behind the
    /// quick panel's Clear bench button.
    func clearBench() {
        components = []
        wires = []
        selectedID = nil
        pendingTerminal = nil
        readouts = [:]
        wireFlows = [:]
        totalSourcePower = 0
    }

    /// The opening scene: a battery–switch–bulb loop already flowing, so
    /// the room shows live current the moment the lab appears — flip the
    /// switch, pull it apart, or Clear bench and build from nothing.
    func reset() {
        clearBench()
        // The bank beside the bench shows four states and this restored
        // exactly one of them — the worst instance of a defect found in
        // three other modules the same day (Pendulums' `frictionOn`,
        // Magnetism's `dynamicsOn`, Kinematics' `respectRoomWalls`).
        // Reset from Electron View used to hand back a bench still
        // swollen to 4× with three lamps lit over it. A flag with no
        // visible control drifts out of reset unnoticed; the moment it
        // gets a lamp, the lamp makes the claim every frame.
        showElectronFlow = true
        trueSpeedMode = false
        showVoltageHeights = false
        showMagneticField = false
        electronView = false
        // The meter is a tool now, standing armed-or-not on the bench,
        // so it has a lamp too. Its `didSet` drops both probes.
        multimeterArmed = false
        meterMode = .voltsDC
        isPaused = false
        clearCapsule()
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
        solve(dt: 1.0 / 90.0)
    }

    /// `restoreSaved` re-opens the user's last bench (AppModel passes
    /// true); tests use the default and always get the starter loop.
    init(restoreSaved: Bool = false) {
        reset()
        refreshSlotNames()
        if restoreSaved, restoreSavedBench() {
            }
    }
}

// MARK: - Time Capsule

extension CircuitsModel: TimeCapsuleRecording {
    /// The bench and its transients. `Component` already carries
    /// `capacitorVoltage`, `inductorCurrent`, `motorSpeed`, `failed` and
    /// `isClosed`, so snapshotting the array snapshots every integrated
    /// quantity on the bench — and because it snapshots the WIRES too, a
    /// scrub across a mid-window rewiring restores the old topology. The
    /// per-frame solve then re-derives every readout for it, which is
    /// why nothing here stores a result.
    ///
    /// A blown LED un-blows when you scrub before its failure and blows
    /// again on resume. That is the demonstration, not a bug.
    ///
    /// Out: `pendingTerminal` and the meter's arming — an instrument's
    /// state is the observer's, and the meter re-reads the restored
    /// circuit anyway.
    struct CapsuleSnapshot: Equatable {
        var components: [Component]
        var wires: [Wire]
        var simTime: Double
    }

    func captureCapsuleSnapshot() -> CapsuleSnapshot {
        CapsuleSnapshot(components: components, wires: wires, simTime: simTime)
    }

    func restoreCapsuleSnapshot(_ snapshot: CapsuleSnapshot) {
        components = snapshot.components
        wires = snapshot.wires
        simTime = snapshot.simTime
        // The scope is a strip chart of the past, and it is monotone in
        // simTime — so scrubbing back cuts the future off it rather than
        // leaving a trace that runs past the instant on screen.
        scopeSamples.removeAll { $0.time > snapshot.simTime }
        if let selectedID, !components.contains(where: { $0.id == selectedID }) {
            self.selectedID = nil
            pendingTerminal = nil
        }
    }
}
