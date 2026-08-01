//
//  MagnetismModel.swift
//  Physics Playground — Magnetism module
//
//  The magnetic sandbox: bar magnets (ideal dipoles) you carry around a
//  room-scale region. Every FREE magnet glides and turns under the exact
//  dipole force and torque from the others (PhysicsCore.MagneticField),
//  so two magnets brought close attract head-to-tail, repel N-to-N, and
//  swing to align — the whole field, its looping lines, and a grid of
//  compass needles reorganise live. The held magnet is the one your hand
//  owns: its position is yours, and the rest of the world responds.
//
//  Motion is overdamped and speed-capped (not momentum dynamics): the
//  magnets settle into equilibrium instead of oscillating, and the tiny
//  SI force/torque magnitudes are turned into a pleasing bounded glide.
//

import Foundation
import Observation
import PhysicsCore
import simd

@MainActor
@Observable
final class MagnetismModel {
    // MARK: Region (immersive-space coordinates)

    nonisolated static let regionCenter = SIMD3<Double>(0, 1.35, -0.7)
    /// Isotropic reach, used for what the region DRAWS — the field-line
    /// tracing radius and the compass grid's span. Narrowed from 0.85
    /// when this bench became the right-hand station of the E&M world:
    /// the grid is laid out as a cube of this span, so at 0.85 the
    /// needles reached across the world's centre line and into the
    /// circuit bench when it stands as Circuit Workshop's coil annex.
    nonisolated static let regionHalfExtent = 0.72
    /// Per-axis bounds for the CLAMP. Height matches the old cube, but
    /// depth stops 15 cm in FRONT of the user instead of 15 cm behind
    /// their head: the cube ran to z = +0.15, so a free cluster that
    /// glided forward ended up floating at the user's ear, looming over
    /// the control pods at enormous parallax. Magnets wander — that is
    /// the module working — but they wander in the room, not in your
    /// face.
    ///
    /// Width is narrower than height for a second reason: this bench
    /// now shares the room with the circuit bench, and a magnet free to
    /// glide 0.85 m off centre could glide out of its own station and
    /// into the other one. CircuitsCoilAnnexTests enforces the clearance.
    nonisolated static let regionHalfExtents = SIMD3<Double>(0.62, 0.85, 0.55)
    nonisolated static let regionFloor = 0.35
    /// Visual length of a bar magnet (m); also the touching distance.
    nonisolated static let magnetLength = 0.16
    nonisolated static let magnetBudget = 4
    nonisolated static let strengthRange = 1.0...12.0
    nonisolated static let defaultStrength = 6.0

    // Overdamped glide tuning (decoupled from the tiny SI magnitudes —
    // direction from the physics, speed capped for a good feel).
    private static let forceGain = 6.0e3
    private static let torqueGain = 9.0e4
    private static let maxLinearSpeed = 0.5     // m/s
    private static let maxAngularSpeed = 3.0    // rad/s
    /// Magnets can't pass through each other — they stick at a touch.
    private static let contactDistance = magnetLength * 0.92
    /// How far above contact a magnet begins to slow — the cushion that
    /// turns an impact into a landing. See `softenedAtContact`.
    private static let contactBand = 0.030
    /// Below this glide speed a magnet is simply at rest. Without it the
    /// last hundredth of a millimetre per second never quite runs out.
    private static let restSpeed = 3.0e-4    // m/s

    private(set) var magnets: [BarMagnet] = []
    private(set) var selectedID: UUID?
    private(set) var heldID: UUID?

    var isPaused = false
    var showFieldLines = true
    var showCompasses = true

    // MARK: The electromagnet your circuit powers

    /// An electromagnet on the field bench, driven by the current the
    /// CIRCUIT bench is actually delivering through its inductor.
    ///
    /// This is the one place the app's nine modules stop being nine
    /// islands. A coil carrying a current is a magnet — m = N·I·A — and
    /// that identity is the whole bridge between the two halves of
    /// electromagnetism. So: build a loop in Circuit Workshop, wire an
    /// inductor into it, and its live current becomes a magnet here that
    /// the other magnets respond to and the carried compass points at.
    /// Open the switch on the circuit bench and the electromagnet dies;
    /// reverse the battery and its poles swap. Nothing is faked: the
    /// current is the solver's, and the moment is N·I·A.
    var electromagnetOn = false
    /// The coil's geometry — a chunky demo solenoid.
    nonisolated static let coilTurns = 400
    nonisolated static let coilRadius = 0.05
    /// Where the electromagnet sits, and which way its axis points.
    var electromagnetPosition = MagnetismModel.regionCenter + SIMD3(0, 0.34, -0.3)
    var electromagnetAxis = SIMD3<Double>(1, 0, 0)
    /// Amps through the coil, pushed in from the circuit bench each
    /// frame. Zero when nothing is wired or the switch is open.
    private(set) var coilCurrent = 0.0

    func setCoilCurrent(_ amps: Double) {
        guard abs(amps - coilCurrent) > 1e-9 else { return }
        coilCurrent = amps
    }

    func moveElectromagnet(to point: SIMD3<Double>) {
        electromagnetPosition = clamp(point)
    }

    /// The coil as a dipole — nil when it is off or carrying nothing.
    var electromagnet: BarMagnet? {
        guard electromagnetOn, abs(coilCurrent) > 1e-6 else { return nil }
        return CurrentLoop.magnet(
            at: electromagnetPosition, axis: electromagnetAxis,
            turns: Self.coilTurns, current: coilCurrent, radius: Self.coilRadius)
    }

    /// m = N·I·A for the current the circuit is delivering, A·m².
    var electromagnetMoment: Double {
        CurrentLoop.momentMagnitude(
            turns: Self.coilTurns, current: coilCurrent,
            area: CurrentLoop.area(radius: Self.coilRadius))
    }

    /// Every dipole in the scene: the bar magnets plus the coil. The
    /// field, the forces and the compass all read this, so the
    /// electromagnet is a first-class source rather than a decoration.
    var allSources: [BarMagnet] {
        electromagnet.map { magnets + [$0] } ?? magnets
    }

    // MARK: The compass you carry

    /// A single hand-held compass, separate from the lattice.
    ///
    /// The lattice shows the field's SHAPE; a compass in your hand is
    /// the experience everyone actually remembers — you walk it around
    /// a magnet and watch the needle swing. It is the same physics
    /// (τ = m × B aligning a dipole with the local field), just at the
    /// end of your arm instead of pinned to a grid, and it is the one
    /// affordance in this module that only exists because you have hands
    /// in the scene.
    var compassOn = true
    var compassPosition = MagnetismModel.regionCenter + SIMD3(0.0, -0.42, 0.55)

    func moveCompass(to point: SIMD3<Double>) {
        var clamped = point
        clamped.y = max(clamped.y, Self.regionFloor)
        compassPosition = clamped
    }

    /// The field where the compass is — what the needle points along.
    var compassField: SIMD3<Double> {
        MagneticField.vector(at: compassPosition, dueTo: allSources)
    }

    /// |B| at the compass in microtesla, for its dial label.
    var compassMicroTesla: Double { simd_length(compassField) * 1e6 }

    var selectedMagnet: BarMagnet? {
        guard let selectedID else { return nil }
        return magnets.first { $0.id == selectedID }
    }

    // MARK: Clock — the overdamped magnetic dynamics

    /// Whether the magnets translate and turn under their mutual forces.
    /// On (the default), the bench is alive: bring two magnets near and
    /// they attract, repel, and swing into alignment. Off, every magnet
    /// holds exactly where you park it — a frozen arrangement whose
    /// field you can study, mirroring the electric bench's stationary
    /// charges.
    var dynamicsOn = true

    // MARK: Faraday induction — the coil notices moving magnets

    /// EMF induced in the electromagnet's coil by the BAR magnets'
    /// motion, volts, lightly smoothed. ε = −N dΦ/dt with the flux
    /// integrated numerically over the coil disc from the same dipole
    /// field every other number in this module comes from. Wave a
    /// magnet through the coil and this is what the wave is worth.
    private(set) var inducedEMF = 0.0
    @ObservationIgnored private var lastCoilFlux: Double?

    private func updateInduction(dt: Double) {
        guard electromagnetOn, dt > 1e-6 else {
            lastCoilFlux = nil
            if inducedEMF != 0 { inducedEMF = 0 }
            return
        }
        let flux = Induction.flux(
            throughDiscAt: electromagnetPosition, normal: electromagnetAxis,
            radius: Self.coilRadius, magnets: magnets)
        if let last = lastCoilFlux {
            let raw = Induction.emf(turns: Self.coilTurns,
                                    fluxNow: flux, fluxBefore: last, dt: dt)
            // ~80 ms smoothing: the raw finite difference carries the
            // simulation's frame jitter; the physical signal doesn't.
            inducedEMF += (raw - inducedEMF) * min(dt * 12, 1)
        }
        lastCoilFlux = flux
    }

    func step(dt: Double) {
        guard !isPaused else { return }
        // BEFORE the dynamics gate: Faraday's law does not care WHY the
        // flux changed. A magnet carried by hand across a frozen bench
        // induces exactly as one gliding under its own forces — the
        // first draft ran this after the gate, and a hand-waved magnet
        // on a frozen bench lit nothing, which is wrong physics.
        updateInduction(dt: dt)
        guard dynamicsOn else {
            // Frozen: no forces, but contact separation still holds so a
            // dragged magnet can't be parked inside another.
            magnets = separated(magnets)
            return
        }
        let h = min(dt, 1.0 / 60.0)
        var next = magnets
        for i in magnets.indices where magnets[i].id != heldID {
            var others = magnets.enumerated().filter { $0.offset != i }.map(\.element)
            // The coil is a source like any other: a magnet near a live
            // electromagnet is pulled by it and swings to align with it.
            if let coil = electromagnet { others.append(coil) }
            guard !others.isEmpty else { continue }

            // Translate down the net force (direction exact; speed capped).
            let force = MagneticField.netForce(on: magnets[i], from: others)
            let fMag = simd_length(force)
            if fMag > 1e-22 {
                let speed = min(Self.forceGain * fMag, Self.maxLinearSpeed)
                let velocity = softenedAtContact(
                    velocity: (force / fMag) * speed,
                    of: magnets[i], among: magnets)
                if simd_length(velocity) > Self.restSpeed {
                    next[i].position = clamp(magnets[i].position + velocity * h)
                }
            }
            // Turn the moment toward the local field (τ = m × B).
            let torque = MagneticField.torque(on: magnets[i], inFieldOf: others)
            let tMag = simd_length(torque)
            if tMag > 1e-22 {
                let rate = min(Self.torqueGain * tMag, Self.maxAngularSpeed)
                let q = simd_quatd(angle: rate * h, axis: torque / tMag)
                next[i].moment = q.act(magnets[i].moment)
            }
        }
        magnets = separated(next)
    }

    /// Takes the INWARD component out of a magnet's glide as it closes
    /// on one it is already touching, so a pair that has come together
    /// stops instead of buzzing.
    ///
    /// Two aligned magnets never came to rest, and the mechanism was a
    /// standoff between the two halves of `step`. The dipole force at
    /// contact is ~0.05 N, which `forceGain` turns into a speed well
    /// past `maxLinearSpeed` — so each magnet drove a full 8 mm inward
    /// every frame, at the cap, and `separated` then hard-projected it
    /// straight back out to exactly where it started. Identical force
    /// next frame, identical 8 mm, identical projection: a limit cycle
    /// locked to the frame rate, running forever, with the visible
    /// symptom of two magnets vibrating against each other. The speed
    /// cap was making it worse rather than better — it removed the only
    /// mechanism by which an approaching magnet would ever slow down.
    ///
    /// Only the closing component is removed, and only in proportion to
    /// how little gap is left. A magnet at contact can still slide
    /// along its neighbour, and can still be pulled away from it; it
    /// simply cannot keep charging into a wall. Real magnets stick.
    private func softenedAtContact(velocity: SIMD3<Double>,
                                   of magnet: BarMagnet,
                                   among all: [BarMagnet]) -> SIMD3<Double> {
        var result = velocity
        for other in all where other.id != magnet.id {
            let delta = other.position - magnet.position
            let distance = simd_length(delta)
            guard distance > 1e-6,
                  distance < Self.contactDistance + Self.contactBand else { continue }
            let toward = delta / distance
            let closing = simd_dot(result, toward)
            guard closing > 0 else { continue }
            // 1 at the far edge of the band, 0 at contact and inside it.
            let gap = (distance - Self.contactDistance) / Self.contactBand
            let ease = min(max(gap, 0), 1)
            result -= toward * (closing * (1 - ease))
        }
        return result
    }

    /// Pushes overlapping magnets apart to the touching distance so they
    /// snap together and stick instead of collapsing into one point. The
    /// held magnet stays put; free ones yield.
    private func separated(_ input: [BarMagnet]) -> [BarMagnet] {
        var result = input
        for _ in 0..<2 {  // a couple of relaxation sweeps
            for a in result.indices {
                for b in (a + 1)..<result.count {
                    let delta = result[b].position - result[a].position
                    let dist = simd_length(delta)
                    guard dist < Self.contactDistance, dist > 1e-6 else { continue }
                    let push = (Self.contactDistance - dist)
                    let dir = delta / dist
                    let aHeld = result[a].id == heldID, bHeld = result[b].id == heldID
                    if aHeld && !bHeld {
                        result[b].position = clamp(result[b].position + dir * push)
                    } else if bHeld && !aHeld {
                        result[a].position = clamp(result[a].position - dir * push)
                    } else if !aHeld && !bHeld {
                        result[a].position = clamp(result[a].position - dir * (push / 2))
                        result[b].position = clamp(result[b].position + dir * (push / 2))
                    }
                }
            }
        }
        return result
    }

    private func clamp(_ p: SIMD3<Double>) -> SIMD3<Double> {
        var c = simd_clamp(p,
                           Self.regionCenter - Self.regionHalfExtents,
                           Self.regionCenter + Self.regionHalfExtents)
        c.y = max(c.y, Self.regionFloor)
        return c
    }

    // MARK: Manipulation

    func grab(id: UUID) {
        guard magnets.contains(where: { $0.id == id }) else { return }
        heldID = id
        selectedID = id
    }

    func move(id: UUID, to point: SIMD3<Double>) {
        guard let index = magnets.firstIndex(where: { $0.id == id }) else { return }
        magnets[index].position = clamp(point)
    }

    func release() { heldID = nil }

    func select(id: UUID) {
        guard magnets.contains(where: { $0.id == id }) else { return }
        selectedID = id
    }

    // MARK: Editing

    func addMagnet() {
        guard magnets.count < Self.magnetBudget else { return }
        let angle = Double(magnets.count) * 1.7
        let offset = SIMD3(cos(angle) * 0.45, sin(angle) * 0.2, sin(angle * 1.3) * 0.3)
        let magnet = BarMagnet(
            position: clamp(Self.regionCenter + offset),
            moment: SIMD3(Self.defaultStrength, 0, 0))
        magnets.append(magnet)
        selectedID = magnet.id
    }

    // MARK: Per-magnet edits — what the Bloom calls

    @discardableResult
    func addMagnet(at position: SIMD3<Double>) -> UUID? {
        guard magnets.count < Self.magnetBudget else { return nil }
        let magnet = BarMagnet(position: clamp(position),
                               moment: SIMD3(Self.defaultStrength, 0, 0))
        magnets.append(magnet)
        selectedID = magnet.id
        return magnet.id
    }

    func removeMagnet(id: UUID) {
        guard magnets.count > 1 else { return }
        magnets.removeAll { $0.id == id }
        if heldID == id { heldID = nil }
        if selectedID == id { selectedID = magnets.last?.id }
    }

    func flipMagnet(id: UUID) {
        guard let index = magnets.firstIndex(where: { $0.id == id }) else { return }
        magnets[index].moment = -magnets[index].moment
    }

    func strength(id: UUID) -> Double {
        magnets.first(where: { $0.id == id })?.strength ?? Self.defaultStrength
    }

    func setStrength(id: UUID, _ value: Double) {
        guard let index = magnets.firstIndex(where: { $0.id == id }) else { return }
        let axis = magnets[index].axis
        magnets[index].moment = axis * min(max(value, Self.strengthRange.lowerBound),
                                           Self.strengthRange.upperBound)
    }

    func removeSelected() {
        guard let selectedID, magnets.count > 1 else { return }
        magnets.removeAll { $0.id == selectedID }
        heldID = nil
        self.selectedID = magnets.last?.id
    }

    /// Reverses the selected magnet's poles (N↔S) — the control that turns
    /// attraction into repulsion without a twist gesture.
    func flipSelected() {
        guard let index = magnets.firstIndex(where: { $0.id == selectedID }) else { return }
        magnets[index].moment = -magnets[index].moment
    }

    /// Strength of the selected magnet (|m|, A·m²), preserving direction.
    var selectedStrength: Double {
        get { selectedMagnet?.strength ?? Self.defaultStrength }
        set {
            guard let index = magnets.firstIndex(where: { $0.id == selectedID }) else { return }
            let axis = magnets[index].axis
            magnets[index].moment = axis * max(newValue, 0.1)
        }
    }

    // MARK: Field readout for the numbers card

    /// |B| in millitesla at the region centre — a live sense of the field.
    var centerFieldMilliTesla: Double {
        MagneticField.magnitude(at: Self.regionCenter, dueTo: allSources) * 1000
    }

    // MARK: Reset

    func reset() {
        // ONE magnet, centred: its looping dipole field IS the opening
        // scene — clean, symmetric, readable, like the electric
        // dipole next door. (Three misaligned magnets used to glide
        // into a chain here; three interleaved loop systems on arrival
        // was a tangle before anyone had seen one field. Add a second
        // magnet yourself and the approach becomes something you DID.)
        magnets = [
            BarMagnet(position: Self.regionCenter,
                      moment: SIMD3(Self.defaultStrength, 0, 0)),
        ]
        selectedID = magnets.last?.id
        heldID = nil
        isPaused = false
        showFieldLines = true
        showCompasses = true
        compassOn = true
        compassPosition = Self.regionCenter + SIMD3(0.0, -0.42, 0.55)
        electromagnetOn = false
        coilCurrent = 0
        electromagnetPosition = Self.regionCenter + SIMD3(0, 0.34, -0.3)
        electromagnetAxis = SIMD3(1, 0, 0)
    }

    init() {
        reset()
        #if DEBUG
        // `-magFrozen 1`: open with dynamics off (CLI screenshot checks).
        if UserDefaults.standard.bool(forKey: "magFrozen") {
            dynamicsOn = false
        }
        #endif
    }
}
