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
import QuartzCore
import simd

@MainActor
@Observable
final class CircuitsModel {
    // MARK: Build volume & budgets

    nonisolated static let buildCenter = SIMD3<Double>(0, 1.25, -0.9)

    /// The bench's nominal volume: where a reset lays the starter loop out
    /// and where the flanking instruments take their clearance bearings.
    /// Not a wall — a hand meets only the floor; `clampToRoomSafety` is
    /// the only clamp.
    nonisolated static let buildHalfExtents = SIMD3<Double>(0.60, 0.48, 0.33)

    /// The free simulation's safety bounds, room-scale and never applied
    /// to a hand.
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
        // Grouped for the reader: power, passives, outputs, control.
        // The rack's order is `CircuitsPartsLayout.kinds(on:)`, not this.
        case battery, acSource, resistor, capacitor, inductor
        case bulb, led, motor, fuse, switcher

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .battery: "Battery"
            case .acSource: "AC source"
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

        /// The name mid-sentence, as the meter's notes use it: "across the
        /// battery", "the AC source is live". Acronyms keep their capitals.
        var inSentence: String {
            switch self {
            case .acSource: "AC source"
            case .led: "LED"
            default: displayName.lowercased()
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
    /// The AC frequency when a part does not say otherwise; each source
    /// carries its own (`Component.acFrequency`).
    nonisolated static let acFrequency = 0.5
    /// A bulb on AC flashes at twice the source's frequency (its power
    /// goes as sin²) and an LED, conducting one half-cycle, at the
    /// frequency itself. WCAG 2.3.1 allows three flashes a second, so the
    /// source stops at 1.5 Hz: 5 Hz flashed a bulb ten times a second.
    nonisolated static let acFrequencyRange = 0.1...1.5        // Hz

    /// A frequency the rail can reach — what every write and every
    /// restore goes through, so a bench saved under the old 5 Hz rail
    /// cannot bring the flashing back.
    nonisolated static func clampedACFrequency(_ hertz: Double) -> Double {
        min(max(hertz, acFrequencyRange.lowerBound), acFrequencyRange.upperBound)
    }

    /// The inductor as a coil: 0.07 m long with 0.019 m windings, so for
    /// an air core L = μ₀N²A/ℓ gives the turn count the field layer draws
    /// with (0.5 H is about 4,960 turns).
    nonisolated static let inductorCoilLength = 0.07
    nonisolated static let inductorCoilRadius = 0.019
    nonisolated static func inductorTurns(henries: Double) -> Int {
        let area = CurrentLoop.area(radius: inductorCoilRadius)
        guard henries > 0, area > 0 else { return 0 }
        return Int((henries * inductorCoilLength / (CurrentLoop.mu0 * area)).squareRoot().rounded())
    }

    /// A resistor is rated: past its rating it stores the excess as heat,
    /// under it it cools, and a sustained overload scorches it. Only
    /// resistors carry a rating; the bulb runs hot by design, the fuse and
    /// LED fail their own way.
    nonisolated static func powerRating(for kind: ComponentKind) -> Double? {
        kind == .resistor ? 2.0 : nil
    }
    /// Joules of excess a resistor absorbs before it scorches: a spike is
    /// forgiven, six seconds at 50 % over is not.
    nonisolated static let thermalBudget = 4.0

    // DC motor: back-EMF and torque share k (V·s/rad = N·m/A); coil resistance is the
    // component's value. No-load steady speed ω = kV/(bR + k²) — the property the tests pin.
    nonisolated static let motorTorqueConstant = 0.06
    nonisolated static let motorFriction = 0.0008
    /// kg·m²: the steel flywheel the motor wears (2026-10-30, contract D4) —
    /// a rim 80 mm across, 26 mm bore, 20 mm thick, on a 4 mm web — so the
    /// spin-up a wearer watches is the inertia they see turning. It was a
    /// round 0.0009 with nothing drawn to carry it; `Tools/circuitparts.py`
    /// refuses to mill a flywheel that disagrees, and `CircuitPropTests`
    /// holds this to its literal there.
    nonisolated static let motorInertia = 0.000543

    /// How long a thrown switch's blade takes to fall into its contact, s.
    /// A real knife switch closes the circuit when the blade lands, not when
    /// the hand lets go — so the bulb lights on the landing (2026-10-30,
    /// contract D3). Opening is immediate: the blade leaves at once.
    nonisolated static let switchCloseDelay = 0.12

    /// How near two leads must come to be one point, for both a pull and a
    /// release. One part's two leads are 0.17 m apart, so this cannot reach
    /// past the end it belongs to.
    nonisolated static let leadReach = 0.06

    // MARK: The turntable (2026-10-18)

    /// The disc the floating circuit stands over — the owner's choice of a
    /// designed container: the parts still float, and a slim milled disc
    /// hovers under them with their shadows on it. Its centre in the room's
    /// x and z, its top's height, and how far it has been turned. Nothing
    /// rests on it; it follows the circuit (`settleStage`).
    nonisolated struct Stage: Equatable, Codable {
        var center: SIMD2<Double>
        var top: Double
        var yaw: Double
    }
    /// The rim's outer radius, as `Tools/circuitparts.py` mills it.
    nonisolated static let stageRadius = 0.45
    /// How far under the circuit's lowest point the stage sits, and the
    /// lowest it may go.
    nonisolated static let stageClearance = 0.30
    nonisolated static let stageFloor = 0.30
    /// Where the stage stands at a reset: the frame the starter loop and the
    /// presets are authored in.
    nonisolated static let homeStage = Stage(center: SIMD2(buildCenter.x, buildCenter.z),
                                             top: 0.82, yaw: 0)
    private(set) var stage = CircuitsModel.homeStage

    /// Carries the whole circuit and its stage by `offset`: every part, so
    /// every wire, rigidly. The offset is clamped, axis by axis, so every part
    /// stays inside the room's safety box and the stage never sinks below its
    /// floor — the circuit slides along a limit rather than shearing at it.
    /// Returns the offset applied.
    @discardableResult
    func moveCircuit(by offset: SIMD3<Double>) -> SIMD3<Double> {
        guard scrubTime == nil, leadPull == nil, !components.isEmpty else { return .zero }
        var low = -SIMD3<Double>(repeating: .infinity), high = SIMD3<Double>(repeating: .infinity)
        var boxLow = Self.buildCenter - Self.safetyHalfExtents
        boxLow.y = max(boxLow.y, Self.floorMargin)
        let boxHigh = Self.buildCenter + Self.safetyHalfExtents
        var lowest = Double.infinity
        for component in components {
            for point in [component.position, component.terminalPosition(0),
                          component.terminalPosition(1)] {
                low = simd_max(low, boxLow - point)
                high = simd_min(high, boxHigh - point)
                lowest = min(lowest, point.y)
            }
        }
        // The stage hangs `stageClearance` under the lowest point and stops
        // at `stageFloor`: the circuit stops with it.
        low.y = max(low.y, Self.stageFloor + Self.stageClearance - lowest)
        let applied = simd_clamp(offset, simd_min(low, .zero), simd_max(high, .zero))
        guard simd_length(applied) > 1e-12 else { return .zero }
        for index in components.indices { components[index].position += applied }
        stage.center += SIMD2(applied.x, applied.z)
        settleStage()
        persistSoon()
        return applied
    }

    // MARK: Turning the circuit on its stage (2026-10-18)

    /// A turn the hand is making: its last bearing about the stage's axis,
    /// when, and how fast it has been turning.
    private struct StageSpin {
        var bearing: Double
        var time: Double
        var rate: Double
    }
    @ObservationIgnored private var stageSpin: StageSpin?
    /// The coast a let-go turn keeps, rad/s, dying away over `stageCoastTime`.
    /// Apparatus, so recorded by the Time Capsule.
    private(set) var stageSpinRate = 0.0
    nonisolated static let stageCoastTime = 0.35
    /// Below this a coast has stopped, rad/s.
    nonisolated static let stageCoastStop = 0.05
    /// The fastest a let-go turn coasts, rad/s — a flick is not a centrifuge.
    nonisolated static let stageCoastLimit = 6.0
    /// A quiet detent tick every this many radians of turn, as the shelf's
    /// crown ticks a slot.
    nonisolated static let stageTickAngle = Double.pi / 6
    @ObservationIgnored private var stageTickTravel = 0.0
    /// Where the hand carrying the stage by its deck last was.
    @ObservationIgnored private var stageCarryHand: SIMD3<Double>?

    /// Turns the whole circuit about the stage's vertical axis by `angle`:
    /// every part's centre and its axis, so every wire, rigidly. Refused
    /// whole if a part would leave the room's safety box, while scrubbed,
    /// or while a lead is being pulled. Returns whether it turned.
    @discardableResult
    func spinCircuit(by angle: Double) -> Bool {
        guard scrubTime == nil, leadPull == nil, !components.isEmpty,
              angle.isFinite, angle != 0 else { return false }
        let turn = simd_quatd(angle: angle, axis: [0, 1, 0])
        let axis = SIMD3(stage.center.x, 0, stage.center.y)
        var turned = components
        for index in turned.indices {
            turned[index].position = axis + turn.act(turned[index].position - axis)
            turned[index].axis = turn.act(turned[index].axis)
            for point in [turned[index].position, turned[index].terminalPosition(0),
                          turned[index].terminalPosition(1)]
            where simd_distance(Self.clampToRoomSafety(point), point) > 1e-9 {
                return false
            }
        }
        components = turned
        stage.yaw = (stage.yaw + angle).remainder(dividingBy: 2 * .pi)
        stageTickTravel += abs(angle)
        if stageTickTravel >= Self.stageTickAngle {
            stageTickTravel = stageTickTravel.truncatingRemainder(dividingBy: Self.stageTickAngle)
            emitSound(.grabTick, at: SIMD3(stage.center.x, stage.top, stage.center.y), volume: 0.12)
        }
        return true
    }

    /// A hand's bearing about the stage's axis, rad, in the sense `yaw`
    /// turns (counter-clockwise from above).
    private func bearing(of hand: SIMD3<Double>) -> Double {
        atan2(-(hand.z - stage.center.y), hand.x - stage.center.x)
    }

    /// A hand takes the rim. `time` is the gesture's clock, s.
    @discardableResult
    func beginSpin(hand: SIMD3<Double>, at time: Double) -> Bool {
        guard scrubTime == nil, leadPull == nil, !components.isEmpty else { return false }
        stageSpinRate = 0
        stageCarryHand = nil
        stageSpin = StageSpin(bearing: bearing(of: hand), time: time, rate: 0)
        return true
    }

    /// The circuit turns with the hand about the stage's axis, one to one.
    func updateSpin(hand: SIMD3<Double>, at time: Double) {
        guard var spin = stageSpin else { return }
        // Too near the axis a bearing is noise.
        guard simd_length(SIMD2(hand.x - stage.center.x, hand.z - stage.center.y)) > 0.05
        else { return }
        let now = bearing(of: hand)
        let delta = (now - spin.bearing).remainder(dividingBy: 2 * .pi)
        let elapsed = time - spin.time
        if spinCircuit(by: delta), elapsed > 1e-4 {
            // Smoothed over ~80 ms: one jittery sample must not set the coast.
            spin.rate += (delta / elapsed - spin.rate) * min(1, elapsed / 0.08)
        }
        spin.bearing = now
        spin.time = time
        stageSpin = spin
    }

    /// Lets the rim go. It coasts on at the hand's rate — unless `coasts` is
    /// false (Reduce Motion), the bench is paused, or the hand had stopped.
    func endSpin(coasts: Bool, at time: Double) {
        guard let spin = stageSpin else { return }
        stageSpin = nil
        let stillFor = time - spin.time
        let rate = coasts && !isPaused && stillFor < 0.1 ? spin.rate : 0
        stageSpinRate = abs(rate) < Self.stageCoastStop
            ? 0 : min(max(rate, -Self.stageCoastLimit), Self.stageCoastLimit)
        persistSoon()
    }

    /// A press on any part stops a coast: the hand wants the circuit still.
    func stopStageCoast() { stageSpinRate = 0 }

    #if DEBUG
    /// `-circStageCoast <deg/s>`: a coast for a still.
    func setStageCoast(rate: Double) { stageSpinRate = rate }
    #endif

    /// A hand takes the deck's band: the circuit rides it.
    @discardableResult
    func beginStageCarry(hand: SIMD3<Double>) -> Bool {
        guard scrubTime == nil, leadPull == nil, !components.isEmpty else { return false }
        stageSpinRate = 0
        stageSpin = nil
        stageCarryHand = hand
        return true
    }

    /// The circuit follows the hand. Against a limit it stops and the hand
    /// slips, so it follows straight back the moment the hand turns.
    func updateStageCarry(hand: SIMD3<Double>) {
        guard let last = stageCarryHand else { return }
        moveCircuit(by: hand - last)
        stageCarryHand = hand
    }

    func endStageCarry() {
        guard stageCarryHand != nil else { return }
        stageCarryHand = nil
        persistSoon()
    }

    /// The coast, each unpaused frame: the turn decays as e^(−t/τ).
    private func coastStage(dt: Double) {
        guard stageSpinRate != 0, stageSpin == nil else { return }
        guard !isPaused, scrubTime == nil, spinCircuit(by: stageSpinRate * dt) else {
            stageSpinRate = 0
            return
        }
        stageSpinRate *= exp(-dt / Self.stageCoastTime)
        if abs(stageSpinRate) < Self.stageCoastStop {
            stageSpinRate = 0
            persistSoon()
        }
    }

    /// A point authored about the home stage, in the stage as it stands: set
    /// over its centre and height. A preset keeps its own facing — authored to
    /// face the wearer, it would face away on a stage turned round.
    private func onStage(_ point: SIMD3<Double>) -> SIMD3<Double> {
        let home = Self.homeStage
        return point + SIMD3(stage.center.x - home.center.x,
                             0, stage.center.y - home.center.y)
    }

    /// Sets the stage `stageClearance` under the circuit's lowest point — a
    /// terminal or a part's centre — and never below `stageFloor`. An empty
    /// bench leaves it where it was.
    func settleStage() {
        var lowest = Double.infinity
        for component in components {
            lowest = min(lowest, component.position.y,
                         component.terminalPosition(0).y, component.terminalPosition(1).y)
        }
        guard lowest.isFinite else { return }
        stage.top = max(Self.stageFloor, lowest - Self.stageClearance)
    }

    nonisolated struct Terminal: Equatable, Hashable, Codable {
        var componentID: UUID
        var end: Int  // 0 = left (battery +), 1 = right
    }

    nonisolated struct Component: Identifiable, Equatable, Codable {
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
        /// Switches only: seconds until a closing blade lands in its contact
        /// — transient. A switch is closed only once its blade is there
        /// (contract D3); 0 when nothing is falling.
        var closingIn = 0.0
        /// Rated parts only: joules of excess dissipation stored as heat
        /// — transient; past `thermalBudget` the part scorches.
        var thermalEnergy = 0.0
        /// AC sources only: their own frequency, Hz — persisted, and a
        /// stored bench without it runs at the old fixed 0.5 Hz.
        var acFrequency = CircuitsModel.acFrequency

        private enum CodingKeys: String, CodingKey {
            case id, kind, position, value, axis, isClosed, capacitorVoltage, acFrequency
        }

        /// Tolerant of every field but the four that define a part, so an
        /// older bench still decodes.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(UUID.self, forKey: .id)
            kind = try container.decode(ComponentKind.self, forKey: .kind)
            position = try container.decode(SIMD3<Double>.self, forKey: .position)
            value = try container.decode(Double.self, forKey: .value)
            if let stored = try container.decodeIfPresent(SIMD3<Double>.self, forKey: .axis),
               simd_length(stored) > 1e-6 {
                axis = simd_normalize(stored)
            }
            isClosed = try container.decodeIfPresent(Bool.self, forKey: .isClosed) ?? true
            capacitorVoltage = try container.decodeIfPresent(Double.self, forKey: .capacitorVoltage) ?? 0
            acFrequency = CircuitsModel.clampedACFrequency(
                try container.decodeIfPresent(Double.self, forKey: .acFrequency)
                    ?? CircuitsModel.acFrequency)
        }

        /// Spelled out because the tolerant `init(from:)` suppresses the
        /// synthesised one.
        init(id: UUID, kind: ComponentKind, position: SIMD3<Double>, value: Double,
             axis: SIMD3<Double> = SIMD3(1, 0, 0), isClosed: Bool = true,
             capacitorVoltage: Double = 0, failed: Bool = false,
             inductorCurrent: Double = 0, motorSpeed: Double = 0,
             thermalEnergy: Double = 0,
             acFrequency: Double = CircuitsModel.acFrequency) {
            self.id = id
            self.kind = kind
            self.position = position
            self.value = value
            self.axis = axis
            self.isClosed = isClosed
            self.capacitorVoltage = capacitorVoltage
            self.failed = failed
            self.inductorCurrent = inductorCurrent
            self.motorSpeed = motorSpeed
            self.thermalEnergy = thermalEnergy
            self.acFrequency = acFrequency
        }

        /// Where one of this part's two leads sits.
        func terminalPosition(_ end: Int) -> SIMD3<Double> {
            let halfSpan = CircuitsModel.terminalOffset
            return position + (end == 0 ? -halfSpan : halfSpan) * axis
        }
    }

    nonisolated struct Wire: Identifiable, Equatable, Codable {
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

    /// Shows the drift at its real relative rate: electrons frozen, the field
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

    /// The loop an electron walks, metres: the chord sum of every carrying
    /// wire, the same distances the field front walks.
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
        let fallback = onStage(Self.buildCenter)
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

    /// The move a release would make. Pure — no mutation — so the renderer can
    /// ghost the landing while the part is still in the hand.
    struct Alignment: Equatable {
        let componentID: UUID
        /// The lead that lands.
        let end: Int
        let target: Terminal
        let position: SIMD3<Double>
        let axis: SIMD3<Double>
    }

    /// Where a release would put this part, if anywhere. The released part
    /// moves and rotates about the landing lead; the target never moves,
    /// which stops cascades.
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

        // Swing the far end away from the joint; landing lead exactly on target.
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

        // Clamp veto: if the safety clamp would move the aligned part, the
        // leads would end up visibly apart — abandon the geometry and let the
        // wire span the gap.
        guard simd_distance(Self.clampToRoomSafety(position), position) < 1e-9 else { return nil }
        return Alignment(componentID: id, end: best.end, target: best.target,
                         position: position, axis: axis)
    }

    /// What a release did. A refusal is shown (the thud), never a silent
    /// no-op.
    enum ReleaseOutcome: Equatable {
        case joined
        /// Something was in reach, and joining it was refused — the
        /// same net through another path, or the wire budget is full.
        case refused
        /// Open air. Honestly silent: no join was on offer.
        case nothingNear
    }

    /// The one place a carried part lands: align first, then wire from the
    /// pairs the aligned part sees. The target never moves, which is also
    /// what stops a cascade.
    @discardableResult
    func release(id: UUID) -> ReleaseOutcome {
        guard scrubTime == nil else { return .nothingNear }
        guard components.contains(where: { $0.id == id }) else { return .nothingNear }
        // Wherever it lands, the stage keeps its clearance under the circuit.
        defer { settleStage() }
        let alignment = alignment(for: id)
        if let alignment, let index = components.firstIndex(where: { $0.id == id }) {
            components[index].position = alignment.position
            components[index].axis = alignment.axis
        }
        let pairs = pendingJoins(for: id)
        guard let component = components.first(where: { $0.id == id }) else {
            return .nothingNear
        }
        guard !pairs.isEmpty else {
            // Nothing joinable, but a same-net terminal in reach gets the same
            // "no" the lead pull gives.
            if let refused = refusedJoins(for: id).first {
                emitSound(.thud, at: component.position, volume: 0.5)
                announceNetRefusal(at: refused.to)
                return .refused
            }
            return .nothingNear
        }
        var joined = false
        for pair in pairs {
            if case .connected = connectTerminals(pair.from, pair.to) { joined = true }
        }
        guard joined else {
            // Pairs were on offer and every join was refused: the budget.
            emitSound(.thud, at: component.position, volume: 0.5)
            return .refused
        }
        // Two dots meeting seat with a snap; a wire across a gap the clamp
        // would not let it close lands with the chime.
        emitSound(alignment == nil ? .chime : .seat, at: component.position, volume: 0.55)
        persistSoon()
        return .joined
    }

    /// The joins a release would refuse: for each end, the nearest foreign
    /// terminal within `leadReach` that is already the same electrical
    /// point through another path. A pair these ends already share a wire
    /// over is excluded. The renderer tints these red while the part is
    /// carried.
    func refusedJoins(for id: UUID) -> [(from: Terminal, to: Terminal)] {
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
                    guard net.sameNet(mine, theirs) else { continue }
                    guard !wires.contains(where: {
                        ($0.from == mine && $0.to == theirs)
                            || ($0.from == theirs && $0.to == mine)
                    }) else { continue }
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

    /// The one verb a carried part is driven by, each frame: a part hanging
    /// by exactly one wired lead swings about its joint, anything else moves
    /// rigidly. A wire never lets go because of distance — it stretches as
    /// far as the hand takes the part, and comes off only when pulled off
    /// its terminal. Composed here so a test can drive the real sequence.
    func drag(id: UUID, toward target: SIMD3<Double>) {
        if !swing(id: id, hand: target) {
            move(id: id, to: target)
        }
    }

    /// A carried part with exactly one wired lead swings about its joint —
    /// the far terminal of that wire, the genuinely fixed point. Within the
    /// body's reach the lead sits on the joint; past it the body tracks the
    /// hand while aiming its lead back, so the wire stretches with it.
    /// Returns whether it owned the carry.
    @discardableResult
    func swing(id: UUID, hand: SIMD3<Double>) -> Bool {
        guard scrubTime == nil else { return false }
        guard let index = components.firstIndex(where: { $0.id == id }) else { return false }
        let ends = (0...1).filter { end in
            wires.contains { $0.from == Terminal(componentID: id, end: end)
                          || $0.to == Terminal(componentID: id, end: end) }
        }
        guard ends.count == 1, let pinned = ends.first else { return false }
        let mine = Terminal(componentID: id, end: pinned)
        let anchors = wires.compactMap { wire -> SIMD3<Double>? in
            if wire.from == mine { return terminalWorldPosition(wire.to) }
            if wire.to == mine { return terminalWorldPosition(wire.from) }
            return nil
        }
        // Several wires on the one lead: hang from the nearest joint.
        guard let pivot = anchors.min(by: {
            simd_distance($0, hand) < simd_distance($1, hand) })
        else { return false }
        var direction = hand - pivot
        let reach = simd_length(direction)
        guard reach > 1e-4 else { return false }
        direction /= reach
        let position = pivot + direction * max(reach, Self.terminalOffset)
        // Same clamp veto as `alignment(for:)`: refuse and let `drag` fall
        // back to the rigid move.
        guard simd_distance(Self.clampToRoomSafety(position), position) < 1e-9 else { return false }
        components[index].axis = pinned == 0 ? direction : -direction
        components[index].position = position
        return true
    }

    // MARK: Detaching

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

    /// Terminal-to-terminal wiring. No self-wires, and no wire between ends
    /// already one point: the same-net rule catches a second path.
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

    /// Folds a point into the nominal bench box — the layout question
    /// `reset`'s seeding and the layout tests ask, never applied to a hand.
    nonisolated static func clampToBench(
        _ point: SIMD3<Double>
    ) -> SIMD3<Double> {
        var clamped = simd_clamp(point,
                                 buildCenter - buildHalfExtents,
                                 buildCenter + buildHalfExtents)
        clamped.y = max(clamped.y, floorMargin)
        return clamped
    }

    /// Clamps a part into the room-scale safety box, the only clamp a hand
    /// meets.
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

    /// A half-made wire, in flight. Lives in the model, not the gesture, so
    /// `removeComponent` can cancel it — where the zombie-wire defect died.
    struct LeadPull: Equatable {
        /// The lead the wire is coming from.
        var source: Terminal
        /// Set when this pull lifted an existing wire off a terminal (a rewire).
        /// The wire is already out of `wires` by then.
        var detached: UUID?
        /// Where the hand is, in bench coordinates.
        var hand: SIMD3<Double>
        /// What a release right now would land on.
        var target: Terminal?
        /// Why a release right now would refuse — nil when it would connect.
        /// Computed every frame, before the release, so preview equals outcome.
        var refusal: ConnectOutcome?
    }

    /// A press on a wire: which wire, and where the hand pressed it. Which
    /// end comes off is decided when the press becomes a pull
    /// (`endToLift`), from the way the hand has moved by then.
    struct WirePress: Equatable, Sendable {
        let wire: UUID
        let pressedAt: SIMD3<Double>
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

    /// Lifts an existing wire's end off its terminal into the same lead
    /// pull, drawn from the end that stayed. The wire leaves `wires`
    /// immediately: the circuit going dark in your hand is the teach.
    func beginRewire(wire id: UUID, grabbing end: Int, hand: SIMD3<Double>) {
        guard scrubTime == nil else { return }
        guard wires.contains(where: { $0.id == id }) else { return }
        // One pull at a time: a second `begin` would lose a lifted wire.
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

    /// Two leads nearer than this are one JOINT (2026-10-18): the renderer
    /// draws one junction dot there and makes it the one thing to grab,
    /// withdrawing the two coincident leads' own targets, which overlapped.
    /// Two 17 mm dots' diameters and 4 mm (0.052 for the lab kit's 24 mm
    /// balls, until 2026-10-30).
    nonisolated static let jointLength = 0.038

    func isJoint(_ wire: Wire) -> Bool { wireLength(wire) < Self.jointLength }

    /// Which end a pull lifts, decided when the press becomes a pull — so
    /// the hand's first 12 mm of travel are known. Along a cable, the end
    /// nearer the hand: that end if pressed near it, and from the middle
    /// the end the hand moved toward. At a joint, where both ends are one
    /// point, the side the hand pulls away from keeps the wire: the lead is
    /// drawn out of that part's contact and the other part's comes free.
    func endToLift(of id: UUID, pressedAt press: SIMD3<Double>,
                   hand: SIMD3<Double>) -> Int? {
        guard let wire = wires.first(where: { $0.id == id }) else { return nil }
        guard isJoint(wire) else { return nearerEnd(of: id, to: hand) }
        let motion = hand - press
        // How far the hand moves toward each side's own part, from the joint.
        func toward(_ terminal: Terminal) -> Double {
            guard let part = components.first(where: { $0.id == terminal.componentID })
            else { return 0 }
            let body = part.position - part.terminalPosition(terminal.end)
            let length = simd_length(body)
            return length > 1e-9 ? simd_dot(body / length, motion) : 0
        }
        // The side pulled away from is the anchor; the other end lifts.
        return toward(wire.from) <= toward(wire.to) ? 1 : 0
    }

    /// Follow the hand, and work out what a release would do.
    func updateLeadPull(hand: SIMD3<Double>) {
        guard var pull = leadPull else { return }
        pull.hand = hand
        // Target found from the lead tip at the same `leadReach` a release
        // uses, so the preview cannot snap to something the release ignores.
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
            // The refusal is the renderer's recoil; no text — and a same-net
            // "no" lights the net that already joins them.
            emitSound(.thud, at: pull.hand, volume: 0.35)
            if outcome == .sameNet { announceNetRefusal(at: target) }
            if let detached = pull.detached {
                // A refused rewire is not a deletion — put the wire back.
                restore(wireID: detached)
            }
            return .refused(outcome)
        }
    }

    /// Abandons a pull without landing it — the part went away, the bench
    /// was cleared, the lab was reset.
    func cancelLeadPull() {
        guard let pull = leadPull else { return }
        leadPull = nil
        if let detached = pull.detached { restore(wireID: detached) }
        // Flush the save `persistNow` deferred during the pull.
        persistSoon()
    }

    /// Puts a lifted wire back exactly as it was. The whole wire is kept:
    /// rebuilding it from the anchor makes a zero-length self-wire.
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

    /// The tapped terminal whose net is lit. A selection, not a display
    /// layer, and selection-driven rather than hover
    /// (`HoverEffectComponent` has no callback). Stores the terminal, not
    /// the node: deleting a part renumbers nodes.
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
        highlightedSource.map(netTerminals(containing:)) ?? []
    }

    /// Every terminal at one electrical point with this one, itself
    /// included — what the tap highlight lights, and what a "these are
    /// already connected" refusal lights to show the path that connects them.
    func netTerminals(containing terminal: Terminal) -> [Terminal] {
        let net = topology()
        guard let node = net.node(of: terminal), node < net.terminalsByNode.count else { return [] }
        return net.terminalsByNode[node]
    }

    /// The last join refused because its two ends were already one point
    /// (2026-10-18): a lead let go on its own net, or a part set down
    /// against it. The renderer lights that net for a moment, so the "no"
    /// shows the connection it found. A full wire budget is not one of
    /// these — it only recoils. An event, like `soundEvent`.
    struct NetRefusal: Equatable {
        let terminal: Terminal
        let serial: Int
    }
    private(set) var lastNetRefusal: NetRefusal?
    private var netRefusalCounter = 0

    private func announceNetRefusal(at terminal: Terminal) {
        netRefusalCounter += 1
        lastNetRefusal = NetRefusal(terminal: terminal, serial: netRefusalCounter)
    }

    /// Whether a wire lies inside the lit net (either end answers — both are one point).
    func isHighlighted(wire: Wire) -> Bool {
        guard let highlightedSource else { return false }
        let net = topology()
        guard let lit = net.node(of: highlightedSource) else { return false }
        return net.node(of: wire.from) == lit
    }

    /// The lead VoiceOver is wiring from — tap-tap wiring, through the
    /// accessibility door only; the pinch path never reads it.
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

    /// VoiceOver's wire removal: the pinch path deletes a wire by pulling
    /// an end into open air, a gesture VoiceOver cannot make. Physical taps
    /// never call this.
    /// VoiceOver's way to take a wire off, which a pinch does by pulling it:
    /// the first activation arms it and a second within `wireArmWindow`
    /// removes it — a destructive verb arms before it fires (2026-10-18; it
    /// used to delete on the first). Returns whether the wire went.
    @discardableResult
    func voiceOverRemoveWire(id: UUID, now: Double = CACurrentMediaTime()) -> Bool {
        if armedWireID == id, now - armedWireAt <= Self.wireArmWindow {
            armedWireID = nil
            deleteWire(id: id)
            return true
        }
        armedWireID = wires.contains { $0.id == id } ? id : nil
        armedWireAt = now
        return false
    }

    /// The wire VoiceOver has armed for removal, and when.
    private(set) var armedWireID: UUID?
    @ObservationIgnored private var armedWireAt = -Double.infinity
    nonisolated static let wireArmWindow = 4.0

    func deleteWire(id: UUID) {
        guard scrubTime == nil else { return }
        guard let wire = wires.first(where: { $0.id == id }) else { return }
        wires.removeAll { $0.id == id }
        if let component = components.first(where: { $0.id == wire.from.componentID }) {
            emitSound(.thud, at: component.terminalPosition(wire.from.end), volume: 0.3)
        }
        persistSoon()
    }

    /// Throws a switch. Open, it starts its blade falling and closes the
    /// circuit `switchCloseDelay` later, when the blade lands; closed, or
    /// still falling, it lifts at once and the circuit opens now.
    func toggleSwitch(id: UUID) {
        guard scrubTime == nil else { return }
        guard let index = components.firstIndex(where: { $0.id == id }),
              components[index].kind == .switcher else { return }
        if components[index].isClosed || components[index].closingIn > 0 {
            components[index].isClosed = false
            components[index].closingIn = 0
            emitSound(.clack, at: components[index].position, volume: 0.3)
        } else {
            components[index].closingIn = Self.switchCloseDelay
        }
        selectedID = id
        persistSoon()
    }

    /// Lands any falling blade whose time is up: the circuit closes this
    /// step, before the solve, with the clack of the blade seating. Counted
    /// in real time even when paused, as an edit is — the hand threw it.
    private func advanceSwitches(dt: Double) {
        for index in components.indices where components[index].closingIn > 0 {
            components[index].closingIn = max(0, components[index].closingIn - dt)
            if components[index].closingIn == 0 {
                components[index].isClosed = true
                emitSound(.clack, at: components[index].position, volume: 0.55)
                persistSoon()
            }
        }
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
        // A half-drawn wire cannot survive its own part: clear pull, voice and
        // highlight state.
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

    /// Solve, then record. The solve runs every frame even while paused (a
    /// frozen bench shows honest readouts); only unpaused frames are
    /// recorded.
    func step(dt: Double) {
        let isRecordingFrame = !isPaused
        coastStage(dt: dt)
        advanceSwitches(dt: dt)
        solve(dt: dt)
        if isRecordingFrame {
            recordCapsuleFrame(dt: min(max(dt, 1e-4), 1.0 / 30.0))
        }
    }

    // MARK: Nets — which terminals are the same electrical point

    /// The bench's connectivity, resolved — the solve, wiring, meter and skyline all read it.
    struct NetTopology {
        /// Load-bearing: keeps the stamping loop index-parallel with
        /// `components`.
        static func slot(componentIndex: Int, end: Int) -> Int { 2 * componentIndex + end }

        /// What the cache was built from; comparing against the live bench is
        /// the invalidation.
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
    /// Rebuild count, so a test can assert that moving a part does not rebuild —
    /// geometry is not topology.
    @ObservationIgnored private(set) var netRebuildCount = 0
    #endif

    /// Connectivity, rebuilt only when topology changed — not moves, values
    /// or switch state. No invalidation call: the cache compares its ids
    /// and wires against the bench.
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
        // `elements[i]` is `components[i]`: the index parity every readout
        // reads back through.
        let elements = components.enumerated().map { (index, component) -> CircuitElement in
            let a = node(index, 0)
            let b = node(index, 1)
            let kind: CircuitElement.Kind = switch component.kind {
            case .battery:
                .battery(volts: component.value,
                         internalResistance: Self.batteryInternalResistance)
            case .acSource:
                .battery(volts: component.value
                            * sin(2 * .pi * component.acFrequency * simTime),
                         internalResistance: Self.batteryInternalResistance)
            case .resistor:
                // A scorched resistor is an open circuit — the loop goes
                // dark, which is how you learn what it was doing.
                component.failed ? .open : .resistor(ohms: component.value)
            case .bulb:
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
        // The meter is a real element, stamped only in A⎓ and only across two
        // different nodes: in V⎓ its shunt would short the measurand.
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
            // Heat: the excess over a rated part's rating accumulates as
            // energy, and cools at the same rate when under it.
            if !isPaused, !component.failed,
               let rating = Self.powerRating(for: component.kind) {
                let excess = solution.powers[index] - rating
                components[index].thermalEnergy = max(
                    0, components[index].thermalEnergy + excess * timeStep)
                if components[index].thermalEnergy > Self.thermalBudget {
                    components[index].failed = true
                    components[index].thermalEnergy = 0
                    emitSound(.boom, at: component.position, volume: 0.35)
                }
            }
        }
        readouts = newReadouts
        totalSourcePower = sourcePower
        // Wire currents, for the electron flow and the wire's field: each
        // terminal pushes its component's current into the wiring, the meter
        // draws its own between its probes in A⎓, and Kirchhoff divides it
        // among the wires (`WireCurrents`; copper's 1/length settles a loop,
        // which the wiring rules never build). Until 2026-10-18 each terminal's
        // current was split evenly over its wires, and the field gave every
        // wire its part's full current: in a parallel net the two disagreed.
        var componentIndex: [UUID: Int] = [:]
        componentIndex.reserveCapacity(components.count)
        for (index, component) in components.enumerated() {
            componentIndex[component.id] = index
        }
        var injections = [Double](repeating: 0, count: components.count * 2)
        for index in components.indices {
            injections[2 * index + 1] += solution.currents[index]
            injections[2 * index] -= solution.currents[index]
        }
        if let meterElementIndex, let probeA, let probeB,
           let a = componentIndex[probeA.componentID],
           let b = componentIndex[probeB.componentID] {
            let meter = solution.currents[meterElementIndex]
            injections[2 * a + probeA.end] -= meter
            injections[2 * b + probeB.end] += meter
        }
        var edges: [WireCurrents.Edge] = []
        var conductances: [Double] = []
        var edgeWires: [UUID] = []
        edges.reserveCapacity(wires.count)
        for wire in wires {
            guard let a = componentIndex[wire.from.componentID],
                  let b = componentIndex[wire.to.componentID] else { continue }
            edges.append(.init(a: 2 * a + wire.from.end, b: 2 * b + wire.to.end))
            let length = simd_distance(components[a].terminalPosition(wire.from.end),
                                       components[b].terminalPosition(wire.to.end))
            conductances.append(1 / max(length, 1e-3))
            edgeWires.append(wire.id)
        }
        let currents = WireCurrents.solve(slotCount: components.count * 2, edges: edges,
                                          conductances: conductances, injections: injections)
        var flows: [UUID: Double] = [:]
        flows.reserveCapacity(edgeWires.count)
        for (id, current) in zip(edgeWires, currents) { flows[id] = current }
        wireFlows = flows
    }

    // MARK: Instruments

    /// Multimeter: arm it, then tap any two terminals. Red probe first.
    var multimeterArmed = false {
        didSet { if !multimeterArmed { probeA = nil; probeB = nil } }
    }
    /// The ammeter's shunt, stamped so current flows through it. Not
    /// `.conductor`: a perfect short's current splits arbitrarily across
    /// parallel paths; 1 mΩ disturbs the loop under a percent.
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
    /// Where a terminal is now, bench coordinates; nil once its part is gone.
    func position(of terminal: Terminal) -> SIMD3<Double>? {
        terminalWorldPosition(terminal)
    }

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

    /// Everything the meter can say, by mode. A⎓ reports current only when
    /// the probes bracket a component whose circuit is otherwise broken;
    /// across a live component it refuses rather than teach the
    /// shorted-ammeter mistake.
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
                    ? "across the \(component!.kind.inSentence)"
                    : "between the probes")

        case .ampsDC:
            // Read the meter's own stamped current, never the bracketed
            // component's. The guard comes first and does not use the stamp, which
            // only exists after a solve.
            let bracketed = bracketsOneComponent
                ? readouts[probeA.componentID]?.amps : nil
            if bracketsOneComponent, let component, let bracketed,
               abs(bracketed) > CircuitSolver.liveCurrentThreshold(volts: vA - vB) {
                return MultimeterReading(
                    display: "FUSE",
                    note: "the \(component.kind.inSentence) is live — probes "
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
                    ? "in series with the \(component!.kind.inSentence)"
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
                        + "\(component.kind.inSentence)")
            }
            return MultimeterReading(
                display: Self.autoRange(ohms, unit: "Ω"),
                note: "across the \(component.kind.inSentence)")

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

    /// The resistance a component presents, ohms; nil where the idea does
    /// not apply (a capacitor's opposition is a reactance).
    nonisolated static func resistance(of component: Component) -> Double? {
        switch component.kind {
        case .resistor: component.failed ? nil : component.value   // scorched: open
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
        // "0.000 A" and no reading are different claims — this says the reading is zero.
        guard abs(value) > 1e-9 else { return "0.000 " + unit }
        // Three decimals in every band, like a real auto-ranging DMM.
        return PhysicsFormat.metric(value, unit, decimals: 3)
    }

    // MARK: Workshop state

    /// The AC sources' shared clock.
    private(set) var simTime = 0.0

    /// Where an AC source is in its cycle, rad: the phase its EMF is the
    /// sine of, for the needle on its dial.
    func acPhase(of component: Component) -> Double {
        2 * .pi * component.acFrequency * simTime
    }

    // MARK: Time Capsule

    @ObservationIgnored var capsule = TimeCapsule<CapsuleSnapshot>()
    @ObservationIgnored var capsuleClock = 0.0
    /// Non-nil while scrubbed into the past, and then the bench is
    /// read-only: every bench-mutating entry point guards on this.
    /// Selection, probing and the net highlight stay live.
    var scrubTime: Double?
    var scrubNonce = 0
    /// Live node voltages by terminal, for the voltage-gradient wires.
    private(set) var terminalVoltages: [Terminal: Double] = [:]
    private(set) var voltageSpan: (min: Double, max: Double) = (0, 0)

    /// One electrical point: its terminals, their centroid (where the
    /// skyline stands its tower) and its potential. Rebuilt every frame on
    /// a topology that is not.
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

    /// Puts a burned/blown part back in service.
    func replaceFailed(id: UUID) {
        guard scrubTime == nil else { return }
        guard let index = components.firstIndex(where: { $0.id == id }) else { return }
        components[index].failed = false
        components[index].thermalEnergy = 0
        emitSound(.chime, at: components[index].position, volume: 0.5)
    }

    /// The frequency rail under a selected AC source.
    func setACFrequency(id: UUID, _ hertz: Double) {
        guard let index = components.firstIndex(where: { $0.id == id }),
              components[index].kind == .acSource else { return }
        components[index].acFrequency = Self.clampedACFrequency(hertz)
    }

    /// Watts a part is dissipating right now, for the card's "of 2 W".
    func dissipation(id: UUID) -> Double {
        readouts[id]?.watts ?? 0
    }

    // MARK: Persistence (the bench survives relaunch)

    /// A bench as it is written. Not private: `migrated` returns one and the
    /// migration tests read it.
    struct SavedBench: Codable {
        var components: [Component]
        var wires: [Wire]
        /// Where the stage stood and how far it was turned. Absent in a bench
        /// written before the stage moved (2026-10-18): `apply` derives one.
        var stage: Stage?
    }

    // MARK: The on-disk row, and why it is not `Component`

    /// A saved component as it comes off the disk, `kind` as a raw String:
    /// decoding straight into `[Component]` throws for the whole array on
    /// one retired kind, and both restore paths swallow that. Fields past
    /// `value` are optional for older files.
    struct StoredComponent: Codable {
        var id: UUID
        var kind: String
        var position: SIMD3<Double>
        var value: Double
        var axis: SIMD3<Double>?
        var isClosed: Bool?
        var capacitorVoltage: Double?
        /// Absent in a bench written before the rail existed → 0.5 Hz.
        var acFrequency: Double?
    }

    struct StoredBench: Codable {
        var components: [StoredComponent]
        var wires: [Wire]
        var stage: Stage?
    }

    /// Brings a bench forward across retired kinds. A retired part is
    /// spliced, not dropped: all stored terminals are partitioned, then a
    /// star is emitted over each net's surviving terminals. Unknown kinds
    /// take the same path.
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
        // The splice: a retired part is a conductor between its own two ends.
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
            component.acFrequency = Self.clampedACFrequency(row.acFrequency ?? Self.acFrequency)
            components.append(component)
            for end in 0...1 {
                survivingTerminals.append((Terminal(componentID: row.id, end: end),
                                           NetTopology.slot(componentIndex: index, end: end)))
            }
        }

        // Nothing retired, nothing rerouted: re-deriving an already-current
        // bench would move cables the user placed.
        if components.count == stored.components.count {
            return SavedBench(components: components, wires: stored.wires, stage: stored.stage)
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
        return SavedBench(components: components, wires: wires, stage: stored.stage)
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
    /// Saves a whole-bench change the wearer made — Clear bench, Reset.
    /// Not inside `reset()` or `clearBench()` themselves: `init` runs
    /// `reset()` before it restores, and a save queued there would write
    /// the starter loop over a bench that failed to restore. Until
    /// 2026-10-14 neither path saved, so a relaunch brought back the bench
    /// the wearer had just cleared.
    func commitBench() { persistSoon() }

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
        // Never save a scrubbed bench: components/wires hold a recorded topology.
        guard scrubTime == nil else { return }
        // Never save mid-pull: a lifted wire is parked in `detachedWires` and
        // a cancel would restore it.
        guard leadPull == nil else { return }
        let bench = SavedBench(components: components, wires: wires, stage: stage)
        if let data = try? JSONEncoder().encode(bench) {
            UserDefaults.standard.set(data, forKey: Self.saveKey)
        }
    }

    /// Installs a decoded bench after sanity checks (`sanitized`).
    @discardableResult
    private func apply(_ bench: SavedBench) -> Bool {
        guard !bench.components.isEmpty,
              bench.components.count <= Self.componentBudget else { return false }
        let bench = Self.sanitized(bench)
        components = bench.components
        wires = bench.wires
        stage = bench.stage ?? Self.derivedStage(for: bench.components)
        stageSpinRate = 0
        settleStage()
        selectedID = nil
        cancelLeadPull()
        voiceWireSource = nil
        highlightedSource = nil
        solve(dt: 1.0 / 90.0)
        return true
    }

    /// A bench as the live rules would have built it (2026-10-18): wires only
    /// between parts that exist, never a terminal to itself, never a second
    /// path between points already joined — checked in file order, the order
    /// they were made — and no more than the budget; parts inside the room's
    /// safety box. Before this a loaded bench skipped every rule a hand meets,
    /// so an old or edited file could hold a loop of wires the live rules
    /// refuse, and `WireCurrents` would have had to guess how it divides.
    /// Presets and the starter loop pass through unchanged.
    static func sanitized(_ bench: SavedBench) -> SavedBench {
        var result = bench
        result.components = bench.components.map { component in
            var placed = component
            placed.position = clampToRoomSafety(component.position)
            return placed
        }
        var index: [UUID: Int] = [:]
        for (position, component) in result.components.enumerated() {
            index[component.id] = position
        }
        var partition = NetPartition(slotCount: result.components.count * 2)
        var kept: [Wire] = []
        for wire in bench.wires {
            guard kept.count < wireBudget, wire.from != wire.to,
                  (0...1).contains(wire.from.end), (0...1).contains(wire.to.end),
                  let a = index[wire.from.componentID],
                  let b = index[wire.to.componentID] else { continue }
            let from = 2 * a + wire.from.end, to = 2 * b + wire.to.end
            guard !partition.areConnected(from, to) else { continue }
            partition.union(from, to)
            kept.append(wire)
        }
        result.wires = kept
        if var stage = result.stage {
            let safe = clampToRoomSafety(SIMD3(stage.center.x, buildCenter.y, stage.center.y))
            stage.center = SIMD2(safe.x, safe.z)
            stage.yaw = stage.yaw.isFinite ? stage.yaw.remainder(dividingBy: 2 * .pi) : 0
            result.stage = stage
        }
        return result
    }

    /// The stage under a bench saved before it could move: centred under its
    /// parts, unturned.
    static func derivedStage(for components: [Component]) -> Stage {
        guard !components.isEmpty else { return homeStage }
        var low = SIMD2<Double>(repeating: .infinity), high = -low
        for component in components {
            let point = SIMD2(component.position.x, component.position.z)
            low = simd_min(low, point)
            high = simd_max(high, point)
        }
        return Stage(center: (low + high) / 2, top: homeStage.top, yaw: 0)
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
            SavedBench(components: components, wires: wires, stage: stage)) else { return false }
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
        // Onto the stage where it stands, not where the clear sends it.
        let standing = stage.center
        clearBench()
        stage.center = standing
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
        // Laid out about the home stage, set over the stage where it stands,
        // facing the wearer.
        for index in components.indices {
            components[index].position = onStage(components[index].position)
        }
        stage.yaw = 0
        stageSpinRate = 0
        selectedID = components.first?.id
        settleStage()
        solve(dt: 1.0 / 90.0)
        // A preset replaces the whole bench; never reached from `init`.
        persistSoon()
    }

    // MARK: The bench's own magnetic field

    /// Every current-carrying straight run for `WireField`: each component
    /// (terminal 0 → 1, its solved current) and each wire (its `from`
    /// component's branch current). Signed, or a loop's two sides would
    /// reinforce.
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
            // The wire's own current, from its from end to its to end — the
            // same number the electron dots ride.
            guard let amps = wireFlows[wire.id], amps != 0 else { continue }
            guard let from = components.first(where: { $0.id == wire.from.componentID }),
                  let to = components.first(where: { $0.id == wire.to.componentID })
            else { continue }
            segments.append(.init(a: from.terminalPosition(wire.from.end),
                                  b: to.terminalPosition(wire.to.end),
                                  current: amps))
        }
        return segments
    }

    /// Every inductor carrying current, as the magnet its coil is:
    /// m = N·I·A along its axis, N from the inductance. A negative current
    /// reverses the moment.
    var coilMagnets: [BarMagnet] {
        components.compactMap { component in
            guard component.kind == .inductor,
                  abs(component.inductorCurrent) > 1e-9 else { return nil }
            return CurrentLoop.magnet(
                at: component.position, axis: component.axis,
                turns: Self.inductorTurns(henries: component.value),
                current: component.inductorCurrent,
                radius: Self.inductorCoilRadius)
        }
    }

    /// The bench's field at a point: every wire segment's, plus every
    /// coil's. The renderer's layer samples this, so what it draws is
    /// the total.
    func magneticField(at point: SIMD3<Double>) -> SIMD3<Double> {
        WireField.field(at: point, segments: currentSegments)
            + MagneticField.vector(at: point, dueTo: coilMagnets)
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

    /// Empties the bench completely — the Clear bench path. The stage goes
    /// home with it: an empty bench has no circuit to have carried, and the
    /// parts that come next come from the shelf.
    func clearBench() {
        components = []
        wires = []
        stage.center = Self.homeStage.center
        stage.yaw = 0
        stageSpinRate = 0
        stageSpin = nil
        stageCarryHand = nil
        armedWireID = nil
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
        // The meter's `didSet` drops both probes.
        multimeterArmed = false
        meterMode = .voltsDC
        isPaused = false
        clearCapsule()
        stage = Self.homeStage
        stageSpinRate = 0
        stageSpin = nil
        stageCarryHand = nil
        seedStarterLoop()
    }

    /// The starter loop, as the lab opens on it and as the home's miniature
    /// stands it: a clean rectangle facing the wearer, the battery along the
    /// bottom, the bulb at the top, the switch upright on the right.
    static let starterParts: [(kind: ComponentKind, position: SIMD3<Double>, axis: SIMD3<Double>)] = [
        (.battery, SIMD3(0, 1.12, -0.9), SIMD3(1, 0, 0)),
        (.switcher, SIMD3(0.30, 1.31, -0.9), SIMD3(0, 1, 0)),
        (.bulb, SIMD3(0, 1.5, -0.9), SIMD3(1, 0, 0)),
    ]
    /// Its wires, part and end to part and end, indices into `starterParts`:
    /// the battery's − to the switch, the switch to the bulb, the bulb back
    /// to the battery's +.
    static let starterWires: [(from: (part: Int, end: Int), to: (part: Int, end: Int))] = [
        ((0, 1), (1, 0)), ((1, 1), (2, 1)), ((2, 0), (0, 0)),
    ]

    private func seedStarterLoop() {
        components = Self.starterParts.map { part in
            Component(id: UUID(), kind: part.kind, position: part.position,
                      value: part.kind.defaultValue, axis: part.axis)
        }
        wires = Self.starterWires.map { wire in
            Wire(id: UUID(),
                 from: Terminal(componentID: components[wire.from.part].id, end: wire.from.end),
                 to: Terminal(componentID: components[wire.to.part].id, end: wire.to.end))
        }
        settleStage()
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
    /// `-circLegacyBench 1` writes a pre-migration bench into the save slot
    /// before this model reads it; nothing else can stage a migration.
    /// Staged: battery → jumper → bulb plus a kind that never existed.
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
    /// The bench and its transients: `Component` carries every integrated
    /// quantity, and the wires restore mid-window rewirings; the per-frame
    /// solve re-derives readouts. Out: the half-made wire and the meter's
    /// arming.
    nonisolated struct CapsuleSnapshot: Equatable {
        var components: [Component]
        var wires: [Wire]
        var simTime: Double
        /// The stage is apparatus, not a display layer: where it stood, how far
        /// it was turned, and the coast it was turning at.
        var stage: Stage
        var stageSpinRate: Double
    }

    func captureCapsuleSnapshot() -> CapsuleSnapshot {
        CapsuleSnapshot(components: components, wires: wires, simTime: simTime,
                        stage: stage, stageSpinRate: stageSpinRate)
    }

    func restoreCapsuleSnapshot(_ snapshot: CapsuleSnapshot) {
        components = snapshot.components
        wires = snapshot.wires
        simTime = snapshot.simTime
        stage = snapshot.stage
        stageSpinRate = snapshot.stageSpinRate
        stageSpin = nil
        stageCarryHand = nil
        // A restore replaces the whole bench, so all in-flight observer state
        // clears unconditionally.
        cancelLeadPull()
        voiceWireSource = nil
        highlightedSource = nil
        if let selectedID, !components.contains(where: { $0.id == selectedID }) {
            self.selectedID = nil
        }
    }
}
