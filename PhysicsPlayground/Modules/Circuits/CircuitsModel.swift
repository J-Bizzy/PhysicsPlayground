//
//  CircuitsModel.swift
//  Physics Playground — Circuits module
//
//  App state for the build-your-own-circuit lab; PhysicsCore's
//  CircuitSolver provides the electrical truth every frame.
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

    /// The bench's NOMINAL volume — where a reset lays the starter loop out
    /// and where the flanking instruments take their clearance bearings.
    /// **NOT a wall: a hand meets only the floor.**
    ///
    /// It was a hand clamp until 2026-08-26, and that was the last survivor
    /// of the merged-worlds-era drag clamps. `ARCHITECTURE.md` has said
    /// since 2026-08-03 that model bounds are split by WHO they bind —
    /// Electric Fields and Magnetism both got `regionHalfExtents` (layout)
    /// and `safetyHalfExtents` (the free simulation, never a hand), and it
    /// names THIS constant as a layout reference in the same sentence.
    /// Circuits was simply skipped. The visible cost was a part pulled from
    /// a rack at x 0.82 being born at 0.70 — a 12 cm jump out of your hand,
    /// audit P1-28 — and a jump the rack could not be moved to fix, since
    /// the clearance rule keeps the rack `stationMargin` OUTSIDE this box
    /// by construction.
    ///
    /// Narrowed 0.70 → 0.60 the same day, once it had stopped being a wall
    /// and could be sized for the job it actually does. See
    /// `CircuitsPartsLayout`.
    nonisolated static let buildHalfExtents = SIMD3<Double>(0.60, 0.48, 0.33)

    /// The free simulation's safety bounds — room-scale, never applied to a
    /// hand. A released part stays in the room; it does not stay on the
    /// bench. Same shape and same reason as `FieldModel.safetyHalfExtents`.
    nonisolated static let safetyHalfExtents = SIMD3<Double>(2.6, 1.6, 2.6)

    nonisolated static let floorMargin = 0.2
    nonisolated static let componentBudget = 16
    nonisolated static let wireBudget = 36
    /// Small internal resistance so a dead short misbehaves physically instead
    /// of exploding the math.
    nonisolated static let batteryInternalResistance = 0.05
    /// Terminals sit at ±x on every component.
    nonisolated static let terminalOffset = 0.085

    // MARK: Components

    enum ComponentKind: String, CaseIterable, Identifiable, Codable {
        // Declaration order is drawer order: power, passives,
        // outputs, control.
        case battery, acSource, resistor, capacitor, inductor
        case bulb, led, motor, fuse, switcher

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
            }
        }
    }

    // Red LED forward drop / on-resistance; burns out past ~30 mA (real 5 mm LEDs).
    nonisolated static let ledForwardDrop = 2.0
    nonisolated static let ledOnResistance = 12.0
    nonisolated static let ledMaxAmps = 0.03
    /// The AC source's fixed frequency — slow enough to watch.
    nonisolated static let acFrequency = 0.5

    // DC motor: back-EMF and torque share k (V·s/rad = N·m/A); coil resistance is the
    // component's value. No-load steady speed ω = kV/(bR + k²) — the property the tests pin.
    nonisolated static let motorTorqueConstant = 0.06
    nonisolated static let motorFriction = 0.0008
    nonisolated static let motorInertia = 0.0009

    /// How near two leads must come to be one point — ONE distance for both a
    /// pull and a release. 0.06: one part's two leads are 0.17 m apart, so this
    /// cannot reach past the end it belongs to.
    nonisolated static let leadReach = 0.06

    /// Carry a part until a snapped connection stretches past this and it pops off.
    /// Much larger than `leadReach`: joining needs precision, leaving needs intent.
    nonisolated static let breakDistance = 0.3

    struct Terminal: Equatable, Hashable, Codable {
        var componentID: UUID
        var end: Int  // 0 = left (battery +), 1 = right
    }

    struct Component: Identifiable, Equatable, Codable {
        let id: UUID
        let kind: ComponentKind
        var position: SIMD3<Double>
        /// Volts, ohms, farads…
        var value: Double
        /// Unit direction from terminal 0 toward terminal 1.
        var axis = SIMD3<Double>(1, 0, 0)
        /// Switches only.
        var isClosed = true
        /// Capacitors only: the integrated state.
        var capacitorVoltage = 0.0
        /// Failure simulation (burned LED, blown fuse) — transient, never
        /// persisted; Replace on the readout clears it.
        var failed = false
        /// Inductors only: the integrated state — transient.
        var inductorCurrent = 0.0
        /// Motors only: the spin speed (rad/s) — transient, integrated
        /// each step from torque against back-EMF and friction.
        var motorSpeed = 0.0

        private enum CodingKeys: String, CodingKey {
            case id, kind, position, value, axis, isClosed, capacitorVoltage
        }

        /// Where one of this part's two leads sits.
        func terminalPosition(_ end: Int) -> SIMD3<Double> {
            let halfSpan = CircuitsModel.terminalOffset
            return position + (end == 0 ? -halfSpan : halfSpan) * axis
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

    var selectedComponent: Component? {
        guard let selectedID else { return nil }
        return components.first { $0.id == selectedID }
    }

    // MARK: Display & time

    var showElectronFlow = true

    // MARK: True speed — the thirteen orders of magnitude

    /// Shows the drift at its REAL relative rate: electrons frozen, the field
    /// front racing.
    var trueSpeedMode = false

    /// A conventional hookup wire: 1 mm radius copper.
    nonisolated static let wireRadius = 1e-3

    /// Largest current anywhere in the circuit, amps — what the drift readout describes.
    var peakCurrent: Double {
        let wireMax = wireFlows.values.map(abs).max() ?? 0
        let partMax = readouts.values.map { abs($0.amps) }.max() ?? 0
        return max(wireMax, partMax)
    }

    /// Drift speed of the electrons at that current, m/s.
    var driftSpeed: Double {
        ChargeTransport.driftSpeed(current: peakCurrent, wireRadius: Self.wireRadius)
    }

    /// The loop an electron walks, metres — summed length of every carrying wire.
    /// A wire is drawn taut between its terminals, so the electron's path is the
    /// chord sum — the same distances the field front walks, so the true-speed
    /// readout and the front agree by construction.
    var conductingPathLength: Double {
        var total = 0.0
        for wire in wires where abs(wireFlows[wire.id] ?? 0) > 5e-4 {
            guard let a = terminalWorldPosition(wire.from),
                  let b = terminalWorldPosition(wire.to) else { continue }
            total += simd_distance(a, b)
        }
        return total
    }

    /// How long one electron takes to go round, seconds.
    var driftLapTime: Double {
        ChargeTransport.traversalTime(length: conductingPathLength, speed: driftSpeed)
    }

    var signalLapTime: Double {
        ChargeTransport.traversalTime(length: conductingPathLength,
                                      speed: ChargeTransport.signalSpeed())
    }
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

    /// Adds a part — at `point` when it comes off the tray, otherwise on a spawn
    /// ring at the build center. Returns the new part's id (nil when budget-full).
    @discardableResult
    func add(_ kind: ComponentKind, at point: SIMD3<Double>? = nil) -> UUID? {
        guard scrubTime == nil else { return nil }
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
        guard scrubTime == nil else { return }
        guard let selectedID,
              let component = components.first(where: { $0.id == selectedID }) else { return }
        wires.removeAll { $0.from.componentID == selectedID || $0.to.componentID == selectedID }
        components.removeAll { $0.id == selectedID }
        if leadPull?.source.componentID == selectedID { cancelLeadPull() }
        if voiceWireSource?.componentID == selectedID { voiceWireSource = nil }
        self.selectedID = components.last?.id
        emitSound(.thud, at: component.position, volume: 0.4)
        persistSoon()
    }

    func select(id: UUID) {
        guard components.contains(where: { $0.id == id }) else { return }
        selectedID = id
    }

    /// The pairs a release right now would wire up — the renderer ghosts these
    /// while a part is carried, so what you preview is what you get.
    func pendingJoins(for id: UUID) -> [(from: Terminal, to: Terminal)] {
        guard let component = components.first(where: { $0.id == id }) else { return [] }
        let net = topology()
        var pairs: [(from: Terminal, to: Terminal)] = []
        for end in 0...1 {
            let mine = Terminal(componentID: id, end: end)
            let minePosition = component.terminalPosition(end)
            var best: (terminal: Terminal, distance: Double)?
            for other in components where other.id != id {
                for otherEnd in 0...1 {
                    let theirs = Terminal(componentID: other.id, end: otherEnd)
                    let distance = simd_distance(minePosition, other.terminalPosition(otherEnd))
                    guard distance < Self.leadReach else { continue }
                    // Already one point: a wire here would carry nothing.
                    guard !net.sameNet(mine, theirs) else { continue }
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

    // MARK: Snap-align — parts land nose to tail

    /// The move a release would make. PURE — no mutation — so the renderer can
    /// ghost the landing while the part is still in the hand.
    struct Alignment: Equatable {
        let componentID: UUID
        /// The lead that lands.
        let end: Int
        let target: Terminal
        let position: SIMD3<Double>
        let axis: SIMD3<Double>
    }

    /// Where a release would put this part, if anywhere.
    /// The released part moves; the target never does (which stops cascades).
    /// One end wins (the closer; the other still gets its wire), and the part
    /// rotates about the landing lead, not the centre.
    func alignment(for id: UUID) -> Alignment? {
        guard let component = components.first(where: { $0.id == id }) else { return nil }
        var best: (end: Int, target: Terminal, position: SIMD3<Double>, distance: Double)?
        for pair in pendingJoins(for: id) {
            guard let targetPosition = terminalWorldPosition(pair.to) else { continue }
            let distance = simd_distance(component.terminalPosition(pair.from.end), targetPosition)
            if best == nil || distance < best!.distance {
                best = (pair.from.end, pair.to, targetPosition, distance)
            }
        }
        guard let best else { return nil }

        // Swing the FAR end away from the joint; landing lead exactly on target.
        let far = component.terminalPosition(1 - best.end)
        var direction = far - best.position
        let reach = simd_length(direction)
        // Released dead-centre there is no direction: keep the existing aim —
        // a degenerate hand is a no-op, never a snap.
        direction = reach > 1e-6
            ? direction / reach
            : (best.end == 0 ? component.axis : -component.axis)
        let axis = best.end == 0 ? direction : -direction
        let position = best.position + direction * Self.terminalOffset

        // CLAMP VETO: if the clamp would move the aligned part, the leads end up
        // visibly apart — abandon the geometry and let the wire span the gap.
        // Against the SAFETY box since 2026-08-26, because that is the only
        // clamp left; the bench stopped being a wall the same day, so vetoing
        // against it would refuse alignments nothing would then move.
        guard simd_distance(Self.clampToRoomSafety(position), position) < 1e-9 else { return nil }
        return Alignment(componentID: id, end: best.end, target: best.target,
                         position: position, axis: axis)
    }

    /// The ONE place a carried part lands. Order matters: align first, then wire
    /// from the pairs the ALIGNED part sees — a release cannot wire one pair and
    /// snap to another. `breakOverstretchedWires` deliberately does NOT run here:
    /// after the alignment's translation it could yank a NEIGHBOUR's contact off.
    func release(id: UUID) {
        guard scrubTime == nil else { return }
        guard components.contains(where: { $0.id == id }) else { return }
        if let alignment = alignment(for: id),
           let index = components.firstIndex(where: { $0.id == id }) {
            components[index].position = alignment.position
            components[index].axis = alignment.axis
        }
        let pairs = pendingJoins(for: id)
        guard !pairs.isEmpty,
              let component = components.first(where: { $0.id == id }) else { return }
        var joined = false
        for pair in pairs {
            if case .connected = connectTerminals(pair.from, pair.to) { joined = true }
        }
        guard joined else { return }
        emitSound(.chime, at: component.position, volume: 0.5)
        persistSoon()
    }

    /// A carried part with exactly ONE wired lead swings about it; both ends
    /// wired or neither, no swing. Aim is a consequence of connection.
    func swing(id: UUID, hand: SIMD3<Double>) {
        guard scrubTime == nil else { return }
        guard let index = components.firstIndex(where: { $0.id == id }) else { return }
        let ends = (0...1).filter { end in
            wires.contains { $0.from == Terminal(componentID: id, end: end)
                          || $0.to == Terminal(componentID: id, end: end) }
        }
        guard ends.count == 1, let pinned = ends.first,
              let pivot = terminalWorldPosition(Terminal(componentID: id, end: pinned))
        else { return }
        var direction = hand - pivot
        let reach = simd_length(direction)
        guard reach > 1e-4 else { return }
        direction /= reach
        // Same clamp veto as `alignment(for:)`: where the clamp would shift the
        // body, the pinned lead would leave its joint.
        let position = pivot + direction * Self.terminalOffset
        guard simd_distance(Self.clampToRoomSafety(position), position) < 1e-9 else { return }
        components[index].axis = pinned == 0 ? direction : -direction
        components[index].position = position
    }

    // MARK: Pull-apart detach (the magnet, in reverse)

    /// Wires short enough at grab time to count as snapped contacts — only these
    /// pop when stretched, so a deliberately long span is never yanked off.
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

    /// Call when a part starts being carried: remember which of its connections
    /// are short contacts (poppable).
    func beginCarry(id: UUID) {
        guard scrubTime == nil else { return }
        poppableWires = Set(wires.filter { wire in
            (wire.from.componentID == id || wire.to.componentID == id)
                && wireLength(wire) < Self.breakDistance
        }.map(\.id))
    }

    /// Call while carrying: any poppable contact stretched past the break
    /// distance snaps off. Bring the part back and it re-snaps on release.
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
    func detachComponent(id: UUID) {
        guard scrubTime == nil else { return }
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

    /// Why a connection did not happen — a refusal is a thing the bench shows,
    /// not a silent `return`.
    enum ConnectOutcome: Equatable {
        case connected(UUID)
        /// The two ends are already the same electrical point.
        case sameNet
        case sameTerminal
        case budgetFull
        /// One of the terminals is not on the bench.
        case missing
    }

    /// Terminal-to-terminal wiring — where every wiring gesture lands. No
    /// self-wires, and no wire between ends ALREADY one point: the same-net rule
    /// is strictly stronger than a duplicate-pair check (it catches a second PATH).
    @discardableResult
    func connectTerminals(_ a: Terminal, _ b: Terminal) -> ConnectOutcome {
        guard a != b else { return .sameTerminal }
        guard components.contains(where: { $0.id == a.componentID }),
              let target = components.first(where: { $0.id == b.componentID })
        else { return .missing }
        guard !areConnected(a, b) else { return .sameNet }
        guard wires.count < Self.wireBudget else { return .budgetFull }
        let wire = Wire(id: UUID(), from: a, to: b)
        wires.append(wire)
        emitSound(.pop, at: target.terminalPosition(b.end), volume: 0.8)
        persistSoon()
        return .connected(wire.id)
    }

    /// Adopt the aim a carry left the part with. Ignores degenerate axes.
    func setAxis(id: UUID, axis: SIMD3<Double>) {
        guard scrubTime == nil else { return }
        guard let index = components.firstIndex(where: { $0.id == id }) else { return }
        let length = simd_length(axis)
        guard length > 1e-6 else { return }
        components[index].axis = axis / length
    }

    /// True while any battery is pushing more current than a healthy circuit
    /// would draw — the load is (nearly) a dead short.
    var hasOverloadedBattery: Bool {
        components.contains { component in
            component.kind == .battery
                && abs(readouts[component.id]?.amps ?? 0) > Self.overloadAmps
        }
    }

    /// A bulb draws ~0.4 A; a dead short ~150 A. Past this is a wiring mistake, not a load.
    nonisolated static let overloadAmps = 2.0

    func move(id: UUID, to point: SIMD3<Double>) {
        guard scrubTime == nil else { return }
        guard let index = components.firstIndex(where: { $0.id == id }) else { return }
        components[index].position = clamp(point)
    }

    /// Folds a point into the NOMINAL bench box. No longer applied to a
    /// hand — this is the layout question ("would this sit on the bench?")
    /// that `reset`'s seeding and the layout tests ask. `clampToRoomSafety`
    /// is what actually binds a released part.
    nonisolated static func clampToBench(
        _ point: SIMD3<Double>
    ) -> SIMD3<Double> {
        var clamped = simd_clamp(point,
                                 buildCenter - buildHalfExtents,
                                 buildCenter + buildHalfExtents)
        clamped.y = max(clamped.y, floorMargin)
        return clamped
    }

    /// Clamps a part into the room-scale safety box — the only clamp a
    /// hand meets, and it is there so a part cannot be carried into next
    /// door, not to keep it on the bench.
    nonisolated static func clampToRoomSafety(
        _ point: SIMD3<Double>
    ) -> SIMD3<Double> {
        var clamped = simd_clamp(point,
                                 buildCenter - safetyHalfExtents,
                                 buildCenter + safetyHalfExtents)
        clamped.y = max(clamped.y, floorMargin)
        return clamped
    }

    private func clamp(_ point: SIMD3<Double>) -> SIMD3<Double> {
        Self.clampToRoomSafety(point)
    }

    // MARK: Wiring — pull a lead

    /// A half-made wire, in flight. Lives in the MODEL, not the gesture, so
    /// `removeComponent` can cancel it — where the zombie-wire defect died.
    struct LeadPull: Equatable {
        /// The lead the wire is coming from.
        var source: Terminal
        /// Set when this pull lifted an EXISTING wire off a terminal (a rewire).
        /// The wire is already out of `wires` by then.
        var detached: UUID?
        /// Where the hand is, in bench coordinates.
        var hand: SIMD3<Double>
        /// What a release right now would land on.
        var target: Terminal?
        /// Why a release right now would refuse — nil when it would connect.
        /// Computed every frame, BEFORE the release, so preview equals outcome.
        var refusal: ConnectOutcome?
    }

    /// One end of one wire — what a hand grabs near a plug.
    struct WireEnd: Equatable, Sendable {
        let wire: UUID
        let end: Int
    }

    /// What a released lead did.
    enum LeadOutcome: Equatable {
        case connected(UUID)
        case refused(ConnectOutcome)
        /// Let go in open air: the lead springs back, nothing changes.
        case retracted
        /// A rewire dropped in open air — the wire it came from is gone.
        case deleted(UUID)
        case none
    }

    private(set) var leadPull: LeadPull?

    /// Start drawing a wire from a lead.
    func beginLeadPull(from source: Terminal, hand: SIMD3<Double>) {
        guard scrubTime == nil else { return }
        guard components.contains(where: { $0.id == source.componentID }) else { return }
        // A pull that replaces another silently eats whatever the first carried.
        cancelLeadPull()
        leadPull = LeadPull(source: source, hand: hand)
        updateLeadPull(hand: hand)
    }

    /// Take an existing wire's END off its terminal into the same lead pull,
    /// drawn from the end that stayed. The wire leaves `wires` IMMEDIATELY —
    /// the circuit going dark in your hand is the teach.
    func beginRewire(wire id: UUID, grabbing end: Int, hand: SIMD3<Double>) {
        guard scrubTime == nil else { return }
        guard wires.contains(where: { $0.id == id }) else { return }
        // One pull at a time: a second `begin` would overwrite a rewire in flight
        // and its wire — already out of `wires` — would cease to exist.
        cancelLeadPull()
        guard let index = wires.firstIndex(where: { $0.id == id }) else { return }
        let wire = wires[index]
        // The grabbed end comes off; the other end becomes the source.
        let anchor = end == 0 ? wire.to : wire.from
        let lifted = end == 0 ? wire.from : wire.to
        wires.remove(at: index)
        detachedWires[id] = wire
        leadPull = LeadPull(source: anchor, detached: id, hand: hand)
        updateLeadPull(hand: hand)
        if let component = components.first(where: { $0.id == lifted.componentID }) {
            emitSound(.grabTick, at: component.terminalPosition(lifted.end), volume: 0.25)
        }
        persistSoon()
    }

    /// Which end of a wire a hand is nearer to — the end it would take.
    func nearerEnd(of id: UUID, to hand: SIMD3<Double>) -> Int? {
        guard let wire = wires.first(where: { $0.id == id }),
              let from = terminalWorldPosition(wire.from),
              let to = terminalWorldPosition(wire.to) else { return nil }
        return simd_distance(from, hand) <= simd_distance(to, hand) ? 0 : 1
    }

    /// Follow the hand, and work out what a release would do.
    func updateLeadPull(hand: SIMD3<Double>) {
        guard var pull = leadPull else { return }
        pull.hand = hand
        // Target found from the LEAD TIP (the hand) at the same `leadReach` a
        // release uses, so the preview cannot snap to something the release ignores.
        var best: (terminal: Terminal, distance: Double)?
        for component in components {
            for end in 0...1 {
                let candidate = Terminal(componentID: component.id, end: end)
                guard candidate != pull.source else { continue }
                let distance = simd_distance(component.terminalPosition(end), hand)
                guard distance < Self.leadReach else { continue }
                if best == nil || distance < best!.distance { best = (candidate, distance) }
            }
        }
        pull.target = best?.terminal
        pull.refusal = best.map { candidate -> ConnectOutcome? in
            if areConnected(pull.source, candidate.terminal) { return .sameNet }
            if wires.count >= Self.wireBudget { return .budgetFull }
            return nil
        } ?? nil
        leadPull = pull
    }

    /// Let go. Lands the wire, refuses it, or retracts.
    @discardableResult
    func endLeadPull() -> LeadOutcome {
        guard let pull = leadPull else { return .none }
        // The pull is over either way — this also flushes the save `persistNow`
        // deferred mid-pull.
        defer { leadPull = nil; persistSoon() }
        guard let target = pull.target else {
            // Open air: a new lead springs back; a rewire takes its wire with it.
            if let detached = pull.detached {
                detachedWires[detached] = nil
                emitSound(.thud, at: pull.hand, volume: 0.5)
                persistSoon()
                return .deleted(detached)
            }
            emitSound(.releaseTick, at: pull.hand, volume: 0.2)
            return .retracted
        }
        let outcome = connectTerminals(pull.source, target)
        switch outcome {
        case .connected(let id):
            // A landed rewire is no longer detached — including landing back
            // where it came from.
            if let detached = pull.detached { detachedWires[detached] = nil }
            return .connected(id)
        default:
            // The refusal is the renderer's recoil; no text.
            emitSound(.thud, at: pull.hand, volume: 0.35)
            if let detached = pull.detached {
                // A refused rewire is not a deletion — put the wire back.
                restore(wireID: detached)
            }
            return .refused(outcome)
        }
    }

    /// Abandon a pull without landing it — the part went away, the bench was
    /// cleared, the lab was reset. This is where the zombie wire died.
    func cancelLeadPull() {
        guard let pull = leadPull else { return }
        leadPull = nil
        if let detached = pull.detached { restore(wireID: detached) }
        // Flush the save `persistNow` deferred during the pull.
        persistSoon()
    }

    /// Put a lifted wire back exactly as it was. THE WHOLE WIRE IS KEPT, not just
    /// the anchor: rebuilding `Wire(from: anchor, to: source)` makes a zero-length
    /// self-wire, because `source` IS the anchor — the zombie wire, rebuilt.
    private func restore(wireID: UUID) {
        guard let wire = detachedWires[wireID] else { return }
        detachedWires[wireID] = nil
        guard components.contains(where: { $0.id == wire.from.componentID }),
              components.contains(where: { $0.id == wire.to.componentID }),
              !wires.contains(where: { $0.id == wireID }) else { return }
        wires.append(wire)
    }

    /// Every wire currently lifted off a terminal, whole, so it can be put back.
    @ObservationIgnored private var detachedWires: [UUID: Wire] = [:]

    // MARK: The accessibility door

    // MARK: Net highlighting — what is this connected to?

    /// The tapped terminal whose net is lit, if any. A selection like `selectedID`,
    /// not a display layer (`ResetCoverageTests` reflects over `Bool`s), and
    /// selection-driven, not hover — `HoverEffectComponent` has no callback.
    /// Stores WHICH TERMINAL WAS TAPPED, not the resolved node: deleting any part
    /// RENUMBERS nodes, so the node is resolved on READ.
    private(set) var highlightedSource: Terminal?

    /// The lit node, resolved now — nil when nothing is lit or the tapped
    /// terminal has since left the bench.
    var highlightedNet: Int? {
        guard let highlightedSource else { return nil }
        return topology().node(of: highlightedSource)
    }

    /// Light the net this terminal belongs to.
    func highlightNet(containing terminal: Terminal) {
        highlightedSource = components.contains { $0.id == terminal.componentID }
            ? terminal : nil
    }

    func clearNetHighlight() { highlightedSource = nil }

    /// The terminals currently lit — empty when nothing is.
    var highlightedTerminals: [Terminal] {
        guard let highlightedSource else { return [] }
        let net = topology()
        guard let node = net.node(of: highlightedSource),
              node < net.terminalsByNode.count else { return [] }
        return net.terminalsByNode[node]
    }

    /// Whether a wire lies inside the lit net (either end answers — both are one point).
    func isHighlighted(wire: Wire) -> Bool {
        guard let highlightedSource else { return false }
        let net = topology()
        guard let lit = net.node(of: highlightedSource) else { return false }
        return net.node(of: wire.from) == lit
    }

    /// The lead VoiceOver is wiring from — tap-tap wiring, reintroduced ONLY
    /// through the accessibility door. The pinch path never reads it (the old
    /// shared `pendingTerminal` let one event arm and wire at once).
    private(set) var voiceWireSource: Terminal?

    /// The VoiceOver action on a terminal: arm, or land.
    @discardableResult
    func voiceOverWire(_ terminal: Terminal) -> LeadOutcome {
        guard scrubTime == nil else { return .none }
        guard components.contains(where: { $0.id == terminal.componentID }) else { return .none }
        guard let source = voiceWireSource else {
            voiceWireSource = terminal
            return .none
        }
        voiceWireSource = nil
        guard source != terminal,
              components.contains(where: { $0.id == source.componentID }) else { return .none }
        let outcome = connectTerminals(source, terminal)
        if case .connected(let id) = outcome { return .connected(id) }
        return .refused(outcome)
    }

    /// Tapping a wire says "this one" — it never deletes; a wire comes off by
    /// being pulled off.
    func selectWire(id: UUID) {
        guard let wire = wires.first(where: { $0.id == id }) else { return }
        selectedID = wire.from.componentID
        highlightNet(containing: wire.from)
        if let component = components.first(where: { $0.id == wire.from.componentID }) {
            emitSound(.releaseTick, at: component.terminalPosition(wire.from.end), volume: 0.2)
        }
    }

    func deleteWire(id: UUID) {
        guard scrubTime == nil else { return }
        guard let wire = wires.first(where: { $0.id == id }) else { return }
        wires.removeAll { $0.id == id }
        if let component = components.first(where: { $0.id == wire.from.componentID }) {
            emitSound(.thud, at: component.terminalPosition(wire.from.end), volume: 0.3)
        }
        persistSoon()
    }

    func toggleSwitch(id: UUID) {
        guard scrubTime == nil else { return }
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

    /// The range a part's value may be pulled across.
    static func valueRange(for kind: ComponentKind) -> ClosedRange<Double> {
        switch kind {
        case .battery, .acSource: 1.0...24.0        // V
        case .resistor: 10.0...4700.0               // Ω
        case .capacitor: 1e-4...1e-2                // F
        case .inductor: 0.05...5.0                  // H
        case .bulb: 4.0...240.0                     // Ω
        case .motor: 1.0...60.0                     // Ω
        case .fuse: 0.05...5.0                      // A
        case .led, .switcher: 0...0
        }
    }

    static func formatValue(_ value: Double, for kind: ComponentKind) -> String {
        switch kind {
        case .battery, .acSource: PhysicsFormat.measurement(value, "V", decimals: 1)
        case .resistor, .bulb, .motor: value >= 1000
            ? PhysicsFormat.measurement(value / 1000, "k\u{03A9}", decimals: 1)
            : PhysicsFormat.measurement(value, "\u{03A9}", decimals: 0)
        // Prefix from magnitude — a fixed mF format rounds the whole µF range to "0 mF".
        case .capacitor: PhysicsFormat.metric(value, "F", decimals: 0)
        case .inductor: PhysicsFormat.measurement(value, "H", decimals: 2)
        case .fuse: PhysicsFormat.measurement(value, "A", decimals: 2)
        case .led, .switcher: ""
        }
    }

    func componentValue(id: UUID) -> Double {
        components.first(where: { $0.id == id })?.value ?? 0
    }

    func setComponentValue(id: UUID, _ value: Double) {
        guard scrubTime == nil else { return }
        guard let index = components.firstIndex(where: { $0.id == id }) else { return }
        let range = Self.valueRange(for: components[index].kind)
        guard range.upperBound > range.lowerBound else { return }
        components[index].value = min(max(value, range.lowerBound), range.upperBound)
        persistSoon()
    }

    func removeComponent(id: UUID) {
        guard scrubTime == nil else { return }
        components.removeAll { $0.id == id }
        wires.removeAll { $0.from.componentID == id || $0.to.componentID == id }
        if selectedID == id { selectedID = components.last?.id }
        // A half-drawn wire cannot survive its own part: this path (the Bloom's
        // Delete) must clear pull/voice/highlight state, or the next tap builds a
        // persisted, un-pinchable wire onto a component that no longer exists.
        if leadPull?.source.componentID == id { cancelLeadPull() }
        if voiceWireSource?.componentID == id { voiceWireSource = nil }
        if highlightedSource?.componentID == id { highlightedSource = nil }
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

    // MARK: The solve (every frame)

    /// Solve, then record. The solve runs every frame even while paused (a frozen
    /// bench shows honest readouts) but only unpaused frames are recorded; priming
    /// solves call `solve` directly and are deliberately not recorded.
    func step(dt: Double) {
        let isRecordingFrame = !isPaused
        solve(dt: dt)
        if isRecordingFrame {
            recordCapsuleFrame(dt: min(max(dt, 1e-4), 1.0 / 30.0))
        }
    }

    // MARK: Nets — which terminals are the same electrical point

    /// The bench's connectivity, resolved — the solve, wiring, meter and skyline all read it.
    struct NetTopology {
        /// `slot = 2 * componentIndex + end` — LOAD-BEARING: keeps the stamping
        /// loop index-parallel with `components` without a lookup table.
        static func slot(componentIndex: Int, end: Int) -> Int { 2 * componentIndex + end }

        /// What the cache was built from — comparing these against the live bench
        /// IS the invalidation mechanism. See `topology()`.
        let componentIDs: [UUID]
        let wires: [Wire]

        let nodeOfSlot: [Int]
        let nodeCount: Int
        private let slotOf: [Terminal: Int]
        /// Indexed by node id; each list sorted by slot.
        let terminalsByNode: [[Terminal]]

        init(components: [Component], wires: [Wire]) {
            componentIDs = components.map(\.id)
            self.wires = wires

            var slots: [Terminal: Int] = [:]
            slots.reserveCapacity(components.count * 2)
            for index in components.indices {
                for end in 0...1 {
                    slots[Terminal(componentID: components[index].id, end: end)]
                        = Self.slot(componentIndex: index, end: end)
                }
            }
            slotOf = slots

            var partition = NetPartition(slotCount: components.count * 2)
            for wire in wires {
                guard let a = slots[wire.from], let b = slots[wire.to] else { continue }
                partition.union(a, b)
            }

            // Ground: first battery's − end, else the first terminal.
            let ground = components.firstIndex { $0.kind == .battery }
                .map { Self.slot(componentIndex: $0, end: 1) } ?? 0
            guard !components.isEmpty else {
                nodeOfSlot = []; nodeCount = 0; terminalsByNode = []
                return
            }
            (nodeOfSlot, nodeCount) = partition.numbering(ground: ground)

            var byNode = [[Terminal]](repeating: [], count: nodeCount)
            for index in components.indices {
                for end in 0...1 {
                    let slot = Self.slot(componentIndex: index, end: end)
                    byNode[nodeOfSlot[slot]]
                        .append(Terminal(componentID: components[index].id, end: end))
                }
            }
            terminalsByNode = byNode
        }

        func node(of terminal: Terminal) -> Int? {
            slotOf[terminal].map { nodeOfSlot[$0] }
        }

        /// Whether two terminals are already the same electrical point
        /// (unknown terminals are not points at all — false).
        func sameNet(_ a: Terminal, _ b: Terminal) -> Bool {
            guard let nodeA = node(of: a), let nodeB = node(of: b) else { return false }
            return nodeA == nodeB
        }
    }

    @ObservationIgnored private var netCache: NetTopology?
    #if DEBUG
    /// Rebuild count, so a test can assert that MOVING a part does not rebuild —
    /// geometry is not topology.
    @ObservationIgnored private(set) var netRebuildCount = 0
    #endif

    /// Connectivity, rebuilt only when TOPOLOGY changed — not moves, values, or
    /// switch state (a switch is an element between nets, never a break in one).
    /// NO INVALIDATION CALL, deliberately: the cache compares its ids/wires
    /// against the bench, so a mutator invalidates it without knowing it exists.
    private func topology() -> NetTopology {
        if let netCache, netCache.componentIDs.count == components.count,
           netCache.wires.count == wires.count {
            var matches = true
            for index in components.indices where netCache.componentIDs[index] != components[index].id {
                matches = false
                break
            }
            if matches {
                for index in wires.indices where netCache.wires[index] != wires[index] {
                    matches = false
                    break
                }
            }
            if matches { return netCache }
        }
        let fresh = NetTopology(components: components, wires: wires)
        netCache = fresh
        #if DEBUG
        netRebuildCount += 1
        #endif
        return fresh
    }

    /// Whether two terminals are already one electrical point.
    func areConnected(_ a: Terminal, _ b: Terminal) -> Bool {
        topology().sameNet(a, b)
    }

    private func solve(dt: Double) {
        guard !components.isEmpty else {
            readouts = [:]
            wireFlows = [:]
            totalSourcePower = 0
            nets = []
            return
        }
        let timeStep = min(max(dt, 1e-4), 1.0 / 30.0)

        // 1–2. Node resolution — cached across frames, see `topology()`.
        let net = topology()
        let nodeCount = net.nodeCount
        @inline(__always) func node(_ index: Int, _ end: Int) -> Int {
            net.nodeOfSlot[NetTopology.slot(componentIndex: index, end: end)]
        }

        // 3. Stamp one element per component and solve.
        if !isPaused { simTime += timeStep }
        // `elements[i]` is `components[i]` — the index parity every readout reads
        // back through; `CircuitsNetTests` asserts it.
        let elements = components.enumerated().map { (index, component) -> CircuitElement in
            let a = node(index, 0)
            let b = node(index, 1)
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
                // Coil in series with a back-EMF source k·ω opposing the drive.
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
            }
            return CircuitElement(nodeA: a, nodeB: b, kind: kind)
        }
        // 3b. The meter is a REAL element: stamped only in A⎓ and only across two
        // DIFFERENT nodes — in V⎓ its shunt would short the measurand; across one
        // node it would be a loop of itself.
        var meterElementIndex: Int?
        var stamped = elements
        if multimeterArmed, meterMode == .ampsDC,
           let probeA, let probeB,
           let a = net.node(of: probeA), let b = net.node(of: probeB) {
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

        // Terminal voltages for the warm↔cool gradient.
        var terminalVolts: [Terminal: Double] = [:]
        for index in components.indices {
            for end in 0...1 {
                terminalVolts[Terminal(componentID: components[index].id, end: end)]
                    = solution.nodeVoltages[node(index, end)]
            }
        }
        terminalVoltages = terminalVolts
        let span = solution.nodeVoltages.dropFirst()
        voltageSpan = (min(span.min() ?? 0, 0), max(span.max() ?? 0, 0))

        // Each net's position is the centroid of its terminals — where the
        // voltage skyline raises its tower.
        nets = net.terminalsByNode.enumerated().map { (id, terminals) in
            var sum = SIMD3<Double>.zero
            for terminal in terminals {
                sum += terminalWorldPosition(terminal) ?? .zero
            }
            return Net(id: id,
                       terminals: terminals,
                       position: terminals.isEmpty ? .zero : sum / Double(terminals.count),
                       voltage: solution.nodeVoltages[id])
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
                // τ = kI − bω, ω += τ/J · dt; speed feeds back as next step's back-EMF.
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
        // 5. Wire currents for the electron flow: each terminal's element current
        // fans out evenly over its wires (a visualization choice). Lookup tables
        // built once — per-wire scans were O(W²) inside a per-frame solve.
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

    // NO OSCILLOSCOPE. `scopeSamples` accumulated a 300-frame window of
    // the selected part's volts and amps every frame and NOTHING READ IT
    // — no scope face was ever built, and the readout that ships is the
    // multimeter. Deleted 2026-08-26.

    /// Multimeter: arm it, then tap any two terminals. Red probe first.
    var multimeterArmed = false {
        didSet { if !multimeterArmed { probeA = nil; probeB = nil } }
    }
    /// The ammeter's shunt, stamped into the network so current flows THROUGH it.
    /// NOT `.conductor`: a perfect short's current is split arbitrarily across
    /// parallel paths — a resistance makes the answer unique. 1 mΩ disturbs the
    /// loop current well under a percent.
    static let ammeterShuntOhms = 0.001


    /// What the meter measured on the last step, amps — `nil` unless it was
    /// actually in the network.
    private(set) var meterCurrent: Double?

    private(set) var probeA: Terminal?
    private(set) var probeB: Terminal?

    /// Red is A, black is B — a voltage reads positive when red is on the
    /// higher potential.
    enum ProbeSlot { case red, black }

    /// Parks a probe on a terminal, or lifts it off with nil. `probeTap` below
    /// survives for the accessibility path.
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

    /// A tap while the meter is armed lands a probe (A, then B, then back to A).
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

    /// The dial: four genuinely different measurements, not four formats of one
    /// number. See `MultimeterReading`.
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
        /// The one line under it — a unit, or the reason there is no number.
        var note: String
        /// Continuity mode only: whether it should be beeping.
        var beeping: Bool = false
        /// True when the meter is asked to do something a real one would object
        /// to. Drives the display's colour.
        var fault: Bool = false
    }

    /// Everything the meter can say, by mode. A⎓ reports current only when the
    /// probes bracket a component whose circuit is otherwise BROKEN — the meter
    /// completing the loop is the meter in series; across a live component it
    /// refuses rather than teach the classic shorted-ammeter mistake.
    var multimeterReading: MultimeterReading? {
        guard let probeA, let probeB else { return nil }
        guard let vA = terminalVoltages[probeA],
              let vB = terminalVoltages[probeB] else { return nil }

        let bracketsOneComponent = probeA.componentID == probeB.componentID
            && probeA.end != probeB.end
        let component = components.first { $0.id == probeA.componentID }
        // Continuity is a topology question — one lookup, not a BFS.
        let sameNode = abs(vA - vB) < 1e-3 && areConnected(probeA, probeB)

        switch meterMode {
        case .voltsDC:
            return MultimeterReading(
                display: Self.autoRange(vA - vB, unit: "V"),
                note: bracketsOneComponent && component != nil
                    ? "across the \(component!.kind.displayName)"
                    : "between the probes")

        case .ampsDC:
            // Read the METER's own stamped current, never the bracketed
            // component's amps. THE GUARD COMES FIRST AND DOES NOT USE THE STAMP:
            // the stamp only exists after a solve, so a stamp-dependent guard
            // answers wrongly for callers that read without stepping
            // (testAmpsModeRefusesToBePutAcrossALiveComponent).
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
            // Nil meterCurrent: probes are not across two different nodes —
            // nothing for a series meter to be in.
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
            // A real meter beeps below a few tens of ohms; same node through copper is zero.
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

    /// The resistance a component presents, ohms — nil where the idea does not
    /// apply. A capacitor is nil, not infinite: its opposition is a
    /// frequency-dependent reactance, not a resistance.
    nonisolated static func resistance(of component: Component) -> Double? {
        switch component.kind {
        case .resistor: component.value
        case .bulb, .led, .motor: component.value
        case .switcher: component.isClosed ? 0.001 : nil
        case .fuse: component.failed ? nil : 0.001
        case .battery, .acSource: nil
        case .capacitor, .inductor: nil
        }
    }

    /// Auto-ranging, the way a real display does it: milli, then unit,
    /// then kilo, always three significant figures.
    nonisolated static func autoRange(_ value: Double, unit: String) -> String {
        // "0.000 A" and no reading are different claims — this says the reading IS zero.
        guard abs(value) > 1e-9 else { return "0.000 " + unit }
        // Three decimals in every band, like a real auto-ranging DMM.
        return PhysicsFormat.metric(value, unit, decimals: 3)
    }

    // MARK: Workshop state

    /// The AC sources' shared clock.
    private(set) var simTime = 0.0

    // MARK: Time Capsule

    @ObservationIgnored var capsule = TimeCapsule<CapsuleSnapshot>()
    @ObservationIgnored var capsuleClock = 0.0
    /// Non-nil while scrubbed into the past — and then THE BENCH IS READ-ONLY:
    /// `restoreCapsuleSnapshot` overwrites `components`/`wires` on every scrub
    /// change, so every bench-mutating entry point guards on this. Selection,
    /// probing and the net highlight stay live.
    var scrubTime: Double?
    var scrubNonce = 0
    /// Live node voltages by terminal, for the voltage-gradient wires.
    private(set) var terminalVoltages: [Terminal: Double] = [:]
    private(set) var voltageSpan: (min: Double, max: Double) = (0, 0)

    /// One electrical point: its terminals, their centroid (where the skyline
    /// stands its tower), and its potential. Voltage is a solve result, so `nets`
    /// is rebuilt every frame on top of a topology that is not.
    struct Net: Identifiable, Equatable {
        /// The compact node number the solver used. 0 is ground.
        let id: Int
        /// Sorted by slot, so this is deterministic.
        let terminals: [Terminal]
        var position: SIMD3<Double>
        var voltage: Double
    }
    private(set) var nets: [Net] = []
    /// The signature 3-D view: raise every node to its voltage — potential as terrain.
    var showVoltageHeights = false

    /// Draw the magnetic field the bench's own current makes.
    var showMagneticField = false
    /// The Electron View toggle: the whole bench swells around the user.
    var electronView = false

    /// Puts a burned/blown part back in service.
    func replaceFailed(id: UUID) {
        guard scrubTime == nil else { return }
        guard let index = components.firstIndex(where: { $0.id == id }) else { return }
        components[index].failed = false
        emitSound(.chime, at: components[index].position, volume: 0.5)
    }

    // MARK: Persistence (the bench survives relaunch)

    /// A bench as it is WRITTEN. Not private: `migrated` returns one and the
    /// migration tests read it.
    struct SavedBench: Codable {
        var components: [Component]
        var wires: [Wire]
    }

    // MARK: The on-disk row, and why it is not `Component`

    /// A saved component as it comes OFF the disk, `kind` as a raw String.
    /// Decoding straight into `[Component]` throws for the WHOLE array on one
    /// unrecognised kind, and both restore paths swallow that with `try?` — so a
    /// retired kind must be DATA to migrate, not a decode failure. Fields past
    /// `value` are optional because older files predate those keys. Read path
    /// only: the JSON matches what `SavedBench` encodes.
    struct StoredComponent: Codable {
        var id: UUID
        var kind: String
        var position: SIMD3<Double>
        var value: Double
        var axis: SIMD3<Double>?
        var isClosed: Bool?
        var capacitorVoltage: Double?
    }

    struct StoredBench: Codable {
        var components: [StoredComponent]
        var wires: [Wire]
    }

    /// Brings a bench forward across retired kinds. A retired part is SPLICED,
    /// not dropped — everything joined through it stays joined. The splice
    /// partitions ALL stored terminals, then emits a star over each net's
    /// SURVIVING terminals (minimal wire set; T − N edges cannot exceed
    /// `wireBudget`). Unknown/corrupt kinds take the same path: drop the row,
    /// keep the bench.
    static func migrated(_ stored: StoredBench) -> SavedBench {
        // Duplicate ids would splice the wrong things together — harden against
        // files the app did not write.
        var stored = stored
        var seenIDs = Set<UUID>()
        stored.components.removeAll { !seenIDs.insert($0.id).inserted }

        var partition = NetPartition(slotCount: stored.components.count * 2)
        var slotOf: [Terminal: Int] = [:]
        for index in stored.components.indices {
            for end in 0...1 {
                slotOf[Terminal(componentID: stored.components[index].id, end: end)]
                    = NetTopology.slot(componentIndex: index, end: end)
            }
        }
        for wire in stored.wires {
            guard let a = slotOf[wire.from], let b = slotOf[wire.to] else { continue }
            partition.union(a, b)
        }
        // THE SPLICE: a retired part is a conductor between its own two ends —
        // without this a battery → jumper → bulb loop comes back as two dangling
        // halves. Unknown kinds too: over-connecting is the safer wrong answer.
        for index in stored.components.indices
        where ComponentKind(rawValue: stored.components[index].kind) == nil {
            partition.union(NetTopology.slot(componentIndex: index, end: 0),
                            NetTopology.slot(componentIndex: index, end: 1))
        }

        // The survivors, in their original order.
        var components: [Component] = []
        var survivingTerminals: [(terminal: Terminal, slot: Int)] = []
        for index in stored.components.indices {
            let row = stored.components[index]
            guard let kind = ComponentKind(rawValue: row.kind) else { continue }
            var component = Component(id: row.id, kind: kind,
                                      position: row.position, value: row.value)
            if let axis = row.axis, simd_length(axis) > 1e-6 {
                component.axis = simd_normalize(axis)
            }
            component.isClosed = row.isClosed ?? true
            component.capacitorVoltage = row.capacitorVoltage ?? 0
            components.append(component)
            for end in 0...1 {
                survivingTerminals.append((Terminal(componentID: row.id, end: end),
                                           NetTopology.slot(componentIndex: index, end: end)))
            }
        }

        // NOTHING RETIRED, NOTHING REROUTED: re-deriving an already-current bench
        // moves cables the user placed (A–B, B–C would come back A–B, A–C).
        // If every row survived, return the file verbatim.
        if components.count == stored.components.count {
            return SavedBench(components: components, wires: stored.wires)
        }

        // One star per net over whatever survived it.
        var firstOfNet: [Int: Terminal] = [:]
        var wires: [Wire] = []
        for entry in survivingTerminals {
            let root = partition.find(entry.slot)
            if let hub = firstOfNet[root] {
                wires.append(Wire(id: UUID(), from: hub, to: entry.terminal))
            } else {
                firstOfNet[root] = entry.terminal
            }
        }
        return SavedBench(components: components, wires: wires)
    }

    /// The one decode path — auto-save and named slots both come through here,
    /// so a migration can never cover one and miss the other.
    private static func decodeBench(_ data: Data) -> SavedBench? {
        guard let stored = try? JSONDecoder().decode(StoredBench.self, from: data) else { return nil }
        return migrated(stored)
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
        // Never save a scrubbed bench: components/wires hold a RECORDED topology.
        guard scrubTime == nil else { return }
        // Never save mid-pull: beginRewire parks the lifted wire in detachedWires,
        // so a mid-pull save omits a connection a cancel would restore. Every
        // pull-resolving path schedules its own save.
        guard leadPull == nil else { return }
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
        cancelLeadPull()
        voiceWireSource = nil
        highlightedSource = nil
        solve(dt: 1.0 / 90.0)
        return true
    }

    /// Restores the auto-saved bench if one exists.
    private func restoreSavedBench() -> Bool {
        guard let data = UserDefaults.standard.data(forKey: Self.saveKey),
              let bench = Self.decodeBench(data)
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
              let bench = Self.decodeBench(data),
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
            // A battery wired to itself — the wire is the short.
            let battery = place(.battery, at: SIMD3(0, 1.12, -0.9))
            connect((battery, 1), (battery, 0))
        }
        selectedID = components.first?.id
        solve(dt: 1.0 / 90.0)
    }

    // MARK: The bench's own magnetic field

    /// Every current-carrying straight run, for `WireField`: each COMPONENT
    /// (terminal 0 → 1, its solved current) and each WIRE (carrying its `from`
    /// component's branch current — a wire is a short, not a solved element).
    /// SIGNED: without the signs a loop's two sides would reinforce instead of opposing.
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
            // Leaving terminal 1 carries the branch current in the component's
            // sense; leaving terminal 0 the sign flips.
            segments.append(.init(a: from.terminalPosition(wire.from.end),
                                  b: to.terminalPosition(wire.to.end),
                                  current: wire.from.end == 1 ? amps : -amps))
        }
        return segments
    }

    /// B at a point, tesla — the bench's field only; Earth's field is Magnetism's business.
    func magneticField(at point: SIMD3<Double>) -> SIMD3<Double> {
        WireField.field(at: point, segments: currentSegments)
    }

    // MARK: Inductor current

    /// The current through the bench's inductors, in amps, summed.
    var inductorCurrent: Double {
        components
            .filter { $0.kind == .inductor }
            .compactMap { readouts[$0.id]?.amps }
            .reduce(0, +)
    }

    // MARK: Reset

    /// Empties the bench completely — the Clear bench path.
    func clearBench() {
        components = []
        wires = []
        selectedID = nil
        cancelLeadPull()
        voiceWireSource = nil
        highlightedSource = nil
        readouts = [:]
        wireFlows = [:]
        totalSourcePower = 0
    }

    /// The opening scene: a battery–switch–bulb loop already flowing.
    func reset() {
        clearBench()
        // Every bank flag must be restored here — a flag with no visible control
        // drifts out of reset unnoticed (ResetCoverageTests).
        showElectronFlow = true
        trueSpeedMode = false
        showVoltageHeights = false
        showMagneticField = false
        electronView = false
        // The meter's `didSet` drops both probes.
        multimeterArmed = false
        meterMode = .voltsDC
        isPaused = false
        clearCapsule()
        seedStarterLoop()
    }

    private func seedStarterLoop() {
        // A clean rectangle: battery bottom, bulb top, switch upright on the right.
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
        #if DEBUG
        Self.seedLegacyBenchIfAsked()
        #endif
        reset()
        refreshSlotNames()
        if restoreSaved, restoreSavedBench() {
            }
    }

    #if DEBUG
    /// `-circLegacyBench 1` writes a PRE-MIGRATION bench into the save slot
    /// before this model reads it — nothing else can stage a migration: the app
    /// cannot mint a retired kind, and by first view the bench is already
    /// restored. Staged: battery → jumper → bulb plus a kind that never existed;
    /// what must come back is a two-part loop that LIGHTS.
    private static func seedLegacyBenchIfAsked() {
        guard UserDefaults.standard.bool(forKey: "circLegacyBench") else { return }
        let battery = UUID(), jumper = UUID(), bulb = UUID(), ghost = UUID()
        let stored = StoredBench(
            components: [
                .init(id: battery, kind: "battery",
                      position: SIMD3(-0.3, 1.25, -0.9), value: 9),
                .init(id: jumper, kind: "wire",
                      position: SIMD3(0, 1.45, -0.9), value: 0.4),
                .init(id: bulb, kind: "bulb",
                      position: SIMD3(0.3, 1.25, -0.9), value: 24),
                .init(id: ghost, kind: "flux-capacitor",
                      position: SIMD3(0, 1.1, -0.9), value: 1),
            ],
            wires: [
                Wire(id: UUID(), from: .init(componentID: battery, end: 1),
                     to: .init(componentID: jumper, end: 0)),
                Wire(id: UUID(), from: .init(componentID: jumper, end: 1),
                     to: .init(componentID: bulb, end: 0)),
                Wire(id: UUID(), from: .init(componentID: bulb, end: 1),
                     to: .init(componentID: battery, end: 0)),
                Wire(id: UUID(), from: .init(componentID: ghost, end: 0),
                     to: .init(componentID: bulb, end: 1)),
            ])
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: saveKey)
        }
    }
    #endif
}

// MARK: - Time Capsule

extension CircuitsModel: TimeCapsuleRecording {
    /// The bench and its transients: `Component` already carries every integrated
    /// quantity, and snapshotting the WIRES restores mid-window rewirings; the
    /// per-frame solve re-derives readouts, so nothing here stores a result.
    /// Out: the half-made wire and the meter's arming (observer state).
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
        // The scope strip chart is monotone in simTime — scrubbing back cuts off the future.
        // A restore replaces the WHOLE bench, so all in-flight observer state
        // clears unconditionally — never gated on something being selected.
        cancelLeadPull()
        voiceWireSource = nil
        highlightedSource = nil
        if let selectedID, !components.contains(where: { $0.id == selectedID }) {
            self.selectedID = nil
        }
    }
}
