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
    // MARK: Scale mappings (the only two numbers between sim and room)

    // There was a second MODE here — an Earth–Moon Lagrange laboratory at
    // its own scale, with its own throw calibration and its own
    // prediction horizon. It is a GRAVE, not a missing door: the Lagrange
    // points earned a real entrance on 2026-07-31 as a display LAYER on
    // whichever planet you last tapped, which is strictly better physics
    // (Jupiter's L4/L5 are where the Trojans actually are, Sun–Earth L2 is
    // where JWST actually is) and strictly less code. The mode it replaced
    // had never had a caller outside its own tests, so every
    // `mode == .solarSystem` branch below was a conditional with one
    // reachable arm. `PhysicsCore.Lagrange.earthMoonSystem` stays — it is
    // tested, and the layer uses the same `Lagrange.points` it always did.

    /// Room meters per astronomical unit: Jupiter's orbit is a 2.6 m ring
    /// — the planets genuinely circle the room.
    nonisolated static let metersPerAU = 0.5
    /// Simulated days per real second at 1× speed.
    nonisolated static let daysPerSecond = 3.0
    /// Sim m/s per display m/s when throwing: tuned so a relaxed ~0.35 m/s
    /// hand toss imparts roughly the scene's natural orbital speed
    /// (~30 km/s).
    nonisolated static let throwVelocityScale = 8.6e4

    /// Sim meters per display meter. A constant now that there is only
    /// one scene — it used to be re-written on entering the other mode.
    let displayToSim = CelestialBody.astronomicalUnit / metersPerAU
    var simToDisplay: Double { 1 / displayToSim }

    // MARK: Budgets & integration limits

    /// Sixteen, not twelve. `reset()` alone puts ten bodies in the scene
    /// (Sun, eight planets, Halley), so twelve meant you could add
    /// exactly TWO worlds before everything — the well, the preset menu,
    /// the twin-suns split — began refusing. A lab about building
    /// systems has to let you build one.
    nonisolated static let bodyBudget = 16
    /// Verlet substep never exceeds 6 simulated hours.
    nonisolated static let maxSubstep = 6.0 * 3600
    nonisolated static let maxSubstepsPerFrame = 96
    /// The clock, INCLUDING REVERSE.
    ///
    /// Velocity Verlet is time-symmetric for a conservative force, so a
    /// negative step does not replay a recording — it integrates the
    /// same equations backwards and arrives at where the system genuinely
    /// was. Perturb an orbit, run it back, and it un-perturbs. That is a
    /// property of the physics and of this integrator specifically (a
    /// naive Euler scheme would not come back), and it costs one sign.
    ///
    /// MERGES ARE THE EXCEPTION and the legend says so: merging two
    /// bodies destroys information, so rewinding past one cannot bring
    /// them back. Everything else is exactly reversible.
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
    /// Still here, still live, and no longer a CONTROL: the star's mass
    /// is its own bead now (`setMass(id:suns:)`). Kept because it is the
    /// clean programmatic way to set the star — used by `reset()` and
    /// pinned by tests — where the bead is the user's way.
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

    /// The scene's natural length — 1 AU. Visualizations normalize
    /// against the field strength at this distance from the primary.
    var characteristicLength: Double { CelestialBody.astronomicalUnit }

    /// Total simulated time, in days (shown on the time panel).
    private(set) var simulatedDays = 0.0

    // MARK: Time Capsule

    @ObservationIgnored var capsule = TimeCapsule<CapsuleSnapshot>()
    @ObservationIgnored var capsuleClock = 0.0
    var scrubTime: Double?
    var scrubNonce = 0

    // The CUSTOM PLANET BUILDER stood here — a distance, a mass exponent
    // and a speed factor, plus `spawnCustom()` to assemble them. It is a
    // GRAVE, not a missing door: it was three sliders in a panel section
    // that was deliberately deleted, and `addBody(at:earths:)` replaced
    // the whole idea with a better one. You pull a world out of the well
    // and it is born on a circular orbit at the distance your hand chose;
    // the throw is the speed factor, and it is a gesture rather than a
    // number. Its last callers were its own tests, now rebased on the
    // well.

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

    // MARK: The star's own mass
    //
    // The primary gets a mass bead like every other body, and the "Sun
    // mass" slider is gone. Mass is the textbook case of a quantity with
    // physical extent — the star visibly inflates as you pull, because
    // radius goes as the cube root — so by the interaction law it is
    // changed by changing that extent, not by a slider in a window.
    //
    // It needs its own range and its own UNIT. The Sun is 333,000 Earth
    // masses, so the planets' 0.02…400 range does not reach it and
    // "333000 Earths" is not a number anyone reads. Solar masses, 0.2×
    // to 4×, are what a star is measured in.
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

    /// The capture must name a body that still exists.
    ///
    /// Found on 2026-08-08 by a test written for something else: park a
    /// planet at an inner world's L4 with no orbital velocity and it
    /// falls into the star within a couple of sim months. It merges, and
    /// `capturedPointName` goes on naming it — the model holding a
    /// verdict about an object that is gone, which is precisely the
    /// failure `reset()` already apologises for a few hundred lines down
    /// ("a verdict about a planet that no longer exists").
    ///
    /// SWEPT, not cleared at each removal site. There are two today and
    /// they do not look alike: `removeBody` deletes, while the merge in
    /// the collision pass REPLACES the captured body with a heavier one
    /// carrying a new id. So "clear it where you delete" was already two
    /// different edits, and a third site would be a third chance to
    /// forget. Asking whether the id still resolves cannot be forgotten
    /// by a future removal, because it does not know about removals.
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

    /// Spawns a body where you pull it out of the well, ALREADY IN
    /// ORBIT: circular, at whatever radius your hand is at, in the
    /// ecliptic and going the same way as everything else.
    ///
    /// It used to be born at rest relative to the primary, and the
    /// on-device verdict was that a new planet's orbit "is all whack".
    /// It was — at rest relative to the Sun means falling straight into
    /// it, and the only thing that could ever save it was the throw.
    /// Rescuing it by hand meant supplying v = √(GM/r) ≈ 26 km/s, which
    /// through this module's velocity mapping is a hand moving at
    /// 0.31 m/s, aimed perpendicular to the radius vector, in the
    /// orbital plane, held steady across a 0.12 s sampling window. That
    /// is not a difficulty; it is a demand nobody can meet, and every
    /// world anyone made fell into the Sun.
    ///
    /// The model already knew how to do this: `CelestialBody`'s
    /// `onCircularOrbit` had been sitting in PhysicsCore, tested, driven
    /// only by the custom-planet builder whose panel was deleted. The
    /// well uses it now, and the THROW becomes what it should always have
    /// been: a perturbation you add to a working orbit, which is what
    /// makes the ellipse open up and the Kepler sweep worth recording.
    /// Release it without moving your hand and you get a clean circle.
    @discardableResult
    func addBody(at displayPoint: SIMD3<Double>, earths: Double = 1) -> UUID? {
        // The budget guard `spawn` has and this one did not. The
        // renderer pools exactly `bodyBudget` spheres,
        // so the 13th world was fully simulated — gravitating, merging,
        // perturbing everything else — and completely invisible.
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

        // Circular speed at the radius the hand chose, directed along
        // the ecliptic and prograde — the direction every other body in
        // the scene is already going, so a new world joins the system
        // rather than driving the wrong way up it.
        if distance > 1e3 {
            // M + m, matching `onCircularOrbit` and the orbit ring's own
            // μ — a world born circular must read back as circular.
            let speed = NBody.circularOrbitSpeed(
                centralMass: primary.mass + body.mass, distance: distance,
                gravitationalConstant: effectiveG)
            let up = SIMD3<Double>(0, 1, 0)
            let radial = offset / distance
            var heading = simd_cross(up, radial)
            let headingLength = simd_length(heading)
            // Directly over a pole there is no ecliptic tangent to pick;
            // fall back to any perpendicular rather than to zero.
            heading = headingLength > 1e-6
                ? heading / headingLength
                : simd_normalize(simd_cross(radial, SIMD3(1, 0, 0)))
            // Sign checked against `CelestialBody.onCircularOrbit`, which
            // every preset body in the scene was built by: it places a
            // planet at +x with velocity −z, and (ŷ × x̂) is −ẑ. Get this
            // backwards and the new world orbits the right shape the
            // wrong way round, which looks fine alone and wrong the
            // instant it passes anything else.
            body.velocity = primary.velocity + speed * heading
        }
        let orbiting = OrbitingBody(id: UUID(), body: body, displayRadius: 0.03)
        bodies.append(orbiting)
        selectedID = orbiting.id
        return orbiting.id
    }

    // `removeSelected()` was deleted here on 2026-08-03, for the same
    // reason as Magnetism's twin: a GRAVE left by the window panel's
    // delete button. A body is removed by the trash petal on its own
    // ring now, which the primary is deliberately not given. No caller
    // anywhere, tests included.

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
        // An explicit tap, and the only thing that re-homes the Lagrange
        // layer. See `lagrangeSecondaryID`.
        if id != primaryBody?.id { lagrangeSecondaryID = id }
    }

    private func applySunMass() {
        guard let index = bodies.firstIndex(where: { $0.body.name == "Sun" }) else { return }
        let old = bodies[index].body.mass
        bodies[index].body.mass = CelestialBody.sun.mass * sunMassMultiplier
        // The star inflates here too, or the bead and the programmatic
        // path would disagree about how big the same mass looks.
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

        // STATION INSERTION. Releasing a body near one of the five points
        // matches its velocity to the rotating frame, so you can find out
        // by hand which points actually hold: L4 and L5 do, and L1, L2
        // and L3 shed their occupants within days because they are saddle
        // points. Park something at Jupiter's L4 and it stays there,
        // which is why the Trojans are there.
        //
        // This branch has existed, correct and unreachable, since it was
        // written — it was gated on a mode with no caller.
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
    //
    // Until now the only way to change an orbit was to throw the planet:
    // `release` multiplies your hand's velocity by 8.6e4, a number that
    // appears nowhere in the room and that no two gestures reproduce. It
    // was the app's last surviving RELATIVE control, of the kind
    // DECISIONS.md convicted when it deleted the spatial dial.
    //
    // The orbit itself is the control now. A selected body draws its
    // osculating conic as a ring with a bead at each end; dragging a bead
    // sets the ellipse's shape and plane directly, in closed form. The
    // whole manipulation lives in `PhysicsCore.ApsisFrame` — read its
    // `dragged` doc for why two beads are enough for five degrees of
    // freedom, and why the plane is transported rather than set.

    /// How much heavier the primary must be than everything else before
    /// a two-body ring means anything.
    ///
    /// Sun/Jupiter is 1047, so the solar system passes easily. Twin suns
    /// is 1.0 and fails — correctly. A planet's osculating ellipse about
    /// ONE of two equal stars is not a description of anything, and the
    /// ring going out when you press "Twin suns" is the scene telling you
    /// the two-body picture just stopped applying.
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

    /// The conic this body is on — the thing the ring draws and the beads
    /// hold. Nil when the body is the primary, when nothing dominates, or
    /// when it is falling dead straight and has no orbital plane at all.
    ///
    /// WHILE A BEAD IS HELD this returns the CARRIED frame rather than
    /// re-deriving one from the state. Re-deriving would recompute the
    /// apse line from the eccentricity vector every frame, which is
    /// ill-conditioned near e = 0 — precisely where someone tuning an
    /// orbit spends their time, and precisely where a jittering ring
    /// would be least forgivable.
    func orbitFrame(for id: UUID) -> ApsisFrame? {
        if let orbitEdit, orbitEdit.bodyID == id { return orbitEdit.frame }
        // A BODY IN THE HAND HAS NO ORBIT. `hold` zeroes its velocity, so
        // its osculating conic is a degenerate radial line — no plane, no
        // ellipse, nothing a ring could honestly draw. The white
        // prediction tube is the right instrument during a hold: it shows
        // the orbit RELEASING would create, which is the question you are
        // actually asking while you hold something.
        //
        // The state alone would nearly answer this — `ApsisFrame` rejects
        // r × v = 0 — but "nearly" rests on the velocity being exactly
        // zero, and a ring that reappears as a wild ellipse the moment
        // one bit of numerical velocity survives is worse than no ring.
        if heldID == id { return nil }
        guard let orbiting = bodies.first(where: { $0.id == id }),
              let primary = ringPrimary(for: orbiting) else { return nil }
        return ApsisFrame(
            position: orbiting.body.position - primary.body.position,
            velocity: orbiting.body.velocity - primary.body.velocity,
            mu: mu(for: orbiting, about: primary))
    }

    /// The same orbit in classical elements, for readouts and the
    /// notebook.
    func orbitElements(for id: UUID) -> OrbitalElements? {
        orbitFrame(for: id)?.elements
    }

    private struct OrbitEdit {
        let bodyID: UUID
        /// The radius of the bead NOT being held. Fixed for the whole
        /// gesture: you grabbed one end, the other stays where it is.
        ///
        /// Deliberately a DISTANCE and not a `.near`/`.far` label. The
        /// held bead can cross the other one mid-drag and become the
        /// opposite apsis, at which point a stored label would be
        /// pointing at the bead in your own hand.
        let otherRadius: Double
        var frame: ApsisFrame
    }

    private var orbitEdit: OrbitEdit?

    var isEditingOrbit: Bool { orbitEdit != nil }

    /// Takes hold of one end of a body's orbit. Fails if there is no
    /// honest ring, or if the far bead was grabbed on an orbit that has
    /// no far end.
    @discardableResult
    func beginOrbitEdit(bodyID: UUID, holding apsis: Apsis) -> Bool {
        guard let frame = orbitFrame(for: bodyID) else { return false }
        guard apsis == .near || frame.hasApoapsis else { return false }
        orbitEdit = OrbitEdit(
            bodyID: bodyID,
            otherRadius: frame.radius(at: apsis == .near ? .far : .near),
            frame: frame)
        // `heldID` already means "attracts everything but does not move",
        // and `step` already restores a held body after every substep —
        // which is exactly the behaviour an edited body wants. Note this
        // does NOT go through `hold(id:at:)`: that zeroes velocity, and
        // this path writes both position AND velocity.
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

    /// Lets go. The body is left on exactly the state that produces the
    /// ring you were just holding, so the ring's meaning is continuous
    /// through the gesture: authored while held, osculating after.
    func endOrbitEdit() {
        guard let edit = orbitEdit else { return }
        orbitEdit = nil
        heldID = nil
        guard let index = bodies.firstIndex(where: { $0.id == edit.bodyID }) else { return }
        // The trail behind it described an orbit that no longer exists.
        bodies[index].trail.removeAll()
        bodies[index].lastTrailPosition = nil
    }

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
    /// matches the scene: ~600 simulated days.
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

    // MARK: The Lagrange points — a LAYER, not a mode
    //
    // `PhysicsCore.Lagrange` solves L1–L3 as real roots of the rotating
    // frame's quintic by bisection, places L4/L5 exactly, and knows the
    // co-rotating velocity. It is tested end to end. For a long time it
    // had no caller outside those tests, because its only door was an
    // Earth–Moon MODE that nothing invoked — the module's own legend
    // admitted it described "a lab no user has ever been able to reach."
    // That mode is now deleted; this layer is what replaced it.
    //
    // The door is a switch plate, and the points belong to the SELECTED
    // planet rather than to a special Earth–Moon scene. That is strictly
    // better physics teaching and strictly less code: `Lagrange.points`
    // was always written for an arbitrary pair, Jupiter's L4 and L5 are
    // where the Trojan asteroids actually live, and Sun–Earth L2 is
    // where JWST actually is. Nothing had to be built; something had to
    // be connected.

    var showLagrangePoints = false

    /// Which point the satellite was inserted at, for the explanation.
    /// Which Lagrange point the last release parked a body at, and
    /// which body.
    ///
    /// WRITTEN IN FOUR PLACES AND READ IN NONE until 2026-08-08 — and
    /// the silence was not cosmetic. `release()` OVERWRITES the velocity
    /// the user just threw with `Lagrange.corotatingVelocity`, which is
    /// the right physics and looks, without a word of explanation, like
    /// the throw was ignored. `lagrangeExplanations` had five paragraphs
    /// ready for exactly that moment and no surface to appear on.
    ///
    /// The body's id rides along so the callout can FOLLOW it. That is
    /// the teaching: L1, L2 and L3 are saddles, so the captured body
    /// slides off over the next few days while the paragraph saying it
    /// would travels with it. L4 and L5 hold, and the paragraph stays
    /// put.
    private(set) var capturedBodyID: UUID?
    private(set) var capturedPointName: String?

    /// Whose points these are — the last planet the user TAPPED, not
    /// whatever happens to be selected.
    ///
    /// The distinction is load-bearing. Spawning a body selects it, so
    /// deriving the host from the live selection meant that pulling a
    /// world out of the well to park at Jupiter's L4 re-pointed the whole
    /// layer at the satellite mid-gesture — the five markers you were
    /// aiming for moved the instant you made the thing to aim with. Only
    /// `select(id:)` — an explicit tap — moves the host.
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

    /// The five points for the live geometry — they co-rotate with the
    /// selected planet as it orbits.
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

    /// Why the point you just parked on behaves the way it does.
    ///
    /// These were written for the deleted Earth–Moon mode and named it in
    /// every line — "L1 balances Earth's pull, the Moon's pull…". The
    /// layer that replaced that mode draws the points for WHICHEVER pair
    /// you tapped, so the old prose would have been confidently wrong for
    /// four planets out of five. Phrased against "the star" and "the
    /// planet", they are true for every pair the layer can show; the real
    /// missions stay because naming them is what makes the point land.
    static let lagrangeExplanations: [String: String] = [
        "L1": "L1 sits between the star and the planet, where their pulls and the orbit's rotation balance — but it is a saddle: any nudge grows, so real L1 missions burn fuel to stay. Watch yours slide off.",
        "L2": "L2 lies beyond the planet, where the two pulls together speed a satellite up enough to keep pace with the planet's orbit. Unstable like L1 — Sun–Earth L2 is where JWST flies, on a halo orbit it has to maintain.",
        "L3": "L3 hides on the far side of the star, opposite the planet — the science-fiction 'counter-Earth' spot. The most weakly unstable of the three collinear points, and still no place to park unattended.",
        "L4": "L4 leads the planet by 60°, an equilateral triangle with the star — and it is genuinely stable: displaced bodies orbit around the point instead of sliding off it. Jupiter's L4 holds thousands of Trojan asteroids.",
        "L5": "L5 trails the planet by 60°, the mirror of L4 and just as stable. Proposed home for space colonies since the 1970s precisely because what you leave here stays.",
    ]

    // MARK: Stepping

    /// Advances the system by one rendered frame of simulated time, in
    /// Verlet substeps small enough to stay stable at 100×.
    func step(dt: Double) {
        // EVERY FRAME, PAUSED OR NOT — a body can be deleted from a
        // stopped room — and AFTER the physics, because the collision
        // pass below is itself one of the things that removes the
        // captured body. Called at the top instead, this was permanently
        // one frame behind the merge it exists to notice.
        defer { pruneCapture() }
        guard !isPaused else { return }
        // Recorded even when the guard below stops the physics: a room
        // that has just merged down to one body still has a present, and
        // scrubbing across that moment must find frames on both sides.
        // WALL-CLOCK seconds, not sim days. The rail's unit is "seconds
        // ago" — seconds of the wearer's life — so the capsule clock is
        // the same on every bench regardless of what its own clock is
        // doing. At 100× a scrub of one second rewinds a century of sky,
        // which is exactly right: it rewinds the second you watched.
        defer { recordCapsuleFrame(dt: min(dt, 1.0 / 30.0)) }
        guard bodies.count > 1 else { return }
        let simDt = min(dt, 1.0 / 30.0) * timeScale * Self.daysPerSecond * 86_400
        // MAGNITUDE, not the signed value. Running time backwards makes
        // `simDt` negative, and `ceil` of a negative number is <= 0, so
        // the clamp would have pinned this to a single substep — one
        // enormous reverse leap per frame, which is exactly the case the
        // substep cap exists to prevent.
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
        // ONE μ FOR THE WHOLE READOUT. This used to be μ = GM here and in
        // the escape speed, but G(M+m) in the period two lines down — two
        // different two-body problems described in one card. The gap is
        // 0.05 % at Jupiter, which is well under any tolerance a test
        // would have caught it with, and it made a body's semi-major axis
        // and its period belong to slightly different orbits.
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

    /// Bumped by `reset()`. The two-hand view scale lives in the space
    /// view (it is a VIEW transform, not state), so the model cannot
    /// reset it directly — but Reset that leaves you at 6x and turned
    /// 40 degrees has not reset the thing the user was looking at.
    private(set) var viewResetNonce = 0

    /// Sun + Earth on its real orbit — the module's opening scene.
    func reset() {
        viewResetNonce += 1
        sweep.reset()
        sweepBodyID = nil
        sweepWindowStart = nil
        sweepHeldArc = []
        // THE FIFTH RESET DEFECT, and it is the same shape as the other
        // four: `reset()` cleared everything the sweep had ACCUMULATED
        // and never restored the flag its own switch plate shows. Turn
        // the Kepler sweep off, press Reset, and the plate stays dark for
        // ever — nothing else in the room contradicts it, which is
        // exactly why this class of bug survives. Found 2026-08-03 by
        // reading `reset()` against the bank, per the standing rule.
        keplerSweepOn = true
        sweepHeldArea = 0
        sweepWindowDays = 30.0
        // An armed prediction and its verdict callout are not layers, so
        // they are not covered by the rule above — but a settled ghost
        // and a verdict about a planet that no longer exists surviving
        // into a brand-new solar system is the same failure in a
        // different costume. `bestPredictionMissAU` deliberately stays:
        // it is a personal best, and the Prophet experiment reads it.
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
        // The rubber-sheet grid is the single most iconic image in
        // gravitation and it was hidden behind a toggle. It opens with
        // the module now; the m^(1/4) depth compression stays disclosed
        // in the UI footnote, as before.
        showSpacetimeGrid = true
        showLagrangePoints = false
        lagrangeSecondaryID = nil
        playOrbitalChord = true
        simulatedDays = 0

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
        clearCapsule()
    }
}

// MARK: - Time Capsule

extension GravityLabModel: TimeCapsuleRecording {
    /// The sky, in sim units, plus the clock it was read against.
    ///
    /// TRAILS ARE NOT IN THE SNAPSHOT. They are the one unbounded array
    /// on this model, and storing a growing copy of one per body per
    /// recorded frame is the memory trap the whole design was built to
    /// avoid. They are rebuilt from the capsule instead, by the same 8 mm
    /// spacing rule `appendTrailPoints` applies live — so a scrubbed
    /// trail is not a reconstruction of the recording, it IS the
    /// recording. Out: `timeScale` (the live clock keeps setting how time
    /// runs; the capsule only records what it produced), the display
    /// layers, and `bestPredictionMissAU`, which is a personal best.
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
            // A body in a hand keeps the hand's position: `heldID` means
            // "attracts everything but does not move", and a restore must
            // not move it either.
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

    /// One body's trail, rebuilt from the recorded frames up to `time`,
    /// under the live spacing and length rules.
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
