//
//  GravityLabModel.swift
//  Physics Playground — Gravity Lab module
//
//  App state for the orbital mechanics lab. The simulation runs in real
//  SI units — actual solar masses, AU distances, km/s speeds — and only
//  the renderer maps it into the room (1 AU = 0.35 m), so every panel
//  number can be checked against an almanac.
//
//  Time is the second mapping: at 1× speed, one real second is 3
//  simulated days (an Earth year in ~2 minutes). High time scales split
//  each frame into Verlet substeps capped at 6 simulated hours, so
//  100× stays symplectic-stable instead of exploding.
//
//  Grabbing a body freezes its motion (it still attracts everything
//  else); a live prediction shows the orbit it would get if released
//  right now, using the hand's current velocity. Releasing applies that
//  velocity — throw gently for an ellipse, hard for an escape.
//

import Foundation
import Observation
import PhysicsCore
import QuartzCore
import simd

@MainActor
@Observable
final class GravityLabModel {
    // MARK: Modes

    enum Mode: Equatable {
        /// The solar system: Sun-centered, 1 AU = 0.35 m.
        case solarSystem
        /// Earth–Moon–satellite: Lagrange laboratory, Moon's orbit = 0.5 m.
        case lagrange
    }

    private(set) var mode: Mode = .solarSystem

    // MARK: Scale mappings (the only two numbers between sim and room)

    /// Room meters per astronomical unit (solar system mode): Jupiter's
    /// orbit is a 2.6 m ring — the planets genuinely circle the room.
    nonisolated static let metersPerAU = 0.5
    /// Real Earth–Moon separation, m.
    nonisolated static let earthMoonSeparation = 3.844e8
    /// Room meters for the Earth–Moon separation (Lagrange mode) — the
    /// five points spread across most of the room.
    nonisolated static let metersPerEarthMoon = 0.8
    /// Simulated days per real second at 1× speed.
    nonisolated static let daysPerSecond = 3.0
    /// Sim m/s per display m/s when throwing, per mode: tuned so a relaxed
    /// ~0.35 m/s hand toss imparts roughly the natural orbital speed of
    /// each scene (~30 km/s solar, ~1 km/s around Earth).
    nonisolated static let solarThrowVelocityScale = 8.6e4
    nonisolated static let lagrangeThrowVelocityScale = 2.9e3

    var throwVelocityScale: Double {
        mode == .solarSystem ? Self.solarThrowVelocityScale : Self.lagrangeThrowVelocityScale
    }

    /// Sim meters per display meter (mode-dependent).
    private(set) var displayToSim = CelestialBody.astronomicalUnit / metersPerAU
    var simToDisplay: Double { 1 / displayToSim }

    // MARK: Budgets & integration limits

    nonisolated static let bodyBudget = 12
    /// Verlet substep never exceeds 6 simulated hours.
    nonisolated static let maxSubstep = 6.0 * 3600
    nonisolated static let maxSubstepsPerFrame = 96
    nonisolated static let timeScales: [Double] = [1, 5, 20, 100]

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
        /// Rendered sphere radius in room meters — exaggerated (real
        /// planets would be invisible at this scale) and labeled as such.
        var displayRadius: Double
        var trail: [SIMD3<Double>] = []
        var lastTrailPosition: SIMD3<Double>?
    }

    // MARK: Predict, then run — the ghost marker

    /// The predict-then-run mechanic: place a ghost where you think the
    /// selected body will be one sweep window from now, let time run,
    /// and the gap between your guess and the sky is the lesson. No
    /// text explains an ellipse like being wrong about one by hand.
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
    /// The best (smallest) resolved miss this session, AU — the number
    /// the Prophet experiment watches.
    private(set) var bestPredictionMissAU: Double?

    /// Arms a prediction on the selected body: the ghost appears AT the
    /// body, one sweep window on the clock. Dragging refines the guess.
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

    func cancelPrediction() {
        prediction = nil
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
        bestPredictionMissAU = min(bestPredictionMissAU ?? .infinity, miss)
        self.prediction = nil
        emitSound(miss < 0.1 ? .chime : .pop,
                  at: body.body.position, volume: 0.8)
    }

    // MARK: Kepler sweep — the second law, recorded live

    /// Paints the area the selected body's radius vector sweeps: the
    /// accruing sector, and the last completed one held for comparison.
    /// Equal windows, equal areas, wildly different shapes.
    var keplerSweepOn = true

    @ObservationIgnored private var sweep = KeplerSweep(horizon: 60 * 86_400)
    @ObservationIgnored private var sweepWindowStart: Double?
    @ObservationIgnored private var sweepBodyID: UUID?
    /// The last COMPLETED window's sector, relative to the primary, sim
    /// metres — and its area. Held on screen while the next accrues.
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
            // A different body: its history is not this body's history.
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
        // Any change to the system — a step, a drag, a merge, a new
        // planet — retires every cached readout. Hanging this off the
        // property rather than off `step` means a new way to move a body
        // cannot forget to invalidate.
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

    /// Multiplies the Sun preset's real mass, live.
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
    /// Kepler's third law as a chord: every bound body sings at a pitch
    /// set by its period, so perturbing an orbit is audible.
    var playOrbitalChord = true

    /// The scene's natural length: 1 AU in solar mode, the Earth–Moon
    /// separation in Lagrange mode. Visualizations normalize against the
    /// field strength at this distance from the primary.
    var characteristicLength: Double {
        mode == .solarSystem ? CelestialBody.astronomicalUnit : Self.earthMoonSeparation
    }

    /// Total simulated time, in days (shown on the time panel).
    private(set) var simulatedDays = 0.0

    // MARK: Custom planet builder

    var customDistanceAU = 1.5
    /// Mass = 10^exponent kg (22 ≈ Moon, 25 ≈ super-Earth, 28 ≈ 5 Jupiters).
    var customMassExponent = 24.0
    /// × the local circular-orbit speed: 1.0 = circle, less = ellipse
    /// falling inward, more = ellipse reaching outward (≥ √2 escapes).
    var customSpeedFactor = 1.0
    private var customCount = 0

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
    /// `PhysicsCore.ThrowSampler` — shared with Projectiles and
    /// Pendulums, which each had their own copy of this buffer.
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
            // The Moon orbits Earth. Its real distance (0.00257 AU) would
            // be under a millimeter in the room, so it spawns at 0.06 AU —
            // distance exaggerated for visibility, masses and speeds real.
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

    func spawnCustom() {
        guard bodies.count < Self.bodyBudget else { return }
        customCount += 1
        let sun = primaryBody?.body ?? .sun
        let distance = customDistanceAU * CelestialBody.astronomicalUnit
        let mass = pow(10, customMassExponent)
        var body = CelestialBody(
            name: "Custom \(customCount)",
            mass: mass,
            radius: 6.4e6
        ).onCircularOrbit(of: sun, distance: distance, gravitationalConstant: effectiveG)
        body.velocity = sun.velocity + customSpeedFactor * (body.velocity - sun.velocity)
        // Display size grows gently with mass: 22 → 6 mm, 28 → 3.6 cm.
        append(body, displayRadius: 0.006 + (customMassExponent - 22) * 0.005)
    }

    private func append(_ body: CelestialBody, displayRadius: Double) {
        let orbiting = OrbitingBody(id: UUID(), body: body, displayRadius: displayRadius)
        bodies.append(orbiting)
        selectedID = orbiting.id
    }

    /// Exaggerated display sizes — the disclosed cheat that makes the
    /// system readable. At true scale Earth at 1 AU = 0.5 m would be
    /// about 30 microns across.
    ///
    /// These were roughly doubled: the inner planets were rendering as
    /// four-pixel specks against a bright wall, too small to recognise,
    /// admire, or reliably pinch. The ordering (and so the story — the
    /// gas giants dwarf the rocky planets, the Sun dwarfs everything)
    /// is preserved exactly; only the overall magnification changed.
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

    /// Mass, in Earth masses, as a quantity you can SEE: the body's
    /// drawn radius tracks the cube root of its mass, the way a real
    /// sphere's radius tracks its volume. Pulling the grip therefore
    /// inflates the planet AND deepens the well it sits in, which is
    /// exactly the connection the lab exists to teach.
    nonisolated static let earthMass = 5.972e24
    nonisolated static let massRangeEarths = 0.02...400.0

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
        // r ∝ m^(1/3): a planet a thousand times heavier is ten times
        // wider, not a thousand times.
        if old > 0 {
            bodies[index].displayRadius *= pow(bodies[index].body.mass / old, 1.0 / 3.0)
            bodies[index].displayRadius = min(max(bodies[index].displayRadius, 0.008), 0.22)
        }
    }

    func displayRadius(id: UUID) -> Double {
        bodies.first(where: { $0.id == id })?.displayRadius ?? 0.02
    }

    func removeBody(id: UUID) {
        bodies.removeAll { $0.id == id }
        if selectedID == id { selectedID = bodies.first?.id }
    }

    /// Spawns a body where you pull it out of the well, at rest
    /// relative to the primary — so it immediately starts to fall, and
    /// you watch a capture or a plunge depending on where you let go.
    @discardableResult
    func addBody(at displayPoint: SIMD3<Double>, earths: Double = 1) -> UUID? {
        let simPosition = displayPoint * displayToSim
        let body = CelestialBody(
            name: "New world", mass: earths * Self.earthMass,
            radius: 6.37e6,
            position: simPosition,
            velocity: primaryBody?.body.velocity ?? .zero)
        let orbiting = OrbitingBody(id: UUID(), body: body, displayRadius: 0.03)
        bodies.append(orbiting)
        selectedID = orbiting.id
        return orbiting.id
    }

    func removeSelected() {
        guard let selectedID, bodies.count > 1,
              selectedID != primaryBody?.id else { return }
        bodies.removeAll { $0.id == selectedID }
        self.selectedID = primaryBody?.id
    }

    /// True while the scene has the single classic Sun (the sun-mass
    /// slider and the binary button only make sense then).
    var hasSingleSun: Bool {
        bodies.contains { $0.body.name == "Sun" }
    }

    /// The showstopper: split the Sun into two half-mass suns waltzing
    /// about their barycenter. Total mass and momentum are conserved
    /// exactly, so distant planets barely notice — until they drift close
    /// and the three-body dance begins.
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
    }

    private func applySunMass() {
        guard let index = bodies.firstIndex(where: { $0.body.name == "Sun" }) else { return }
        bodies[index].body.mass = CelestialBody.sun.mass * sunMassMultiplier
    }

    // MARK: Hold / throw

    func grab(id: UUID, at displayPoint: SIMD3<Double>, timestamp: Double = CACurrentMediaTime()) {
        guard bodies.contains(where: { $0.id == id }) else { return }
        heldID = id
        selectedID = id
        capturedPointName = nil
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
        return throwVelocityScale * handVelocity
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

        // Lagrange mode: releasing near one of the five points matches the
        // body's velocity to the rotating frame ("station insertion"), so
        // the user can experience which points actually hold — L4/L5 do,
        // L1/L2/L3 drift off within days. Real dynamics from then on.
        if mode == .lagrange, let (name, point) = nearestLagrangePoint(
            to: bodies[index].body.position, within: 0.06 * displayToSim) {
            if let pair = earthMoonPair() {
                bodies[index].body.position = point
                bodies[index].body.velocity = Lagrange.corotatingVelocity(
                    at: point, primary: pair.primary, secondary: pair.secondary)
                capturedPointName = name
            }
        } else {
            capturedPointName = nil
        }
    }

    var heldBodyID: UUID? { heldID }

    /// Everything the held-body orbit prediction needs, packaged so the
    /// 1200-step n-body integration can run OFF the main thread (the
    /// renderer's pipeline calls NBody.predictedPath with these).
    struct PredictionInputs: Sendable {
        var bodies: [CelestialBody]
        var index: Int
        var dt: Double
        var steps = 1200
        var pointStride = 6
        var gravitationalConstant: Double
    }

    /// Snapshot for the "orbit you're about to create" preview, with the
    /// current hand velocity substituted on the held body. Lookahead
    /// matches the scene: ~600 days solar, ~17 days Earth–Moon.
    func heldPredictionInputs(timestamp: Double = CACurrentMediaTime()) -> PredictionInputs? {
        guard let heldID, let index = bodies.firstIndex(where: { $0.id == heldID }) else { return nil }
        var snapshot = bodies.map(\.body)
        snapshot[index].velocity = currentHandVelocity(timestamp: timestamp)
        return PredictionInputs(
            bodies: snapshot, index: index,
            dt: mode == .solarSystem ? 12 * 3600 : 1200,
            gravitationalConstant: effectiveG
        )
    }

    /// The predicted path itself (sim coordinates) — the synchronous
    /// form the tests pin; the renderer computes the same thing from
    /// `heldPredictionInputs` on its worker.
    func heldPrediction(timestamp: Double = CACurrentMediaTime()) -> [SIMD3<Double>] {
        guard let inputs = heldPredictionInputs(timestamp: timestamp) else { return [] }
        return NBody.predictedPath(
            bodies: inputs.bodies, of: inputs.index,
            dt: inputs.dt, steps: inputs.steps, pointStride: inputs.pointStride,
            gravitationalConstant: inputs.gravitationalConstant
        )
    }

    // MARK: Lagrange mode

    /// Which point the satellite was inserted at, for the explanation.
    private(set) var capturedPointName: String?

    private func earthMoonPair() -> (primary: CelestialBody, secondary: CelestialBody)? {
        guard mode == .lagrange,
              let earth = bodies.first(where: { $0.body.name == "Earth" })?.body,
              let moon = bodies.first(where: { $0.body.name == "Moon" })?.body
        else { return nil }
        return (earth, moon)
    }

    /// The five points for the live Earth–Moon geometry — they co-rotate
    /// with the Moon as it orbits.
    var lagrangePoints: [(name: String, position: SIMD3<Double>)] {
        guard let pair = earthMoonPair() else { return [] }
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

    static let lagrangeExplanations: [String: String] = [
        "L1": "L1 balances Earth's pull, the Moon's pull, and the orbit's rotation — but it's a saddle point: any nudge grows, so real L1 missions burn fuel for station-keeping. Watch your satellite slide off within days.",
        "L2": "L2 sits beyond the Moon, where the combined pull of both bodies speeds a satellite up to match the Moon's orbit. Unstable like L1 — the Sun–Earth L2 is where JWST lives, on a slowly maintained halo orbit.",
        "L3": "L3 hides on the far side of Earth from the Moon — the science-fiction 'counter-Earth' spot. It's the most weakly unstable of the three colinear points, but still won't hold without correction.",
        "L4": "L4 leads the Moon by 60°, forming an equilateral triangle — and it's genuinely stable: displaced satellites orbit *around* the point (watch the trail 'tadpole'). Jupiter's L4/L5 hold thousands of Trojan asteroids.",
        "L5": "L5 trails the Moon by 60° — the mirror of L4 and just as stable. Proposed home for space colonies since the 1970s precisely because things parked here stay.",
    ]

    /// Rebuilds the scene as Earth–Moon–satellite at Lagrange scale
    /// (the Moon's real orbit becomes half a meter of room).
    func enterLagrangeMode() {
        mode = .lagrange
        displayToSim = Self.earthMoonSeparation / Self.metersPerEarthMoon
        bodies.removeAll()
        heldID = nil
        throwSampler.reset()
        capturedPointName = nil
        simulatedDays = 0
        timeScale = 1
        isPaused = false

        let (earth, moon) = Lagrange.earthMoonSystem(gravitationalConstant: effectiveG)
        bodies.append(OrbitingBody(id: UUID(), body: earth, displayRadius: 0.045))
        bodies.append(OrbitingBody(id: UUID(), body: moon, displayRadius: 0.018))

        // The satellite starts near (not at) L4 — grab it and place it.
        var satellite = CelestialBody(name: "Satellite", mass: 1e3, radius: 5)
        let l4 = Lagrange.points(primary: earth, secondary: moon,
                                 gravitationalConstant: effectiveG).l4
        satellite.position = l4 + SIMD3(0.06 * Self.earthMoonSeparation, 0, 0)
        satellite.velocity = Lagrange.corotatingVelocity(at: satellite.position,
                                                         primary: earth, secondary: moon)
        let orbiting = OrbitingBody(id: UUID(), body: satellite, displayRadius: 0.008)
        bodies.append(orbiting)
        selectedID = orbiting.id
    }

    func exitLagrangeMode() {
        reset()
    }

    // MARK: Stepping

    /// Advances the system by one rendered frame of simulated time, in
    /// Verlet substeps small enough to stay stable at 100×.
    func step(dt: Double) {
        guard !isPaused, bodies.count > 1 else { return }
        let simDt = min(dt, 1.0 / 30.0) * timeScale * Self.daysPerSecond * 86_400
        let substeps = min(max(Int(ceil(simDt / Self.maxSubstep)), 1), Self.maxSubstepsPerFrame)
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

    /// Trail points are dropped by distance traveled (about 8 mm of room
    /// space) so trails look smooth at every time scale.
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

    /// Bodies merge when their *rendered* spheres overlap. Real radii are
    /// invisibly small at this scale, so collision uses display size —
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

    // MARK: Readouts (all real units; the panel converts for display)

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

    /// Readouts already computed for the current state of the system.
    ///
    /// Outside observation on purpose: this is a memo of values derived
    /// from state that IS observed, and registering writes to it during
    /// a read would invalidate the very views asking for it.
    @ObservationIgnored private var readoutCache: [UUID: Readout] = [:]
    @ObservationIgnored private var readoutGeneration: UInt64 = 0
    @ObservationIgnored private var cachedGeneration: UInt64 = .max

    /// Everything worth knowing about one body's orbit, right now.
    ///
    /// This is not cheap — it sums the potential energy against every
    /// other body, and copies the whole system to do it — and it has
    /// several callers per frame: the data panel, the orbital chord, and
    /// the labels. They all ask about the same unchanged system, so the
    /// first one pays and the rest read the answer. Cleared the moment
    /// `step` advances the bodies, so a cached readout can never
    /// describe a state that has already moved on.
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
        let semiMajor = NBody.semiMajorAxis(
            distance: distance, speed: relativeSpeed,
            centralMass: primary.body.mass, gravitationalConstant: effectiveG)

        let result = Readout(
            distanceAU: distance / CelestialBody.astronomicalUnit,
            speedKmPerS: relativeSpeed / 1000,
            accelerationMS2: effectiveG * primary.body.mass / (distance * distance),
            massKg: body.mass,
            periodDays: semiMajor.map {
                NBody.orbitalPeriod(semiMajorAxis: $0,
                                    centralMass: primary.body.mass + body.mass,
                                    gravitationalConstant: effectiveG) / 86_400
            },
            kineticEnergy: kinetic,
            potentialEnergy: potential,
            totalEnergy: kinetic + potential,
            escapeSpeedKmPerS: NBody.escapeSpeed(
                centralMass: primary.body.mass, distance: distance,
                gravitationalConstant: effectiveG) / 1000,
            isBound: semiMajor != nil,
            forceNewtons: effectiveG * primary.body.mass * body.mass / (distance * distance)
        )
        readoutCache[orbiting.id] = result
        return result
    }

    // MARK: Reset

    /// Sun + Earth on its real orbit — the module's opening scene.
    func reset() {
        sweep.reset()
        sweepBodyID = nil
        sweepWindowStart = nil
        sweepHeldArc = []
        mode = .solarSystem
        displayToSim = CelestialBody.astronomicalUnit / Self.metersPerAU
        capturedPointName = nil
        bodies.removeAll()
        heldID = nil
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
        // The rubber-sheet grid is the single most iconic image in
        // gravitation and it was hidden behind a toggle. It opens with
        // the module now; the m^(1/4) depth compression stays disclosed
        // in the UI footnote, as before.
        showSpacetimeGrid = true
        playOrbitalChord = true
        simulatedDays = 0
        customCount = 0
        customDistanceAU = 1.5
        customMassExponent = 24.0
        customSpeedFactor = 1.0

        // The whole solar system, live from the start: every planet on
        // its true circular orbit (real masses, real AU distances at
        // 1 AU = 0.5 m — Neptune really is 15 m away; walk toward it).
        append(.sun, displayRadius: Self.displayRadius(for: .sun))
        let planets: [CelestialBody] = [.mercury, .venus, .earth, .mars,
                                        .jupiter, .saturn, .uranus, .neptune]
        for planet in planets {
            let distance = (CelestialBody.meanOrbitAU(of: planet.name) ?? 1)
                * CelestialBody.astronomicalUnit
            append(planet.onCircularOrbit(of: .sun, distance: distance),
                   displayRadius: Self.displayRadius(for: planet))
        }
        // And a comet on Halley's real orbit — a = 17.8 AU, e = 0.967,
        // retrograde at 162°. The planets share one plane, which is true
        // and, rendered in a room, a flat disc at chest height. The comet
        // climbs right out of it, so the system finally has a reason to
        // be looked at from above and below, and its perihelion sprint is
        // the vis-viva equation made watchable.
        append(CelestialBody.comet.onEllipticalOrbit(
            of: .sun,
            semiMajorAxis: 17.834 * CelestialBody.astronomicalUnit,
            eccentricity: 0.967,
            inclination: 162 * .pi / 180,
            gravitationalConstant: effectiveG),
            displayRadius: Self.displayRadius(for: .comet))
        selectedID = bodies.first(where: { $0.body.name == "Earth" })?.id
    }
}
