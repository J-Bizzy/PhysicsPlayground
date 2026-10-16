//
//  PendulumsModel.swift
//  Physics Playground — Pendulums module
//
//  App state for the pendulum lab: fully nonlinear pendulum rigs.
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

    /// Where a pendulum lands when you have not said otherwise: collars a
    /// hand's width under the title bar (which rides at about 1.75 m), bobs
    /// at 1.07, both inside a standing reach.
    nonisolated static let defaultPivot = SIMD3<Double>(0, 1.62, -1.1)
    /// Minimum air under a bob at the bottom of its swing; the pivot's
    /// floor is this plus the cable's length.
    nonisolated static let minimumPivotHeight = 0.30

    nonisolated static let lengthRange = 0.25...1.6      // m
    nonisolated static let massRange = 0.1...5.0         // kg
    nonisolated static let gravityRange = 0.5...25.0     // m/s²
    nonisolated static let dampingRange = 0.0...1.0      // N·s/m
    nonisolated static let pendulumBudget = 7

    // MARK: Pendulums

    /// Rig kind — genuinely different physics: simple = taut cable on a
    /// sphere (Verlet); double = two-angle exact Lagrangian (RK4).
    enum Kind: Equatable {
        case simple
        case double
    }

    struct Pendulum: Identifiable, Equatable {
        let id: UUID
        var kind: Kind = .simple
        var length: Double
        var mass: Double
        var damping: Double
        var bobRadius: Double
        var cableThickness: Double
        /// Physics state: bob position/velocity relative to the pivot.
        var state: SphericalPendulum
        /// Where this pendulum hangs from — anywhere in the room.
        var pivotPoint: SIMD3<Double>
        /// While a hand holds the bob, physics freezes and the bob
        /// tracks the hand exactly.
        var isGrabbed = false

        // MARK: The double pendulum's extra half
        // The double rig's extra fields are stored flat so the struct stays
        // `Equatable` and cheap to copy.

        /// The lower rod's length, m.
        var length2: Double = 0.35
        /// The lower bob's mass, kg.
        var mass2: Double = 1.0
        /// The two-angle state. Nil for a simple pendulum.
        var doubleState: DoublePendulum?
        /// Unit horizontal vector — the vertical plane the double pendulum swings in.
        var planeAxis: SIMD3<Double> = SIMD3(1, 0, 0)

        /// The rig `DoublePendulum` needs, assembled from this pendulum.
        var doubleRig: DoublePendulum.Rig {
            DoublePendulum.Rig(length1: length, length2: length2,
                               mass1: mass, mass2: mass2, damping: damping)
        }

        /// Where the lower bob is, in world space. The planar solution
        /// lives in (along-plane, up); this lifts it back into the room.
        var lowerBobWorld: SIMD3<Double>? {
            guard kind == .double, let doubleState else { return nil }
            let planar = doubleState.lowerBob(rig: doubleRig)
            return pivot + planeAxis * planar.x + SIMD3(0, planar.y, 0)
        }

        /// Where the upper bob is for a double pendulum — the elbow.
        var upperBobWorld: SIMD3<Double>? {
            guard kind == .double, let doubleState else { return nil }
            let planar = doubleState.upperBob(rig: doubleRig)
            return pivot + planeAxis * planar.x + SIMD3(0, planar.y, 0)
        }

        var pivot: SIMD3<Double> { pivotPoint }
        /// The bob a hand grabs and a readout describes — the lower bob
        /// on a double pendulum.
        var bobWorld: SIMD3<Double> {
            lowerBobWorld ?? (pivot + state.position)
        }

        func period(gravity: Double) -> Double {
            SphericalPendulum.smallAnglePeriod(length: length, gravity: gravity)
        }
    }

    private(set) var pendulums: [Pendulum] = []
    private(set) var selectedID: UUID?

    // MARK: Springs — two pendulums coupled

    /// A spring joining two simple pendulums' bobs. Natural length: the
    /// distance between the bobs when both hang still, so a coupled pair at
    /// rest has a slack-free, unstretched spring.
    struct Spring: Identifiable, Equatable {
        let id: UUID
        let a: UUID
        let b: UUID
        var restLength: Double
    }

    private(set) var springs: [Spring] = []
    /// Every spring's constant, N/m — More's slider.
    var springStiffness = PendulumsModel.defaultStiffness
    nonisolated static let stiffnessRange = 0.5...8.0
    /// 2 N/m on two 1 kg, 0.6 m pendulums: a beat of about thirteen seconds,
    /// slow enough to watch the swing pass across.
    nonisolated static let defaultStiffness = 2.0
    /// How far apart two pivots may be to be coupled: closer and the spring
    /// would run through a cradle's other balls (the cradle spans 28 cm),
    /// further and it is a rope across the room.
    nonisolated static let couplingRange = 0.3...0.9

    /// The spring a pendulum is on, if any.
    func spring(of id: UUID) -> Spring? {
        springs.first { $0.a == id || $0.b == id }
    }

    func partner(of id: UUID) -> UUID? {
        guard let spring = spring(of: id) else { return nil }
        return spring.a == id ? spring.b : spring.a
    }

    /// The uncoupled simple pendulum this one would couple to: the nearest
    /// whose pivot is within reach of a spring.
    func couplingCandidate(for id: UUID) -> UUID? {
        guard let me = pendulums.first(where: { $0.id == id }),
              me.kind == .simple, spring(of: id) == nil else { return nil }
        return pendulums
            .filter { other in
                other.id != id && other.kind == .simple && spring(of: other.id) == nil
                    && Self.couplingRange.contains(simd_distance(other.pivot, me.pivot))
            }
            .min { simd_distance($0.pivot, me.pivot) < simd_distance($1.pivot, me.pivot) }?
            .id
    }

    /// Joins this pendulum to `other`, or to its nearest free neighbour, with
    /// a spring.
    @discardableResult
    func couple(id: UUID, to partner: UUID? = nil) -> Bool {
        guard let other = partner ?? couplingCandidate(for: id),
              other != id, spring(of: id) == nil, spring(of: other) == nil,
              let a = pendulums.first(where: { $0.id == id }),
              let b = pendulums.first(where: { $0.id == other }) else { return false }
        let hangingA = a.pivot - SIMD3(0, a.length, 0)
        let hangingB = b.pivot - SIMD3(0, b.length, 0)
        springs.append(Spring(id: UUID(), a: id, b: other,
                              restLength: simd_distance(hangingA, hangingB)))
        emitSound(.pop, at: (a.bobWorld + b.bobWorld) / 2, volume: 0.4)
        return true
    }

    func uncouple(id: UUID) {
        springs.removeAll { $0.a == id || $0.b == id }
    }

    func setSpringStiffness(_ value: Double) {
        springStiffness = min(max(value, Self.stiffnessRange.lowerBound),
                              Self.stiffnessRange.upperBound)
    }

    /// Two pendulums and a spring, hung beside the cradle and 15 cm behind
    /// its line (so the cradle's end ball can never reach them), the outer
    /// one pulled back along the spring, away from the cradle: the swing
    /// passes to the inner one and back. Far enough right that the cradle's
    /// end ball, swinging out, does not pass in front of the pair.
    @discardableResult
    func addCoupledPair() -> Bool {
        guard pendulums.count + 2 <= Self.pendulumBudget else { return false }
        let length = 0.6
        let left = Self.defaultPivot + SIMD3(0.62, 0, -0.15)
        let right = left + SIMD3(0.4, 0, 0)
        guard let a = addPendulum(length: length, angle: 0, mass: 1.0, at: left),
              let b = addPendulum(length: length, angle: 0, mass: 1.0, at: right) else { return false }
        if let index = pendulums.firstIndex(where: { $0.id == b }) {
            pendulums[index].state = SphericalPendulum(length: length, angle: 0.3)
        }
        // Its own partner, by name: nearest-first would hand the spring to
        // the cradle's end bob, 35 cm away against the partner's 40.
        couple(id: a, to: b)
        selectedID = b
        return true
    }

    /// The rig `CoupledPendulums` steps for this spring.
    private func coupledRig(_ spring: Spring, _ a: Pendulum, _ b: Pendulum) -> CoupledPendulums.Rig {
        CoupledPendulums.Rig(pivotA: a.pivot, pivotB: b.pivot,
                             lengthA: a.length, lengthB: b.length,
                             massA: a.mass, massB: b.mass,
                             stiffness: springStiffness, restLength: spring.restLength,
                             dampingA: frictionOn ? a.damping : 0,
                             dampingB: frictionOn ? b.damping : 0)
    }

    /// The forces on a bob, as the Force layer draws them: gravity, the
    /// cable's tension (including what it takes to hold the spring), the
    /// spring, and their sum with the air's drag.
    func forces(on pendulum: Pendulum)
        -> (gravity: SIMD3<Double>, tension: SIMD3<Double>, spring: SIMD3<Double>, net: SIMD3<Double>) {
        let gravityForce = SIMD3(0, -gravity * pendulum.mass, 0)
        let radial = simd_normalize(pendulum.state.position)
        var springForce = SIMD3<Double>.zero
        var tension = pendulum.state.tension(length: pendulum.length, gravity: gravity,
                                             mass: pendulum.mass)
        if pendulum.kind == .simple, let spring = spring(of: pendulum.id),
           let other = pendulums.first(where: { $0.id == (spring.a == pendulum.id ? spring.b : spring.a) }) {
            springForce = CoupledPendulums.springForceOnA(
                bobA: pendulum.bobWorld, bobB: other.bobWorld,
                stiffness: springStiffness, restLength: spring.restLength)
            tension += simd_dot(springForce, radial)
        }
        let tensionForce = -radial * tension
        let drag = -(frictionOn ? pendulum.damping : 0) * pendulum.state.velocity
        return (gravityForce, tensionForce, springForce,
                gravityForce + tensionForce + springForce + drag)
    }

    // MARK: Global knobs

    var gravity = 9.81

    /// Bob-on-bob restitution, 0…1 (1 = elastic, what a steel cradle very nearly is).
    var bobRestitution = 1.0
    var isPaused = false
    /// Time scale (pause is separate). The range is stated once, here —
    /// any control driving it must read this constant.
    nonisolated static let timeScaleRange = 0.1...5.0
    var timeScale = 1.0

    // MARK: Time Capsule

    @ObservationIgnored var capsule = TimeCapsule<CapsuleSnapshot>()
    @ObservationIgnored var capsuleClock = 0.0
    var scrubTime: Double?
    var scrubNonce = 0

    var showVelocity = true
    var showForces = false

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
                     mass: Double = 1.0, at: SIMD3<Double>? = nil) -> UUID? {
        guard pendulums.count < Self.pendulumBudget else { return nil }
        // Clamp at birth — must agree with movePivot's clamp, or the rig
        // jumps out of the hand on the first drag frame.
        var pivot = at ?? Self.defaultPivot
        pivot.y = max(pivot.y, Self.minimumPivotHeight + length)
        let pendulum = Pendulum(
            id: UUID(), length: length, mass: mass, damping: 0.02,
            bobRadius: 0.035, cableThickness: 0.002,
            state: SphericalPendulum(length: length, angle: angle),
            pivotPoint: pivot)
        pendulums.append(pendulum)
        selectedID = pendulum.id
        emitSound(.pop, at: pendulum.bobWorld, volume: 0.5)
        return pendulum.id
    }

    /// Newton's cradle cold-open: five identical bobs (equal masses swap
    /// velocities exactly — the mechanism), zero damping, spaced one diameter
    /// apart; `BobCollision.contactSlop` makes the contact survive float.
    func loadNewtonsCradle() {
        pendulums = []
        let count = 5
        let radius = 0.035
        let length = 0.55
        for index in 0..<count {
            let pivot = Self.defaultPivot
                + SIMD3(Double(index) * radius * 2 - Double(count - 1) * radius, 0, 0)
            let angle = index == 0 ? -0.55 : 0.0
            pendulums.append(Pendulum(
                id: UUID(), kind: .simple, length: length, mass: 0.2,
                damping: 0, bobRadius: radius, cableThickness: 0.0016,
                state: SphericalPendulum(length: length, angle: angle),
                pivotPoint: pivot))
        }
        selectedID = nil
        bobRestitution = 1.0
    }

    /// A double pendulum: the chaotic one.
    @discardableResult
    func addDoublePendulum(at point: SIMD3<Double>? = nil) -> UUID? {
        guard pendulums.count < Self.pendulumBudget else { return nil }
        let upper = 0.40
        let lower = 0.32
        var pivot = point ?? Self.defaultPivot
        pivot.y = max(pivot.y, Self.minimumPivotHeight + upper + lower)
        // Started well away from hanging — chaos needs enough energy to
        // carry the upper rod over the top.
        let pendulum = Pendulum(
            id: UUID(), kind: .double, length: upper, mass: 1.0,
            damping: 0.01, bobRadius: 0.032, cableThickness: 0.002,
            state: SphericalPendulum(length: upper, angle: 0),
            pivotPoint: pivot,
            length2: lower, mass2: 1.0,
            doubleState: DoublePendulum(theta1: 2.2, theta2: 1.4))
        pendulums.append(pendulum)
        selectedID = pendulum.id
        emitSound(.pop, at: pendulum.bobWorld, volume: 0.5)
        return pendulum.id
    }

    /// Moves a pendulum's pivot. Clamped so a bob can never end up
    /// below the floor.
    func movePivot(id: UUID, to point: SIMD3<Double>) {
        guard let index = pendulums.firstIndex(where: { $0.id == id }) else { return }
        var clamped = point
        clamped.y = max(clamped.y, Self.minimumPivotHeight + pendulums[index].length)
        pendulums[index].pivotPoint = clamped
    }

    func removePendulum(id: UUID) {
        pendulums.removeAll { $0.id == id }
        uncouple(id: id)
        if selectedID == id { selectedID = pendulums.last?.id }
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
    }

    func setMass(id: UUID, _ mass: Double) {
        guard let index = pendulums.firstIndex(where: { $0.id == id }) else { return }
        pendulums[index].mass = min(max(mass, Self.massRange.lowerBound), Self.massRange.upperBound)
    }

    func setDamping(id: UUID, _ damping: Double) {
        guard let index = pendulums.firstIndex(where: { $0.id == id }) else { return }
        pendulums[index].damping = min(max(damping, 0), Self.dampingRange.upperBound)
    }

    // MARK: Grab & release

    func beginGrab(id: UUID) {
        guard let index = pendulums.firstIndex(where: { $0.id == id }) else { return }
        pendulums[index].isGrabbed = true
        selectedID = id
    }

    /// The bob follows the hand's direction at the cable's length — the
    /// cable is inextensible; only the length bead changes L.
    func moveGrabbed(id: UUID, toWorld hand: SIMD3<Double>) {
        guard let index = pendulums.firstIndex(where: { $0.id == id }),
              pendulums[index].isGrabbed else { return }
        let offset = hand - pendulums[index].pivot
        let distance = simd_length(offset)
        guard distance > 1e-6 else { return }
        pendulums[index].state.position =
            (offset / distance) * pendulums[index].length
        pendulums[index].state.velocity = .zero
    }

    /// Below this a release is a set-down, not a throw, and makes no whoosh —
    /// the same rule Projectiles and Orbital Mechanics keep.
    nonisolated static let throwWhooshSpeed = 0.25

    /// Release with the hand's velocity: clamp to the sphere, project
    /// the velocity tangent, resume. `isThrow` false is a handing-back that
    /// is not the hand's at all (the end of a length edit), and is silent.
    func release(id: UUID, handVelocity: SIMD3<Double>, isThrow: Bool = true) {
        guard let index = pendulums.firstIndex(where: { $0.id == id }) else { return }
        var pendulum = pendulums[index]
        let direction = simd_normalize(pendulum.state.position)
        pendulum.state.position = direction * pendulum.length
        var velocity = handVelocity
        velocity -= simd_dot(velocity, direction) * direction
        pendulum.state.velocity = velocity
        pendulum.isGrabbed = false
        pendulums[index] = pendulum
        let speed = simd_length(velocity)
        if isThrow, speed > Self.throwWhooshSpeed {
            emitSound(.whoosh, at: pendulum.bobWorld,
                      volume: min(0.3 + speed * 0.2, 0.9))
        }
    }

    // MARK: Simulation

    /// Fixed internal substep — small enough that even 20× time scale
    /// stays glassy.
    nonisolated static let substep = 1.0 / 720.0
    private var accumulator = 0.0

    /// The friction kill-switch: off = an ideal pendulum that swings
    /// forever (per-pendulum damping is bypassed, not forgotten).
    var frictionOn = true

    func step(dt: Double) {
        guard !isPaused, timeScale > 0 else { return }
        // Capsule clock is wall-clock (the wearer's), not simulation time.
        defer { recordCapsuleFrame(dt: min(dt, 0.1)) }
        accumulator += min(dt, 0.1) * timeScale
        let substep = Self.substep
        var steps = 0
        while accumulator >= substep, steps < 400 {
            accumulator -= substep
            steps += 1
            // Coupled pairs move together; a held bob still pulls on its partner.
            var coupled = Set<UUID>()
            for spring in springs {
                guard let ia = pendulums.firstIndex(where: { $0.id == spring.a }),
                      let ib = pendulums.firstIndex(where: { $0.id == spring.b }) else { continue }
                coupled.formUnion([spring.a, spring.b])
                let heldA = pendulums[ia].isGrabbed, heldB = pendulums[ib].isGrabbed
                guard !(heldA && heldB) else { continue }
                let next = CoupledPendulums.step(
                    CoupledPendulums(a: pendulums[ia].state, b: pendulums[ib].state),
                    dt: substep, rig: coupledRig(spring, pendulums[ia], pendulums[ib]),
                    gravity: gravity, heldA: heldA, heldB: heldB)
                if !heldA { pendulums[ia].state = next.a }
                if !heldB { pendulums[ib].state = next.b }
            }
            for index in pendulums.indices
            where !pendulums[index].isGrabbed && !coupled.contains(pendulums[index].id) {
                switch pendulums[index].kind {
                case .simple:
                    pendulums[index].state = SphericalPendulum.step(
                        pendulums[index].state, dt: substep,
                        length: pendulums[index].length, gravity: gravity,
                        mass: pendulums[index].mass,
                        damping: frictionOn ? pendulums[index].damping : 0)
                case .double:
                    guard var doubleState = pendulums[index].doubleState else { break }
                    var rig = pendulums[index].doubleRig
                    if !frictionOn { rig.damping = 0 }
                    doubleState = DoublePendulum.step(
                        doubleState, dt: substep, rig: rig, gravity: gravity)
                    pendulums[index].doubleState = doubleState
                    // Mirror the lower bob into `state` (pivot-relative, in the
                    // swing plane) — everything downstream reads `state`.
                    let planar = doubleState.lowerBob(rig: rig)
                    let planarVelocity = doubleState.lowerBobVelocity(rig: rig)
                    let axis = pendulums[index].planeAxis
                    pendulums[index].state = SphericalPendulum(
                        position: axis * planar.x + SIMD3(0, planar.y, 0),
                        velocity: axis * planarVelocity.x
                            + SIMD3(0, planarVelocity.y, 0))
                }
            }
            resolveBobCollisions()
        }
        if steps > 0 { watchSwingsPassing() }
    }

    // MARK: A swing passed across (`Remark`)

    /// For each spring, the bob that was at rest when its pair's swing
    /// began. The whole swing arriving in it is a moment worth a gleam.
    @ObservationIgnored private var quietBob: [UUID: UUID] = [:]

    /// The swing energy a bob carries above hanging still: ½mv² + mg(y + L),
    /// y measured from the pivot.
    func swingEnergy(_ pendulum: Pendulum) -> Double {
        0.5 * pendulum.mass * simd_length_squared(pendulum.state.velocity)
            + pendulum.mass * gravity * (pendulum.state.position.y + pendulum.length)
    }

    /// Below 5 % of the pair's swing a bob is the quiet one; above 95 %,
    /// the swing has passed wholly into it. The spring's own small energy
    /// is left out, so the shares are the two bobs' alone.
    private func watchSwingsPassing() {
        for spring in springs {
            guard let a = pendulums.first(where: { $0.id == spring.a }),
                  let b = pendulums.first(where: { $0.id == spring.b }),
                  !a.isGrabbed, !b.isGrabbed else {
                quietBob[spring.id] = nil
                continue
            }
            let energyA = swingEnergy(a), energyB = swingEnergy(b)
            let total = energyA + energyB
            guard total > 1e-4 else { quietBob[spring.id] = nil; continue }
            if let quiet = quietBob[spring.id] {
                let receiver = quiet == a.id ? a : b
                guard swingEnergy(receiver) / total > 0.95 else { continue }
                quietBob[spring.id] = nil
                if Remark.claim(.swingPassedAcross) {
                    emitSound(.gleam, at: receiver.bobWorld, volume: Remark.volume)
                }
            } else if energyA / total < 0.05 {
                quietBob[spring.id] = a.id
            } else if energyB / total < 0.05 {
                quietBob[spring.id] = b.id
            }
        }
    }

    // MARK: Bobs that meet

    /// Elastic bob collisions along the line of centres. Simple pendulums only
    /// (a rod's impulse response couples both angles — a 1-D exchange injects
    /// energy). Sorted sweep: the cradle's impulse must cross one contact at a time.
    ///
    /// Resolved per cluster of bobs near enough to touch, so rigs that cannot
    /// meet do not share a sweep: with one sweep over the whole room, a
    /// pendulum hung anywhere tilted the cradle's sort axis and changed its
    /// iteration budget. `PendulumsCoupledTests` holds the cradle to swinging
    /// exactly as it would alone beside a coupled pair.
    private func resolveBobCollisions() {
        let movable = pendulums.indices.filter {
            pendulums[$0].kind == .simple && !pendulums[$0].isGrabbed
        }
        guard movable.count > 1 else { return }
        // Union-find over bobs within a hand's width of contact.
        var parent = Array(movable.indices)
        func root(_ i: Int) -> Int {
            var i = i
            while parent[i] != i { parent[i] = parent[parent[i]]; i = parent[i] }
            return i
        }
        for i in movable.indices {
            for j in movable.indices where j > i {
                let a = pendulums[movable[i]], b = pendulums[movable[j]]
                let reach = a.bobRadius + b.bobRadius + BobCollision.contactSlop + 0.05
                if simd_distance(a.bobWorld, b.bobWorld) <= reach {
                    parent[root(i)] = root(j)
                }
            }
        }
        var clusters: [Int: [Int]] = [:]
        for i in movable.indices { clusters[root(i), default: []].append(movable[i]) }
        for cluster in clusters.values.sorted(by: { $0[0] < $1[0] }) where cluster.count > 1 {
            resolveCollisions(among: cluster)
        }
    }

    /// The sorted sweep over one cluster of bobs that can touch.
    private func resolveCollisions(among movable: [Int]) {

        // Sweep axis: first→last pivot; if pivots coincide, fall back to bobs.
        // A degenerate axis skips the sort, never the resolution.
        var axis = pendulums[movable.last!].pivot - pendulums[movable.first!].pivot
        if simd_length(axis) <= 1e-6 {
            axis = pendulums[movable.last!].bobWorld
                - pendulums[movable.first!].bobWorld
        }
        let ordered: [Int]
        if simd_length(axis) > 1e-6 {
            let unit = simd_normalize(axis)
            ordered = movable.sorted {
                simd_dot(pendulums[$0].bobWorld, unit)
                    < simd_dot(pendulums[$1].bobWorld, unit)
            }
        } else {
            ordered = movable
        }

        for _ in 0..<(4 * ordered.count) {
            var touched = false
            for slot in 0..<(ordered.count - 1) {
                let i = ordered[slot], j = ordered[slot + 1]
                let a = pendulums[i], b = pendulums[j]
                let separation = b.bobWorld - a.bobWorld
                let gap = simd_length(separation)
                let contact = a.bobRadius + b.bobRadius + BobCollision.contactSlop
                guard gap <= contact, gap > 1e-9 else { continue }

                // Exchange along the line of centres — the frictionless contact normal.
                let normal = separation / gap
                let va = simd_dot(a.state.velocity, normal)
                let vb = simd_dot(b.state.velocity, normal)
                guard vb - va < 0 else { continue }      // already parting

                let (na, nb) = BobCollision.exchange((velocity: va, mass: a.mass),
                                                     (velocity: vb, mass: b.mass),
                                                     restitution: bobRestitution)
                // Off-axis exchange conserves energy (measured Δ3.6e-15 J over 1800
                // steps); a tangent-projection "fix" was tried and reverted.
                pendulums[i].state.velocity += normal * (na - va)
                pendulums[j].state.velocity += normal * (nb - vb)
                touched = true
                if abs(na - va) > 0.05 {
                    emitSound(.clack, at: a.bobWorld,
                              volume: min(abs(na - va) * 0.4, 0.8))
                }
            }
            if !touched { break }
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
        // A coupled bob is let go into its spring: its partner swings on too.
        if let spring = spring(of: id),
           let other = pendulums.first(where: { $0.id == partner(of: id) }) {
            let rig = coupledRig(spring, pendulum, other)
            var pair = CoupledPendulums(a: state, b: other.state)
            for _ in 0..<points {
                for _ in 0..<stepsPerPoint {
                    pair = CoupledPendulums.step(pair, dt: Self.substep, rig: rig, gravity: gravity)
                }
                path.append(pendulum.pivot + pair.a.position)
            }
            return path
        }
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

    /// Opens on Newton's cradle.
    func reset() {
        pendulums = []
        selectedID = nil
        quietBob = [:]
        gravity = 9.81
        isPaused = false
        timeScale = 1.0
        showVelocity = true
        showForces = false
        springs = []
        springStiffness = Self.defaultStiffness
        // Reset must restore every plate-backed flag — ResetCoverageTests
        // reflects over Bools.
        frictionOn = true
        accumulator = 0
        clearCapsule()
        loadNewtonsCradle()
    }

    init() {
        reset()
        #if DEBUG
        // `-penCoupled 1` hangs the coupled pair beside the cradle;
        // `-penSpringK <N/m>` sets its spring.
        if UserDefaults.standard.bool(forKey: "penCoupled") { addCoupledPair() }
        let stiffness = UserDefaults.standard.double(forKey: "penSpringK")
        if stiffness > 0 { setSpringStiffness(stiffness) }
        #endif
    }
}

// MARK: - Time Capsule

extension PendulumsModel: TimeCapsuleRecording {
    /// Dynamical state only. `accumulator` is genuine physics state — dropping it
    /// restores up to one substep out of phase. Out: frictionOn, layers, selection.
    struct CapsuleSnapshot: Equatable {
        var pendulums: [Pendulum]
        var accumulator: Double
        var gravity: Double
        var bobRestitution: Double
        /// The springs and their constant: they change how the bobs move.
        var springs: [Spring]
        var springStiffness: Double
    }

    func captureCapsuleSnapshot() -> CapsuleSnapshot {
        CapsuleSnapshot(pendulums: pendulums, accumulator: accumulator,
                        gravity: gravity, bobRestitution: bobRestitution,
                        springs: springs, springStiffness: springStiffness)
    }

    func restoreCapsuleSnapshot(_ snapshot: CapsuleSnapshot) {
        // The hand wins: a currently grabbed bob is not moved; one grabbed
        // in the snapshot comes back released.
        var restored = snapshot.pendulums
        for index in restored.indices {
            let id = restored[index].id
            if let live = pendulums.first(where: { $0.id == id }), live.isGrabbed {
                restored[index] = live
            } else {
                restored[index].isGrabbed = false
            }
        }
        pendulums = restored
        accumulator = snapshot.accumulator
        gravity = snapshot.gravity
        bobRestitution = snapshot.bobRestitution
        springs = snapshot.springs.filter { spring in
            pendulums.contains { $0.id == spring.a } && pendulums.contains { $0.id == spring.b }
        }
        springStiffness = snapshot.springStiffness
        if let selectedID, !pendulums.contains(where: { $0.id == selectedID }) {
            self.selectedID = nil
        }
    }

    /// The bobs' recorded paths for the walkable tube (lower bob on a double rig).
    func capsuleRecordedPaths(stride: Int = 4) -> [[SIMD3<Float>]] {
        guard scrubTime != nil, let span = capsule.span else { return [] }
        var paths: [UUID: [SIMD3<Float>]] = [:]
        for frame in capsule.frames(in: span, stride: stride) {
            for pendulum in frame.snapshot.pendulums {
                let point = SIMD3<Float>(pendulum.bobWorld)
                if let last = paths[pendulum.id]?.last,
                   simd_distance(last, point) < 0.004 { continue }
                paths[pendulum.id, default: []].append(point)
            }
        }
        return paths.values.filter { $0.count >= 2 }
    }
}
