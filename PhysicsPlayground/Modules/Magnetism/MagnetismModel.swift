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
            let others = magnets.enumerated().filter { $0.offset != i }.map(\.element)
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
                           Self.regionCenter - SIMD3(repeating: Self.regionHalfExtent),
                           Self.regionCenter + SIMD3(repeating: Self.regionHalfExtent))
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
        MagneticField.magnitude(at: Self.regionCenter, dueTo: magnets) * 1000
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
