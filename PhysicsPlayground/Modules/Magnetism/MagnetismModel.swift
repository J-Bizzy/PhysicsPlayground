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
    /// The physics safety bounds — room-scale, not a wall a hand meets.
    /// Binds only the free simulation, so a flicked magnet settles in the
    /// room rather than sailing off.
    nonisolated static let safetyHalfExtents = SIMD3<Double>(2.6, 1.6, 2.6)
    nonisolated static let regionFloor = 0.35
    /// Visual length of a bar magnet (m); also the touching distance.
    nonisolated static let magnetLength = 0.16
    nonisolated static let magnetBudget = 4
    nonisolated static let strengthRange = 1.0...12.0
    /// The moments a magnet's track clicks into: every whole A·m².
    nonisolated static let strengthDetents = (1...12).map(Double.init)
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
    /// Every magnet a hand is currently holding — a set, because two
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

    /// Whether the room is standing on a planet. Compasses only: Earth's
    /// field is deliberately not applied to the bar magnets or the field
    /// lines, only to the compasses.
    var earthFieldOn = true

    /// Earth's field in the room, T — zero when switched off.
    var earthField: SIMD3<Double> {
        earthFieldOn ? GeomagneticField.vector() : .zero
    }

    /// What a compass feels anywhere in the room: every magnet, plus the
    /// planet. Distinct from the field the magnets feel from each other.
    func compassField(at point: SIMD3<Double>) -> SIMD3<Double> {
        MagneticField.vector(at: point, dueTo: magnets) + earthField
    }

    /// The field where the hand compass is — what its needle points along.
    var compassField: SIMD3<Double> { compassField(at: compassPosition) }

    /// |B| at the compass in microtesla, for its dial label.
    var compassMicroTesla: Double { simd_length(compassField) * 1e6 }

    var selectedMagnet: BarMagnet? {
        guard let selectedID else { return nil }
        return magnets.first { $0.id == selectedID }
    }

    // MARK: Pickup coils — Faraday's law, lit

    /// A coil with a bicolour LED across it. Push a magnet through and the
    /// LED lights: red one way, green the other.
    nonisolated struct Coil: Identifiable, Equatable {
        let id: UUID
        var position: SIMD3<Double>
        /// Unit vector along the bore.
        var axis: SIMD3<Double>
        var turns: Int
        /// Flux linkage at the last step, Wb·turns: what the next EMF is a
        /// difference from.
        var linkage: Double
        /// ε = −dΛ/dt, V.
        var emf: Double = 0
        /// Through the LED pair, A; positive lights red.
        var current: Double = 0
    }

    private(set) var coils: [Coil] = []
    /// The winding `Tools/pickupcoil.py` mills: copper from `windingInner`
    /// to `windingOuter`, `coilLength` long, and its mean radius.
    nonisolated static let windingInner = 0.051
    nonisolated static let windingOuter = 0.062
    nonisolated static let coilRadius = 0.0565
    nonisolated static let coilLength = 0.080
    /// The share of the winding's cross-section that is copper: round
    /// enamelled wire wound in layers leaves the rest to enamel and gaps.
    nonisolated static let copperFill = 0.55
    /// The bore a magnet passes through, and the flanges' radius.
    nonisolated static let coilBoreRadius = 0.048
    nonisolated static let coilFlangeRadius = 0.072
    nonisolated static let coilBudget = 2
    /// Every option fills the same bobbin, so fewer turns are thicker wire:
    /// the EMF goes as N and the resistance as N², and only the finest
    /// winding clears the LED's 1.6 V at a hand's pace.
    nonisolated static let turnOptions = [2500, 5000, 10_000]
    nonisolated static let defaultTurns = 10_000

    /// The wire a winding of `turns` is wound with: the gauge that fills the
    /// drawn winding — 0.25 mm for 10 000 turns, 0.50 mm for 2500.
    nonisolated static func wireDiameter(turns: Int) -> Double {
        let copper = copperFill * (windingOuter - windingInner) * coilLength
            / Double(max(turns, 1))
        return (4 * copper / .pi).squareRoot()
    }

    var selectedCoil: Coil? {
        guard let selectedID else { return nil }
        return coils.first { $0.id == selectedID }
    }

    /// The coil as PhysicsCore sees it.
    nonisolated static func pickupCoil(_ coil: Coil) -> PickupCoil {
        PickupCoil(center: coil.position, axis: coil.axis, radius: coilRadius,
                   length: coilLength, turns: coil.turns,
                   wireDiameter: wireDiameter(turns: coil.turns))
    }

    @discardableResult
    func addCoil(at position: SIMD3<Double>) -> UUID? {
        guard coils.count < Self.coilBudget else { return nil }
        var coil = Coil(id: UUID(), position: floored(position), axis: SIMD3(1, 0, 0),
                        turns: Self.defaultTurns, linkage: 0)
        coil.linkage = Self.pickupCoil(coil).linkage(magnets: magnets)
        coils.append(coil)
        selectedID = coil.id
        return coil.id
    }

    func moveCoil(id: UUID, to point: SIMD3<Double>) {
        guard let index = coils.firstIndex(where: { $0.id == id }) else { return }
        coils[index].position = floored(point)
    }

    func removeCoil(id: UUID) {
        coils.removeAll { $0.id == id }
        heldIDs.remove(id)
        if selectedID == id { selectedID = magnets.last?.id }
    }

    /// 2500 → 5000 → 10 000 turns, and round again. The linkage is measured
    /// afresh, so changing the winding is not itself a jolt of EMF.
    func cycleTurns(id: UUID) {
        guard let index = coils.firstIndex(where: { $0.id == id }) else { return }
        let options = Self.turnOptions
        let next = options.first { $0 > coils[index].turns } ?? options[0]
        coils[index].turns = next
        coils[index].linkage = Self.pickupCoil(coils[index]).linkage(magnets: magnets)
    }

    /// A quarter turn about the vertical: the bore that ran left to right
    /// now runs toward you. A real coil turned by hand this fast would
    /// flash, so the linkage is re-measured rather than differenced.
    func turnCoil(id: UUID) {
        guard let index = coils.firstIndex(where: { $0.id == id }) else { return }
        let a = coils[index].axis
        coils[index].axis = simd_normalize(SIMD3(-a.z, a.y, a.x))
        coils[index].linkage = Self.pickupCoil(coils[index]).linkage(magnets: magnets)
    }

    // MARK: The bore is a sleeve

    /// Half the magnet's widest section, corner to corner: its chrome band,
    /// 5.6 cm square with 4 mm corners.
    nonisolated static let magnetHalfDiagonal = 0.038
    /// How far off the axis a magnet inside the bore can sit: a centimetre.
    nonisolated static var boreClearance: Double { coilBoreRadius - magnetHalfDiagonal }
    /// How fast the bore turns a carried magnet into line at full weight,
    /// rad/s: a quarter turn in about a sixth of a second.
    private static let boreAlignRate = 10.0

    /// Where a carried magnet stands for where the hand carries it. A bar
    /// can only be inside a coil lying along the bore, a centimetre off its
    /// axis at most; so over the coil's length, fading through the half
    /// magnet past each end, the bore draws it in toward the axis, and off
    /// the bore it goes where the hand does. Continuous everywhere and
    /// monotonic across the axis, so a hand drawn sideways out of the mouth
    /// never makes the magnet jump.
    nonisolated static func sleeved(_ point: SIMD3<Double>, through coil: Coil) -> SIMD3<Double> {
        let offset = point - coil.position
        let along = simd_dot(offset, coil.axis)
        let across = offset - along * coil.axis
        let r = simd_length(across)
        let weight = (1 - smoothstep(coilLength / 2, coilLength / 2 + magnetLength / 2, abs(along)))
            * borePull(r)
        guard r > 1e-9, weight > 0 else { return point }
        let held = boreClearance * tanh(r / boreClearance)
        let radius = r - (r - held) * weight
        return coil.position + along * coil.axis + across * (radius / r)
    }

    /// How strongly a carried magnet's aim is turned toward a coil's bore,
    /// 0…1: full from the moment its leading end reaches either mouth, fading
    /// out a magnet's length beyond; full within the bore's radius of the
    /// axis, gone a little past the flanges, so a magnet held beside the
    /// coil keeps its aim.
    nonisolated static func boreAim(of point: SIMD3<Double>, toward coil: Coil) -> Double {
        let offset = point - coil.position
        let along = simd_dot(offset, coil.axis)
        let r = simd_length(offset - along * coil.axis)
        let mouth = coilLength / 2 + magnetLength / 2
        return (1 - smoothstep(mouth, mouth + magnetLength, abs(along))) * borePull(r)
    }

    /// Full inside the bore's radius of the axis, nothing 2 cm past the flanges.
    private nonisolated static func borePull(_ r: Double) -> Double {
        1 - smoothstep(coilBoreRadius, coilFlangeRadius + 0.02, r)
    }

    private nonisolated static func smoothstep(_ low: Double, _ high: Double, _ x: Double) -> Double {
        let t = min(max((x - low) / (high - low), 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// A carried bar nearing a coil's mouth turns to lie along the bore,
    /// keeping whichever pole already led: it could not go in otherwise, and
    /// a hand that cannot turn what it holds needs the bore to do it. The
    /// turn is real motion of the magnet, so it induces like any other.
    private func alignHeldMagnetsWithBores(dt: Double) {
        guard !coils.isEmpty, !heldIDs.isEmpty else { return }
        for index in magnets.indices where heldIDs.contains(magnets[index].id) {
            for coil in coils {
                let weight = Self.boreAim(of: magnets[index].position, toward: coil)
                let moment = magnets[index].moment
                let strength = simd_length(moment)
                guard weight > 0, strength > 1e-12 else { continue }
                let aim = moment / strength
                let target = simd_dot(aim, coil.axis) < 0 ? -coil.axis : coil.axis
                let remaining = acos(min(max(simd_dot(aim, target), -1), 1))
                let pivot = simd_cross(aim, target)
                guard remaining > Self.restAngle, simd_length(pivot) > 1e-12 else { continue }
                let turn = min(remaining, Self.boreAlignRate * weight * dt)
                magnets[index].moment = simd_quatd(angle: turn, axis: simd_normalize(pivot))
                    .act(moment)
            }
        }
    }

    /// Faraday's law for every coil, once the magnets have moved this step:
    /// ε = −ΔΛ/Δt over the frame, and the current that EMF drives through
    /// the winding's resistance and the LED pair. The coil's own inductance
    /// is millihenries against hundreds of ohms — microseconds — so the
    /// current is the EMF's within the frame.
    private func stepCoils(dt: Double) {
        guard !coils.isEmpty, dt > 1e-6 else { return }
        for index in coils.indices {
            let coil = Self.pickupCoil(coils[index])
            let now = coil.linkage(magnets: magnets)
            let emf = -(now - coils[index].linkage) / dt
            coils[index].linkage = now
            coils[index].emf = emf
            coils[index].current = BicolourLED.current(emf: emf, resistance: coil.resistance)
            // The first time this session an LED plainly lights.
            if abs(coils[index].current) >= Self.firstLightCurrent, Remark.claim(.firstLight) {
                emitSound(.gleam, at: coils[index].position, volume: Remark.volume)
            }
        }
    }

    /// A tenth of the LED's rated 10 mA: plainly lit, not a flicker.
    nonisolated static let firstLightCurrent = 0.001

    // MARK: Sound events (the renderer plays them spatially)

    private(set) var soundEvent: SpatialSoundEvent?
    @ObservationIgnored private var soundCounter = 0

    private func emitSound(_ kind: SoundPalette.Sound, at position: SIMD3<Double>, volume: Double) {
        soundCounter += 1
        soundEvent = SpatialSoundEvent(id: soundCounter, kind: kind,
                                       position: position, volume: volume)
    }

    // MARK: Clock — the overdamped magnetic dynamics

    /// Whether the magnets translate and turn under their mutual forces.
    /// Off, every magnet holds exactly where you park it.
    var dynamicsOn = true

    // MARK: Inertia — the alternative bench, behind a launch argument

    /// Whether the magnets have mass and rotational inertia. Off by default
    /// (the glide), on with `-magInertia 1`; both ship. DEBUG-only, and the
    /// mode carries a known defect (a touching pair never settles).
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
        // After the magnets have moved (defers run last-declared first), and
        // before the frame is recorded — and whether or not they move freely:
        // a magnet carried by hand induces just the same.
        defer { stepCoils(dt: dt) }
        alignHeldMagnetsWithBores(dt: min(dt, 1.0 / 30.0))
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

                // Still the point dipole, measured 50% low at contact — but the
                // pole-pair remedy is worse: pathological at and inside contact.
                // `testTheBarForceIsUnusableWhereThePolesMeet` pins it; do not "fix"
                // without reading.
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

    /// Takes the approaching component out of two touching magnets'
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
            // Never past it: clamp the step to the angle remaining so an
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

    /// Takes the inward component out of a magnet's glide as it closes on
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

    /// The free simulation's safety bound — never applied to a hand.
    /// Room-scale, so it only ever fires on a magnet that has drifted
    /// or been flicked far across the room.
    private func clamp(_ p: SIMD3<Double>) -> SIMD3<Double> {
        var c = simd_clamp(p,
                           Self.regionCenter - Self.safetyHalfExtents,
                           Self.regionCenter + Self.safetyHalfExtents)
        c.y = max(c.y, Self.regionFloor)
        return c
    }

    /// A hand meets no walls, only the floor.
    private func floored(_ p: SIMD3<Double>) -> SIMD3<Double> {
        var c = p
        c.y = max(c.y, Self.regionFloor)
        return c
    }

    // MARK: Manipulation

    func grab(id: UUID) {
        guard magnets.contains(where: { $0.id == id })
                || coils.contains(where: { $0.id == id }) else { return }
        heldIDs.insert(id)
        selectedID = id
    }

    func move(id: UUID, to point: SIMD3<Double>) {
        guard let index = magnets.firstIndex(where: { $0.id == id }) else { return }
        // Through a coil's bore, the bore guides it (`sleeved`).
        let guided = coils.reduce(floored(point)) { Self.sleeved($0, through: $1) }
        magnets[index].position = floored(guided)
    }

    /// One hand lets go; whatever the other hand holds stays held.
    func release(id: UUID) { heldIDs.remove(id) }

    /// Everything lets go — reset, and the legacy single-drag path.
    func release() { heldIDs.removeAll() }

    func select(id: UUID) {
        guard magnets.contains(where: { $0.id == id })
                || coils.contains(where: { $0.id == id }) else { return }
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

    #if DEBUG
    /// Turns a magnet to point along `axis` at its strength — the staged
    /// coil pass's, which the simulator has no hand to make.
    func setStrength(id: UUID, _ value: Double, along axis: SIMD3<Double>) {
        guard let index = magnets.firstIndex(where: { $0.id == id }) else { return }
        magnets[index].moment = simd_normalize(axis) * value
    }
    #endif

    // MARK: Field readout for the Physics box

    /// |B| in millitesla at the region centre — a live sense of the field.
    var centerFieldMilliTesla: Double {
        MagneticField.magnitude(at: Self.regionCenter, dueTo: magnets) * 1000
    }

    // MARK: Reset

    /// What `-magInertia` asked for at launch — `reset()` returns to this
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
        // Two magnets, and the second is the module: one magnet has nothing to
        // attract, so the lab opened as a diagram of itself. The second sits
        // off-axis with its moment turned away, so the pair visibly swings into
        // alignment as the wearer arrives.
        magnets = [
            BarMagnet(position: Self.regionCenter - SIMD3(0.34, 0, 0),
                      moment: SIMD3(Self.defaultStrength, 0, 0)),
            BarMagnet(position: Self.regionCenter + SIMD3(0.34, 0, 0.12),
                      moment: SIMD3(Self.defaultStrength * cos(1.05),
                                    Self.defaultStrength * sin(1.05), 0)),
        ]
        selectedID = magnets.last?.id
        // No coil in the opening room: one comes out of the well when wanted.
        coils = []
        heldIDs.removeAll()
        isPaused = false
        showFieldLines = true
        compassOn = true
        // A flag with no visible control drifts out of reset unnoticed;
        // `-magFrozen` reopens frozen after this runs.
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
    nonisolated struct CapsuleSnapshot: Equatable {
        var magnets: [BarMagnet]
        var bodies: [UUID: DipoleBody]
        var compassPosition: SIMD3<Double>
        /// The coils, with the linkage the next EMF differences from: a
        /// restore without it would flash every LED.
        var coils: [Coil]
    }

    func captureCapsuleSnapshot() -> CapsuleSnapshot {
        CapsuleSnapshot(magnets: magnets, bodies: bodies,
                        compassPosition: compassPosition, coils: coils)
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
        var restoredCoils = snapshot.coils
        for index in restoredCoils.indices where heldIDs.contains(restoredCoils[index].id) {
            if let live = coils.first(where: { $0.id == restoredCoils[index].id }) {
                restoredCoils[index] = live
            }
        }
        coils = restoredCoils
        if let selectedID, !magnets.contains(where: { $0.id == selectedID }),
           !coils.contains(where: { $0.id == selectedID }) {
            self.selectedID = nil
        }
    }
}
