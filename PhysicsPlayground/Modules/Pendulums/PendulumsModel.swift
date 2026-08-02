//
//  PendulumsModel.swift
//  Physics Playground — Pendulums module
//
//  App state for the pendulum lab: any number of pendulums, each hung
//  from its own pivot anywhere in the room and each a fully nonlinear
//  SphericalPendulum from
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

    // RIGGING, not a bench.
    //
    // The pivots used to ride a single beam overhead, evenly spaced —
    // which made five pendulums a ROW, and a row of planar swings is a
    // one-dimensional phenomenon drawn along a line. You could have
    // watched it on paper.
    //
    // A pivot is now a point you place anywhere in the room. Hang one
    // from over the sofa and another by the window; throw a bob
    // sideways and it orbits in a true cone rather than a plane. The
    // room is the rig.

    /// Where a pendulum lands when you have not said otherwise.
    nonisolated static let defaultPivot = SIMD3<Double>(0, 2.0, -1.1)
    /// How much air a bob must keep under it at the bottom of its
    /// swing. The pivot's floor is this PLUS the cable's length, so a
    /// long pendulum has to hang from higher up.
    ///
    /// It was 0.85 m, which is not clearance — it is chest height. With
    /// a default 0.8 m cable that put the pivot's floor at 1.65 m,
    /// nineteen centimetres above the spawn well's own mouth: pulling a
    /// pendulum out and moving your hand a millimetre teleported the
    /// whole rig up out of your fingers, and it could not be hung
    /// anywhere in the lower half of the room afterwards. A bob a third
    /// of a metre off the floor is not in the floor.
    nonisolated static let minimumPivotHeight = 0.30

    nonisolated static let lengthRange = 0.25...1.6      // m
    nonisolated static let massRange = 0.1...5.0         // kg
    nonisolated static let gravityRange = 0.5...25.0     // m/s²
    nonisolated static let dampingRange = 0.0...1.0      // N·s/m
    nonisolated static let bobRadiusRange = 0.02...0.07  // m
    nonisolated static let cableRange = 0.001...0.006    // m
    nonisolated static let pendulumBudget = 7

    // MARK: Pendulums

    /// What kind of rig this is.
    ///
    /// The two are genuinely different physics, not a display option: a
    /// simple pendulum is a taut cable constrained to a sphere and
    /// integrated by Verlet, while a double pendulum is a non-separable
    /// two-angle system integrated by RK4 from the exact Lagrangian. They
    /// share a pivot, a mass and a bob radius, and nothing else.
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
        //
        // Present only when `kind == .double`. Kept as plain stored
        // properties rather than an associated value on `Kind` so the
        // struct stays `Equatable` and cheap to copy in the render loop.

        /// The lower rod's length, m.
        var length2: Double = 0.35
        /// The lower bob's mass, kg.
        var mass2: Double = 1.0
        /// The two-angle state. Nil for a simple pendulum.
        var doubleState: DoublePendulum?
        /// Which vertical plane the double pendulum swings in — a unit
        /// horizontal vector. A planar system needs a plane, and this is
        /// it; the rig faces the user by default.
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

        /// Where the UPPER bob is for a double pendulum — the elbow.
        var upperBobWorld: SIMD3<Double>? {
            guard kind == .double, let doubleState else { return nil }
            let planar = doubleState.upperBob(rig: doubleRig)
            return pivot + planeAxis * planar.x + SIMD3(0, planar.y, 0)
        }

        var pivot: SIMD3<Double> { pivotPoint }
        /// The bob a hand grabs and a readout describes. For a double
        /// pendulum that is the LOWER bob — the one whose path is the
        /// thing worth watching.
        var bobWorld: SIMD3<Double> {
            lowerBobWorld ?? (pivot + state.position)
        }

        func period(gravity: Double) -> Double {
            SphericalPendulum.smallAnglePeriod(length: length, gravity: gravity)
        }
    }

    private(set) var pendulums: [Pendulum] = []
    private(set) var selectedID: UUID?

    // MARK: Global knobs

    var gravity = 9.81 { didSet { insight(.gravity) } }

    /// How elastic a bob-on-bob collision is, 0…1.
    ///
    /// 1 is perfectly elastic, which is what a cradle of polished steel
    /// very nearly is and what makes it run for minutes. It is a stored
    /// property rather than a constant because `frictionOn` already
    /// decides whether this rig is idealised, and a cradle that loses
    /// energy at the contacts while its cables lose none would be
    /// incoherent — see `step`.
    var bobRestitution = 1.0
    var isPaused = false
    /// Time scale. Pause is separate.
    ///
    /// The range is stated ONCE, here, because it is now the rail's range
    /// too. The comment that stood in its place claimed "0.25× … 20×"
    /// while the slider driving it ran 0.1 … 5.0 — a number nobody could
    /// reach described in a doc comment nobody could check.
    nonisolated static let timeScaleRange = 0.1...5.0
    var timeScale = 1.0

    enum TrailMode: String, CaseIterable, Identifiable {
        case off, short, long, infinite
        var id: String { rawValue }
    }
    var trailMode: TrailMode = .short
    var showVelocity = true
    var showAcceleration = false
    var showForces = false

    // MARK: Foucault — the reason this pendulum is spherical
    //
    // `SphericalPendulum` has been fully 3-D since it was written, and
    // until now nothing needed the third dimension: a planar pendulum
    // would have rendered everything this bench showed. Foucault is the
    // physics that makes the sphere necessary — and the one demonstration
    // here where passthrough room-scale is load-bearing rather than
    // decorative, because the swing plane holds still against the stars
    // and YOUR ROOM turns underneath it.

    var foucaultOn = false {
        didSet {
            guard foucaultOn != oldValue else { return }
            resetFloorMarkers()
            insightText = foucaultOn
                ? "The swing plane is fixed against the STARS. What turns is the room — and you are standing in it."
                : ""
        }
    }

    /// Where on Earth this bench is standing, degrees.
    nonisolated static let latitudeRange = -90.0...90.0
    var latitudeDegrees = EarthRotation.sites
        .first { $0.name == "Paris" }?.latitudeDegrees ?? 48.8462 {
        didSet { if foucaultOn { resetFloorMarkers() } }
    }

    /// How much faster than Earth the frame is turned, for watchability.
    ///
    /// Earth's real rate at Paris is 11.3° per hour — correct, and far too
    /// slow to stand and watch, so the app runs the frame faster and SAYS
    /// SO. The physics stays exact for the Ω actually integrated: raising
    /// this is precisely equivalent to standing on a planet that spins
    /// faster, which is why it is honest in a way a faked rotation would
    /// not be. Every readout quotes the true rate beside the shown one.
    nonisolated static let spinRange = 200.0...20_000.0
    var earthSpin = 3_000.0

    /// Ω in the lab frame, rad/s — zero unless the effect is switched on,
    /// so `SphericalPendulum.step` reduces to the ordinary pendulum bit
    /// for bit rather than by a branch.
    var earthRotation: SIMD3<Double> {
        guard foucaultOn else { return .zero }
        return EarthRotation.angularVelocity(latitudeDegrees: latitudeDegrees,
                                             spin: earthSpin)
    }

    /// The plane's apparent turn rate here, rad/s (Ω sin φ, exaggerated).
    var precessionRate: Double {
        guard foucaultOn else { return 0 }
        return EarthRotation.precessionRate(latitudeDegrees: latitudeDegrees,
                                            spin: earthSpin)
    }

    /// The TRUE rate, degrees per hour — the number that is actually so,
    /// quoted beside the one you can see.
    var truePrecessionDegreesPerHour: Double {
        EarthRotation.precessionRate(latitudeDegrees: latitudeDegrees)
            * 3600 * 180 / .pi
    }

    /// How long the plane really takes to come back, hours. `nil` at the
    /// equator, where it never does — an answer, not a missing number.
    var truePrecessionHours: Double? {
        EarthRotation.precessionPeriod(latitudeDegrees: latitudeDegrees)
            .map { $0 / 3600 }
    }

    // MARK: The Panthéon ring
    //
    // Foucault's own demonstration did not ask you to watch: it left a
    // RECORD. A ring of markers on the floor that the swing knocks over
    // one by one, so the precession is a thing that has visibly happened
    // rather than a motion you have to catch in the act.

    nonisolated static let markerCount = 24
    nonisolated static let markerRingRadius = 0.55

    /// Which markers are still standing, by index around the ring.
    private(set) var standingMarkers: Set<Int> = []
    /// The plane angle the ring was laid out against, rad — markers are
    /// knocked from where the swing STARTED, so the count is a measure of
    /// how far it has come since.
    private(set) var markerOriginAngle: Double = 0
    private(set) var markersFelled = 0

    private func resetFloorMarkers() {
        standingMarkers = Set(0..<Self.markerCount)
        markersFelled = 0
        markerOriginAngle = currentPlaneAngle ?? 0
    }

    /// The swing plane of the pendulum that drives the ring — the first
    /// one, since the ring is one ring and cannot follow seven bobs.
    var currentPlaneAngle: Double? {
        guard let first = pendulums.first else { return nil }
        let horizontal = SIMD2(first.state.position.x, first.state.position.z)
        guard simd_length(horizontal) > 0.02 else { return nil }
        return EarthRotation.planeAngle(of: horizontal)
    }

    /// Fells any marker the swing plane has now swept past.
    ///
    /// The ring covers a HALF turn, not a whole one, because a plane is
    /// the same plane whichever way the bob is travelling along it — the
    /// same fold `EarthRotation.planeAngle` makes.
    private func advanceFloorMarkers(dt: Double) {
        guard let angle = currentPlaneAngle else { return }
        var swept = angle - markerOriginAngle
        while swept > .pi / 2 { swept -= .pi }
        while swept < -.pi / 2 { swept += .pi }
        let perMarker = Double.pi / Double(Self.markerCount)
        let reached = Int(abs(swept) / perMarker)
        guard reached > 0 else { return }
        let direction = swept < 0 ? -1 : 1
        for step in 1...reached {
            let index = ((direction * step) % Self.markerCount
                         + Self.markerCount) % Self.markerCount
            if standingMarkers.remove(index) != nil { markersFelled += 1 }
        }
    }

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
            insightText = "Damping drains energy every swing — the arc decays exponentially, and the trail cools from orange toward blue as it goes."
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
                     mass: Double = 1.0, at: SIMD3<Double>? = nil) -> UUID? {
        guard pendulums.count < Self.pendulumBudget else { return nil }
        // Clamped at BIRTH, not on the first frame of the drag that
        // follows. It used to be legal to create a pendulum somewhere
        // `movePivot` would immediately refuse to keep it, so the thing
        // appeared under your fingers and jumped out of them one frame
        // later — the well's whole promise, broken by an inconsistency
        // between two functions three lines apart.
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

    /// NEWTON'S CRADLE — five identical bobs hanging in a touching row,
    /// with the first drawn back.
    ///
    /// This is what the module opens with, and it is the right cold-open
    /// for the same reason it is the right desk toy: it is a question
    /// before it is a demonstration. Everyone has seen one; almost nobody
    /// can say why one ball leaves rather than two slower ones.
    ///
    /// IDENTICAL MASSES, and that is not decoration. Equal masses swap
    /// velocities exactly in an elastic collision, which is the whole
    /// mechanism — a cradle of mismatched balls does something much less
    /// tidy. Zero damping, because a cradle's cables are effectively
    /// lossless over the time anyone watches, and the only energy it
    /// really sheds is at the contacts.
    ///
    /// The bobs are placed exactly one diameter apart so they start in
    /// contact. `BobCollision.contactSlop` is what makes that survive
    /// floating point.
    func loadNewtonsCradle() {
        pendulums = []
        let count = 5
        let radius = 0.035
        let length = 0.55
        for index in 0..<count {
            let pivot = Self.defaultPivot
                + SIMD3(Double(index) * radius * 2 - Double(count - 1) * radius, 0, 0)
            // The first ball starts lifted; the rest hang plumb and
            // touching. One in, one out.
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
        // Started well away from hanging, because a double pendulum
        // released near the bottom just swings — the chaos this exists to
        // show needs enough energy to carry the upper rod over the top.
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
                pivotPoint: Self.defaultPivot
                    + SIMD3(Double(index - 2) * 0.30, 0,
                            -abs(Double(index - 2)) * 0.10))
            pendulums.append(pendulum)
        }
        selectedID = pendulums.first?.id
        insightText = "Five lengths, 4% apart: they leave together, drift out of step, then re-align — the beat period is set by the difference of their frequencies."
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
        if selectedID == id { selectedID = pendulums.last?.id }
    }

    // `removeSelected()` deleted 2026-07-29 with the six-slider window
    // panel that was its only caller. Deletion is a Bloom petal, which
    // already routes through `removePendulum(id:)` above.

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

    // `setBobRadius`, `setCableThickness` and `setInitialAngle` deleted
    // 2026-07-29 with the same panel. The first two set cosmetics rather
    // than physics; the third set an initial condition that grabbing the
    // bob and letting go already sets, and sets more honestly — your hand
    // supplies the angle AND the velocity, where the slider silently
    // supplied a velocity of zero.

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
                switch pendulums[index].kind {
                case .simple:
                    pendulums[index].state = SphericalPendulum.step(
                        pendulums[index].state, dt: substep,
                        length: pendulums[index].length, gravity: gravity,
                        mass: pendulums[index].mass,
                        damping: frictionOn ? pendulums[index].damping : 0,
                        angularVelocity: earthRotation)
                case .double:
                    guard var doubleState = pendulums[index].doubleState else { break }
                    var rig = pendulums[index].doubleRig
                    if !frictionOn { rig.damping = 0 }
                    doubleState = DoublePendulum.step(
                        doubleState, dt: substep, rig: rig, gravity: gravity)
                    pendulums[index].doubleState = doubleState
                }
            }
            resolveBobCollisions()
            if foucaultOn { advanceFloorMarkers(dt: substep) }
        }
    }

    // MARK: Bobs that meet

    /// Elastic collisions between bobs, resolved along the line joining
    /// their centres.
    ///
    /// SIMPLE PENDULUMS ONLY, and that is a physical statement rather
    /// than a shortcut: a double pendulum's bob is on a rod whose
    /// reaction to an impulse involves both angles at once, and applying
    /// a 1-D exchange to one of its bobs would put energy into the system
    /// through a constraint the exchange does not know about. A cradle is
    /// made of simple pendulums; so is every collision worth watching
    /// here.
    ///
    /// The bobs are SORTED ALONG THE LINE and swept in order, because
    /// that ordering is the whole trick of Newton's cradle — the impulse
    /// crosses as a compression wave, one contact at a time, and a
    /// simultaneous solve would admit answers real cradles do not give.
    /// `BobCollision` carries the reasoning and the exchange arithmetic;
    /// this projects the room onto the line and writes the answer back.
    private func resolveBobCollisions() {
        let movable = pendulums.indices.filter {
            pendulums[$0].kind == .simple && !pendulums[$0].isGrabbed
        }
        guard movable.count > 1 else { return }

        // The line the bobs are strung out on: from the first pivot to
        // the last. For a cradle that is the rail they hang from.
        let first = pendulums[movable.first!].pivot
        let last = pendulums[movable.last!].pivot
        var axis = last - first
        guard simd_length(axis) > 1e-6 else { return }
        axis = simd_normalize(axis)

        let ordered = movable.sorted {
            simd_dot(pendulums[$0].bobWorld, axis)
                < simd_dot(pendulums[$1].bobWorld, axis)
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

                // Along the line of CENTRES, not along the rail: two bobs
                // meeting slightly off-axis still exchange along the
                // normal, which is what a frictionless contact does.
                let normal = separation / gap
                let va = simd_dot(a.state.velocity, normal)
                let vb = simd_dot(b.state.velocity, normal)
                guard vb - va < 0 else { continue }      // already parting

                let (na, nb) = BobCollision.exchange((velocity: va, mass: a.mass),
                                                     (velocity: vb, mass: b.mass),
                                                     restitution: bobRestitution)
                pendulums[i].state.velocity += normal * (na - va)
                pendulums[j].state.velocity += normal * (nb - vb)
                touched = true
                if abs(na - va) > 0.05 {
                    emitSound(.pop, at: a.bobWorld,
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

    /// Opens on the FIVE-PENDULUM WAVE.
    ///
    /// It used to open with a single bob on a thread — the module's most
    /// mesmerising exhibit was sitting behind a button called
    /// "Resonance ×5". Five lengths stepped 4% apart leave together,
    /// drift into a travelling wave, scramble, and re-align; it is alive
    /// and legible from the first second, and every parameter the module
    /// teaches (length sets period, mass doesn't) is visible in it.
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
        // Reset restored four of the five states the switch bank shows and
        // silently skipped this one, so an ideal pendulum stayed ideal
        // through a reset while its plate sat dark over a bench that was
        // still swinging for ever. Invisible while these were toggles in a
        // collapsed card; a lit lamp is a claim, and the claim was wrong.
        frictionOn = true
        // Checked before it shipped, per the rule the other four taught.
        foucaultOn = false
        latitudeDegrees = EarthRotation.sites
            .first { $0.name == "Paris" }?.latitudeDegrees ?? 48.8462
        earthSpin = 3_000.0
        resetFloorMarkers()
        insightText = ""
        accumulator = 0
        // THE CRADLE IS THE COLD OPEN (2026-08-02), not the five-length
        // resonance rig. Resonance is still a plate in the room, and it
        // is the better SECOND thing to see — but a cradle asks its
        // question before it demonstrates anything, and "why does one
        // ball leave and not two" is a better first sentence than five
        // bobs drifting out of phase.
        loadNewtonsCradle()
    }

    init() {
        reset()
    }
}
