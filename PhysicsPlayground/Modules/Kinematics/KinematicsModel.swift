//
//  KinematicsModel.swift
//  Physics Playground — Kinematics module
//
//  App state for projectile motion. All physics happens in true SI units
//  in "physics space" — launch point at the origin, +y up, +x downrange,
//  ground at y = 0 — and only the renderer scales it down to the 1:10
//  tabletop diorama. Panel numbers are therefore always real-world values.
//
//  In-flight projectiles step with RK4 (drag is velocity-dependent, so
//  velocity Verlet doesn't apply). Each flight drops "strobe dots" at
//  equal time intervals — the classic strobe-photo view of kinematics:
//  wider spacing means faster.
//

import Foundation
import Observation
import PhysicsCore
import simd

@MainActor
@Observable
final class KinematicsModel {
    // MARK: Diorama geometry (physics meters; display = physics × displayScale)

    nonisolated static let displayScale = 0.1
    /// Table bounds. The launch point is at x = 0; the plate runs a little
    /// behind it and 12.5 m downrange (1.25 m at diorama scale).
    nonisolated static let tableMinX = -1.5
    nonisolated static let tableMaxX = 12.5
    nonisolated static let tableHalfDepth = 3.6

    // MARK: Control ranges

    nonisolated static let speedRange = 1.0...10.0          // m/s
    nonisolated static let elevationRangeDegrees = 5.0...85.0
    nonisolated static let maxAzimuthDegrees = 30.0
    nonisolated static let gravityRange = 1.0...30.0        // m/s²
    nonisolated static let gravityPresets: [(name: String, value: Double)] = [
        ("Moon", 1.62), ("Earth", 9.81), ("Jupiter", 24.79),
    ]

    // MARK: Budgets (degrade by not drawing, never by dropping frames)

    nonisolated static let flightBudget = 8
    nonisolated static let dotsPerFlight = 60
    /// Strobe interval: one dot per 1/15 s of flight.
    nonisolated static let dotInterval = 1.0 / 15.0

    // MARK: Projectile selection

    enum ProjectileKind: String, CaseIterable, Identifiable {
        case tableTennisBall, basketball, golfBall, cannonball

        var id: String { rawValue }

        var projectile: Projectile {
            switch self {
            case .tableTennisBall: .tableTennisBall
            case .basketball: .basketball
            case .golfBall: .golfBall
            case .cannonball: .cannonball
            }
        }
    }

    // MARK: Launch state

    var launchSpeed = 7.0
    var gravity = 9.81
    var airResistance = false
    var kind: ProjectileKind = .basketball
    /// Unit aim vector from the muzzle (+x downrange, +y up).
    private(set) var aimDirection = KinematicsModel.direction(elevationDegrees: 45, azimuthDegrees: 0)

    // MARK: Aiming

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
        let azimuth = min(max(azimuthDegrees, -Self.maxAzimuthDegrees), Self.maxAzimuthDegrees)
        aimDirection = Self.direction(elevationDegrees: elevation, azimuthDegrees: azimuth)
    }

    /// Aim from the in-space bead drag: `point` is where the user's hand
    /// is, in physics space relative to the muzzle. Elevation and azimuth
    /// are clamped so the launcher can't point into the table or off it.
    func aim(toward point: SIMD3<Double>) {
        guard simd_length(point) > 0.05 else { return }
        let direction = simd_normalize(point)
        setAim(
            elevationDegrees: asin(max(-1, min(1, direction.y))) * 180 / .pi,
            azimuthDegrees: atan2(direction.z, direction.x) * 180 / .pi
        )
    }

    // MARK: Derived launch quantities

    var launchVelocity: SIMD3<Double> { launchSpeed * aimDirection }

    var drag: ProjectileMotion.Drag? {
        airResistance ? ProjectileMotion.Drag(projectile: kind.projectile) : nil
    }

    /// The live predicted trajectory for the current aim — a few hundred
    /// RK4 steps, microseconds of work, so it's fine to recompute on read.
    var prediction: ProjectileMotion.Trajectory {
        ProjectileMotion.simulate(
            launchVelocity: launchVelocity, gravity: gravity, drag: drag, maxDuration: 12
        )
    }

    var terminalSpeed: Double? {
        airResistance
            ? ProjectileMotion.terminalSpeed(projectile: kind.projectile, gravity: gravity)
            : nil
    }

    // MARK: Flights

    struct Flight: Identifiable, Equatable {
        let id: UUID
        let kind: ProjectileKind
        var state: ParticleDynamics.State
        var elapsed = 0.0
        var maxHeight = 0.0
        var nextDotTime = KinematicsModel.dotInterval
        /// Strobe positions at equal time intervals.
        var dots: [SIMD3<Double>] = []

        enum Status: Equatable { case flying, landed, offTable }
        var status: Status = .flying
    }

    private(set) var flights: [Flight] = []

    struct FlightSummary: Equatable {
        var projectileName: String
        var range: Double
        var apexHeight: Double
        var flightTime: Double
        var wentOffTable: Bool
    }

    private(set) var lastFlight: FlightSummary?

    func fire() {
        if flights.count >= Self.flightBudget {
            flights.removeFirst()
        }
        flights.append(Flight(
            id: UUID(),
            kind: kind,
            state: ParticleDynamics.State(position: .zero, velocity: launchVelocity)
        ))
    }

    func clearFlights() {
        flights.removeAll()
        lastFlight = nil
    }

    /// Advances every in-flight projectile by one rendered frame. Two RK4
    /// substeps per frame; a stalled frame is clamped so debugger pauses
    /// don't become one giant physics leap.
    func step(dt: Double) {
        guard flights.contains(where: { $0.status == .flying }) else { return }
        let frameDt = min(dt, 1.0 / 30.0)

        for index in flights.indices where flights[index].status == .flying {
            var flight = flights[index]
            let drag = airResistance
                ? ProjectileMotion.Drag(projectile: flight.kind.projectile)
                : nil

            let previous = flight.state
            let substep = frameDt / 2
            for _ in 0..<2 {
                flight.state = Integrators.rk4Step(flight.state, dt: substep) { _, velocity in
                    ProjectileMotion.acceleration(velocity: velocity, gravity: gravity, drag: drag)
                }
            }
            let previousElapsed = flight.elapsed
            flight.elapsed += frameDt
            flight.maxHeight = max(flight.maxHeight, flight.state.position.y)

            // Strobe dots at exact multiples of dotInterval, interpolated
            // inside the frame so their spacing genuinely encodes speed.
            while flight.elapsed >= flight.nextDotTime, flight.dots.count < Self.dotsPerFlight {
                let fraction = (flight.nextDotTime - previousElapsed) / frameDt
                flight.dots.append(
                    previous.position + fraction * (flight.state.position - previous.position)
                )
                flight.nextDotTime += Self.dotInterval
            }

            if flight.state.position.y <= 0, flight.state.velocity.y < 0 {
                // Landed: interpolate the touchdown inside the frame.
                let dip = previous.position.y - flight.state.position.y
                let fraction = dip > 0 ? previous.position.y / dip : 0
                let landing = previous.position + fraction * (flight.state.position - previous.position)
                flight.state = ParticleDynamics.State(position: landing)
                flight.elapsed = previousElapsed + fraction * frameDt
                flight.status = .landed
                lastFlight = FlightSummary(
                    projectileName: flight.kind.projectile.name,
                    range: simd_length(SIMD2(landing.x, landing.z)),
                    apexHeight: flight.maxHeight,
                    flightTime: flight.elapsed,
                    wentOffTable: false
                )
            } else if flight.state.position.x < Self.tableMinX
                        || flight.state.position.x > Self.tableMaxX
                        || abs(flight.state.position.z) > Self.tableHalfDepth {
                // Left the diorama mid-air ("off the table").
                flight.status = .offTable
                lastFlight = FlightSummary(
                    projectileName: flight.kind.projectile.name,
                    range: simd_length(SIMD2(flight.state.position.x, flight.state.position.z)),
                    apexHeight: flight.maxHeight,
                    flightTime: flight.elapsed,
                    wentOffTable: true
                )
            }
            flights[index] = flight
        }
    }

    // MARK: Reset

    /// Returns the module to its freshly-entered state. Wired to the
    /// shell's Reset button through the module descriptor.
    func reset() {
        flights.removeAll()
        lastFlight = nil
        launchSpeed = 7.0
        gravity = 9.81
        airResistance = false
        kind = .basketball
        aimDirection = Self.direction(elevationDegrees: 45, azimuthDegrees: 0)
    }
}
