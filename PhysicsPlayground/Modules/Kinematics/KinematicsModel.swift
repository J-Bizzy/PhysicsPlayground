//
//  KinematicsModel.swift
//  Physics Playground — Kinematics module
//
//  App state for room-scale projectile motion: physics space IS the room
//  (1:1, immersive-space coordinates, the real floor at y = 0), so every
//  number the room shows is literally true of what you're looking at.
//
//  Two ways to launch:
//    · grab any ball and THROW it — release velocity is estimated from
//      the hand's last ~0.1 s of motion, optionally amplified by the
//      throw boost for small rooms;
//    · the free-floating launcher — grab its body to move it anywhere,
//      pinch-drag the bead to aim, Fire for repeatable, precise launches.
//
//  Flights bounce on the floor, the room's walls, and the ceiling with
//  each ball's real restitution — always; a ball that leaves the room
//  is a bug, not a setting — then roll briefly to rest. Time steps in
//  simulated time (strobe dots stay equal-Δt in *simulated* time, so
//  slow motion never lies about speed). The hoop/scoring machinery is
//  dormant: retired from the surface 2026-07-29, kept in the model.
//

import Foundation
import Observation
import PhysicsCore
import QuartzCore
import simd

@MainActor
@Observable
final class KinematicsModel {
    // MARK: Control ranges

    nonisolated static let speedRange = 0.5...15.0            // m/s
    nonisolated static let elevationRangeDegrees = -85.0...85.0
    nonisolated static let gravityRange = 0.0...30.0          // m/s²
    /// `PhysicsCore.SurfaceGravity` — shared with Pendulums, which had
    /// its own copy of these numbers. Zero-g included here: a projectile
    /// with no gravity is a straight line, which is worth seeing.
    nonisolated static let gravityPresets = SurfaceGravity.all
    nonisolated static let windSpeedRange = 0.0...15.0        // m/s
    nonisolated static let timeScaleRange = 0.1...2.0
    nonisolated static let throwBoostRange = 1.0...3.0
    nonisolated static let customMassRange = 0.005...5.0      // kg
    nonisolated static let customDiameterRange = 0.02...0.35  // m

    // MARK: Budgets (degrade by not drawing, never by dropping frames)

    nonisolated static let flightBudget = 12
    nonisolated static let dotsPerFlight = 40
    /// Strobe interval in *simulated* seconds.
    nonisolated static let dotInterval = 1.0 / 15.0
    nonisolated static let ringBudget = 3

    // MARK: Room bounds & launcher

    /// Flights beyond this radius from the room origin are gone for good.
    nonisolated static let escapeRadius = 30.0
    nonisolated static let launcherHome = SIMD3<Double>(-0.6, 1.1, -1.2)
    /// Barrel length: balls launch from the muzzle tip.
    nonisolated static let barrelLength = 0.28
    nonisolated static let ballSpawnPoint = SIMD3<Double>(0.15, 1.25, -0.9)
    nonisolated static let ringRadius = 0.23                  // regulation-ish rim
    nonisolated static let ringSpawnPoint = SIMD3<Double>(0.7, 1.6, -1.5)

    // MARK: Projectile selection

    enum ProjectileKind: String, CaseIterable, Identifiable {
        case tableTennisBall, basketball, golfBall, cannonball, custom
        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .tableTennisBall: "Table-tennis ball"
            case .basketball: "Basketball"
            case .golfBall: "Golf ball"
            case .cannonball: "Cannonball"
            case .custom: "Custom ball"
            }
        }
    }

    var kind: ProjectileKind = .golfBall
    /// The custom ball, editable live (smooth-sphere Cd, mid restitution).
    var customMass = 0.25
    var customDiameter = 0.10

    var projectile: Projectile {
        switch kind {
        case .tableTennisBall: .tableTennisBall
        case .basketball: .basketball
        case .golfBall: .golfBall
        case .cannonball: .cannonball
        case .custom: Projectile(
            name: "Custom ball", mass: customMass, diameter: customDiameter,
            dragCoefficient: 0.47, restitution: 0.6)
        }
    }

    // MARK: Environment

    var gravity = 9.81
    var airResistance = false

    /// Whether flights bounce off the walls and ceiling, or sail
    /// through. Defaults ON — and when on, it always works: before the
    /// real room is scanned (and always in the simulator) the walls
    /// default to the generous unscanned box; on device the shared
    /// room model replaces them with the detected walls plus the
    /// scanned boundary.
    var respectRoomWalls = true
    var roomWalls: [RoomWalls.Wall] = RoomWalls.box(of: .unscanned)
    /// The room's box, for the containment clamp — the guarantee that
    /// no ball ever ends a frame outside the room.
    var roomBounds: RoomBox = .unscanned

    init() {
        // The welcome scene lives in reset() — and reset() only ran
        // from the reset button, so the module opened BARE: no hoops,
        // no staged balls, no opening shot. Open the way reset leaves
        // things.
        reset()

        // Debug hook: `simctl launch … -kinWalls 1` seeds a synthetic
        // wall across the room and fires a ball at it, so the bounce is
        // verifiable in the simulator (real walls are device-only).
        // Close enough (1.4 m) that the welcome shot actually reaches
        // it before landing.
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "kinWalls") {
            roomWalls = [RoomWalls.Wall(
                center: SIMD3(1.4, 1.5, -0.9), normal: SIMD3(1, 0, 0),
                uAxis: SIMD3(0, 0, 1), vAxis: SIMD3(0, 1, 0),
                halfU: 2.5, halfV: 1.5)]
            fire()
        }
        #endif
    }
    var windSpeed = 0.0
    /// Wind heading in degrees; 0 blows toward +x, 90 toward +z.
    var windDirectionDegrees = 0.0

    var wind: SIMD3<Double> {
        let heading = windDirectionDegrees * .pi / 180
        return windSpeed * SIMD3(cos(heading), 0, sin(heading))
    }

    private func drag(for projectile: Projectile) -> ProjectileMotion.Drag? {
        airResistance ? ProjectileMotion.Drag(projectile: projectile, wind: wind) : nil
    }

    // MARK: Time control

    var timeScale = 1.0
    var isPaused = false

    // MARK: Launcher

    var launcherPosition = KinematicsModel.launcherHome
    var launchSpeed = 6.0
    /// Unit aim vector. Negative elevation is allowed — the launcher can
    /// sit high and fire downward.
    private(set) var aimDirection = KinematicsModel.direction(elevationDegrees: 45, azimuthDegrees: 0)

    nonisolated static func direction(elevationDegrees: Double, azimuthDegrees: Double) -> SIMD3<Double> {
        let elevation = elevationDegrees * .pi / 180
        let azimuth = azimuthDegrees * .pi / 180
        return SIMD3(
            cos(elevation) * cos(azimuth),
            sin(elevation),
            cos(elevation) * sin(azimuth)
        )
    }

    var elevationDegrees: Double {
        get { asin(max(-1, min(1, aimDirection.y))) * 180 / .pi }
        set { setAim(elevationDegrees: newValue, azimuthDegrees: azimuthDegrees) }
    }

    var azimuthDegrees: Double {
        atan2(aimDirection.z, aimDirection.x) * 180 / .pi
    }

    func setAim(elevationDegrees: Double, azimuthDegrees: Double) {
        let elevation = min(max(elevationDegrees, Self.elevationRangeDegrees.lowerBound),
                            Self.elevationRangeDegrees.upperBound)
        aimDirection = Self.direction(elevationDegrees: elevation, azimuthDegrees: azimuthDegrees)
    }

    /// Aim from the bead drag: `point` is the hand in room space; aim from
    /// the launcher toward it (azimuth free — fire anywhere in the room).
    func aim(toward point: SIMD3<Double>) {
        let offset = point - launcherPosition
        guard simd_length(offset) > 0.05 else { return }
        let direction = simd_normalize(offset)
        setAim(
            elevationDegrees: asin(max(-1, min(1, direction.y))) * 180 / .pi,
            azimuthDegrees: atan2(direction.z, direction.x) * 180 / .pi
        )
    }

    func moveLauncher(to point: SIMD3<Double>) {
        var clamped = point
        clamped.y = max(clamped.y, 0.15)
        launcherPosition = clamped
    }

    var muzzlePoint: SIMD3<Double> {
        launcherPosition + Self.barrelLength * aimDirection
    }

    /// The live predicted trajectory from the launcher, bounces included —
    /// a few hundred RK4 steps, microseconds, fine to recompute on read.
    var prediction: ProjectileMotion.Trajectory {
        ProjectileMotion.simulate(
            from: muzzlePoint,
            launchVelocity: launchSpeed * aimDirection,
            gravity: gravity,
            drag: drag(for: projectile),
            restitution: projectile.restitution,
            maxBounces: 4,
            walls: respectRoomWalls ? roomWalls : [],
            maxDuration: 12
        )
    }

    var terminalSpeed: Double? {
        airResistance
            ? ProjectileMotion.terminalSpeed(projectile: projectile, gravity: gravity)
            : nil
    }

    // MARK: Flights

    struct Flight: Identifiable, Equatable {
        let id: UUID
        var projectile: Projectile
        var state: ParticleDynamics.State
        var elapsed = 0.0
        var maxHeight = 0.0
        var nextDotTime = KinematicsModel.dotInterval
        var dots: [SIMD3<Double>] = []
        var bounces = 0
        /// Where this arc began, for the range readout.
        var launchPoint = SIMD3<Double>.zero
        var wasThrown = false
        /// Each flight can score each hoop once (a real rim has a net —
        /// a ball bouncing back up and through again shouldn't re-score).
        var scoredRings: Set<UUID> = []

        enum Status: Equatable {
            /// Hovering, waiting to be grabbed (fresh "ball to throw").
            case staged
            /// In the user's hand.
            case held
            case flying
            /// On the floor, shedding the last of its speed.
            case rolling
            case rested
        }
        var status: Status = .staged
    }

    private(set) var flights: [Flight] = []

    struct FlightSummary: Equatable {
        var projectileName: String
        var range: Double
        var apexHeight: Double
        var flightTime: Double
        var wasThrown: Bool
    }

    private(set) var lastFlight: FlightSummary?

    // MARK: Catching

    /// How near a fingertip has to be to a flying ball to catch it.
    /// Generous — a real catch is a hand, not a point.
    nonisolated static let catchRadius = 0.14

    /// The last catch, for the callout that appears at the caught ball.
    struct Catch: Equatable {
        var id: UUID
        var speed: Double
        var height: Double
        var flightTime: Double
        var kineticEnergy: Double
        var position: SIMD3<Double>
    }
    private(set) var lastCatch: Catch?
    var catchingEnabled = true

    /// Catches any flying ball that reaches an open hand: freezes it,
    /// records what it was doing at that instant, and stages it to be
    /// thrown again.
    ///
    /// This is the piece the module was missing. Everything else here is
    /// launch-and-watch; a catch is the moment the simulation reaches
    /// BACK to you, and it is only possible because there are real hands
    /// in the scene. The numbers it freezes — impact speed, height,
    /// flight time, kinetic energy — are the ones a stopwatch and a
    /// tape measure could never give you mid-flight.
    @discardableResult
    func catchBalls(atFingertips fingertips: [SIMD3<Double>]) -> Bool {
        guard catchingEnabled, !fingertips.isEmpty else { return false }
        var caught = false
        for index in flights.indices where flights[index].status == .flying {
            let position = flights[index].state.position
            guard fingertips.contains(where: {
                simd_distance($0, position) < Self.catchRadius
            }) else { continue }

            let velocity = flights[index].state.velocity
            let speed = simd_length(velocity)
            lastCatch = Catch(
                id: flights[index].id,
                speed: speed,
                height: position.y,
                flightTime: flights[index].elapsed,
                kineticEnergy: 0.5 * flights[index].projectile.mass * speed * speed,
                position: position)
            flights[index].state.velocity = .zero
            flights[index].status = .staged
            emitSound(.thud, at: position, volume: min(0.3 + speed * 0.1, 0.9))
            caught = true
        }
        return caught
    }

    /// Hand-motion samples for the ball currently being held.
    /// `PhysicsCore.ThrowSampler` — shared with Gravity Lab and
    /// Pendulums, which each had their own copy of this buffer.
    private var throwSampler = ThrowSampler()
    private var heldFlightID: UUID?
    /// Release-velocity multiplier — ×1 is a physically honest throw.
    var throwBoost = 1.0

    private func insertFlight(_ flight: Flight) {
        if flights.count >= Self.flightBudget {
            // Evict settled balls before airborne ones.
            if let index = flights.firstIndex(where: { $0.status == .rested || $0.status == .staged }) {
                flights.remove(at: index)
            } else {
                flights.removeFirst()
            }
        }
        flights.append(flight)
    }

    /// Fires the launcher.
    func fire() {
        var flight = Flight(
            id: UUID(),
            projectile: projectile,
            state: ParticleDynamics.State(
                position: muzzlePoint,
                velocity: launchSpeed * aimDirection
            )
        )
        flight.status = .flying
        flight.maxHeight = muzzlePoint.y
        flight.launchPoint = muzzlePoint
        insertFlight(flight)
        emitSound(.pop, at: muzzlePoint, volume: 0.8)
    }

    /// Spawns a fresh ball hovering at `ballSpawnPoint`, ready to grab
    /// and throw. (It said "by the panel" until 2026-08-03; the spawn
    /// point is its own constant and has never been near a window.)
    func spawnBall() {
        let stagedCount = flights.filter { $0.status == .staged }.count
        let angle = Double(stagedCount) * 2.4
        let offset = SIMD3(cos(angle) * 0.12, Double(stagedCount) * 0.02, sin(angle) * 0.12)
        insertFlight(Flight(
            id: UUID(),
            projectile: projectile,
            state: ParticleDynamics.State(position: Self.ballSpawnPoint + offset)
        ))
    }

    /// Spawns a ball AT THE HAND — the well's spawn (owner, 2026-08-04:
    /// the launcher used to be the only way a ball came into the room).
    /// Staged, so it hangs inert exactly where it is born until a throw
    /// gives it a velocity; it wears whatever kind the ball fan has
    /// picked, so the well and the launcher agree about what a ball is.
    @discardableResult
    func spawnBall(at position: SIMD3<Double>) -> UUID {
        let flight = Flight(
            id: UUID(),
            projectile: projectile,
            state: ParticleDynamics.State(position: position))
        insertFlight(flight)
        return flight.id
    }

    func clearFlights() {
        flights.removeAll()
        lastFlight = nil
        heldFlightID = nil
        throwSampler.reset()
    }

    // MARK: Throwing

    func grabBall(id: UUID) {
        guard let index = flights.firstIndex(where: { $0.id == id }) else { return }
        heldFlightID = id
        throwSampler.reset()
        flights[index].status = .held
        // A re-thrown ball starts a fresh flight record.
        flights[index].dots.removeAll()
        flights[index].elapsed = 0
        flights[index].nextDotTime = Self.dotInterval
        flights[index].bounces = 0
        flights[index].scoredRings.removeAll()
    }

    /// `timestamp` defaults to the wall clock; tests inject exact times.
    func holdBall(id: UUID, at position: SIMD3<Double>, timestamp: Double = CACurrentMediaTime()) {
        guard let index = flights.firstIndex(where: { $0.id == id }) else { return }
        flights[index].state = ParticleDynamics.State(position: position)
        guard heldFlightID == id else { return }
        throwSampler.record(position, at: timestamp)
    }

    /// Releases the held ball with the hand's velocity over the final
    /// ~0.1 s of motion (endpoint estimate over the sample window).
    func releaseBall(id: UUID, timestamp: Double = CACurrentMediaTime()) {
        guard let index = flights.firstIndex(where: { $0.id == id }) else { return }
        defer {
            heldFlightID = nil
            throwSampler.reset()
        }

        guard let handVelocity = throwSampler.velocity(at: timestamp) else {
            // No meaningful motion: the ball just hovers where released.
            flights[index].status = .staged
            return
        }

        let velocity = throwBoost * handVelocity
        flights[index].state.velocity = velocity
        flights[index].status = .flying
        flights[index].maxHeight = flights[index].state.position.y
        flights[index].launchPoint = flights[index].state.position
        flights[index].wasThrown = true
        emitSound(.whoosh, at: flights[index].state.position,
                  volume: min(simd_length(velocity) / 8, 1))
    }

    // MARK: Hoops

    struct Ring: Identifiable, Equatable {
        let id: UUID
        /// Where the user placed it (the orbit's center when hoops move).
        var anchor: SIMD3<Double>
        var position: SIMD3<Double>
        var phase: Double
        var score = 0
    }

    private(set) var rings: [Ring] = []
    /// Bumped shortly after a score so observers re-render the flash off.
    private(set) var ringFlashNonce = 0

    /// Moving targets: hoops circle their anchors — the skill mode.
    var hoopsOrbit = false
    nonisolated static let hoopOrbitRadius = 0.25
    nonisolated static let hoopOrbitSpeed = 0.55  // rad/s (simulated time)

    var totalScore: Int { rings.reduce(0) { $0 + $1.score } }

    /// Consecutive scoring flights; a landed miss (with hoops up) resets it.
    private(set) var streak = 0
    private(set) var bestStreak = UserDefaults.standard.integer(forKey: "kinematics.bestStreak")

    func addRing() {
        guard rings.count < Self.ringBudget else { return }
        let anchor = Self.ringSpawnPoint
            + SIMD3(Double(rings.count) * 0.55, Double(rings.count) * 0.15, 0)
        rings.append(Ring(id: UUID(), anchor: anchor, position: anchor,
                          phase: Double(rings.count) * 2.1))
    }

    func removeLastRing() {
        guard !rings.isEmpty else { return }
        rings.removeLast()
    }

    func moveRing(id: UUID, to point: SIMD3<Double>) {
        guard let index = rings.firstIndex(where: { $0.id == id }) else { return }
        var clamped = point
        clamped.y = max(clamped.y, 0.3)
        rings[index].anchor = clamped
        if !hoopsOrbit {
            rings[index].position = clamped
        }
    }

    /// Advances hoop motion (independent of whether anything is flying).
    private func stepRings(dt: Double) {
        for index in rings.indices {
            if hoopsOrbit {
                rings[index].phase += Self.hoopOrbitSpeed * dt
                rings[index].position = rings[index].anchor + SIMD3(
                    Self.hoopOrbitRadius * cos(rings[index].phase),
                    0,
                    Self.hoopOrbitRadius * sin(rings[index].phase)
                )
            } else if rings[index].position != rings[index].anchor {
                rings[index].position = rings[index].anchor
            }
        }
    }

    /// Returns the hoops newly scored by this segment of flight.
    private func checkRings(
        previous: SIMD3<Double>,
        current: SIMD3<Double>,
        ballRadius: Double,
        alreadyScored: Set<UUID>
    ) -> Set<UUID> {
        var newlyScored: Set<UUID> = []
        for index in rings.indices where !alreadyScored.contains(rings[index].id) {
            let ring = rings[index]
            // Downward pass through the ring's horizontal plane…
            guard previous.y > ring.position.y, current.y <= ring.position.y else { continue }
            let fraction = (previous.y - ring.position.y) / (previous.y - current.y)
            let crossing = previous + fraction * (current - previous)
            // …inside the rim (ball center comfortably within the ring).
            let planar = SIMD2(crossing.x - ring.position.x, crossing.z - ring.position.z)
            if simd_length(planar) < Self.ringRadius - ballRadius * 0.5 {
                rings[index].score += 1
                newlyScored.insert(ring.id)
                emitSound(.chime, at: ring.position, volume: 1)
                let generation = ringFlashNonce
                Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(450))
                    guard let self, self.ringFlashNonce == generation else { return }
                    self.ringFlashNonce += 1
                }
            }
        }
        return newlyScored
    }

    // MARK: Stepping

    // MARK: Sounds (data only; the renderer positions and plays them)

    private(set) var soundEvent: SpatialSoundEvent?
    private var soundCounter = 0

    private func emitSound(_ kind: SoundPalette.Sound, at position: SIMD3<Double>, volume: Double) {
        soundCounter += 1
        soundEvent = SpatialSoundEvent(id: soundCounter, kind: kind,
                                       position: position, volume: volume)
    }

    /// Advances every active flight by one rendered frame, in simulated
    /// time (dt × timeScale). Two RK4 substeps per frame; stalled frames
    /// are clamped so debugger pauses don't become physics leaps.
    func step(dt: Double) {
        guard !isPaused else { return }
        let frameDt = min(dt, 1.0 / 30.0) * timeScale
        stepRings(dt: frameDt)
        guard flights.contains(where: { $0.status == .flying || $0.status == .rolling }) else { return }

        for index in flights.indices {
            switch flights[index].status {
            case .flying: stepFlying(index: index, dt: frameDt)
            case .rolling: stepRolling(index: index, dt: frameDt)
            default: continue
            }
        }

        flights.removeAll {
            simd_length($0.state.position) > Self.escapeRadius
        }
    }

    private func stepFlying(index: Int, dt: Double) {
        var flight = flights[index]
        let drag = drag(for: flight.projectile)
        let previous = flight.state
        let substep = dt / 2
        for _ in 0..<2 {
            flight.state = Integrators.rk4Step(flight.state, dt: substep) { _, velocity in
                ProjectileMotion.acceleration(velocity: velocity, gravity: gravity, drag: drag)
            }
        }
        let previousElapsed = flight.elapsed
        flight.elapsed += dt
        flight.maxHeight = max(flight.maxHeight, flight.state.position.y)

        flight.scoredRings.formUnion(checkRings(
            previous: previous.position,
            current: flight.state.position,
            ballRadius: flight.projectile.diameter / 2,
            alreadyScored: flight.scoredRings
        ))

        // Strobe dots at exact simulated-time intervals, interpolated
        // inside the frame so their spacing genuinely encodes speed.
        while flight.elapsed >= flight.nextDotTime, flight.dots.count < Self.dotsPerFlight {
            let fraction = (flight.nextDotTime - previousElapsed) / dt
            flight.dots.append(
                previous.position + fraction * (flight.state.position - previous.position)
            )
            flight.nextDotTime += Self.dotInterval
        }

        // Wall contact: the real room pushes back (when enabled).
        if respectRoomWalls, !roomWalls.isEmpty,
           let hit = RoomWalls.strike(
               previous: previous.position, current: flight.state.position,
               velocity: flight.state.velocity,
               radius: flight.projectile.diameter / 2,
               restitution: flight.projectile.restitution,
               walls: roomWalls) {
            flight.bounces += 1
            emitSound(.thud, at: hit.position, volume: min(hit.impactSpeed / 6, 1))
            flight.state = ParticleDynamics.State(
                position: hit.position, velocity: hit.velocity)
        }
        contain(&flight)

        // Floor contact (ball center at its radius above y = 0).
        let floor = flight.projectile.diameter / 2
        if flight.state.position.y <= floor, flight.state.velocity.y < 0 {
            let dip = previous.position.y - flight.state.position.y
            let fraction = dip > 0 ? (previous.position.y - floor) / dip : 0
            let contact = previous.position + fraction * (flight.state.position - previous.position)
            let contactTime = previousElapsed + fraction * dt

            if flight.bounces == 0 {
                lastFlight = FlightSummary(
                    projectileName: flight.projectile.name,
                    range: simd_length(SIMD2(contact.x - flight.launchPoint.x,
                                             contact.z - flight.launchPoint.z)),
                    apexHeight: flight.maxHeight,
                    flightTime: contactTime,
                    wasThrown: flight.wasThrown
                )
                // Streak bookkeeping: with hoops up, every flight either
                // scored (streak grows) or missed (streak dies).
                if !rings.isEmpty {
                    if flight.scoredRings.isEmpty {
                        streak = 0
                    } else {
                        streak += 1
                        if streak > bestStreak {
                            bestStreak = streak
                            UserDefaults.standard.set(bestStreak, forKey: "kinematics.bestStreak")
                        }
                    }
                }
            }
            emitSound(.thud, at: contact,
                      volume: min(abs(flight.state.velocity.y) / 6, 1))

            let reboundSpeed = -flight.state.velocity.y * flight.projectile.restitution
            if reboundSpeed > ProjectileMotion.restSpeed {
                flight.bounces += 1
                flight.state = ParticleDynamics.State(
                    position: SIMD3(contact.x, floor, contact.z),
                    velocity: ProjectileMotion.bounce(
                        velocity: flight.state.velocity,
                        restitution: flight.projectile.restitution
                    )
                )
            } else {
                flight.state = ParticleDynamics.State(
                    position: SIMD3(contact.x, floor, contact.z),
                    velocity: SIMD3(flight.state.velocity.x, 0, flight.state.velocity.z)
                )
                flight.status = simd_length(flight.state.velocity) > 0.05 ? .rolling : .rested
            }
        }
        flights[index] = flight
    }

    /// Rolling: horizontal exponential decay (simplified rolling friction)
    /// until the ball stops.
    private func stepRolling(index: Int, dt: Double) {
        var flight = flights[index]
        let decay = exp(-1.5 * dt)
        var velocity = flight.state.velocity * decay
        velocity.y = 0
        let previous = flight.state.position
        var position = previous + dt * velocity
        position.y = flight.projectile.diameter / 2

        // Rolling balls respect walls too. They didn't — a ball that
        // had settled into a roll passed straight through the same
        // wall it had just bounced off, which read as the feature
        // simply giving up.
        if respectRoomWalls, !roomWalls.isEmpty,
           let hit = RoomWalls.strike(
               previous: previous, current: position,
               velocity: velocity,
               radius: flight.projectile.diameter / 2,
               restitution: flight.projectile.restitution * 0.5,
               walls: roomWalls) {
            position = hit.position
            position.y = flight.projectile.diameter / 2
            velocity = SIMD3(hit.velocity.x, 0, hit.velocity.z)
        }

        flight.state = ParticleDynamics.State(position: position, velocity: velocity)
        contain(&flight)
        if simd_length(velocity) < 0.05 {
            flight.state.velocity = .zero
            flight.status = .rested
        }
        flights[index] = flight
    }

    /// The invariant the segment test cannot promise on its own: a ball
    /// NEVER ends a frame outside the room. Whatever slips past the
    /// strike test — anchor churn replacing walls mid-flight, a spawn
    /// beyond a plane, numeric residue — is clamped back inside the
    /// scanned bounds with its velocity reflected. Belt and braces:
    /// the strike gives the honest bounce, this guarantees containment.
    private func contain(_ flight: inout Flight) {
        guard respectRoomWalls else { return }
        let box = roomBounds
        let r = flight.projectile.diameter / 2
        var position = flight.state.position
        var velocity = flight.state.velocity
        var corrected = false
        for axis in 0..<3 {
            let center = box.center[axis]
            let reach = box.halfExtents[axis] - r
            guard reach > 0 else { continue }
            if position[axis] > center + reach {
                position[axis] = center + reach
                if velocity[axis] > 0 { velocity[axis] = -velocity[axis] * flight.projectile.restitution }
                corrected = true
            } else if position[axis] < center - reach, axis != 1 {
                // (The floor handles the low side of y itself.)
                position[axis] = center - reach
                if velocity[axis] < 0 { velocity[axis] = -velocity[axis] * flight.projectile.restitution }
                corrected = true
            }
        }
        if corrected {
            flight.state = ParticleDynamics.State(position: position, velocity: velocity)
        }
    }

    // MARK: Reset

    /// Returns the module to its freshly-entered state — and that state
    /// is a PLAYGROUND, not an empty range.
    ///
    /// It used to open with a launcher, a ghost arc, and nothing else:
    /// no ball to throw, no hoop to aim at, and a default launch speed
    /// of 6 m/s, which at 45° carries 4.7 m — further than most rooms
    /// are long, so the very first arc left through the wall. Now it
    /// opens with hoops hung in the air, balls staged ready to grab,
    /// and a speed picked so the whole flight lands inside the room.
    func reset() {
        clearFlights()
        rings.removeAll()
        hoopsOrbit = false
        streak = 0
        launcherPosition = Self.launcherHome
        launchSpeed = Self.roomFittingSpeed
        gravity = 9.81
        airResistance = false
        // The third state a switch bank shows that reset had never
        // restored — Pendulums' `frictionOn` and Magnetism's `dynamicsOn`
        // were the other two, all found the same day. A flag with no
        // visible control drifts out of reset and stays wrong
        // indefinitely, because nothing in the room contradicts it; the
        // moment it gets a lamp, the lamp makes the claim every frame.
        // Walls off + Reset used to hand back a room balls flew straight
        // out of.
        respectRoomWalls = true
        windSpeed = 0
        windDirectionDegrees = 0
        timeScale = 1.0
        isPaused = false
        throwBoost = 1.0
        kind = .golfBall
        customMass = 0.25
        customDiameter = 0.10
        lastCatch = nil
        catchingEnabled = true
        aimDirection = Self.direction(elevationDegrees: 45, azimuthDegrees: 0)

        // The welcome scene: one shot already in the air, from the
        // launcher's own muzzle — every ball in this module is born at
        // the barrel tip, never conjured mid-air. (Floating staged
        // basketballs and pre-hung hoops used to open here; they read
        // as things spawning out of nowhere.)
        fire()
    }

    /// A launch speed whose 45° range fits inside a typical room.
    ///
    /// Range at 45° is v²/g, so v = √(g · R). Aiming for a 2.5 m range
    /// puts the landing point comfortably short of the far wall and
    /// keeps the whole parabola — apex included — inside the space the
    /// user can actually see.
    nonisolated static let roomFittingSpeed = (9.81 * 2.5).squareRoot()
}
