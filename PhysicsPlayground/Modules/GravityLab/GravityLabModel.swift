//
//  GravityLabModel.swift
//  App state for the orbital mechanics lab. Simulation runs in real SI units;
//  only the renderer maps sim into the room, so every number checks against an almanac.
//

import Foundation
import Observation
import PhysicsCore
import QuartzCore
import simd

@MainActor
@Observable
final class GravityLabModel {
    // MARK: Scale mappings (the only two numbers between sim and room)

    /// Room meters per astronomical unit.
    nonisolated static let metersPerAU = 0.5
    /// Simulated days per real second at 1× speed.
    nonisolated static let daysPerSecond = 3.0
    /// Sim m/s per display m/s when throwing: a relaxed ~0.35 m/s toss ≈ orbital speed (~30 km/s).
    nonisolated static let throwVelocityScale = 8.6e4

    /// Sim meters per display meter.
    let displayToSim = CelestialBody.astronomicalUnit / metersPerAU
    var simToDisplay: Double { 1 / displayToSim }

    // MARK: Budgets & integration limits

    /// `reset()` alone seeds ten bodies; the budget must leave room to build a system.
    nonisolated static let bodyBudget = 16
    /// Verlet substep never exceeds 6 simulated hours.
    nonisolated static let maxSubstep = 6.0 * 3600
    nonisolated static let maxSubstepsPerFrame = 96
    /// The clock, including reverse: velocity Verlet is time-symmetric, so a negative step runs the physics backwards (merges are the one irreversible exception).
    nonisolated static let timeScales: [Double] = [-20, -1, 1, 5, 20, 100]

    enum TrailLength: String, CaseIterable, Identifiable {
        case short, medium, long
        var id: String { rawValue }
        var points: Int {
            switch self {
            case .short: 60
            case .medium: 240
            case .long: 720
            }
        }
    }

    // MARK: Bodies

    struct OrbitingBody: Identifiable, Equatable {
        let id: UUID
        var body: CelestialBody
        /// Rendered sphere radius in room meters — exaggerated and labeled as such.
        var displayRadius: Double
        var trail: [SIMD3<Double>] = []
        var lastTrailPosition: SIMD3<Double>?
    }

    // MARK: Predict, then run — the ghost marker

    /// Predict-then-run: place a ghost where you think the body will be one sweep window from now.
    struct Prediction: Equatable {
        var bodyID: UUID
        /// The guess, sim metres. The user drags this.
        var position: SIMD3<Double>
        /// When the guess was placed and when it resolves, sim days.
        var placedAt: Double
        var resolvesAt: Double
    }

    struct PredictionVerdict: Equatable {
        let bodyPosition: SIMD3<Double>
        let guess: SIMD3<Double>
        let missAU: Double
        /// Display until (wall-ish sim time); the renderer fades it out.
        let shownAt: Double
    }

    private(set) var prediction: Prediction?
    private(set) var predictionVerdict: PredictionVerdict?

    /// Arms a prediction on the selected body: the ghost appears AT the body, one sweep window out.
    func armPrediction() {
        guard let selected = selectedBody, selected.id != primaryBody?.id else { return }
        prediction = Prediction(
            bodyID: selected.id,
            position: selected.body.position,
            placedAt: simulatedDays,
            resolvesAt: simulatedDays + sweepWindowDays)
        predictionVerdict = nil
    }

    func movePrediction(to simPoint: SIMD3<Double>) {
        prediction?.position = simPoint
    }

    private func resolvePredictionIfDue() {
        guard let prediction, simulatedDays >= prediction.resolvesAt else { return }
        guard let body = bodies.first(where: { $0.id == prediction.bodyID }) else {
            self.prediction = nil
            return
        }
        let miss = simd_distance(body.body.position, prediction.position)
            / CelestialBody.astronomicalUnit
        predictionVerdict = PredictionVerdict(
            bodyPosition: body.body.position,
            guess: prediction.position,
            missAU: miss,
            shownAt: simulatedDays)
        self.prediction = nil
        emitSound(miss < 0.1 ? .chime : .pop,
                  at: body.body.position, volume: 0.8)
    }

    // MARK: Kepler sweep — the second law, recorded live

    /// Paints the swept sector: equal windows, equal areas, wildly different shapes.
    var keplerSweepOn = true

    @ObservationIgnored private var sweep = KeplerSweep(horizon: 60 * 86_400)
    @ObservationIgnored private var sweepWindowStart: Double?
    @ObservationIgnored private var sweepBodyID: UUID?
    /// The last COMPLETED window's sector (relative to the primary, sim metres) and its area.
    private(set) var sweepHeldArc: [SIMD3<Double>] = []
    private(set) var sweepHeldArea = 0.0
    /// One sweep window, days: a twelfth of the selected orbit.
    private(set) var sweepWindowDays = 30.0

    /// The accruing sector, computed on demand at the renderer's cadence.
    func sweepCurrentGeometry() -> (arc: [SIMD3<Double>], area: Double)? {
        guard keplerSweepOn, let start = sweepWindowStart,
              let last = sweep.samples.last, last.time > start else { return nil }
        return (sweep.arc(from: start, to: last.time),
                sweep.area(from: start, to: last.time))
    }

    private func recordSweep() {
        guard keplerSweepOn,
              let primary = primaryBody,
              let selected = selectedBody,
              selected.id != primary.id else {
            if sweepBodyID != nil {
                sweep.reset(); sweepBodyID = nil
                sweepWindowStart = nil; sweepHeldArc = []
            }
            return
        }
        if sweepBodyID != selected.id {
            sweep.reset()
            sweepBodyID = selected.id
            sweepWindowStart = nil
            sweepHeldArc = []
        }
        let window = readout(for: selected)?.periodDays
            .map { min(max($0 / 12, 2), 500) } ?? 30
        sweepWindowDays = window
        sweep.horizon = window * 86_400 * 2.2

        let now = simulatedDays * 86_400
        sweep.record(time: now, position: selected.body.position - primary.body.position)
        guard let start = sweepWindowStart else {
            sweepWindowStart = now
            return
        }
        if now - start >= window * 86_400 {
            // Freeze the finished sector; the next begins where it ended.
            sweepHeldArc = sweep.arc(from: start, to: now)
            sweepHeldArea = sweep.area(from: start, to: now)
            sweepWindowStart = now
        }
    }

    private(set) var bodies: [OrbitingBody] = [] {
        // Any change retires every cached readout — a new mutation path cannot forget to invalidate.
        didSet { readoutGeneration &+= 1 }
    }
    private(set) var selectedID: UUID?

    var selectedBody: OrbitingBody? {
        guard let selectedID else { return nil }
        return bodies.first { $0.id == selectedID }
    }

    /// The dominant attractor (for escape speed, periods, the sun light).
    var primaryBody: OrbitingBody? {
        bodies.max { $0.body.mass < $1.body.mass }
    }

    // MARK: Environment controls

    /// Multiplies the Sun preset's real mass, live (the programmatic path; the mass bead is the user's way).
    var sunMassMultiplier = 1.0 {
        didSet { applySunMass() }
    }
    /// Multiplies Newton's G, live — the "what if gravity were stronger" knob.
    var gMultiplier = 1.0
    var effectiveG: Double { NBody.gravitationalConstant * gMultiplier }

    var timeScale = 1.0
    var isPaused = false
    var trailLength: TrailLength = .medium

    var showVelocityVector = true
    var showAccelerationVector = false
    var showForceVector = true
    /// Drifting particles that trace the local field direction.
    var showFieldParticles = false
    /// The rubber-sheet picture — conceptual, and labeled as such.
    var showSpacetimeGrid = false
    /// Kepler's third law as a chord: every bound body's pitch is set by its period.
    var playOrbitalChord = true

    /// The scene's natural length — 1 AU; visualizations normalize against it.
    var characteristicLength: Double { CelestialBody.astronomicalUnit }

    /// Total simulated time, in days (shown on the time panel).
    private(set) var simulatedDays = 0.0

    // MARK: Time Capsule

    @ObservationIgnored var capsule = TimeCapsule<CapsuleSnapshot>()
    @ObservationIgnored var capsuleClock = 0.0
    var scrubTime: Double?
    var scrubNonce = 0

    // MARK: Merge flash (renderer reads position when nonce changes)

    private(set) var mergeNonce = 0
    private(set) var lastMergePosition = SIMD3<Double>.zero

    // MARK: Sounds (data only; the renderer positions and plays them)

    private(set) var soundEvent: SpatialSoundEvent?
    private var soundCounter = 0

    private func emitSound(_ kind: SoundPalette.Sound, at position: SIMD3<Double>, volume: Double) {
        soundCounter += 1
        soundEvent = SpatialSoundEvent(id: soundCounter, kind: kind,
                                       position: position, volume: volume)
    }

    // MARK: Hold / throw

    private var heldID: UUID?
    /// `PhysicsCore.ThrowSampler` — shared with Projectiles and Pendulums.
    private var throwSampler = ThrowSampler()

    init() {
        reset()
    }

    // MARK: Spawning

    enum Preset: String, CaseIterable, Identifiable {
        case mercury, venus, earth, mars, jupiter, saturn, uranus, neptune, moon, asteroid
        var id: String { rawValue }
        var displayName: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
    }

    func spawn(_ preset: Preset) {
        guard bodies.count < Self.bodyBudget else { return }
        let sun = primaryBody?.body ?? .sun
        let au = CelestialBody.astronomicalUnit

        switch preset {
        case .moon:
            // Real lunar distance would be sub-millimeter here; spawns at 0.06 AU —
            // distance exaggerated, masses and speeds real.
            if let earth = bodies.first(where: { $0.body.name == "Earth" })?.body {
                append(CelestialBody.moon.onCircularOrbit(
                    of: earth, distance: 0.06 * au, gravitationalConstant: effectiveG),
                    displayRadius: 0.008)
            } else {
                append(CelestialBody.moon.onCircularOrbit(
                    of: sun, distance: au, gravitationalConstant: effectiveG),
                    displayRadius: 0.008)
            }
        default:
            let template: CelestialBody = switch preset {
            case .mercury: .mercury
            case .venus: .venus
            case .earth: .earth
            case .mars: .mars
            case .jupiter: .jupiter
            case .saturn: .saturn
            case .uranus: .uranus
            case .neptune: .neptune
            case .asteroid: .asteroid
            case .moon: .moon
            }
            let distance = (CelestialBody.meanOrbitAU(of: template.name) ?? 1) * au
            append(template.onCircularOrbit(
                of: sun, distance: distance, gravitationalConstant: effectiveG),
                displayRadius: Self.displayRadius(for: template))
        }
    }

    private func append(_ body: CelestialBody, displayRadius: Double) {
        let orbiting = OrbitingBody(id: UUID(), body: body, displayRadius: displayRadius)
        bodies.append(orbiting)
        selectedID = orbiting.id
    }

    /// Exaggerated display sizes — the disclosed cheat that keeps the system readable.
    /// The ordering (giants dwarf rockies, the Sun dwarfs everything) is preserved exactly.
    private static func displayRadius(for body: CelestialBody) -> Double {
        switch body.name {
        case "Sun": 0.135
        case "Jupiter": 0.078
        case "Saturn": 0.066
        case "Uranus", "Neptune": 0.046
        case "Earth", "Venus": 0.036
        case "Mars": 0.028
        case "Mercury": 0.023
        case "Moon": 0.016
        case "Comet": 0.013
        default: 0.014
        }
    }

    // MARK: Per-body edits — what the Bloom calls

    /// Mass in Earth masses; the drawn radius tracks the cube root of mass.
    nonisolated static let earthMass = 5.972e24
    nonisolated static let massRangeEarths = 0.02...400.0

    // MARK: The star's own mass
    // Its own range and UNIT: the Sun is 333,000 Earth masses, so it is set in solar masses.
    nonisolated static let primaryMassRangeSuns = 0.2...4.0

    func massInSuns(id: UUID) -> Double {
        guard let body = bodies.first(where: { $0.id == id }) else { return 1 }
        return body.body.mass / CelestialBody.sun.mass
    }

    func setMass(id: UUID, suns: Double) {
        guard let index = bodies.firstIndex(where: { $0.id == id }) else { return }
        let clamped = min(max(suns, Self.primaryMassRangeSuns.lowerBound),
                          Self.primaryMassRangeSuns.upperBound)
        let old = bodies[index].body.mass
        bodies[index].body.mass = clamped * CelestialBody.sun.mass
        if old > 0 {
            bodies[index].displayRadius *= pow(bodies[index].body.mass / old, 1.0 / 3.0)
        }
    }

    func massInEarths(id: UUID) -> Double {
        guard let body = bodies.first(where: { $0.id == id }) else { return 1 }
        return body.body.mass / Self.earthMass
    }

    func setMass(id: UUID, earths: Double) {
        guard let index = bodies.firstIndex(where: { $0.id == id }) else { return }
        let clamped = min(max(earths, Self.massRangeEarths.lowerBound),
                          Self.massRangeEarths.upperBound)
        let old = bodies[index].body.mass
        bodies[index].body.mass = clamped * Self.earthMass
        // r ∝ m^(1/3)
        if old > 0 {
            bodies[index].displayRadius *= pow(bodies[index].body.mass / old, 1.0 / 3.0)
            bodies[index].displayRadius = min(max(bodies[index].displayRadius, 0.008), 0.22)
        }
    }

    func displayRadius(id: UUID) -> Double {
        bodies.first(where: { $0.id == id })?.displayRadius ?? 0.02
    }

    /// Drops the capture when its body no longer exists. Swept here, not at each removal site, so no edit path can forget it.
    private func pruneCapture() {
        guard let id = capturedBodyID else { return }
        guard !bodies.contains(where: { $0.id == id }) else { return }
        capturedBodyID = nil
        capturedPointName = nil
    }

    func removeBody(id: UUID) {
        if orbitEdit?.bodyID == id { endOrbitEdit() }
        bodies.removeAll { $0.id == id }
        if selectedID == id { selectedID = bodies.first?.id }
    }

    /// Spawns a body at the hand's radius already on a circular prograde ecliptic orbit; the throw perturbs a working orbit.
    @discardableResult
    func addBody(at displayPoint: SIMD3<Double>, earths: Double = 1) -> UUID? {
        // Budget guard: the renderer pools exactly `bodyBudget` spheres; an over-budget body would gravitate invisibly.
        guard bodies.count < Self.bodyBudget else { return nil }
        let primary = primaryBody?.body ?? .sun
        let simPosition = displayPoint * displayToSim
        let offset = simPosition - primary.position
        let distance = simd_length(offset)
        var body = CelestialBody(
            name: "New world", mass: earths * Self.earthMass,
            radius: 6.37e6,
            position: simPosition,
            velocity: primary.velocity)

        if distance > 1e3 {
            // M + m, matching `onCircularOrbit` and the ring's μ — born circular must read back circular.
            let speed = NBody.circularOrbitSpeed(
                centralMass: primary.mass + body.mass, distance: distance,
                gravitationalConstant: effectiveG)
            let up = SIMD3<Double>(0, 1, 0)
            let radial = offset / distance
            var heading = simd_cross(up, radial)
            let headingLength = simd_length(heading)
            // Over a pole there is no ecliptic tangent; fall back to any perpendicular, never zero.
            heading = headingLength > 1e-6
                ? heading / headingLength
                : simd_normalize(simd_cross(radial, SIMD3(1, 0, 0)))
            // Sign matches `CelestialBody.onCircularOrbit` (+x with velocity −z).
            body.velocity = primary.velocity + speed * heading
        }
        let orbiting = OrbitingBody(id: UUID(), body: body, displayRadius: 0.03)
        bodies.append(orbiting)
        selectedID = orbiting.id
        return orbiting.id
    }

    /// True while the scene has the single classic Sun.
    var hasSingleSun: Bool {
        bodies.contains { $0.body.name == "Sun" }
    }

    /// Splits the Sun into two half-mass suns about their barycenter; mass and momentum conserved exactly.
    func makeBinary() {
        guard let index = bodies.firstIndex(where: { $0.body.name == "Sun" }),
              bodies.count < Self.bodyBudget else { return }
        let sun = bodies[index].body
        let separation = 0.4 * CelestialBody.astronomicalUnit
        let half = sun.mass / 2
        // Mutual circular orbit: relative speed √(GM_total/d), split evenly.
        let orbitSpeed = (effectiveG * sun.mass / separation).squareRoot() / 2

        var sunA = CelestialBody(name: "Sun A", mass: half, radius: sun.radius)
        sunA.position = sun.position + SIMD3(-separation / 2, 0, 0)
        sunA.velocity = sun.velocity + SIMD3(0, 0, orbitSpeed)
        var sunB = CelestialBody(name: "Sun B", mass: half, radius: sun.radius)
        sunB.position = sun.position + SIMD3(separation / 2, 0, 0)
        sunB.velocity = sun.velocity + SIMD3(0, 0, -orbitSpeed)

        bodies[index] = OrbitingBody(id: UUID(), body: sunA, displayRadius: 0.055)
        bodies.insert(OrbitingBody(id: UUID(), body: sunB, displayRadius: 0.055),
                      at: index + 1)
        selectedID = bodies[index].id
        emitSound(.boom, at: sun.position, volume: 1)
    }

    func select(id: UUID) {
        guard bodies.contains(where: { $0.id == id }) else { return }
        selectedID = id
        // An explicit tap is the only thing that re-homes the Lagrange layer.
        if id != primaryBody?.id { lagrangeSecondaryID = id }
    }

    private func applySunMass() {
        guard let index = bodies.firstIndex(where: { $0.body.name == "Sun" }) else { return }
        let old = bodies[index].body.mass
        bodies[index].body.mass = CelestialBody.sun.mass * sunMassMultiplier
        // Inflate here too, so the bead and the programmatic path agree.
        if old > 0 {
            bodies[index].displayRadius *= pow(bodies[index].body.mass / old, 1.0 / 3.0)
        }
    }

    // MARK: Hold / throw

    func grab(id: UUID, at displayPoint: SIMD3<Double>, timestamp: Double = CACurrentMediaTime()) {
        guard bodies.contains(where: { $0.id == id }) else { return }
        heldID = id
        selectedID = id
        capturedPointName = nil
        capturedBodyID = nil
        throwSampler.reset()
        hold(id: id, at: displayPoint, timestamp: timestamp)
    }

    /// `displayPoint` is in room coordinates relative to the system center.
    func hold(id: UUID, at displayPoint: SIMD3<Double>, timestamp: Double = CACurrentMediaTime()) {
        guard let index = bodies.firstIndex(where: { $0.id == id }) else { return }
        bodies[index].body.position = displayPoint * displayToSim
        bodies[index].body.velocity = .zero
        guard heldID == id else { return }
        throwSampler.record(displayPoint, at: timestamp)
    }

    /// The sim velocity the body would get if released now.
    func currentHandVelocity(timestamp: Double = CACurrentMediaTime()) -> SIMD3<Double> {
        guard let handVelocity = throwSampler.velocity(at: timestamp) else { return .zero }
        return Self.throwVelocityScale * handVelocity
    }

    func release(id: UUID, timestamp: Double = CACurrentMediaTime()) {
        guard let index = bodies.firstIndex(where: { $0.id == id }) else { return }
        defer {
            heldID = nil
            throwSampler.reset()
        }
        guard heldID == id else { return }
        bodies[index].body.velocity = currentHandVelocity(timestamp: timestamp)
        bodies[index].trail.removeAll()
        bodies[index].lastTrailPosition = nil
        let speed = simd_length(bodies[index].body.velocity)
        if speed > 1000 {
            emitSound(.whoosh, at: bodies[index].body.position, volume: min(speed / 45_000, 1))
        }

        // Station insertion: releasing near a Lagrange point matches the rotating
        // frame — L4/L5 hold, L1–L3 shed their occupants within days.
        if let (name, point) = nearestLagrangePoint(
            to: bodies[index].body.position, within: 0.06 * displayToSim),
           let pair = lagrangePair() {
            bodies[index].body.position = point
            bodies[index].body.velocity = Lagrange.corotatingVelocity(
                at: point, primary: pair.primary, secondary: pair.secondary)
            capturedPointName = name
            capturedBodyID = bodies[index].id
        } else {
            capturedPointName = nil
            capturedBodyID = nil
        }
    }

    var heldBodyID: UUID? { heldID }

    // MARK: The orbit as an object
    // Bead drags set the ellipse's shape and plane directly, in closed form (see `PhysicsCore.ApsisFrame.dragged`).

    /// How dominant the primary must be before a two-body ring means anything:
    /// Sun/Jupiter is 1047 and passes; twin suns is 1.0 and correctly fails.
    nonisolated static let ringDominance = 20.0

    /// The body a ring is drawn around, or nil if no ring is honest here.
    func ringPrimary(for orbiting: OrbitingBody) -> OrbitingBody? {
        guard let primary = primaryBody, primary.id != orbiting.id else { return nil }
        let rivals = bodies.filter { $0.id != primary.id }.map(\.body.mass)
        guard let heaviestRival = rivals.max(),
              primary.body.mass >= Self.ringDominance * heaviestRival else { return nil }
        return primary
    }

    /// μ = G(M + m) for a body against its primary.
    private func mu(for orbiting: OrbitingBody, about primary: OrbitingBody) -> Double {
        NBody.standardGravitationalParameter(
            primaryMass: primary.body.mass, bodyMass: orbiting.body.mass,
            gravitationalConstant: effectiveG)
    }

    /// The conic this body is on, or nil (primary, nothing dominant, or radial fall).
    /// While a bead is held returns the carried frame: re-deriving the apse line each frame is ill-conditioned near e = 0.
    func orbitFrame(for id: UUID) -> ApsisFrame? {
        if let orbitEdit, orbitEdit.bodyID == id { return orbitEdit.frame }
        // A held body has no orbit: `hold` zeroes velocity, so the conic is a degenerate radial line.
        if heldID == id { return nil }
        guard let orbiting = bodies.first(where: { $0.id == id }),
              let primary = ringPrimary(for: orbiting) else { return nil }
        return ApsisFrame(
            position: orbiting.body.position - primary.body.position,
            velocity: orbiting.body.velocity - primary.body.velocity,
            mu: mu(for: orbiting, about: primary))
    }

    /// The same orbit in classical elements, for readouts and the notebook.
    func orbitElements(for id: UUID) -> OrbitalElements? {
        orbitFrame(for: id)?.elements
    }

    private struct OrbitEdit {
        let bodyID: UUID
        /// Radius of the bead not held, fixed for the gesture — a distance, not a near/far label (the held bead can cross the other mid-drag).
        let otherRadius: Double
        var frame: ApsisFrame
    }

    private var orbitEdit: OrbitEdit?

    var isEditingOrbit: Bool { orbitEdit != nil }

    /// Takes hold of one end of a body's orbit; fails without an honest ring or a missing far end.
    @discardableResult
    func beginOrbitEdit(bodyID: UUID, holding apsis: Apsis) -> Bool {
        guard let frame = orbitFrame(for: bodyID) else { return false }
        guard apsis == .near || frame.hasApoapsis else { return false }
        orbitEdit = OrbitEdit(
            bodyID: bodyID,
            otherRadius: frame.radius(at: apsis == .near ? .far : .near),
            frame: frame)
        // `heldID` means "attracts but does not move"; not via `hold(id:at:)`, which zeroes velocity — this path writes position and velocity.
        heldID = bodyID
        selectedID = bodyID
        return true
    }

    /// Reshapes the orbit so the held bead sits under the hand.
    func dragApsis(toDisplayPoint displayPoint: SIMD3<Double>) {
        guard var edit = orbitEdit,
              let index = bodies.firstIndex(where: { $0.id == edit.bodyID }),
              let primary = ringPrimary(for: bodies[index]) else { return }
        let focus = primary.body.position
        let offset = bodies[index].body.position - focus
        let length = simd_length(offset)

        edit.frame = edit.frame.dragged(
            handOffset: displayPoint * displayToSim - focus,
            otherRadius: edit.otherRadius,
            bodyDirection: length > 0 ? offset / length : edit.frame.periapsisDirection)
        orbitEdit = edit

        let state = edit.frame.state()
        bodies[index].body.position = focus + state.position
        bodies[index].body.velocity = primary.body.velocity + state.velocity
    }

    /// Lets go, leaving the body on exactly the state that produces the ring just held.
    func endOrbitEdit() {
        guard let edit = orbitEdit else { return }
        orbitEdit = nil
        heldID = nil
        guard let index = bodies.firstIndex(where: { $0.id == edit.bodyID }) else { return }
        // The trail behind it described an orbit that no longer exists.
        bodies[index].trail.removeAll()
        bodies[index].lastTrailPosition = nil
    }

    /// Inputs for the held-body orbit prediction, packaged so the n-body integration runs off the main thread.
    struct PredictionInputs: Sendable {
        var bodies: [CelestialBody]
        var index: Int
        var dt: Double
        var steps = 1200
        var pointStride = 6
        var gravitationalConstant: Double
    }

    /// Snapshot for the release preview, hand velocity substituted; lookahead ~600 sim days.
    func heldPredictionInputs(timestamp: Double = CACurrentMediaTime()) -> PredictionInputs? {
        guard let heldID, let index = bodies.firstIndex(where: { $0.id == heldID }) else { return nil }
        var snapshot = bodies.map(\.body)
        snapshot[index].velocity = currentHandVelocity(timestamp: timestamp)
        return PredictionInputs(
            bodies: snapshot, index: index,
            dt: 12 * 3600,
            gravitationalConstant: effectiveG
        )
    }

    // MARK: The Lagrange points — a LAYER, not a mode

    var showLagrangePoints = false

    /// Which Lagrange point the last release parked a body at, and which body; the id rides along so the callout follows it.
    private(set) var capturedBodyID: UUID?
    private(set) var capturedPointName: String?

    /// Whose points these are — the last planet TAPPED, not the live selection (spawning would re-point the layer mid-gesture). Only `select(id:)` moves the host.
    private(set) var lagrangeSecondaryID: UUID?

    /// The pair whose Lagrange points are shown.
    private func lagrangePair() -> (primary: CelestialBody, secondary: CelestialBody)? {
        guard showLagrangePoints,
              let hostID = lagrangeSecondaryID ?? selectedBody?.id,
              let host = bodies.first(where: { $0.id == hostID }),
              let primary = primaryBody, primary.id != host.id
        else { return nil }
        return (primary.body, host.body)
    }

    /// The five points, co-rotating with the selected planet.
    var lagrangePoints: [(name: String, position: SIMD3<Double>)] {
        guard showLagrangePoints,
              let pair = lagrangePair() else { return [] }
        return Lagrange.points(primary: pair.primary, secondary: pair.secondary,
                               gravitationalConstant: effectiveG).all
    }

    private func nearestLagrangePoint(
        to position: SIMD3<Double>, within radius: Double
    ) -> (String, SIMD3<Double>)? {
        lagrangePoints
            .map { ($0.name, $0.position) }
            .min { simd_distance($0.1, position) < simd_distance($1.1, position) }
            .flatMap { simd_distance($0.1, position) < radius ? $0 : nil }
    }

    /// Why the parked point behaves as it does — phrased against "the star"/"the planet" so each line holds for every pair.
    static let lagrangeExplanations: [String: String] = [
        "L1": "L1 sits between the star and the planet, where their pulls and the orbit's rotation balance — but it is a saddle: any nudge grows, so real L1 missions burn fuel to stay. Watch yours slide off.",
        "L2": "L2 lies beyond the planet, where the two pulls together speed a satellite up enough to keep pace with the planet's orbit. Unstable like L1 — Sun–Earth L2 is where JWST flies, on a halo orbit it has to maintain.",
        "L3": "L3 hides on the far side of the star, opposite the planet — the science-fiction 'counter-Earth' spot. The most weakly unstable of the three collinear points, and still no place to park unattended.",
        "L4": "L4 leads the planet by 60°, an equilateral triangle with the star — and it is genuinely stable: displaced bodies orbit around the point instead of sliding off it. Jupiter's L4 holds thousands of Trojan asteroids.",
        "L5": "L5 trails the planet by 60°, the mirror of L4 and just as stable. Proposed home for space colonies since the 1970s precisely because what you leave here stays.",
    ]

    // MARK: Stepping

    /// Advances one rendered frame of simulated time, in Verlet substeps stable at 100×.
    func step(dt: Double) {
        // Every frame, paused or not, and after the physics (the collision pass removes the captured body).
        defer { pruneCapture() }
        guard !isPaused else { return }
        // Recorded even when the body-count guard stops the physics (scrub needs both sides); wall-clock seconds, not sim days.
        defer { recordCapsuleFrame(dt: min(dt, 1.0 / 30.0)) }
        guard bodies.count > 1 else { return }
        let simDt = min(dt, 1.0 / 30.0) * timeScale * Self.daysPerSecond * 86_400
        // Magnitude, not signed: reverse makes simDt negative, and ceil of a negative would pin this to one enormous substep.
        let substeps = min(max(Int(ceil(abs(simDt) / Self.maxSubstep)), 1),
                           Self.maxSubstepsPerFrame)
        let h = simDt / Double(substeps)

        var system = bodies.map(\.body)
        let heldIndex = heldID.flatMap { id in bodies.firstIndex { $0.id == id } }
        for _ in 0..<substeps {
            NBody.step(bodies: &system, dt: h, gravitationalConstant: effectiveG)
            if let heldIndex {
                // A held body attracts others but does not move.
                system[heldIndex] = bodies[heldIndex].body
            }
        }
        for index in bodies.indices {
            bodies[index].body = system[index]
        }
        simulatedDays += simDt / 86_400
        recordSweep()
        resolvePredictionIfDue()

        appendTrailPoints()
        resolveCollisions()
    }

    /// Trail points are dropped by distance traveled (~8 mm of room space).
    private func appendTrailPoints() {
        let spacing = 0.008 * displayToSim
        for index in bodies.indices where bodies[index].id != heldID {
            let position = bodies[index].body.position
            if let last = bodies[index].lastTrailPosition,
               simd_distance(last, position) < spacing { continue }
            bodies[index].trail.append(position)
            bodies[index].lastTrailPosition = position
            let cap = trailLength.points
            if bodies[index].trail.count > cap {
                bodies[index].trail.removeFirst(bodies[index].trail.count - cap)
            }
        }
    }

    /// Bodies merge when their RENDERED spheres overlap (real radii are invisibly small);
    /// the merge itself conserves real mass and momentum exactly.
    private func resolveCollisions() {
        var index = 0
        while index < bodies.count {
            var collided = false
            for other in (index + 1)..<bodies.count {
                let a = bodies[index], b = bodies[other]
                if a.id == heldID || b.id == heldID { continue }
                let distance = simd_distance(a.body.position, b.body.position) * simToDisplay
                if distance < 0.85 * (a.displayRadius + b.displayRadius) {
                    let merged = NBody.merged(a.body, b.body)
                    let survivor = OrbitingBody(
                        id: UUID(), body: merged,
                        displayRadius: cbrt(pow(a.displayRadius, 3) + pow(b.displayRadius, 3)),
                        trail: [], lastTrailPosition: nil
                    )
                    lastMergePosition = merged.position
                    mergeNonce += 1
                    emitSound(.boom, at: merged.position, volume: 0.9)
                    let selectionWasInvolved = selectedID == a.id || selectedID == b.id
                    bodies.remove(at: other)
                    bodies[index] = survivor
                    if selectionWasInvolved { selectedID = survivor.id }
                    collided = true
                    break
                }
            }
            if !collided { index += 1 }
        }
    }

    // MARK: Readouts (all real units; the readout card converts for display)

    struct Readout {
        var distanceAU: Double
        var speedKmPerS: Double
        var accelerationMS2: Double
        var massKg: Double
        var periodDays: Double?     // nil when unbound
        var kineticEnergy: Double
        var potentialEnergy: Double
        var totalEnergy: Double
        var escapeSpeedKmPerS: Double
        var isBound: Bool
        var forceNewtons: Double
    }

    /// Memo of derived readouts. Outside observation on purpose: a write during a read would invalidate the views asking for it.
    @ObservationIgnored private var readoutCache: [UUID: Readout] = [:]
    @ObservationIgnored private var readoutGeneration: UInt64 = 0
    @ObservationIgnored private var cachedGeneration: UInt64 = .max

    /// Everything about one body's orbit right now. Expensive (sums PE against every body); the first caller pays, the rest read the cache.
    func readout(for orbiting: OrbitingBody) -> Readout? {
        if cachedGeneration != readoutGeneration {
            cachedGeneration = readoutGeneration
            readoutCache.removeAll(keepingCapacity: true)
        } else if let cached = readoutCache[orbiting.id] {
            return cached
        }

        guard let primary = primaryBody, primary.id != orbiting.id else { return nil }
        let all = bodies.map(\.body)
        guard let index = bodies.firstIndex(where: { $0.id == orbiting.id }) else { return nil }

        let body = orbiting.body
        let offset = body.position - primary.body.position
        let distance = simd_length(offset)
        let relativeSpeed = simd_length(body.velocity - primary.body.velocity)
        let kinetic = NBody.kineticEnergy(of: body)
        let potential = NBody.potentialEnergy(of: index, in: all, gravitationalConstant: effectiveG)
        // One μ for the whole readout — G(M+m) everywhere, or semi-major axis and period belong to slightly different orbits.
        let twoBodyMass = primary.body.mass + body.mass
        let semiMajor = NBody.semiMajorAxis(
            distance: distance, speed: relativeSpeed,
            centralMass: twoBodyMass, gravitationalConstant: effectiveG)

        let result = Readout(
            distanceAU: distance / CelestialBody.astronomicalUnit,
            speedKmPerS: relativeSpeed / 1000,
            accelerationMS2: effectiveG * primary.body.mass / (distance * distance),
            massKg: body.mass,
            periodDays: semiMajor.map {
                NBody.orbitalPeriod(semiMajorAxis: $0, centralMass: twoBodyMass,
                                    gravitationalConstant: effectiveG) / 86_400
            },
            kineticEnergy: kinetic,
            potentialEnergy: potential,
            totalEnergy: kinetic + potential,
            escapeSpeedKmPerS: NBody.escapeSpeed(
                centralMass: twoBodyMass, distance: distance,
                gravitationalConstant: effectiveG) / 1000,
            isBound: semiMajor != nil,
            forceNewtons: effectiveG * primary.body.mass * body.mass / (distance * distance)
        )
        readoutCache[orbiting.id] = result
        return result
    }

    // MARK: Reset

    /// Bumped by `reset()` so the view can reset the two-hand scale, which is a view transform the model cannot touch directly.
    private(set) var viewResetNonce = 0

    /// Sun + Earth on its real orbit — the module's opening scene.
    func reset() {
        viewResetNonce += 1
        sweep.reset()
        sweepBodyID = nil
        sweepWindowStart = nil
        sweepHeldArc = []
        // reset() must restore every plate-backed flag — ResetCoverageTests reflects over Bools.
        keplerSweepOn = true
        sweepHeldArea = 0
        sweepWindowDays = 30.0
        // A settled ghost or a verdict about a deleted planet must not survive into a new system.
        prediction = nil
        predictionVerdict = nil
        capturedPointName = nil
        capturedBodyID = nil
        bodies.removeAll()
        heldID = nil
        orbitEdit = nil
        throwSampler.reset()
        sunMassMultiplier = 1.0
        gMultiplier = 1.0
        timeScale = 1.0
        isPaused = false
        trailLength = .medium
        showVelocityVector = true
        showAccelerationVector = false
        showForceVector = true
        showFieldParticles = false
        // Grid opens with the module; m^(1/4) depth compression stays disclosed in the UI footnote.
        showSpacetimeGrid = true
        showLagrangePoints = false
        lagrangeSecondaryID = nil
        playOrbitalChord = true
        simulatedDays = 0

        // Full solar system from the start: real masses, real AU distances at 1 AU = 0.5 m.
        append(.sun, displayRadius: Self.displayRadius(for: .sun))
        let planets: [CelestialBody] = [.mercury, .venus, .earth, .mars,
                                        .jupiter, .saturn, .uranus, .neptune]
        for planet in planets {
            let distance = (CelestialBody.meanOrbitAU(of: planet.name) ?? 1)
                * CelestialBody.astronomicalUnit
            append(planet.onCircularOrbit(of: .sun, distance: distance),
                   displayRadius: Self.displayRadius(for: planet))
        }
        // A comet on Halley's real orbit — a = 17.8 AU, e = 0.967, retrograde at 162° —
        // climbs out of the ecliptic disc.
        append(CelestialBody.comet.onEllipticalOrbit(
            of: .sun,
            semiMajorAxis: 17.834 * CelestialBody.astronomicalUnit,
            eccentricity: 0.967,
            inclination: 162 * .pi / 180,
            gravitationalConstant: effectiveG),
            displayRadius: Self.displayRadius(for: .comet))
        // NOTHING is selected on arrival (2026-08-29). Selection drives the
        // orbit ring, the data card, the v/a/F arrows AND the Kepler sweep
        // readout — with Earth pre-selected the module opened wearing all
        // four at once, stacked on the inner system. The quiet sky is the
        // opening image; tap a planet and the room answers, the same "this
        // one" grammar every other module teaches.
        selectedID = nil
        clearCapsule()
    }
}

// MARK: - Time Capsule

extension GravityLabModel: TimeCapsuleRecording {
    /// The sky in sim units plus its clock. Trails are NOT snapshotted — never snapshot an unbounded array; they are rebuilt from the capsule under the live 8 mm spacing rule. `timeScale` and display layers stay out.
    struct CapsuleSnapshot: Equatable {
        struct Body: Equatable {
            var id: UUID
            var body: CelestialBody
            var displayRadius: Double
        }
        var bodies: [Body]
        var simulatedDays: Double
        var sunMassMultiplier: Double
        var gMultiplier: Double
        var prediction: Prediction?
        var predictionVerdict: PredictionVerdict?
    }

    func captureCapsuleSnapshot() -> CapsuleSnapshot {
        CapsuleSnapshot(
            bodies: bodies.map {
                .init(id: $0.id, body: $0.body, displayRadius: $0.displayRadius)
            },
            simulatedDays: simulatedDays,
            sunMassMultiplier: sunMassMultiplier,
            gMultiplier: gMultiplier,
            prediction: prediction,
            predictionVerdict: predictionVerdict)
    }

    func restoreCapsuleSnapshot(_ snapshot: CapsuleSnapshot) {
        bodies = snapshot.bodies.map { recorded in
            var restored = OrbitingBody(id: recorded.id, body: recorded.body,
                                        displayRadius: recorded.displayRadius)
            // A body in a hand keeps the hand's position: a restore must not move it.
            if recorded.id == heldBodyID,
               let live = bodies.first(where: { $0.id == recorded.id }) {
                restored.body = live.body
            }
            restored.trail = recordedTrail(for: recorded.id, upTo: scrubTime)
            restored.lastTrailPosition = restored.trail.last
            return restored
        }
        simulatedDays = snapshot.simulatedDays
        sunMassMultiplier = snapshot.sunMassMultiplier
        gMultiplier = snapshot.gMultiplier
        prediction = snapshot.prediction
        predictionVerdict = snapshot.predictionVerdict
        if let selectedID, !bodies.contains(where: { $0.id == selectedID }) {
            self.selectedID = nil
        }
    }

    /// One body's trail rebuilt from recorded frames up to `time`, under live spacing/length rules.
    private func recordedTrail(for id: UUID, upTo time: Double?) -> [SIMD3<Double>] {
        guard let time, let span = capsule.span else { return [] }
        let spacing = 0.008 * displayToSim
        var trail: [SIMD3<Double>] = []
        for frame in capsule.frames(in: span.lowerBound...time) {
            guard let body = frame.snapshot.bodies.first(where: { $0.id == id })
            else { continue }
            let position = body.body.position
            if let last = trail.last, simd_distance(last, position) < spacing {
                continue
            }
            trail.append(position)
        }
        let cap = trailLength.points
        if trail.count > cap { trail.removeFirst(trail.count - cap) }
        return trail
    }
}
