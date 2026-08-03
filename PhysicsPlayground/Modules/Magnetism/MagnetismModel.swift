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
    /// tracing radius and the compass grid's span.
    nonisolated static let regionHalfExtent = 0.72
    /// Per-axis bounds for the CLAMP. Height matches the old cube, but
    /// depth stops 15 cm in FRONT of the user instead of 15 cm behind
    /// their head: the cube ran to z = +0.15, so a free cluster that
    /// glided forward ended up floating at the user's ear, looming over
    /// the control pods at enormous parallax. Magnets wander — that is
    /// the module working — but they wander in the room, not in your
    /// face.
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
    /// Rotation below this in one step is not motion, it is noise.
    private static let restAngle = 2.0e-5   // rad
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

    // MARK: Earth's own field

    /// Whether the room is standing on a planet.
    ///
    /// COMPASSES ONLY. Earth's field really does pull on the bar magnets
    /// too — that is how a compass needle works, and a lone bar magnet
    /// left alone on a bench really does creep round to north. It is
    /// deliberately not applied to them here (owner's call, 2026-08-01):
    /// at these strengths it is strong enough to matter, and a sandbox
    /// where every magnet you park slowly swings north is a different
    /// toy from the one this module is. The compasses get the whole
    /// truth; the magnets get each other.
    ///
    /// The FIELD LINES are left alone for the same reason and a stronger
    /// one: adding a uniform background to a dipole does not decorate the
    /// picture, it changes its topology — the closed loops open out and
    /// run off to infinity, with a pair of neutral points where the two
    /// fields cancel. That is real and it is beautiful, but it is a
    /// different demonstration and nobody asked for it.
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
    /// — i.e. it has been carried clear of the magnets and is reading
    /// the planet. The readout says which, because "48.3 µT" means two
    /// completely different things on either side of that line.
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
    /// On (the default), the bench is alive: bring two magnets near and
    /// they attract, repel, and swing into alignment. Off, every magnet
    /// holds exactly where you park it — a frozen arrangement whose
    /// field you can study, mirroring the electric bench's stationary
    /// charges.
    var dynamicsOn = true

    // MARK: Inertia — the alternative bench, behind a launch argument

    /// Whether the magnets have MASS AND ROTATIONAL INERTIA.
    ///
    /// Off by default (the glide below), on with `-magInertia 1`, and
    /// the two exist side by side on purpose: this reverses a decision
    /// this file's own header records ("the magnets settle into
    /// equilibrium instead of oscillating"), and a reversal made on
    /// feel has to be judged on feel, in a headset, against the thing
    /// it replaces. See DECISIONS.md.
    ///
    /// What changes: with inertia a needle released at an angle swings
    /// PAST alignment and rings back, which is the single most
    /// recognisable thing a magnetism bench can show and which nothing
    /// without inertia can do. What does not change: the fields, forces
    /// and torques, which were always exact.
    ///
    /// DEBUG-only, like every other launch-argument read in the app: a
    /// release build has no way to set the flag, and the mode carries a
    /// known defect (a touching pair never settles — DECISIONS.md
    /// 2026-08-03), so the glide is the only bench a wearer can reach.
    #if DEBUG
    var inertiaOn = UserDefaults.standard.bool(forKey: "magInertia")
    #else
    var inertiaOn = false
    #endif

    /// Per-magnet velocity and angular velocity. Empty while the glide
    /// is driving, so switching modes starts from rest rather than
    /// inheriting a mobility "velocity" that was never one.
    private var bodies: [UUID: DipoleBody] = [:]

    /// Linear drag, 1/s. The one tunable number in the inertial path.
    /// Air alone would take minutes to still a needle; a lab pivots it
    /// in oil so a demonstration settles in a few swings.
    private static let inertialDamping = 0.9

    func step(dt: Double) {
        guard !isPaused else { return }
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
        // Substepped: the torque on a magnet close to another is large,
        // and a frame-length step through it would resolve a swing into
        // a staircase. Four substeps at 90 Hz is 360 Hz of physics,
        // which is comfortably inside the stiffest period the bench can
        // produce.
        let substeps = 4
        let h = min(dt, 1.0 / 60.0) / Double(substeps)
        for _ in 0..<substeps {
            var next = magnets
            for i in magnets.indices {
                let id = magnets[i].id
                guard id != heldID else {
                    // A held magnet is the hand's, not the physics'. Its
                    // stored motion is cleared so releasing it does not
                    // hand back a velocity from before the grab.
                    bodies[id] = DipoleBody()
                    continue
                }
                let others = magnets.enumerated().filter { $0.offset != i }.map(\.element)
                guard !others.isEmpty else { continue }

                let force = MagneticField.netForce(on: magnets[i], from: others)
                let field = MagneticField.vector(at: magnets[i].position, dueTo: others)
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

                // The station's walls are inelastic: a magnet that
                // reaches one stops rather than bouncing off a boundary
                // that is a display limit and not a physical object.
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
    /// velocities — an inelastic contact.
    ///
    /// Without this the inertial bench reproduces, exactly, the standoff
    /// that `softenedAtContact` was written to fix for the glide. The
    /// dipole force at contact is enormous, so a pair that has come
    /// together keeps accelerating INTO each other; `separated` then
    /// hard-projects them apart every substep while the bodies retain
    /// the inward velocity that put them there. The pair sits buzzing at
    /// the frame rate, apparently at rest and visibly vibrating.
    ///
    /// Real magnets snapping together lose that energy to the click, so
    /// this is the honest model and not a damping fudge: only the
    /// component along the line of centres is removed, and only when
    /// they are actually closing. Sliding across each other is untouched.
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
        for i in magnets.indices where magnets[i].id != heldID {
            let others = magnets.enumerated().filter { $0.offset != i }.map(\.element)
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
            // Turn the moment toward the local field (τ = m × B), and
            // NEVER PAST IT.
            //
            // This is where the residual jitter lived. `softenedAtContact`
            // below fixed the translational half of the same standoff and
            // the rotational half was left alone, so a pair that had come
            // together and stopped moving went on twitching: the torque at
            // contact is enormous, `torqueGain` saturates it at
            // `maxAngularSpeed`, and a fixed 3 rad/s step overshoots
            // alignment every frame. Past alignment the torque reverses,
            // the next step overshoots back, and the pair sits in a
            // rotational limit cycle locked to the frame rate — visibly
            // buzzing while apparently at rest.
            //
            // The fix is the honest one rather than a damping fudge: the
            // rotation carries m onto B, so the most it can ever need is
            // the angle between them. Clamp the step to that and an
            // aligned pair lands exactly on alignment and stops dead,
            // which is what real magnets do.
            let field = MagneticField.vector(at: magnets[i].position, dueTo: others)
            let torque = simd_cross(magnets[i].moment, field)
            let tMag = simd_length(torque)
            let fieldMag = simd_length(field)
            let momentMag = simd_length(magnets[i].moment)
            if tMag > 1e-22, fieldMag > 1e-18, momentMag > 1e-18 {
                let rate = min(Self.torqueGain * tMag, Self.maxAngularSpeed)
                let cosine = simd_dot(magnets[i].moment / momentMag, field / fieldMag)
                let remaining = acos(min(max(cosine, -1), 1))
                let stepAngle = min(rate * h, remaining)
                // Below this the pair is aligned to well under a pixel of
                // rotation, and stepping anyway is how numerical noise
                // becomes visible movement.
                if stepAngle > Self.restAngle {
                    let q = simd_quatd(angle: stepAngle, axis: torque / tMag)
                    next[i].moment = q.act(magnets[i].moment)
                }
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

    // `removeSelected()` was deleted here on 2026-08-03. A GRAVE, not a
    // missing door: it was the window panel's delete button, and the
    // panel was deleted on 2026-08-01. Removing a magnet is the trash
    // petal on its own ring now (`MagnetismSpaceView.syncBloom` →
    // `removeMagnet(id:)`), which is better in the way the interaction
    // law says — you delete the thing you are holding, not "the
    // selection" named somewhere else. It had no caller anywhere,
    // including tests.

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

    // MARK: Field readout for the notebook
    //
    // This said "for the numbers card", which was the window panel's,
    // and `centerFieldMilliTesla`'s only reader has been the lab
    // notebook since that panel was deleted. The compass's own µT
    // Callout is what the room shows.

    /// |B| in millitesla at the region centre — a live sense of the field.
    var centerFieldMilliTesla: Double {
        MagneticField.magnitude(at: Self.regionCenter, dueTo: magnets) * 1000
    }

    // MARK: Reset

    /// What `-magInertia` asked for at launch. `reset()` returns to THIS
    /// rather than to `false`: the argument is how the alternative bench
    /// is staged for a screenshot, and a Reset that silently dropped
    /// back to the glide would photograph the wrong one.
    #if DEBUG
    private let inertiaAtLaunch = UserDefaults.standard.bool(forKey: "magInertia")
    #else
    private let inertiaAtLaunch = false
    #endif

    func reset() {
        // Covered by `ResetCoverageTests`, which enumerates every Bool on
        // this model — so adding `inertiaOn` above obliged this line
        // rather than relying on anybody remembering it. That is the
        // whole point of that test.
        inertiaOn = inertiaAtLaunch
        bodies.removeAll()
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
        // The fourth state the switch bank shows, and reset restored the
        // other three while silently skipping this one — so freezing the
        // magnets and pressing Reset left them frozen under a dark plate
        // claiming they were free. The identical omission was found in
        // Pendulums' `frictionOn` the same day: a flag with no visible
        // control can drift out of reset unnoticed for months, and the
        // moment it gets a lamp the lamp starts telling the truth about
        // it. (`-magFrozen` still opens frozen — `init()` applies it
        // after this runs.)
        dynamicsOn = true
        earthFieldOn = true
        compassPosition = Self.regionCenter + SIMD3(0.0, -0.42, 0.55)
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
