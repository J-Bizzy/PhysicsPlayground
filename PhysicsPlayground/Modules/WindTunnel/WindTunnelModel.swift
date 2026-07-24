//
//  WindTunnelModel.swift
//  Physics Playground — Wind Tunnel module
//
//  App state for the tabletop wind tunnel: ideal flow moves left-to-
//  right across a 1.2 × 0.8 m test section at table height, around a
//  grabbable cylinder. Plane coordinates are meters from the section
//  center (x downstream, y across); everything is 1:1 with the room and
//  all readouts are true values.
//
//  The field is steady state — moving the cylinder or changing spin
//  reshapes it instantly and exactly (it's the analytic solution, not a
//  solver). Time controls affect only the air particles and the
//  cylinder's spin animation.
//

import Foundation
import Observation
import PhysicsCore
import simd

@MainActor
@Observable
final class WindTunnelModel {
    // MARK: Test section geometry & ranges

    /// Half-extent downstream (x) and across (y), m — a two-meter test
    /// section you walk alongside.
    nonisolated static let halfLength = 1.0
    nonisolated static let halfWidth = 0.6

    nonisolated static let windSpeedRange = 0.2...2.0     // m/s
    nonisolated static let radiusRange = 0.03...0.12      // m
    nonisolated static let circulationRange = -1.5...1.5  // m²/s
    nonisolated static let timeScaleRange = 0.1...1.0

    // MARK: Flow state

    var windSpeed = 1.0
    var cylinderRadius = 0.06 {
        didSet { cylinderCenter = clampCylinder(cylinderCenter) }
    }
    private(set) var cylinderCenter = SIMD2<Double>(-0.3, 0)
    /// Γ, counterclockwise-positive seen from above.
    var circulation = 0.0

    var showStreamlines = true
    var showParticles = true
    var isPaused = false
    var timeScale = 1.0

    // MARK: Drag lab

    /// The body in the test section. The cylinder keeps the exact
    /// ideal-flow exhibit (streamlines, Cp probe, KJ lift, spin); the
    /// other shapes tell the empirical drag story — same frontal size,
    /// wildly different measured drag coefficients.
    var testBody: DragBody = .cylinder

    nonisolated static let airDensity = 1.225   // kg/m³, sea level 15 °C
    /// The visual cylinder's span (its reference area is 2r × span).
    nonisolated static let cylinderSpan = 0.9

    /// F = ½ρv²·Cd·A for the current body, size, and wind (newtons).
    var dragForce: Double {
        DragBody.dragForce(
            airDensity: Self.airDensity, speed: windSpeed,
            dragCoefficient: testBody.dragCoefficient,
            frontalArea: testBody.frontalArea(
                radius: cylinderRadius * testBody.sizeMultiplier,
                cylinderSpan: Self.cylinderSpan))
    }

    /// Live obstacles from ARKit on device — tracked hands/forearms and
    /// coarse room-mesh voxels. These are voxelised straight into the
    /// flow solver's solid mask, so the air goes around them for the same
    /// reason it goes around the test body: it cannot pass through.
    /// Always empty in the simulator.
    var obstacles = ObstacleField()

    /// The current body's sphere silhouette in section coordinates
    /// (origin on the beam axis) — what gets stamped into the solver's
    /// solid mask. Empty for the cylinder, which the renderer voxelises
    /// as a full-span column instead.
    var bodyObstacles: ObstacleField {
        guard testBody != .cylinder else { return ObstacleField() }
        return ObstacleField(spheres: testBody.obstacleSpheres(
            center: SIMD3(cylinderCenter.x, 0, cylinderCenter.y),
            halfWidth: cylinderRadius * testBody.sizeMultiplier))
    }

    /// The exact analytic flow for the current state.
    var flow: CylinderFlow {
        CylinderFlow(
            freeStreamSpeed: windSpeed,
            center: cylinderCenter,
            radius: cylinderRadius,
            circulation: circulation
        )
    }

    // MARK: Cylinder & probe placement

    func moveCylinder(to point: SIMD2<Double>) {
        cylinderCenter = clampCylinder(point)
        probePosition = pushOutOfCylinder(probePosition)
    }

    private func clampCylinder(_ point: SIMD2<Double>) -> SIMD2<Double> {
        let xLimit = Self.halfLength - cylinderRadius - 0.05
        let yLimit = Self.halfWidth - cylinderRadius - 0.02
        return SIMD2(
            min(max(point.x, -xLimit), xLimit),
            min(max(point.y, -yLimit), yLimit)
        )
    }

    private(set) var probePosition = SIMD2<Double>(0.45, 0.25)

    func moveProbe(to point: SIMD2<Double>) {
        let clamped = SIMD2(
            min(max(point.x, -Self.halfLength), Self.halfLength),
            min(max(point.y, -Self.halfWidth), Self.halfWidth)
        )
        probePosition = pushOutOfCylinder(clamped)
    }

    /// The probe reads the air, not the metal: it can't sit inside.
    private func pushOutOfCylinder(_ point: SIMD2<Double>) -> SIMD2<Double> {
        let offset = point - cylinderCenter
        let distance = simd_length(offset)
        let minimum = cylinderRadius + 0.015
        guard distance < minimum else { return point }
        let direction = distance > 1e-9 ? offset / distance : SIMD2(1, 0)
        return cylinderCenter + minimum * direction
    }

    // MARK: Readouts (all exact)

    /// Spin rate that matches the circulation: ω = Γ/(2πa²), shown as rpm.
    var spinRPM: Double {
        circulation / (2 * .pi * cylinderRadius * cylinderRadius) * 60 / (2 * .pi)
    }

    /// Kutta–Joukowski lift per unit span, N/m (y component of the plane).
    var liftPerSpan: Double {
        flow.liftPerSpan().y
    }

    struct ProbeReadout: Equatable {
        var speed: Double
        var speedRatio: Double
        var pressureCoefficient: Double
    }

    var probeReadout: ProbeReadout {
        let speed = flow.speed(at: probePosition)
        return ProbeReadout(
            speed: speed,
            speedRatio: speed / windSpeed,
            pressureCoefficient: flow.pressureCoefficient(at: probePosition)
        )
    }

    /// Fast/slow extremes on the surface (the shoulders, ± the spin term).
    var shoulderSpeeds: (top: Double, bottom: Double) {
        (flow.surfaceSpeed(atAngle: .pi / 2), flow.surfaceSpeed(atAngle: -.pi / 2))
    }

    var stagnationPoints: [SIMD2<Double>] {
        flow.stagnationPoints()
    }

    // MARK: Reset

    func reset() {
        windSpeed = 1.0
        cylinderRadius = 0.06
        cylinderCenter = SIMD2(-0.3, 0)
        circulation = 0.0
        showStreamlines = true
        showParticles = true
        isPaused = false
        timeScale = 1.0
        probePosition = SIMD2(0.45, 0.25)
        testBody = .cylinder
        obstacles = ObstacleField()
    }

    init() {
        reset()
        // Debug hook: `simctl launch … -windBody car` starts with that
        // body in the section (the picker can't be pinched from the CLI).
        #if DEBUG
        if let raw = UserDefaults.standard.string(forKey: "windBody"),
           let body = DragBody(rawValue: raw) {
            testBody = body
        }
        #endif
    }
}
