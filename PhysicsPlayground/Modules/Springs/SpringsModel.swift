//
//  SpringsModel.swift
//  Physics Playground — Springs module
//
//  App state for the spring lab: a horizontal apparatus at chest
//  height driven by PhysicsCore's RK4 SpringOscillator, plus the
//  coupled-oscillator showcase (two masses, three springs) where
//  energy audibly sloshes between the blocks. A ring buffer records
//  the motion for the floating scrolling graph.
//
//  Displacements are along world X, SI units.
//

import Foundation
import Observation
import PhysicsCore
import simd

@MainActor
@Observable
final class SpringsModel {
    // MARK: Layout

    /// Center of the apparatus, chest height.
    nonisolated static let center = SIMD3<Double>(0, 1.15, -0.85)
    /// Support columns sit at ±railHalfLength.
    nonisolated static let railHalfLength = 0.6

    nonisolated static let stiffnessRange = 5.0...200.0   // N/m
    nonisolated static let massRange = 0.1...4.0          // kg
    nonisolated static let dampingRange = 0.0...3.0       // N·s/m
    nonisolated static let restLengthRange = 0.25...0.6   // m
    nonisolated static let extensionRange = 0.1...0.4     // m

    // MARK: Parameters

    var stiffness = 40.0 { didSet { insight(.stiffness) } }
    var mass = 0.5 { didSet { insight(.mass) } }
    var damping = 0.1 { didSet { insight(.damping) } }
    var restLength = 0.45
    var maxExtension = 0.3
    /// Gravity along the motion axis (as if the rail were tipped
    /// vertical): shifts the equilibrium to −mg/k, exactly.
    var gravityOn = false { didSet { insight(.gravity) } }

    var isPaused = false
    var timeScale = 1.0

    enum Mode: String { case single, coupled }
    private(set) var mode: Mode = .single

    // MARK: State

    private(set) var state = SpringOscillator(displacement: 0.12)
    private(set) var coupled = CoupledSprings(displacements: SIMD2(0.18, 0))
    /// Which block a hand holds: 0 (single & coupled) or 1 (coupled).
    private(set) var grabbedBlock: Int?

    var showVelocity = true
    var showAcceleration = false
    var showForce = true
    var showEnergyBars = true
    var showGhost = true

    enum GraphMode: String, CaseIterable, Identifiable {
        case position, velocity, acceleration, energy
        var id: String { rawValue }
    }
    var graphMode: GraphMode = .position

    // MARK: Derived readouts (single mode)

    var biasForce: Double { gravityOn ? -9.81 * mass : 0 }
    var equilibriumOffset: Double { biasForce / stiffness }

    var period: Double { SpringOscillator.period(stiffness: stiffness, mass: mass) }
    var frequency: Double { 1 / period }

    var springForce: Double { -stiffness * state.displacement }
    var acceleration: Double {
        (springForce - damping * state.velocity + biasForce) / mass
    }

    func energies() -> (kinetic: Double, potential: Double) {
        state.energies(stiffness: stiffness, mass: mass)
    }

    /// Block center in world space (single mode): the left support
    /// anchors the spring; the block rides at rest length + x.
    var blockWorld: SIMD3<Double> {
        Self.center + SIMD3(-Self.railHalfLength + restLength + state.displacement, 0, 0)
    }

    func coupledBlockWorld(_ index: Int) -> SIMD3<Double> {
        // Rest positions at ±railHalfLength/3.
        let rest = Self.railHalfLength / 3 * (index == 0 ? -1 : 1)
        let x = index == 0 ? coupled.displacements.x : coupled.displacements.y
        return Self.center + SIMD3(rest + x, 0, 0)
    }

    // MARK: Insight

    private(set) var insightText = ""

    enum InsightTopic { case stiffness, mass, damping, gravity, coupled }

    private func insight(_ topic: InsightTopic) {
        switch topic {
        case .stiffness:
            insightText = "Stiffer spring, faster bounce: T = 2π√(m/k), so quadrupling k halves the period. Watch the waveform squeeze."
        case .mass:
            insightText = "More mass, more inertia: the same spring force accelerates it less, so the period grows as √m."
        case .damping:
            insightText = "Damping opposes velocity — the envelope decays exponentially while the period barely changes (light damping)."
        case .gravity:
            insightText = "Tipping gravity onto the axis doesn't change the period at all — it only shifts the equilibrium to mg/k. The oscillation is identical around the new center."
        case .coupled:
            insightText = "Two masses, three springs: pull one block and watch its energy drain into the other and slosh back — a beat set by the difference of the two normal-mode frequencies."
        }
    }

    // MARK: Modes

    func setMode(_ newMode: Mode) {
        guard mode != newMode else { return }
        mode = newMode
        grabbedBlock = nil
        if newMode == .coupled {
            coupled = CoupledSprings(displacements: SIMD2(0.18, 0))
            insight(.coupled)
        } else {
            state = SpringOscillator(displacement: 0.12)
        }
        clearHistory()
    }

    /// Coupling spring between the two masses (coupled mode).
    var coupling = 8.0

    // MARK: Grab & release

    func beginGrab(block: Int) {
        grabbedBlock = block
    }

    func moveGrabbed(toWorldX x: Double) {
        guard let grabbedBlock else { return }
        switch mode {
        case .single:
            let anchor = Self.center.x - Self.railHalfLength + restLength
            let displacement = min(max(x - anchor, -maxExtension), maxExtension)
            state = SpringOscillator(displacement: displacement, velocity: 0)
        case .coupled:
            let rest = Self.center.x + Self.railHalfLength / 3 * (grabbedBlock == 0 ? -1 : 1)
            let displacement = min(max(x - rest, -maxExtension), maxExtension)
            if grabbedBlock == 0 {
                coupled.displacements.x = displacement
                coupled.velocities.x = 0
            } else {
                coupled.displacements.y = displacement
                coupled.velocities.y = 0
            }
        }
    }

    func release(handVelocityX: Double) {
        guard let grabbedBlock else { return }
        let clamped = min(max(handVelocityX, -3), 3)
        switch mode {
        case .single:
            state.velocity = clamped
        case .coupled:
            if grabbedBlock == 0 {
                coupled.velocities.x = clamped
            } else {
                coupled.velocities.y = clamped
            }
        }
        self.grabbedBlock = nil
    }

    // MARK: Simulation & history

    nonisolated static let substep = 1.0 / 720.0
    private var accumulator = 0.0
    private var sampleAccumulator = 0.0

    /// Ring buffer for the scrolling graph: newest last, ~6 s at 30 Hz.
    private(set) var history: [Double] = []
    nonisolated static let historyCapacity = 180

    private func clearHistory() {
        history = []
    }

    private var graphValue: Double {
        switch graphMode {
        case .position:
            mode == .single ? state.displacement : coupled.displacements.x
        case .velocity:
            mode == .single ? state.velocity : coupled.velocities.x
        case .acceleration:
            mode == .single ? acceleration
                : (-stiffness * coupled.displacements.x
                   + coupling * (coupled.displacements.y - coupled.displacements.x)) / mass
        case .energy:
            mode == .single
                ? energies().kinetic + energies().potential
                : coupled.massEnergies(stiffness: stiffness, coupling: coupling,
                                       masses: SIMD2(mass, mass)).x
        }
    }

    func step(dt: Double) {
        guard !isPaused, timeScale > 0 else { return }
        accumulator += min(dt, 0.1) * timeScale
        var steps = 0
        while accumulator >= Self.substep, steps < 400 {
            accumulator -= Self.substep
            steps += 1
            if grabbedBlock == nil || mode == .coupled {
                switch mode {
                case .single:
                    state = SpringOscillator.step(
                        state, dt: Self.substep, stiffness: stiffness,
                        mass: mass, damping: damping, biasForce: biasForce)
                case .coupled:
                    // While one block is held, pin it and let the other run.
                    var next = CoupledSprings.step(
                        coupled, dt: Self.substep, stiffness: stiffness,
                        coupling: coupling, masses: SIMD2(mass, mass), damping: damping)
                    if grabbedBlock == 0 {
                        next.displacements.x = coupled.displacements.x
                        next.velocities.x = 0
                    } else if grabbedBlock == 1 {
                        next.displacements.y = coupled.displacements.y
                        next.velocities.y = 0
                    }
                    coupled = next
                }
            }
            sampleAccumulator += Self.substep
            if sampleAccumulator >= 1.0 / 30.0 {
                sampleAccumulator = 0
                history.append(graphValue)
                if history.count > Self.historyCapacity {
                    history.removeFirst(history.count - Self.historyCapacity)
                }
            }
        }
    }

    /// Amplitude a release right now would reach (single mode, from
    /// energy): the ghost shows the two turning points.
    func predictedAmplitude() -> Double {
        let energies = energies()
        let total = energies.kinetic + energies.potential
        return (2 * total / stiffness).squareRoot()
    }

    // MARK: Reset

    func reset() {
        stiffness = 40
        mass = 0.5
        damping = 0.1
        restLength = 0.45
        maxExtension = 0.3
        gravityOn = false
        isPaused = false
        timeScale = 1.0
        mode = .single
        state = SpringOscillator(displacement: 0.12, velocity: 0)
        coupled = CoupledSprings(displacements: SIMD2(0.18, 0))
        grabbedBlock = nil
        graphMode = .position
        showVelocity = true
        showAcceleration = false
        showForce = true
        showEnergyBars = true
        showGhost = true
        insightText = ""
        accumulator = 0
        clearHistory()
    }

    init() {
        reset()
    }
}
