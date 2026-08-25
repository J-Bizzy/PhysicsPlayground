//
//  MagnetismModel.swift
//  Physics Playground — Magnetism module
//
//  Bar magnets (ideal dipoles) carried around a room-scale region; free
//  magnets glide and turn under exact dipole force/torque from the others.
//  Motion is overdamped and speed-capped (not momentum dynamics).
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
    /// The physics SAFETY bounds — room-scale, not a wall a hand meets.
    /// Binds only the FREE simulation, so a flicked magnet settles in the
    /// room rather than sailing off.
    nonisolated static let safetyHalfExtents = SIMD3<Double>(2.6, 1.6, 2.6)
    nonisolated static let regionFloor = 0.35
    /// Visual length of a bar magnet (m); also the touching distance.
    nonisolated static let magnetLength = 0.16
    nonisolated static let magnetBudget = 4
    nonisolated static let strengthRange = 1.0...12.0
    nonisolated static let defaultStrength = 6.0

    // Overdamped glide tuning — direction from the physics, speed capped.
    private static let forceGain = 6.0e3
    private static let torqueGain = 9.0e4
    private static let maxLinearSpeed = 0.5     // m/s
    private static let maxAngularSpeed = 3.0    // rad/s
    /// Magnets can't pass through each other — they stick at a touch.
    private static let contactDistance = magnetLength * 0.92
    /// Rotation below this in one step is not motion, it is noise.
    private static let restAngle = 2.0e-5   // rad
    /// How far above contact a magnet begins to slow. See `softenedAtContact`.
    private static let contactBand = 0.030
    /// Below this glide speed a magnet is simply at rest.
    private static let restSpeed = 3.0e-4    // m/s

    private(set) var magnets: [BarMagnet] = []
    private(set) var selectedID: UUID?
    /// Every magnet a hand is currently holding — a SET, because two
    /// hands can each carry one.
    private(set) var heldIDs: Set<UUID> = []

    var isPaused = false
    var showFieldLines = true

    // MARK: The compass you carry

    /// A single hand-held compass, walked around the magnets to watch the
    /// needle swing (τ = m × B aligning a dipole with the local field).
    var compassOn = true
    var compassPosition = MagnetismModel.regionCenter + SIMD3(0.0, -0.42, 0.55)

    func moveCompass(to point: SIMD3<Double>) {
        var clamped = point
        clamped.y = max(clamped.y, Self.regionFloor)
        compassPosition = clamped
    }

    // MARK: Earth's own field

    /// Whether the room is standing on a planet. COMPASSES ONLY: Earth's
    /// field is deliberately not applied to the bar magnets or the field
    /// lines, only to the compasses.
    var earthFieldOn = true

    /// Earth's field in the room, T — zero when switched off.
    var earthField: SIMD3<Double> {
        earthFieldOn ? GeomagneticField.vector() : .zero
    }

    /// What a COMPASS feels anywhere in the room: every magnet, plus the
    /// planet. Distinct from the field the magnets feel from each other.
    func compassField(at point: SIMD3<Double>) -> SIMD3<Double> {
        MagneticField.vector(at: point, dueTo: magnets) + earthField
    }

    /// The field where the hand compass is — what its needle points along.
    var compassField: SIMD3<Double> { compassField(at: compassPosition) }

    /// True when Earth is the bigger part of what the hand compass feels
    /// — carried clear of the magnets, reading the planet.
    var compassIsReadingEarth: Bool {
        guard earthFieldOn else { return false }
        let fromMagnets = MagneticField.vector(at: compassPosition, dueTo: magnets)
        return simd_length(fromMagnets) < simd_length(earthField)
    }

    /// |B| at the compass in microtesla, for its dial label.
    var compassMicroTesla: Double { simd_length(compassField) * 1e6 }

    var selectedMagnet: BarMagnet? {
        guard let selectedID else { return nil }
        return magnets.first { $0.id == selectedID }
    }

    // MARK: Clock — the overdamped magnetic dynamics

    /// Whether the magnets translate and turn under their mutual forces.
    /// Off, every magnet holds exactly where you park it.
    var dynamicsOn = true

    // MARK: Inertia — the alternative bench, behind a launch argument

    /// Whether the magnets have MASS AND ROTATIONAL INERTIA. Off by
    /// default (the glide), on with `-magInertia 1`; both ship (a needle
    /// released at an angle overshoots and rings). See DECISIONS.md.
    /// DEBUG-only: a release build cannot set the flag, and the mode
    /// carries a known defect (a touching pair never settles).
    #if DEBUG
    var inertiaOn = UserDefaults.standard.bool(forKey: "magInertia")
    #else
    var inertiaOn = false
    #endif

    /// Per-magnet velocity and angular velocity. Empty while the glide
    /// drives, so switching modes starts from rest.
    private var bodies: [UUID: DipoleBody] = [:]

    // MARK: Time Capsule

    @ObservationIgnored var capsule = TimeCapsule<CapsuleSnapshot>()
    @ObservationIgnored var capsuleClock = 0.0
    var scrubTime: Double?
    var scrubNonce = 0

    /// Linear drag, 1/s — the one tunable in the inertial path.
    private static let inertialDamping = 0.9

    func step(dt: Double) {
        guard !isPaused else { return }
        defer { recordCapsuleFrame(dt: min(dt, 1.0 / 30.0)) }
        guard dynamicsOn else {
            // Frozen: no forces, but contact separation still holds so a
            // dragged magnet can't be parked inside another.
            bodies.removeAll()
            magnets = separated(magnets)
            return
        }
        if inertiaOn {
            stepWithInertia(dt: dt)
            return
        }
        bodies.removeAll()
        stepOverdamped(dt: dt)
    }

    /// The inertial bench: F = ma and τ = Iα, with the exact dipole
    /// force and torque, integrated by `PhysicsCore.DipoleDynamics`.
    private func stepWithInertia(dt: Double) {
        // Substepped: the torque close in is large; four substeps at
        // 90 Hz is 360 Hz of physics.
        let substeps = 4
        let h = min(dt, 1.0 / 60.0) / Double(substeps)
        for _ in 0..<substeps {
            var next = magnets
            for i in magnets.indices {
                let id = magnets[i].id
                guard !heldIDs.contains(id) else {
                    // A held magnet is the hand's, not the physics'; its
                    // stored motion is cleared.
                    bodies[id] = DipoleBody()
                    continue
                }
                guard magnets.count > 1 else { continue }

                // STILL THE POINT DIPOLE, AND IT IS THE WRONG MODEL HERE,
                // measured 50% low at contact — but the pole-pair remedy
                // (`netBarForce`) is worse: pathological at/inside contact
                // (repulsion at r/L = 1.0). Both models are unusable where
                // the magnets meet; the dipole keeps the sign right.
                // `testTheBarForceIsUnusableWhereThePolesMeet` pins it. Do
                // not "fix" without reading.
                let force = MagneticField.netForce(on: magnets, at: i)
                let field = MagneticField.vector(
                    at: magnets[i].position, dueTo: magnets, excluding: i)
                let torque = simd_cross(magnets[i].moment, field)

                let strength = magnets[i].strength
                var body = bodies[id] ?? DipoleBody()
                var position = magnets[i].position
                var moment = magnets[i].moment
                DipoleDynamics.step(
                    body: &body, position: &position, moment: &moment,
                    force: force, torque: torque,
                    mass: DipoleDynamics.mass(moment: strength),
                    momentOfInertia: DipoleDynamics.momentOfInertia(
                        moment: strength, length: Self.magnetLength),
                    damping: Self.inertialDamping,
                    dt: h)

                // Inelastic walls: a magnet that reaches one stops.
                let clamped = clamp(position)
                if clamped != position { body.velocity = .zero }
                next[i].position = clamped
                next[i].moment = moment
                bodies[id] = body
            }
            magnets = separated(next)
            killVelocityIntoContacts()
        }
        // Anything that has left the bench forgets its motion.
        let live = Set(magnets.map(\.id))
        bodies = bodies.filter { live.contains($0.key) }
    }

    /// Takes the APPROACHING component out of two touching magnets'
    /// velocities — an inelastic contact, so a snapped-together pair does
    /// not sit buzzing. Only the component along the line of centres, and
    /// only while closing; sliding is untouched.
    private func killVelocityIntoContacts() {
        for a in magnets.indices {
            for b in (a + 1)..<magnets.count {
                let delta = magnets[b].position - magnets[a].position
                let distance = simd_length(delta)
                guard distance < Self.contactDistance, distance > 1e-9 else { continue }
                let axis = delta / distance

                let towardB = simd_dot(bodies[magnets[a].id]?.velocity ?? .zero, axis)
                if towardB > 0, var body = bodies[magnets[a].id] {
                    body.velocity -= axis * towardB
                    bodies[magnets[a].id] = body
                }
                let towardA = simd_dot(bodies[magnets[b].id]?.velocity ?? .zero, -axis)
                if towardA > 0, var body = bodies[magnets[b].id] {
                    body.velocity += axis * towardA
                    bodies[magnets[b].id] = body
                }
            }
        }
    }

    /// The overdamped glide — the bench's default since it was written.
    private func stepOverdamped(dt: Double) {
        let h = min(dt, 1.0 / 60.0)
        var next = magnets
        for i in magnets.indices where !heldIDs.contains(magnets[i].id) {
            guard magnets.count > 1 else { continue }

            // Translate down the net force (direction exact; speed
            // capped). Point dipole — see the note in `stepWithInertia`.
                let force = MagneticField.netForce(on: magnets, at: i)
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
            // Turn the moment toward the local field (τ = m × B), and
            // NEVER PAST IT: clamp the step to the angle remaining so an
            // aligned pair lands on alignment and stops dead, instead of
            // overshooting into a frame-rate limit cycle.
            let field = MagneticField.vector(
                at: magnets[i].position, dueTo: magnets, excluding: i)
            let torque = simd_cross(magnets[i].moment, field)
            let tMag = simd_length(torque)
            let fieldMag = simd_length(field)
            let momentMag = simd_length(magnets[i].moment)
            if tMag > 1e-22, fieldMag > 1e-18, momentMag > 1e-18 {
                let rate = min(Self.torqueGain * tMag, Self.maxAngularSpeed)
                let cosine = simd_dot(magnets[i].moment / momentMag, field / fieldMag)
                let remaining = acos(min(max(cosine, -1), 1))
                let stepAngle = min(rate * h, remaining)
                // Below this the rotation is sub-pixel; stepping is noise.
                if stepAngle > Self.restAngle {
                    let q = simd_quatd(angle: stepAngle, axis: torque / tMag)
                    next[i].moment = q.act(magnets[i].moment)
                }
            }
        }
        magnets = separated(next)
    }

    /// Takes the INWARD component out of a magnet's glide as it closes on
    /// one it is already touching, so a snapped pair stops instead of
    /// buzzing. Only the closing component, in proportion to the gap
    /// left; a magnet can still slide along or be pulled away.
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

    /// Pushes overlapping magnets apart to the touching distance. The
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
                    let aHeld = heldIDs.contains(result[a].id)
                    let bHeld = heldIDs.contains(result[b].id)
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

    /// The FREE simulation's safety bound — never applied to a hand.
    /// Room-scale, so it only ever fires on a magnet that has drifted
    /// or been flicked far across the room.
    private func clamp(_ p: SIMD3<Double>) -> SIMD3<Double> {
        var c = simd_clamp(p,
                           Self.regionCenter - Self.safetyHalfExtents,
                           Self.regionCenter + Self.safetyHalfExtents)
        c.y = max(c.y, Self.regionFloor)
        return c
    }

    /// A hand meets no walls (owner, 2026-08-03) — only the floor.
    private func floored(_ p: SIMD3<Double>) -> SIMD3<Double> {
        var c = p
        c.y = max(c.y, Self.regionFloor)
        return c
    }

    // MARK: Manipulation

    func grab(id: UUID) {
        guard magnets.contains(where: { $0.id == id }) else { return }
        heldIDs.insert(id)
        selectedID = id
    }

    func move(id: UUID, to point: SIMD3<Double>) {
        guard let index = magnets.firstIndex(where: { $0.id == id }) else { return }
        magnets[index].position = floored(point)
    }

    /// One hand lets go; whatever the other hand holds stays held.
    func release(id: UUID) { heldIDs.remove(id) }

    /// Everything lets go — reset, and the legacy single-drag path.
    func release() { heldIDs.removeAll() }

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
        // Born at the fingertips; a hand meets no walls.
        let magnet = BarMagnet(position: floored(position),
                               moment: SIMD3(Self.defaultStrength, 0, 0))
        magnets.append(magnet)
        selectedID = magnet.id
        return magnet.id
    }

    func removeMagnet(id: UUID) {
        // Deleting down to an empty room is allowed: the well can always
        // hand back a magnet.
        magnets.removeAll { $0.id == id }
        heldIDs.remove(id)
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

    // MARK: Field readout for the notebook

    /// |B| in millitesla at the region centre — a live sense of the field.
    var centerFieldMilliTesla: Double {
        MagneticField.magnitude(at: Self.regionCenter, dueTo: magnets) * 1000
    }

    // MARK: Reset

    /// What `-magInertia` asked for at launch — `reset()` returns to THIS
    /// rather than `false`, so Reset keeps the staged bench.
    #if DEBUG
    private let inertiaAtLaunch = UserDefaults.standard.bool(forKey: "magInertia")
    #else
    private let inertiaAtLaunch = false
    #endif

    func reset() {
        // ResetCoverageTests enumerates every Bool, so a new flag obliges
        // a line here.
        inertiaOn = inertiaAtLaunch
        bodies.removeAll()
        // TWO magnets, and the second one is the module.
        //
        // It was one, centred, on the reasoning that "its looping dipole
        // field IS the opening scene". The field was drawn and it was
        // correct and NOTHING MOVED — one magnet has nothing to attract, so
        // the lab opened as a diagram of itself and stayed that way until
        // the wearer thought to do something.
        //
        // The second sits off-axis with its moment turned well away from
        // the first, so with `dynamicsOn` (below) the pair visibly swings
        // into alignment over a few seconds as the wearer arrives. That is
        // the module's own `firstRunHint` — "Bring two close and watch —
        // they pull together head-to-tail" — happening without being asked
        // for, which is what the home screen's "every exhibit is a
        // perpetual live demo" means applied to a lab.
        //
        // Far enough apart to read as two objects and to take a moment
        // settling; the overdamped glide is what keeps that legible rather
        // than a snap.
        magnets = [
            BarMagnet(position: Self.regionCenter - SIMD3(0.34, 0, 0),
                      moment: SIMD3(Self.defaultStrength, 0, 0)),
            BarMagnet(position: Self.regionCenter + SIMD3(0.34, 0, 0.12),
                      moment: SIMD3(Self.defaultStrength * cos(1.05),
                                    Self.defaultStrength * sin(1.05), 0)),
        ]
        selectedID = magnets.last?.id
        heldIDs.removeAll()
        isPaused = false
        showFieldLines = true
        compassOn = true
        // A flag with no visible control can drift out of reset unnoticed;
        // restore it here. (`-magFrozen` reopens frozen — `init()` applies
        // it after this runs.)
        dynamicsOn = true
        earthFieldOn = true
        compassPosition = Self.regionCenter + SIMD3(0.0, -0.42, 0.55)
        clearCapsule()
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

// MARK: - Time Capsule

extension MagnetismModel: TimeCapsuleRecording {
    /// The magnets, their motion, and the compass position. `bodies` is
    /// in the snapshot to carry the inertial regime's velocities — a
    /// needle restored without them loses the overshoot-and-ring. Out:
    /// the bank's flags and the selection.
    struct CapsuleSnapshot: Equatable {
        var magnets: [BarMagnet]
        var bodies: [UUID: DipoleBody]
        var compassPosition: SIMD3<Double>
    }

    func captureCapsuleSnapshot() -> CapsuleSnapshot {
        CapsuleSnapshot(magnets: magnets, bodies: bodies,
                        compassPosition: compassPosition)
    }

    func restoreCapsuleSnapshot(_ snapshot: CapsuleSnapshot) {
        // A held magnet stays where the hand has it — nothing moves it,
        // including the past.
        var restored = snapshot.magnets
        for index in restored.indices where heldIDs.contains(restored[index].id) {
            if let live = magnets.first(where: { $0.id == restored[index].id }) {
                restored[index] = live
            }
        }
        for held in heldIDs where !restored.contains(where: { $0.id == held }) {
            if let live = magnets.first(where: { $0.id == held }) {
                restored.append(live)
            }
        }
        magnets = restored
        bodies = snapshot.bodies
        // A held magnet's stored motion is the hand's, not the recording's.
        for held in heldIDs { bodies[held] = DipoleBody() }
        compassPosition = snapshot.compassPosition
        if let selectedID, !magnets.contains(where: { $0.id == selectedID }) {
            self.selectedID = nil
        }
    }
}
