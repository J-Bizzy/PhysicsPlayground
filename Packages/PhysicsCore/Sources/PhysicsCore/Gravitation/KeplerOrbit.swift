//
//  KeplerOrbit.swift
//  PhysicsCore — Gravitation
//
//  The two-body problem in time: an `ApsisFrame` (shape, plane, and where
//  the body is) plus the instant that place applies to, and Kepler's
//  equation to carry it forward. Bound orbits only — every orbit the app
//  propagates this way is a closed one.
//
//      M = M₀ + n (t − t₀),   n = √(μ/a³)
//      E − e sin E = M        (Newton, from Danby's starting guess)
//      ν = 2 atan2(√(1+e) sin(E/2), √(1−e) cos(E/2))
//
//  `reaching(apoapsis:through:)` is the transfer the opening flies: the one
//  ellipse with its focus at the star, its far end exactly at a point P,
//  that passes through a departure point D.
//

import Foundation
import simd

public struct KeplerOrbit: Sendable, Equatable {
    /// Shape, plane and position; `frame.trueAnomaly` is where the body is
    /// at `epoch`.
    public var frame: ApsisFrame
    public var epoch: Double

    public init(frame: ApsisFrame, epoch: Double) {
        self.frame = frame
        self.epoch = epoch
    }

    public var mu: Double { frame.mu }
    public var eccentricity: Double { frame.eccentricity }
    public var semiMajorAxis: Double { (frame.periapsisRadius + frame.apoapsisRadius) / 2 }
    /// n = √(μ/a³), rad/s.
    public var meanMotion: Double {
        let a = semiMajorAxis
        return (mu / (a * a * a)).squareRoot()
    }
    public var period: Double { 2 * .pi / meanMotion }

    // MARK: Kepler's equation

    /// E such that E − e sin E = M, for 0 ≤ e < 1: Newton's method from
    /// Danby's guess E₀ = M + 0.85 e sgn(sin M), which converges for every
    /// M and every bound e.
    public static func eccentricAnomaly(meanAnomaly m: Double, eccentricity e: Double) -> Double {
        let mean = remainder(m, 2 * .pi)
        var anomaly = mean + 0.85 * e * (sin(mean) >= 0 ? 1 : -1)
        for _ in 0..<50 {
            let f = anomaly - e * sin(anomaly) - mean
            let step = f / (1 - e * cos(anomaly))
            anomaly -= step
            if abs(step) < 1e-15 { break }
        }
        return anomaly + (m - mean)
    }

    public static func trueAnomaly(eccentricAnomaly anomaly: Double, eccentricity e: Double) -> Double {
        2 * atan2((1 + e).squareRoot() * sin(anomaly / 2), (1 - e).squareRoot() * cos(anomaly / 2))
    }

    public static func meanAnomaly(trueAnomaly nu: Double, eccentricity e: Double) -> Double {
        let anomaly = 2 * atan2((1 - e).squareRoot() * sin(nu / 2), (1 + e).squareRoot() * cos(nu / 2))
        return anomaly - e * sin(anomaly)
    }

    // MARK: Where, when

    /// True anomaly at time `t`.
    public func trueAnomaly(at t: Double) -> Double {
        let e = eccentricity
        let m = Self.meanAnomaly(trueAnomaly: frame.trueAnomaly, eccentricity: e)
            + meanMotion * (t - epoch)
        return Self.trueAnomaly(eccentricAnomaly: Self.eccentricAnomaly(meanAnomaly: m, eccentricity: e),
                                eccentricity: e)
    }

    /// Position and velocity relative to the focus at time `t`.
    public func state(at t: Double) -> (position: SIMD3<Double>, velocity: SIMD3<Double>) {
        var at = frame
        at.trueAnomaly = trueAnomaly(at: t)
        return at.state()
    }

    /// The time, forward, from true anomaly `from` to true anomaly `to`.
    public func timeOfFlight(from: Double, to: Double) -> Double {
        let e = eccentricity
        var delta = Self.meanAnomaly(trueAnomaly: to, eccentricity: e)
            - Self.meanAnomaly(trueAnomaly: from, eccentricity: e)
        delta = delta.truncatingRemainder(dividingBy: 2 * .pi)
        if delta < 0 { delta += 2 * .pi }
        return delta / meanMotion
    }

    /// When the body next reaches its far end, at or after `epoch`.
    public var apoapsisTime: Double { epoch + timeOfFlight(from: frame.trueAnomaly, to: .pi) }

    /// Specific orbital energy, J/kg: −μ/2a.
    public var specificEnergy: Double { -mu / (2 * semiMajorAxis) }

    // MARK: Building one

    /// A circular orbit of `radius` about `normal`, the body on `direction`
    /// (projected into the plane) at `epoch`.
    public static func circular(radius: Double, normal: SIMD3<Double>,
                                through direction: SIMD3<Double>,
                                mu: Double, epoch: Double) -> KeplerOrbit {
        let n = simd_normalize(normal)
        let planar = simd_normalize(direction - simd_dot(direction, n) * n)
        return KeplerOrbit(frame: ApsisFrame(periapsisDirection: planar, orbitNormal: n,
                                             periapsisRadius: radius, apoapsisRadius: radius,
                                             trueAnomaly: 0, mu: mu),
                           epoch: epoch)
    }

    /// The bound orbit, focus at the origin, whose apoapsis is exactly
    /// `apoapsis` and which passes through `point` at `time`, turning in the
    /// sense of `sense` (its normal on `sense`'s side). The apse line is
    /// the line through P and the focus, so periapsis is −P̂, r_a = |P|,
    /// and the one free shape parameter follows from the conic through D:
    /// r(1 + e cos θ) = r_a(1 − e), θ measured from periapsis, so
    /// e = (r_a − r)/(r_a + r cos θ). Nil unless D lies strictly inside r_a
    /// and the result is an ellipse.
    public static func reaching(apoapsis: SIMD3<Double>, through point: SIMD3<Double>,
                                sense: SIMD3<Double>, mu: Double, at time: Double) -> KeplerOrbit? {
        let farRadius = simd_length(apoapsis), radius = simd_length(point)
        guard farRadius > 0, radius > 0, radius < farRadius * (1 - 1e-12) else { return nil }
        let periapsisHat = -apoapsis / farRadius
        let pointHat = point / radius
        var normal = simd_cross(pointHat, -periapsisHat)
        if simd_length(normal) < 1e-12 {
            // D on the apse line: any plane holding it — take the one nearest `sense`.
            normal = sense - simd_dot(sense, periapsisHat) * periapsisHat
            guard simd_length(normal) > 1e-12 else { return nil }
        }
        normal = simd_normalize(normal)
        if simd_dot(normal, sense) < 0 { normal = -normal }
        let cosTheta = simd_dot(pointHat, periapsisHat)
        let e = (farRadius - radius) / (farRadius + radius * cosTheta)
        guard e >= 0, e < 1 - 1e-12 else { return nil }
        let semiLatus = farRadius * (1 - e)
        let frame = ApsisFrame(
            periapsisDirection: periapsisHat, orbitNormal: normal,
            periapsisRadius: semiLatus / (1 + e), apoapsisRadius: farRadius,
            trueAnomaly: OrbitalElements.signedAngle(from: periapsisHat, to: pointHat, about: normal),
            mu: mu)
        return KeplerOrbit(frame: frame, epoch: time)
    }
}
