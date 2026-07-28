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
    nonisolated static let regionHalfExtent = 0.85
    /// Per-axis bounds for the CLAMP. Width and height match the old
    /// cube, but depth stops 15 cm in FRONT of the user instead of
    /// 15 cm behind their head: the cube ran to z = +0.15, so a free
    /// cluster that glided forward ended up floating at the user's ear,
    /// looming over the control pods at enormous parallax. Magnets
    /// wander — that is the module working — but they wander in the
    /// room, not in your face.
    nonisolated static let regionHalfExtents = SIMD3<Double>(0.85, 0.85, 0.55)
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

    func step(dt: Double) {
        guard !isPaused else { return }
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
                next[i].position = clamp(magnets[i].position + (force / fMag) * speed * h)
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
        // Three magnets, well apart and deliberately MISALIGNED: they
        // open alive, gliding and swinging into a chain.
        //
        // The old opening put two magnets close enough that they had
        // already snapped into a single bar before anyone looked — you
        // could not tell there were two, and the snap, which is the whole
        // point of the module, had already happened off-screen. Starting
        // them further out, at angles, and staggered in depth means the
        // approach IS the opening scene, and it uses all three axes.
        magnets = [
            BarMagnet(position: Self.regionCenter + SIMD3(-0.62, -0.12, 0.18),
                      moment: SIMD3(Self.defaultStrength, 0, 0)),
            BarMagnet(position: Self.regionCenter + SIMD3(0.62, 0.10, -0.20),
                      moment: SIMD3(Self.defaultStrength * 0.72,
                                    Self.defaultStrength * 0.62, 0)),
            BarMagnet(position: Self.regionCenter + SIMD3(0.05, 0.46, 0.34),
                      moment: SIMD3(0, -Self.defaultStrength * 0.85,
                                    Self.defaultStrength * 0.4)),
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
