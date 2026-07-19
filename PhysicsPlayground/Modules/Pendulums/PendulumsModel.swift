//
//  PendulumsModel.swift
//  Physics Playground — Pendulums module
//
//  App state for the pendulum lab: any number of pendulums hanging
//  from a floating beam, each a fully nonlinear SphericalPendulum from
//  PhysicsCore. Substepped integration keeps motion glassy at every
//  time scale; grabbing freezes a pendulum and release rethrows it
//  with the hand's velocity, projected onto the taut-cable sphere.
//
//  All SI units. Positions are immersive-space world coordinates.
//

import Foundation
import Observation
import PhysicsCore
import simd

@MainActor
@Observable
final class PendulumsModel {
    // MARK: Layout

    /// The beam the pivots ride, floating overhead.
    nonisolated static let beamCenter = SIMD3<Double>(0, 2.1, -1.1)
    nonisolated static let beamHalfLength = 0.9

    nonisolated static let lengthRange = 0.25...1.6      // m
    nonisolated static let massRange = 0.1...5.0         // kg
    nonisolated static let gravityRange = 0.5...25.0     // m/s²
    nonisolated static let dampingRange = 0.0...1.0      // N·s/m
    nonisolated static let bobRadiusRange = 0.02...0.07  // m
    nonisolated static let cableRange = 0.001...0.006    // m
    nonisolated static let pendulumBudget = 7

    // MARK: Pendulums

    struct Pendulum: Identifiable, Equatable {
        let id: UUID
        var length: Double
        var mass: Double
        var damping: Double
        var bobRadius: Double
        var cableThickness: Double
        /// Physics state: bob position/velocity relative to the pivot.
        var state: SphericalPendulum
        /// Pivot offset along the beam (world x from beam center).
        var beamOffset: Double
        /// While a hand holds the bob, physics freezes and the bob
        /// tracks the hand exactly.
        var isGrabbed = false

        var pivot: SIMD3<Double> {
            PendulumsModel.beamCenter + SIMD3(beamOffset, 0, 0)
        }
        var bobWorld: SIMD3<Double> { pivot + state.position }

        func period(gravity: Double) -> Double {
            SphericalPendulum.smallAnglePeriod(length: length, gravity: gravity)
        }
    }

    private(set) var pendulums: [Pendulum] = []
    private(set) var selectedID: UUID?

    // MARK: Global knobs

    var gravity = 9.81 { didSet { insight(.gravity) } }
    var isPaused = false
    /// Time scale: 0.25× … 20×. Pause is separate.
    var timeScale = 1.0

    enum TrailMode: String, CaseIterable, Identifiable {
        case off, short, long, infinite
        var id: String { rawValue }
    }
    var trailMode: TrailMode = .short
    var showVelocity = true
    var showAcceleration = false
    var showForces = false
    var showEnergyBars = true

    /// The contextual one-liner shown after a parameter change.
    private(set) var insightText = ""

    enum InsightTopic {
        case length, mass, gravity, damping
    }

    private func insight(_ topic: InsightTopic) {
        switch topic {
        case .length:
            insightText = "Longer cable, longer period: T = 2π√(L/g) — the restoring pull acts over a bigger arc, so each swing takes longer. Mass doesn't appear at all."
        case .mass:
            insightText = "Mass changes the forces and the energy, but not the period — gravity accelerates every mass equally, so the swing timing is untouched."
        case .gravity:
            insightText = "Stronger gravity stiffens the restoring force: period shrinks as 1/√g. On the Moon this pendulum would swing in slow motion."
        case .damping:
            insightText = "Damping drains energy every swing — watch the energy bars' total shrink and the arc decay exponentially."
        }
    }

    // MARK: Editing

    var selected: Pendulum? {
        pendulums.first { $0.id == selectedID }
    }

    func select(id: UUID) {
        guard pendulums.contains(where: { $0.id == id }) else { return }
        selectedID = id
    }

    @discardableResult
    func addPendulum(length: Double = 0.8, angle: Double = 0.45,
                     mass: Double = 1.0) -> UUID? {
        guard pendulums.count < Self.pendulumBudget else { return nil }
        let pendulum = Pendulum(
            id: UUID(), length: length, mass: mass, damping: 0.02,
            bobRadius: 0.035, cableThickness: 0.002,
            state: SphericalPendulum(length: length, angle: angle),
            beamOffset: 0)
        pendulums.append(pendulum)
        selectedID = pendulum.id
        relayoutBeam()
        emitSound(.pop, at: pendulum.bobWorld, volume: 0.5)
        return pendulum.id
    }

    /// Five pendulums, lengths stepped 4% apart: they start in phase,
    /// drift, scramble, and re-align — beat frequencies teaching
    /// themselves.
    func loadResonancePreset() {
        pendulums = []
        for index in 0..<5 {
            let length = 0.7 * pow(1.04, Double(index))
            let pendulum = Pendulum(
                id: UUID(), length: length, mass: 1.0, damping: 0,
                bobRadius: 0.032, cableThickness: 0.002,
                state: SphericalPendulum(length: length, angle: 0.5),
                beamOffset: 0)
            pendulums.append(pendulum)
        }
        selectedID = pendulums.first?.id
        relayoutBeam()
        insightText = "Five lengths, 4% apart: they leave together, drift out of step, then re-align — the beat period is set by the difference of their frequencies."
    }

    /// Spread pivots evenly along the beam.
    private func relayoutBeam() {
        let count = pendulums.count
        guard count > 0 else { return }
        for index in pendulums.indices {
            let fraction = count == 1 ? 0.5 : Double(index) / Double(count - 1)
            pendulums[index].beamOffset =
                (fraction - 0.5) * 2 * Self.beamHalfLength * 0.85
        }
    }

    func removeSelected() {
        guard let selectedID else { return }
        pendulums.removeAll { $0.id == selectedID }
        self.selectedID = pendulums.last?.id
        relayoutBeam()
    }

    // MARK: Live parameter edits (no reset — the swing carries on)

    func setLength(id: UUID, _ length: Double) {
        guard let index = pendulums.firstIndex(where: { $0.id == id }) else { return }
        let clamped = min(max(length, Self.lengthRange.lowerBound), Self.lengthRange.upperBound)
        var pendulum = pendulums[index]
        // Re-project the bob onto the new sphere, keeping its direction
        // and speed — the swing continues from where it is.
        let direction = simd_normalize(pendulum.state.position)
        pendulum.state.position = direction * clamped
        pendulum.length = clamped
        pendulums[index] = pendulum
        insight(.length)
    }

    func setMass(id: UUID, _ mass: Double) {
        guard let index = pendulums.firstIndex(where: { $0.id == id }) else { return }
        pendulums[index].mass = min(max(mass, Self.massRange.lowerBound), Self.massRange.upperBound)
        insight(.mass)
    }

    func setDamping(id: UUID, _ damping: Double) {
        guard let index = pendulums.firstIndex(where: { $0.id == id }) else { return }
        pendulums[index].damping = min(max(damping, 0), Self.dampingRange.upperBound)
        insight(.damping)
    }

    func setBobRadius(id: UUID, _ radius: Double) {
        guard let index = pendulums.firstIndex(where: { $0.id == id }) else { return }
        pendulums[index].bobRadius = min(max(radius, Self.bobRadiusRange.lowerBound),
                                         Self.bobRadiusRange.upperBound)
    }

    func setCableThickness(id: UUID, _ thickness: Double) {
        guard let index = pendulums.firstIndex(where: { $0.id == id }) else { return }
        pendulums[index].cableThickness = min(max(thickness, Self.cableRange.lowerBound),
                                              Self.cableRange.upperBound)
    }

    func setInitialAngle(id: UUID, _ angle: Double) {
        guard let index = pendulums.firstIndex(where: { $0.id == id }) else { return }
        pendulums[index].state = SphericalPendulum(
            length: pendulums[index].length, angle: angle)
    }

    // MARK: Grab & release

    func beginGrab(id: UUID) {
        guard let index = pendulums.firstIndex(where: { $0.id == id }) else { return }
        pendulums[index].isGrabbed = true
        selectedID = id
    }

    /// The bob follows the hand exactly; only the physics state's
    /// direction is stored (cable drawn pivot→hand by the renderer).
    func moveGrabbed(id: UUID, toWorld hand: SIMD3<Double>) {
        guard let index = pendulums.firstIndex(where: { $0.id == id }),
              pendulums[index].isGrabbed else { return }
        let offset = hand - pendulums[index].pivot
        let distance = simd_length(offset)
        guard distance > 1e-6 else { return }
        // Store the true hand offset (may exceed L while held taut-plus;
        // the sim clamps back to the sphere on release).
        pendulums[index].state.position = offset
        pendulums[index].state.velocity = .zero
    }

    /// Release with the hand's velocity: clamp to the sphere, project
    /// the velocity tangent, resume.
    func release(id: UUID, handVelocity: SIMD3<Double>) {
        guard let index = pendulums.firstIndex(where: { $0.id == id }) else { return }
        var pendulum = pendulums[index]
        let direction = simd_normalize(pendulum.state.position)
        pendulum.state.position = direction * pendulum.length
        var velocity = handVelocity
        velocity -= simd_dot(velocity, direction) * direction
        pendulum.state.velocity = velocity
        pendulum.isGrabbed = false
        pendulums[index] = pendulum
        emitSound(.whoosh, at: pendulum.bobWorld,
                  volume: min(0.3 + simd_length(velocity) * 0.2, 0.9))
    }

    // MARK: Simulation

    /// Fixed internal substep — small enough that even 20× time scale
    /// stays glassy.
    nonisolated static let substep = 1.0 / 720.0
    private var accumulator = 0.0

    /// The friction kill-switch: off = an ideal pendulum that swings
    /// forever (per-pendulum damping is bypassed, not forgotten).
    var frictionOn = true {
        didSet {
            insightText = frictionOn
                ? "Air resistance is back — each swing hands a little energy to the air, and the amplitude decays."
                : "Frictionless: an ideal pendulum. The energy just trades between height and speed — it will swing forever."
        }
    }

    func step(dt: Double) {
        guard !isPaused, timeScale > 0 else { return }
        accumulator += min(dt, 0.1) * timeScale
        let substep = Self.substep
        var steps = 0
        while accumulator >= substep, steps < 400 {
            accumulator -= substep
            steps += 1
            for index in pendulums.indices where !pendulums[index].isGrabbed {
                pendulums[index].state = SphericalPendulum.step(
                    pendulums[index].state, dt: substep,
                    length: pendulums[index].length, gravity: gravity,
                    mass: pendulums[index].mass,
                    damping: frictionOn ? pendulums[index].damping : 0)
            }
        }
    }

    /// Simulate a copy forward for the ghost-prediction path (from a
    /// hypothetical release right now).
    func predictedPath(id: UUID, seconds: Double, points: Int) -> [SIMD3<Double>] {
        guard let pendulum = pendulums.first(where: { $0.id == id }) else { return [] }
        let direction = simd_normalize(pendulum.state.position)
        var state = SphericalPendulum(
            position: direction * pendulum.length, velocity: .zero)
        var path: [SIMD3<Double>] = []
        let stepsPerPoint = max(Int(seconds / Double(points) / Self.substep), 1)
        for _ in 0..<points {
            for _ in 0..<stepsPerPoint {
                state = SphericalPendulum.step(
                    state, dt: Self.substep, length: pendulum.length,
                    gravity: gravity, mass: pendulum.mass,
                    damping: frictionOn ? pendulum.damping : 0)
            }
            path.append(pendulum.pivot + state.position)
        }
        return path
    }

    // MARK: Sound events (renderer plays them spatially)

    private(set) var soundEvent: SpatialSoundEvent?
    private var soundCounter = 0

    private func emitSound(_ kind: SoundPalette.Sound, at position: SIMD3<Double>, volume: Double) {
        soundCounter += 1
        soundEvent = SpatialSoundEvent(
            id: soundCounter, kind: kind, position: position, volume: volume)
    }

    // MARK: Reset

    func reset() {
        pendulums = []
        selectedID = nil
        gravity = 9.81
        isPaused = false
        timeScale = 1.0
        trailMode = .short
        showVelocity = true
        showAcceleration = false
        showForces = false
        showEnergyBars = true
        insightText = ""
        accumulator = 0
        addPendulum()
        // A welcome swing, already alive.
        if let id = pendulums.first?.id,
           let index = pendulums.firstIndex(where: { $0.id == id }) {
            pendulums[index].state.velocity = SIMD3(0.3, 0, 0)
        }
    }

    init() {
        reset()
    }
}
