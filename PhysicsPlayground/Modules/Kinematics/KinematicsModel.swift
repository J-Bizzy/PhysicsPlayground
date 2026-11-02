//
//  KinematicsModel.swift
//  Physics Playground — Kinematics: app state for room-scale projectile motion.
//
//  Physics space is the room: 1:1 immersive-space coordinates, real floor at y = 0; a ball that leaves the room is a bug, not a setting.
//  Strobe dots are equal-Δt in simulated time. The hoop/scoring machinery is dormant: off the surface, kept in the model.
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
    /// Shared `PhysicsCore.SurfaceGravity` presets (zero-g included).
    nonisolated static let gravityPresets = SurfaceGravity.all
    nonisolated static let windSpeedRange = 0.0...15.0        // m/s
    /// The custom ball's mass. Its diameter stays 10 cm: drag depends on
    /// diameter, so "same size, different mass" is the clean experiment.
    nonisolated static let customMassRange = 0.05...5.0        // kg
    nonisolated static let timeScaleRange = 0.1...2.0

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

    nonisolated enum ProjectileKind: String, CaseIterable, Identifiable {
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
    /// The custom ball, editable live.
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

    // MARK: Display layers (More), off until asked for

    /// The predicted arc and its apex and landing marks, and the vacuum
    /// ghost while the air is on. Off by default since 2026-10-17: the room
    /// is the launcher and the balls, and the prediction is a request.
    var showsTrajectory = false
    /// Every number in the room: the bead's angle and speed, the apex and
    /// landing labels, and the callouts on a flying, thrown or caught ball.
    /// Off by default; More's Values keep the full record either way.
    var showsNumbers = false

    /// Whether flights bounce off walls and ceiling. Defaults on; the unscanned box stands in until the shared room model supplies detected walls.
    var respectRoomWalls = true
    var roomWalls: [RoomWalls.Wall] = RoomWalls.box(of: .unscanned)
    /// The walls a flying ball bounces off: everything but an upward-facing
    /// surface, which is a support and goes through the floor law (a ball
    /// can rest on a table).
    private var strikeWalls: [RoomWalls.Wall] { roomWalls.filter { $0.normal.y < 0.9 } }
    /// The height of whatever the ball would land on directly below
    /// `point`: the highest upward-facing wall under it, else the floor.
    func supportHeight(under point: SIMD3<Double>) -> Double {
        var best = 0.0
        for wall in roomWalls where wall.normal.y >= 0.9 && wall.center.y <= point.y + 1e-6 {
            let offset = point - wall.center
            guard abs(simd_dot(offset, wall.uAxis)) <= wall.halfU,
                  abs(simd_dot(offset, wall.vAxis)) <= wall.halfV else { continue }
            best = max(best, wall.center.y)
        }
        return best
    }
    /// The hands as things a ball can bounce off, in module space, fed
    /// by the SpaceView each frame. A hand moving faster than `swatSpeed`
    /// is a swat; slower, it catches (`catchBalls`).
    var handStrikes: [SphereStrike.Sphere] = []
    nonisolated static let swatSpeed = 1.2                    // m/s
    /// The room's box for the containment clamp — no ball ever ends a frame outside the room.
    /// Nil in deep space, where there is no room to be outside (`RoomModel.tangible`).
    var roomBounds: RoomBox? = .unscanned

    init() {
        reset()

        // `-kinWalls 1`: seed a synthetic wall and fire at it (real walls are device-only); at 1.4 m the welcome shot reaches it.
        #if DEBUG
        let kinWalls = UserDefaults.standard.integer(forKey: "kinWalls")
        if kinWalls > 0 {
            roomWalls = [RoomWalls.Wall(
                center: SIMD3(1.4, 1.5, -0.9), normal: SIMD3(1, 0, 0),
                uAxis: SIMD3(0, 0, 1), vAxis: SIMD3(0, 1, 0),
                halfU: 2.5, halfV: 1.5)]
            fire()
            if kinWalls >= 2 {
                // `-kinWalls 2`: also a 12 m/s ball at the wall — the fast regime the bounce fixes exist for; the gentle shot proves nothing about tunnelling.
                let savedSpeed = launchSpeed
                launchSpeed = 12
                setAim(elevationDegrees: 12, azimuthDegrees: 0)
                fire()
                launchSpeed = savedSpeed
            }
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

    // MARK: Time Capsule

    @ObservationIgnored var capsule = TimeCapsule<CapsuleSnapshot>()
    @ObservationIgnored var capsuleClock = 0.0
    var scrubTime: Double?
    var scrubNonce = 0

    // MARK: Launcher

    var launcherPosition = KinematicsModel.launcherHome
    var launchSpeed = 6.0
    /// Unit aim vector. Negative elevation is allowed — the launcher can sit high and fire downward.
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

    /// Aim from the bead drag: `point` is the hand in room space; aim the launcher toward it (azimuth free).
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

    /// Live predicted trajectory, bounces included — a few hundred RK4 steps, fine to recompute on read.
    var prediction: ProjectileMotion.Trajectory {
        ProjectileMotion.simulate(
            from: muzzlePoint,
            launchVelocity: launchSpeed * aimDirection,
            gravity: gravity,
            drag: drag(for: projectile),
            restitution: projectile.restitution,
            maxBounces: 4,
            walls: respectRoomWalls ? roomWalls : [],
            // The ball's own radius — omitted, the arc is drawn for a point and corners short of every wall and floor bounce.
            radius: projectile.diameter / 2,
            maxDuration: 12
        )
    }

    var terminalSpeed: Double? {
        airResistance
            ? ProjectileMotion.terminalSpeed(projectile: projectile, gravity: gravity)
            : nil
    }

    // MARK: Flights

    nonisolated struct Flight: Identifiable, Equatable {
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
        /// Each flight can pass each hoop once — a bounce back up through the rim must not count again.
        var passedRings: Set<UUID> = []
        /// Where and how a hand let this ball go; nil for a launcher's shot,
        /// and cleared while the ball is held again.
        var release: Release?
        /// Which launch this was, counting up across the session: the order
        /// flights left, which their place in `flights` is not (a rethrown
        /// ball keeps its slot). The strobe keeps the newest one's dots.
        var launchSerial = 0

        /// A throw's initial conditions: the ones your arm set.
        nonisolated struct Release: Equatable {
            var position: SIMD3<Double>
            var velocity: SIMD3<Double>
            var speed: Double { simd_length(velocity) }
            /// Above the horizontal, degrees.
            var elevationDegrees: Double {
                atan2(velocity.y, simd_length(SIMD2(velocity.x, velocity.z))) * 180 / .pi
            }
        }

        enum Status: Equatable {
            /// Hovering, waiting to be grabbed.
            case staged
            case held
            case flying
            /// On the floor, shedding the last of its speed.
            case rolling
            case rested
        }
        var status: Status = .staged
    }

    private(set) var flights: [Flight] = []

    nonisolated struct FlightSummary: Equatable {
        var projectileName: String
        var range: Double
        var apexHeight: Double
        var flightTime: Double
        var wasThrown: Bool
    }

    private(set) var lastFlight: FlightSummary?

    // MARK: Catching

    /// Fingertip-to-ball catch distance — generous, because a catch is a hand, not a point.
    nonisolated static let catchRadius = 0.14

    /// The last catch, for the callout that appears at the caught ball.
    nonisolated struct Catch: Equatable {
        var id: UUID
        var speed: Double
        var height: Double
        var flightTime: Double
        var kineticEnergy: Double
        var position: SIMD3<Double>
    }
    private(set) var lastCatch: Catch?
    var catchingEnabled = true

    /// Catches any flying ball that reaches an open hand: freezes it, records that instant, stages it to rethrow.
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

    /// Hand-motion samples for the held ball (shared `PhysicsCore.ThrowSampler`),
    /// kept long enough for `releaseVelocity` to look back past the
    /// follow-through.
    private var throwSampler = ThrowSampler(window: 0.16)
    private var heldFlightID: UUID?
    /// The last `launchSerial` handed out.
    private var launchCounter = 0
    private func nextLaunchSerial() -> Int {
        launchCounter += 1
        return launchCounter
    }
    /// The ball most recently thrown by hand — what the release callout and
    /// More's release readings read. A pointer into `flights`, so out of
    /// the snapshot: a restore that loses the ball loses the readout.
    private(set) var latestThrowID: UUID?
    var latestThrow: Flight? {
        guard let latestThrowID else { return nil }
        return flights.first { $0.id == latestThrowID && $0.release != nil }
    }
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

    func fire() {
        // Monkey and hunter: every hoop armed to drop is re-hung and let go the
        // instant the shot leaves, so the ball and the hoop fall the same and
        // meet.
        for index in rings.indices where rings[index].dropOnFire {
            rings[index].position = rings[index].anchor
            rings[index].falling = true
            rings[index].fallSpeed = 0
        }
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
        flight.launchSerial = nextLaunchSerial()
        insertFlight(flight)
        emitSound(.launch, at: muzzlePoint, volume: 0.8)
    }

    /// Spawns a fresh ball hovering at `ballSpawnPoint`, ready to grab and throw.
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

    /// Spawns a staged ball at the hand (the well's spawn), inert until a throw, wearing the ball fan's current kind.
    @discardableResult
    func spawnBall(at position: SIMD3<Double>) -> UUID {
        let flight = Flight(
            id: UUID(),
            projectile: projectile,
            state: ParticleDynamics.State(position: position))
        insertFlight(flight)
        return flight.id
    }

    #if DEBUG
    /// A throw without a hand: the ball leaves `point` at `velocity`, exactly
    /// as `releaseBall` would have let it go. `-kinThrow`'s, for a still of a
    /// thrown ball and its release callout, which the simulator has no hand for.
    @discardableResult
    func stageThrow(from point: SIMD3<Double>, velocity: SIMD3<Double>) -> UUID {
        let id = spawnBall(at: point)
        guard let index = flights.firstIndex(where: { $0.id == id }) else { return id }
        flights[index].state.velocity = velocity
        flights[index].status = .flying
        flights[index].maxHeight = point.y
        flights[index].launchPoint = point
        flights[index].wasThrown = true
        flights[index].launchSerial = nextLaunchSerial()
        flights[index].release = Flight.Release(position: point, velocity: velocity)
        latestThrowID = id
        return id
    }
    #endif

    func clearFlights() {
        flights.removeAll()
        lastFlight = nil
        latestThrowID = nil
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
        flights[index].passedRings.removeAll()
        flights[index].release = nil
    }

    /// `timestamp` defaults to the wall clock; tests inject exact times.
    func holdBall(id: UUID, at position: SIMD3<Double>, timestamp: Double = CACurrentMediaTime()) {
        guard let index = flights.firstIndex(where: { $0.id == id }) else { return }
        flights[index].state = ParticleDynamics.State(position: position)
        guard heldFlightID == id else { return }
        throwSampler.record(position, at: timestamp)
    }

    /// Releases the held ball with the velocity the hand let go at — its
    /// fastest stretch just before the pinch was reported open, not the
    /// follow-through after (`ThrowSampler.releaseVelocity`).
    func releaseBall(id: UUID, timestamp: Double = CACurrentMediaTime()) {
        guard let index = flights.firstIndex(where: { $0.id == id }) else { return }
        defer {
            heldFlightID = nil
            throwSampler.reset()
        }

        guard let handVelocity = throwSampler.releaseVelocity(at: timestamp) else {
            flights[index].status = .staged
            return
        }

        let velocity = throwBoost * handVelocity
        flights[index].state.velocity = velocity
        flights[index].status = .flying
        flights[index].maxHeight = flights[index].state.position.y
        flights[index].launchPoint = flights[index].state.position
        flights[index].wasThrown = true
        flights[index].launchSerial = nextLaunchSerial()
        flights[index].release = Flight.Release(position: flights[index].state.position,
                                                velocity: velocity)
        latestThrowID = id
        emitSound(.whoosh, at: flights[index].state.position,
                  volume: min(simd_length(velocity) / 8, 1))
    }

    /// Sets down the ball a hand holds, where it is and with no throw.
    /// Leaving the lab mid-carry never delivers the gesture's end, and a
    /// ball left `.held` hangs glowing in the air on the next visit.
    func releaseAll() {
        guard let id = heldFlightID else { return }
        // No samples, no velocity: the release is a set-down, not a throw.
        throwSampler.reset()
        releaseBall(id: id)
    }

    // MARK: Hoops

    nonisolated struct Ring: Identifiable, Equatable {
        let id: UUID
        /// Where the user placed it (the orbit's center when hoops move).
        var anchor: SIMD3<Double>
        var position: SIMD3<Double>
        var phase: Double
        /// Balls that have passed down through it — what lights it.
        var passes = 0
        /// Monkey and hunter: armed, the hoop lets go the
        /// instant a shot leaves the launcher and falls with the ball.
        var dropOnFire = false
        var falling = false
        var fallSpeed = 0.0
    }
    /// Where a dropped hoop comes to rest: lying on the floor.
    nonisolated static let fallenHoopHeight = 0.02

    private(set) var rings: [Ring] = []
    /// Bumped shortly after a pass so observers re-render the flash off.
    private(set) var ringFlashNonce = 0

    /// Moving targets: hoops circle their anchors — the skill mode.
    var hoopsOrbit = false
    nonisolated static let hoopOrbitRadius = 0.25
    nonisolated static let hoopOrbitSpeed = 0.55  // rad/s (simulated time)


    func addRing() {
        guard rings.count < Self.ringBudget else { return }
        let anchor = Self.ringSpawnPoint
            + SIMD3(Double(rings.count) * 0.55, Double(rings.count) * 0.15, 0)
        rings.append(Ring(id: UUID(), anchor: anchor, position: anchor,
                          phase: Double(rings.count) * 2.1))
    }

    /// A hoop born at the hand — the well's spawn. Nil at the budget, which
    /// is the well's cue to fade in refusal. Held no lower than `moveRing`
    /// allows.
    @discardableResult
    func addRing(at point: SIMD3<Double>) -> UUID? {
        guard rings.count < Self.ringBudget else { return nil }
        var clamped = point
        clamped.y = max(clamped.y, 0.3)
        let ring = Ring(id: UUID(), anchor: clamped, position: clamped,
                        phase: Double(rings.count) * 2.1)
        rings.append(ring)
        return ring.id
    }

    func removeLastRing() {
        guard !rings.isEmpty else { return }
        rings.removeLast()
    }

    /// The hoop's own Delete petal.
    func removeRing(id: UUID) {
        rings.removeAll { $0.id == id }
        if aimTargetID == id { aimTargetID = nil }
    }

    // MARK: Aiming at a hoop

    /// Which hoop the launcher is being aimed at — a selection mirrored from
    /// the view's ring state, so the renderer can draw the two ghost arcs
    /// and the callout. Out of the snapshot; cleared by `reset()`.
    var aimTargetID: UUID?

    enum AimSolution: Equatable { case low, high }

    private struct AimKey: Equatable {
        var hoop: SIMD3<Double>
        var launcher: SIMD3<Double>
        var speed: Double
        var gravity: Double
        var air: Bool
        var wind: SIMD3<Double>
        var projectile: Projectile
    }
    @ObservationIgnored private var aimCache: (key: AimKey, roots: (low: Double, high: Double)?)?

    /// Both launch angles, radians above horizontal, that put the ball
    /// through `ringID` (low arc first), or nil when out of range. Exact in
    /// a vacuum, numerical with the air on. Each root is refined against
    /// its own muzzle in three fixed-point passes. Memoised: the drag
    /// search costs tens of simulations and a petal asks every frame.
    func solutions(for ringID: UUID) -> (low: Double, high: Double)? {
        guard let ring = rings.first(where: { $0.id == ringID }) else { return nil }
        let key = AimKey(hoop: ring.position, launcher: launcherPosition,
                         speed: launchSpeed, gravity: gravity, air: airResistance,
                         wind: wind, projectile: projectile)
        if let cached = aimCache, cached.key == key { return cached.roots }
        let roots = computeSolutions(hoop: ring.position)
        aimCache = (key, roots)
        return roots
    }

    private func computeSolutions(hoop: SIMD3<Double>) -> (low: Double, high: Double)? {
        let flat = SIMD2(hoop.x - launcherPosition.x, hoop.z - launcherPosition.z)
        guard simd_length(flat) > 1e-6 else { return nil }
        let azimuthDegrees = atan2(flat.y, flat.x) * 180 / .pi
        let drag = drag(for: projectile)
        func roots(fromMuzzle muzzle: SIMD3<Double>) -> (low: Double, high: Double)? {
            let x = simd_length(SIMD2(hoop.x - muzzle.x, hoop.z - muzzle.z))
            let y = hoop.y - muzzle.y
            if let drag {
                return ProjectileMotion.launchAnglesWithDrag(
                    toReachHorizontal: x, vertical: y, speed: launchSpeed, gravity: gravity,
                    drag: drag, radius: projectile.diameter / 2)
            }
            return ProjectileMotion.launchAngles(
                toReachHorizontal: x, vertical: y, speed: launchSpeed, gravity: gravity)
        }
        func refine(_ pick: ((low: Double, high: Double)) -> Double) -> Double? {
            var muzzle = launcherPosition
            var angle: Double?
            for _ in 0..<3 {
                guard let found = roots(fromMuzzle: muzzle) else { return nil }
                let picked = pick(found)
                angle = picked
                muzzle = launcherPosition + Self.barrelLength * Self.direction(
                    elevationDegrees: picked * 180 / .pi, azimuthDegrees: azimuthDegrees)
            }
            return angle
        }
        guard let low = refine({ $0.low }), let high = refine({ $0.high }) else { return nil }
        return (min(low, high), max(low, high))
    }

    /// The bearing from the launcher to a hoop, in `direction`'s degrees.
    private func azimuthDegrees(to hoop: SIMD3<Double>) -> Double {
        atan2(hoop.z - launcherPosition.z, hoop.x - launcherPosition.x) * 180 / .pi
    }

    /// Points the launcher along the chosen solution for `ringID`. A
    /// no-op when the hoop is out of range — there is nothing to aim at.
    func aim(atSolution solution: AimSolution, for ringID: UUID) {
        guard let ring = rings.first(where: { $0.id == ringID }),
              let roots = solutions(for: ringID) else { return }
        let elevation = (solution == .low ? roots.low : roots.high) * 180 / .pi
        setAim(elevationDegrees: elevation, azimuthDegrees: azimuthDegrees(to: ring.position))
    }

    /// The whole flight at one solution — bounces, walls and any
    /// cross-wind included — so the ghost shows exactly where that angle
    /// sends the ball, including a miss the in-plane solve cannot see.
    func solutionArc(_ solution: AimSolution, for ringID: UUID) -> ProjectileMotion.Trajectory? {
        guard let ring = rings.first(where: { $0.id == ringID }),
              let roots = solutions(for: ringID) else { return nil }
        let direction = Self.direction(
            elevationDegrees: (solution == .low ? roots.low : roots.high) * 180 / .pi,
            azimuthDegrees: azimuthDegrees(to: ring.position))
        return ProjectileMotion.simulate(
            from: launcherPosition + Self.barrelLength * direction,
            launchVelocity: launchSpeed * direction,
            gravity: gravity,
            drag: drag(for: projectile),
            restitution: projectile.restitution,
            maxBounces: 4,
            walls: respectRoomWalls ? roomWalls : [],
            radius: projectile.diameter / 2,
            maxDuration: 12)
    }

    /// The arc the same launch would follow in a vacuum, drawn faintly
    /// beside the real one while the air is on, so drag is the gap between
    /// them. Nil with the air off.
    var vacuumPrediction: ProjectileMotion.Trajectory? {
        guard airResistance else { return nil }
        return ProjectileMotion.simulate(
            from: muzzlePoint,
            launchVelocity: launchSpeed * aimDirection,
            gravity: gravity,
            drag: nil,
            restitution: projectile.restitution,
            maxBounces: 4,
            walls: respectRoomWalls ? roomWalls : [],
            radius: projectile.diameter / 2,
            maxDuration: 12)
    }

    func moveRing(id: UUID, to point: SIMD3<Double>) {
        guard let index = rings.firstIndex(where: { $0.id == id }) else { return }
        var clamped = point
        clamped.y = max(clamped.y, 0.3)
        rings[index].anchor = clamped
        // A hand on a hoop ends its fall — it is placed, not dropped.
        rings[index].falling = false
        rings[index].fallSpeed = 0
        if !hoopsOrbit {
            rings[index].position = clamped
        }
    }

    /// The hoop's "Drop when fired" petal. Disarming re-hangs it.
    func setDropOnFire(id: UUID, _ armed: Bool) {
        guard let index = rings.firstIndex(where: { $0.id == id }) else { return }
        rings[index].dropOnFire = armed
        if !armed {
            rings[index].falling = false
            rings[index].fallSpeed = 0
            rings[index].position = rings[index].anchor
        }
    }

    /// Advances hoop motion (independent of whether anything is flying).
    private func stepRings(dt: Double) {
        for index in rings.indices {
            if rings[index].falling {
                // Free fall in a vacuum: the demo's claim is that hoop and ball fall
                // the same, and drag on the hoop would break it.
                rings[index].fallSpeed += gravity * dt
                rings[index].position.y -= rings[index].fallSpeed * dt
                if rings[index].position.y <= Self.fallenHoopHeight {
                    rings[index].position.y = Self.fallenHoopHeight
                    rings[index].falling = false
                    rings[index].fallSpeed = 0
                }
                continue
            }
            if hoopsOrbit {
                rings[index].phase += Self.hoopOrbitSpeed * dt
                rings[index].position = rings[index].anchor + SIMD3(
                    Self.hoopOrbitRadius * cos(rings[index].phase),
                    0,
                    Self.hoopOrbitRadius * sin(rings[index].phase)
                )
            } else if !rings[index].dropOnFire,
                      rings[index].position != rings[index].anchor {
                // Orbit switched off: back to the anchor, except for an armed hoop,
                // which lies where it fell until the next shot re-hangs it.
                rings[index].position = rings[index].anchor
            }
        }
    }

    /// Returns the hoops newly passed by this segment of flight.
    private func checkRings(
        previous: SIMD3<Double>,
        current: SIMD3<Double>,
        ballRadius: Double,
        alreadyPassed: Set<UUID>
    ) -> Set<UUID> {
        var newlyPassed: Set<UUID> = []
        for index in rings.indices where !alreadyPassed.contains(rings[index].id) {
            let ring = rings[index]
            let met: Bool
            if ring.falling {
                // Falling with the ball, the hoop is met wherever the two coincide.
                met = simd_length(current - ring.position) < Self.ringRadius - ballRadius * 0.5
            } else {
                // Downward pass through the ring's horizontal plane…
                guard previous.y > ring.position.y, current.y <= ring.position.y else { continue }
                let fraction = (previous.y - ring.position.y) / (previous.y - current.y)
                let crossing = previous + fraction * (current - previous)
                // …inside the rim (ball center comfortably within the ring).
                let planar = SIMD2(crossing.x - ring.position.x, crossing.z - ring.position.z)
                met = simd_length(planar) < Self.ringRadius - ballRadius * 0.5
            }
            if met {
                rings[index].passes += 1
                newlyPassed.insert(ring.id)
                emitSound(.chime, at: ring.position, volume: 1)
                let generation = ringFlashNonce
                Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(450))
                    guard let self, self.ringFlashNonce == generation else { return }
                    self.ringFlashNonce += 1
                }
            }
        }
        return newlyPassed
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

    /// Advances flights one rendered frame in simulated time (dt × timeScale); two RK4 substeps, stalled frames clamped.
    func step(dt: Double) {
        guard !isPaused else { return }
        let frameDt = min(dt, 1.0 / 30.0) * timeScale
        // Record after the step, in wall-clock seconds — the rail's unit must mean the same on every bench.
        defer { recordCapsuleFrame(dt: min(dt, 1.0 / 30.0)) }
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

        flight.passedRings.formUnion(checkRings(
            previous: previous.position,
            current: flight.state.position,
            ballRadius: flight.projectile.diameter / 2,
            alreadyPassed: flight.passedRings
        ))

        // Strobe dots at exact simulated-time intervals, interpolated inside the frame so spacing genuinely encodes speed.
        while flight.elapsed >= flight.nextDotTime, flight.dots.count < Self.dotsPerFlight {
            let fraction = (flight.nextDotTime - previousElapsed) / dt
            flight.dots.append(
                previous.position + fraction * (flight.state.position - previous.position)
            )
            flight.nextDotTime += Self.dotInterval
        }

        // Wall contact: step time left after contact runs along the reflection and can strike again (a corner takes two bounces in one frame); bounded so a wedge never hangs a frame.
        if respectRoomWalls, !roomWalls.isEmpty {
            let walls = strikeWalls
            var segmentStart = previous.position
            var timeLeft = dt
            for _ in 0..<3 {
                guard let hit = RoomWalls.strike(
                    previous: segmentStart, current: flight.state.position,
                    velocity: flight.state.velocity,
                    radius: flight.projectile.diameter / 2,
                    restitution: flight.projectile.restitution,
                    walls: walls) else { break }
                flight.bounces += 1
                emitSound(.thud, at: hit.position, volume: min(hit.impactSpeed / 6, 1))
                timeLeft *= (1 - hit.t)
                flight.state = ParticleDynamics.State(
                    position: hit.position + hit.velocity * timeLeft,
                    velocity: hit.velocity)
                segmentStart = hit.position
                if timeLeft <= 1e-6 { break }
            }
        }
        // A hand in the way: an open hand swats a ball the way a wall bounces
        // it, plus the hand's own motion. A slow hand catches instead.
        if !handStrikes.isEmpty,
           let hit = SphereStrike.strike(
               previous: previous.position, current: flight.state.position,
               velocity: flight.state.velocity,
               radius: flight.projectile.diameter / 2,
               restitution: flight.projectile.restitution,
               spheres: handStrikes, dt: dt) {
            flight.bounces += 1
            flight.wasThrown = true
            emitSound(.thud, at: hit.position, volume: min(hit.impactSpeed / 6, 1))
            flight.state = ParticleDynamics.State(
                position: hit.position + hit.velocity * dt * (1 - hit.t),
                velocity: hit.velocity)
        }
        contain(&flight)

        // Floor contact: the ball's centre at its radius above whatever
        // is under it — the floor, or a table it is falling onto.
        let floor = supportHeight(under: previous.position) + flight.projectile.diameter / 2
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

    /// Rolling: horizontal exponential decay until the ball stops.
    private func stepRolling(index: Int, dt: Double) {
        var flight = flights[index]
        let decay = exp(-1.5 * dt)
        var velocity = flight.state.velocity * decay
        velocity.y = 0
        let previous = flight.state.position
        let radius = flight.projectile.diameter / 2
        var position = previous + dt * velocity
        let supportBefore = supportHeight(under: previous)
        // Rolled off the edge: the surface under the ball is lower than the one
        // it rolled on, so it is flying again.
        let supportAfter = supportHeight(under: position)
        if supportAfter < supportBefore - 0.02 {
            flight.status = .flying
            flight.state = ParticleDynamics.State(
                position: SIMD3(position.x, supportBefore + radius, position.z),
                velocity: velocity)
            flights[index] = flight
            return
        }
        position.y = supportAfter + radius

        // Rolling balls respect walls too.
        if respectRoomWalls, !roomWalls.isEmpty,
           let hit = RoomWalls.strike(
               previous: previous, current: position,
               velocity: velocity,
               radius: radius,
               restitution: flight.projectile.restitution * 0.5,
               walls: strikeWalls) {
            position = hit.position
            position.y = supportHeight(under: position) + radius
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

    /// Invariant: a ball never ends a frame outside the room — whatever slips past the strike test is clamped back inside `roomBounds` with velocity reflected.
    private func contain(_ flight: inout Flight) {
        guard respectRoomWalls, let box = roomBounds else { return }
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

    /// Returns the module to its freshly-entered state — a playground, not an empty range.
    func reset() {
        clearFlights()
        rings.removeAll()
        hoopsOrbit = false
        launcherPosition = Self.launcherHome
        launchSpeed = Self.roomFittingSpeed
        gravity = 9.81
        airResistance = false
        showsTrajectory = false
        showsNumbers = false
        // Plate-backed flag — reset must restore it (ResetCoverageTests reflects over every Bool).
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
        aimTargetID = nil
        aimCache = nil
        clearCapsule()
        // No welcome shot since 2026-10-17 (owner's call): throwing is the
        // main act, so the room opens quiet with a ball waiting at the hand
        // (the ball well's mouth) and the first flight is the one you throw.
    }

    /// Launch speed whose 45° range (v²/g) is 2.5 m, so the whole parabola fits a typical room.
    nonisolated static let roomFittingSpeed = (9.81 * 2.5).squareRoot()
}

// MARK: - Time Capsule

extension KinematicsModel: TimeCapsuleRecording {
    /// The experiment, not the observer: flights, hoops, aim, environment.
    /// Excluded: room walls/bounds (the live room feeds them), settings, sounds.
    nonisolated struct CapsuleSnapshot: Equatable {
        var flights: [Flight]
        var rings: [Ring]
        var lastFlight: FlightSummary?
        var lastCatch: Catch?
        var launcherPosition: SIMD3<Double>
        var aimDirection: SIMD3<Double>
        var launchSpeed: Double
        var gravity: Double
        var airResistance: Bool
        var windSpeed: Double
        var windDirectionDegrees: Double
        var kind: ProjectileKind
        var customMass: Double
        var customDiameter: Double
    }

    func captureCapsuleSnapshot() -> CapsuleSnapshot {
        CapsuleSnapshot(
            flights: flights,
            rings: rings,
            lastFlight: lastFlight,
            lastCatch: lastCatch,
            launcherPosition: launcherPosition,
            aimDirection: aimDirection,
            launchSpeed: launchSpeed,
            gravity: gravity,
            airResistance: airResistance,
            windSpeed: windSpeed,
            windDirectionDegrees: windDirectionDegrees,
            kind: kind,
            customMass: customMass,
            customDiameter: customDiameter
        )
    }

    /// Recorded flight polylines for the scrub tube — strided down from 90 Hz, near-coincident points dropped so a settling ball doesn't stack degenerate segments.
    func capsuleRecordedPaths(stride: Int = 6) -> [[SIMD3<Float>]] {
        guard scrubTime != nil, let span = capsule.span else { return [] }
        var paths: [UUID: [SIMD3<Float>]] = [:]
        for frame in capsule.frames(in: span, stride: stride) {
            for flight in frame.snapshot.flights
            where flight.status == .flying || flight.status == .rolling {
                let point = SIMD3<Float>(flight.state.position)
                if let last = paths[flight.id]?.last,
                   simd_distance(last, point) < 0.004 { continue }
                paths[flight.id, default: []].append(point)
            }
        }
        return paths.values.filter { $0.count >= 2 }
    }

    func restoreCapsuleSnapshot(_ snapshot: CapsuleSnapshot) {
        var restored = snapshot.flights
        // The past hand is gone: a then-held ball comes back staged.
        for index in restored.indices where restored[index].status == .held {
            restored[index].status = .staged
        }
        // The present hand wins: a live-held ball is never moved by a restore.
        if let heldID = heldFlightID,
           let live = flights.first(where: { $0.id == heldID }) {
            if let index = restored.firstIndex(where: { $0.id == heldID }) {
                restored[index] = live
            } else {
                restored.append(live)
            }
        }
        flights = restored
        rings = snapshot.rings
        lastFlight = snapshot.lastFlight
        lastCatch = snapshot.lastCatch
        launcherPosition = snapshot.launcherPosition
        aimDirection = snapshot.aimDirection
        launchSpeed = snapshot.launchSpeed
        gravity = snapshot.gravity
        airResistance = snapshot.airResistance
        windSpeed = snapshot.windSpeed
        windDirectionDegrees = snapshot.windDirectionDegrees
        kind = snapshot.kind
        customMass = snapshot.customMass
        customDiameter = snapshot.customDiameter
    }
}
