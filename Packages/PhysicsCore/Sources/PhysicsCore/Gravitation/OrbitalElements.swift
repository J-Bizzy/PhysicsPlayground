//  OrbitalElements.swift — the conic a body is on now, as readout and as handle.
//
//  Two types on purpose: `OrbitalElements` is the readout (textbook a, e, i, Ω, ω, ν —
//  singular for circular/equatorial orbits, hence `degeneracy`); `ApsisFrame` is the
//  Handle (p̂, ĥ, r_p, r_a, ν — vectors and distances only, nothing singular). Closed
//  form both ways; pure geometry, no Kepler's equation anywhere.
//
//  Frame: +Y up, orbits in xz (see CelestialBody); ŷ substitutes for the textbook ẑ.
//  Prograde means h along +ŷ and i = 0 — get that backwards and every orbit builds
//  retrograde while looking correct in a still frame. In-plane angles use the signed
//  quadrant-safe form ∠(a, b; n̂) = atan2((a × b)·n̂, a·b) — no clamping, no lost quadrant.

import Foundation
import simd

// MARK: - Which end of the orbit

/// The two apsides — the near and far ends of the apse line. `far` does
/// not exist on an unbound orbit; see `ApsisFrame.hasApoapsis`.
public enum Apsis: String, Sendable, CaseIterable {
    case near, far
}

// MARK: - Where the classical elements stop being defined

/// Which classical angles this orbit leaves undetermined — conventions, not errors;
/// deterministic, so the round trip stays exact. Shape is `ConicKind`, independently.
public enum OrbitDegeneracy: String, Sendable, Equatable, CaseIterable {
    /// Everything is determined.
    case none
    /// e ≈ 0: no periapsis; ω undefined, ν becomes the argument of latitude (from the node).
    case circular
    /// i ≈ 0 or π: no node line, so Ω is undefined. ω is measured from x̂.
    case equatorial
    /// Both. ν is the true longitude, measured from x̂.
    case circularEquatorial
}

/// What shape the conic is — the question `degeneracy` deliberately does not answer.
public enum ConicKind: String, Sendable, Equatable, CaseIterable {
    /// e < 1. Closed: it has a far end, and a period.
    case ellipse
    /// e ≈ 1. a is infinite; `semiLatusRectum` is still exact.
    case parabola
    /// e > 1. a and r_a are negative, and there is no far end.
    case hyperbola
}

// MARK: - The classical six

public struct OrbitalElements: Sendable, Equatable {
    /// a, metres. `nil` at exactly parabolic, where it is infinite.
    public var semiMajorAxis: Double?
    /// p = h²/μ, metres. Always finite — prefer it to `a` where a formula allows: the one size parameter no conic degenerates.
    public var semiLatusRectum: Double
    public var eccentricity: Double
    /// i, radians, 0…π from +ŷ: i = 0 prograde in xz, i = π retrograde.
    public var inclination: Double
    /// Ω, radians. Zero when equatorial.
    public var longitudeOfAscendingNode: Double
    /// ω, radians. From the ascending node, or from x̂ when equatorial.
    public var argumentOfPeriapsis: Double
    /// ν, radians. From periapsis, or from the node / x̂ when circular.
    public var trueAnomaly: Double
    /// Standard gravitational parameter, m³/s².
    public var mu: Double
    /// Which angles above are conventions rather than measurements.
    public var degeneracy: OrbitDegeneracy

    /// Ellipse, parabola or hyperbola — independent of `degeneracy`.
    public var kind: ConicKind {
        if semiMajorAxis == nil { return .parabola }
        return eccentricity > 1 ? .hyperbola : .ellipse
    }

    public init(semiMajorAxis: Double?, semiLatusRectum: Double,
                eccentricity: Double, inclination: Double,
                longitudeOfAscendingNode: Double, argumentOfPeriapsis: Double,
                trueAnomaly: Double, mu: Double,
                degeneracy: OrbitDegeneracy = .none) {
        self.semiMajorAxis = semiMajorAxis
        self.semiLatusRectum = semiLatusRectum
        self.eccentricity = eccentricity
        self.inclination = inclination
        self.longitudeOfAscendingNode = longitudeOfAscendingNode
        self.argumentOfPeriapsis = argumentOfPeriapsis
        self.trueAnomaly = trueAnomaly
        self.mu = mu
        self.degeneracy = degeneracy
    }

    // MARK: Derived

    /// r_p = p/(1+e). Always positive, always finite.
    public var periapsisRadius: Double { semiLatusRectum / (1 + eccentricity) }

    /// r_a = p/(1−e): +∞ on a parabola, negative on a hyperbola — load-bearing, so that
    /// e = (r_a−r_p)/(r_a+r_p) and p = 2·r_p·r_a/(r_p+r_a) hold branch-free for all three
    /// conics. Anything that wants to draw a far end should ask `hasApoapsis`.
    public var apoapsisRadius: Double {
        let denominator = 1 - eccentricity
        guard abs(denominator) > 1e-12 else { return .infinity }
        return semiLatusRectum / denominator
    }

    public var isBound: Bool { eccentricity < 1 - 1e-12 }
    public var hasApoapsis: Bool { isBound }

    /// T = 2π√(a³/μ). `nil` when unbound — there is no period.
    public var period: Double? {
        guard let a = semiMajorAxis, a > 0, isBound else { return nil }
        return 2 * .pi * (a * a * a / mu).squareRoot()
    }

    // MARK: State → elements

    /// Osculating elements from state relative to the focus. Nil only for a radial
    /// trajectory (r × v = 0), where no orbital plane exists.
    public static func from(position r: SIMD3<Double>,
                            velocity v: SIMD3<Double>,
                            mu: Double) -> OrbitalElements? {
        let distance = simd_length(r)
        guard distance > 0, mu > 0 else { return nil }

        let h = simd_cross(r, v)
        let hMagnitude = simd_length(h)
        // Straight up or straight down: no plane, no conic in space.
        guard hMagnitude > 1e-9 * distance * max(simd_length(v), 1e-9) else { return nil }
        let hHat = h / hMagnitude

        // e⃗ = (v × h)/μ − r̂. Its magnitude is e and it points at periapsis.
        let eccentricityVector = simd_cross(v, h) / mu - r / distance
        let e = simd_length(eccentricityVector)

        let p = hMagnitude * hMagnitude / mu
        let a: Double? = abs(e - 1) > Self.parabolicTolerance
            ? p / (1 - e * e)
            : nil

        let inclination = acos(min(max(hHat.y, -1), 1))

        // Node line n = ŷ × ĥ; vanishes exactly when the orbit is equatorial.
        let node = simd_cross(Self.referenceNormal, hHat)
        let nodeMagnitude = simd_length(node)
        let isEquatorial = nodeMagnitude < Self.degeneracyTolerance
        let isCircular = e < Self.degeneracyTolerance

        let nodeHat = isEquatorial ? Self.referenceDirection : node / nodeMagnitude
        // No periapsis: the node (or x̂) stands in — same choice every time, so the round trip closes.
        let periapsisHat = isCircular ? nodeHat : eccentricityVector / e

        let ascendingNode = isEquatorial
            ? 0
            : Self.signedAngle(from: Self.referenceDirection, to: nodeHat,
                               about: Self.referenceNormal)
        let argumentOfPeriapsis = Self.signedAngle(
            from: nodeHat, to: periapsisHat, about: hHat)
        let trueAnomaly = Self.signedAngle(
            from: periapsisHat, to: r / distance, about: hHat)

        let degeneracy: OrbitDegeneracy
        switch (isCircular, isEquatorial) {
        case (true, true): degeneracy = .circularEquatorial
        case (true, false): degeneracy = .circular
        case (false, true): degeneracy = .equatorial
        case (false, false): degeneracy = .none
        }

        return OrbitalElements(
            semiMajorAxis: a, semiLatusRectum: p, eccentricity: e,
            inclination: inclination,
            longitudeOfAscendingNode: ascendingNode,
            argumentOfPeriapsis: argumentOfPeriapsis,
            trueAnomaly: trueAnomaly, mu: mu, degeneracy: degeneracy)
    }

    // MARK: Elements → state

    /// The state vector these elements describe, relative to the focus.
    public func state() -> (position: SIMD3<Double>, velocity: SIMD3<Double>) {
        frame.state()
    }

    /// The same orbit as a handle — the drag path's conversion, exact both ways.
    public var frame: ApsisFrame {
        let sinI = sin(inclination), cosI = cos(inclination)
        // ĥ from (i, Ω), inverting `node = ŷ × ĥ` and `ĥ·ŷ = cos i`.
        let hHat = SIMD3<Double>(sinI * sin(longitudeOfAscendingNode),
                                 cosI,
                                 sinI * cos(longitudeOfAscendingNode))
        // The node line, or x̂ where there isn't one.
        let nodeHat: SIMD3<Double> = abs(sinI) < Self.degeneracyTolerance
            ? Self.referenceDirection
            : SIMD3(cos(longitudeOfAscendingNode), 0,
                    -sin(longitudeOfAscendingNode))
        // p̂ = node turned through ω about ĥ (Rodrigues; n̂·ĥ = 0 term is zero by construction).
        let periapsisHat = nodeHat * cos(argumentOfPeriapsis)
            + simd_cross(hHat, nodeHat) * sin(argumentOfPeriapsis)
        return ApsisFrame(
            periapsisDirection: simd_normalize(periapsisHat),
            orbitNormal: simd_normalize(hHat),
            periapsisRadius: periapsisRadius,
            apoapsisRadius: apoapsisRadius,
            trueAnomaly: trueAnomaly,
            mu: mu)
    }

    // MARK: The frame this file is written in

    /// +Y is up; orbits live in the xz plane. See the file header.
    public static let referenceNormal = SIMD3<Double>(0, 1, 0)
    public static let referenceDirection = SIMD3<Double>(1, 0, 0)

    /// "Not determined" threshold: ~a nanoradian — no orbit reaches it by accident, every deliberately-built one exactly.
    static let degeneracyTolerance = 1e-10
    /// e within this of 1 is treated as parabolic, where a is infinite.
    static let parabolicTolerance = 1e-8

    /// Signed angle from `a` to `b` about `axis`, in (−π, π]. One atan2, not acos + sign
    /// test: no clamping, cannot pick the wrong half of the circle.
    static func signedAngle(from a: SIMD3<Double>, to b: SIMD3<Double>,
                            about axis: SIMD3<Double>) -> Double {
        atan2(simd_dot(simd_cross(a, b), axis), simd_dot(a, b))
    }
}

// MARK: - The handle

/// An orbit as two directions and two distances — the graspable form. Nothing here is
/// singular: a control cannot stop working at e = 0, exactly where a tuning user lingers.
public struct ApsisFrame: Sendable, Equatable {
    /// Unit vector from the focus toward periapsis — the apse line.
    public var periapsisDirection: SIMD3<Double>
    /// Unit angular-momentum direction. Perpendicular to the apse line — the invariant this type preserves hardest.
    public var orbitNormal: SIMD3<Double>
    /// r_p, metres. Always positive.
    public var periapsisRadius: Double
    /// r_a, metres — negative on a hyperbola, +∞ on a parabola; deliberate, see `OrbitalElements.apoapsisRadius`.
    public var apoapsisRadius: Double
    /// Where the body is on the conic, radians from periapsis.
    public var trueAnomaly: Double
    public var mu: Double

    public init(periapsisDirection: SIMD3<Double>, orbitNormal: SIMD3<Double>,
                periapsisRadius: Double, apoapsisRadius: Double,
                trueAnomaly: Double, mu: Double) {
        self.periapsisDirection = periapsisDirection
        self.orbitNormal = orbitNormal
        self.periapsisRadius = periapsisRadius
        self.apoapsisRadius = apoapsisRadius
        self.trueAnomaly = trueAnomaly
        self.mu = mu
    }

    /// The osculating frame of a body at `position` moving at `velocity`,
    /// both relative to the focus. Nil only for a radial trajectory.
    public init?(position r: SIMD3<Double>, velocity v: SIMD3<Double>, mu: Double) {
        let distance = simd_length(r)
        guard distance > 0, mu > 0 else { return nil }
        let h = simd_cross(r, v)
        let hMagnitude = simd_length(h)
        guard hMagnitude > 1e-9 * distance * max(simd_length(v), 1e-9) else { return nil }
        let hHat = h / hMagnitude
        let eccentricityVector = simd_cross(v, h) / mu - r / distance
        let e = simd_length(eccentricityVector)

        // Circular fallback differs from `OrbitalElements` on purpose: the body's own
        // direction, not the node — these vectors place the drag beads on the planet.
        let periapsisHat = e < OrbitalElements.degeneracyTolerance
            ? r / distance
            : eccentricityVector / e

        let p = hMagnitude * hMagnitude / mu
        self.periapsisDirection = periapsisHat
        self.orbitNormal = hHat
        self.periapsisRadius = p / (1 + e)
        self.apoapsisRadius = abs(1 - e) > 1e-12 ? p / (1 - e) : .infinity
        self.trueAnomaly = OrbitalElements.signedAngle(
            from: periapsisHat, to: r / distance, about: hHat)
        self.mu = mu
    }

    // MARK: Shape

    /// In-plane direction 90° ahead of periapsis: p̂, ĥ, q̂ is a right-handed perifocal basis.
    public var alongTrack: SIMD3<Double> {
        simd_cross(orbitNormal, periapsisDirection)
    }

    /// e = (r_a − r_p)/(r_a + r_p); the ratio tends to 1 at an infinite far end.
    public var eccentricity: Double {
        guard apoapsisRadius.isFinite else { return 1 }
        let sum = apoapsisRadius + periapsisRadius
        guard abs(sum) > 1e-12 else { return 1 }
        return (apoapsisRadius - periapsisRadius) / sum
    }

    /// p = 2·r_p·r_a/(r_p + r_a) — harmonic mean; tends to 2·r_p at infinity, giving the parabola exactly.
    public var semiLatusRectum: Double {
        guard apoapsisRadius.isFinite else { return 2 * periapsisRadius }
        let sum = apoapsisRadius + periapsisRadius
        guard abs(sum) > 1e-12 else { return periapsisRadius }
        return 2 * periapsisRadius * apoapsisRadius / sum
    }

    public var isBound: Bool { apoapsisRadius.isFinite && apoapsisRadius > 0 }
    /// Whether there is a far end to put a bead on at all.
    public var hasApoapsis: Bool { isBound }

    /// Where an apsis sits, relative to the focus.
    public func apsisPoint(_ apsis: Apsis) -> SIMD3<Double> {
        switch apsis {
        case .near: periapsisDirection * periapsisRadius
        case .far: -periapsisDirection * apoapsisRadius
        }
    }

    public func radius(at apsis: Apsis) -> Double {
        apsis == .near ? periapsisRadius : apoapsisRadius
    }

    // MARK: Frame → state

    /// State vector relative to the focus. At ν = 0 it reduces to r = a(1−e),
    /// |v| = √(μ(1+e)/(a(1−e))) — `CelestialBody.onEllipticalOrbit`'s formula exactly.
    public func state() -> (position: SIMD3<Double>, velocity: SIMD3<Double>) {
        let p = semiLatusRectum
        let e = eccentricity
        let q = alongTrack
        let cosNu = cos(trueAnomaly), sinNu = sin(trueAnomaly)
        let r = p / max(1 + e * cosNu, 1e-12)
        let speedScale = (mu / p).squareRoot()
        return (position: r * (cosNu * periapsisDirection + sinNu * q),
                velocity: speedScale * (-sinNu * periapsisDirection
                                        + (e + cosNu) * q))
    }

    public var elements: OrbitalElements {
        OrbitalElements.from(position: state().position,
                             velocity: state().velocity, mu: mu)
            // Unreachable in practice (the frame was built from a state with h ≠ 0);
            // exists so the property is not optional for every caller.
            ?? OrbitalElements(
                semiMajorAxis: nil, semiLatusRectum: semiLatusRectum,
                eccentricity: eccentricity, inclination: 0,
                longitudeOfAscendingNode: 0, argumentOfPeriapsis: 0,
                trueAnomaly: trueAnomaly, mu: mu)
    }

    // MARK: The drag
    // Pure function of a hand position — lives here so `swift test` runs it without a simulator.

    /// This orbit reshaped by a hand at `handOffset` (from focus, m) holding one bead while
    /// the other stays at `otherRadius`. Well-posed because: (1) beads are unlabelled — the
    /// nearer of ρ/otherRadius is periapsis, labels swap smoothly at the circular crossing;
    /// (2) the plane is parallel-transported, not set — ĥ projected ⊥ the new apse line
    /// (in-plane drags bit-exact, out-of-plane the minimum rotation; holonomy is accepted);
    /// (3) the body keeps its bearing, not its ν. Degenerate hands (at the focus, on the
    /// pole) are no-OPS, never snaps.
    public func dragged(handOffset: SIMD3<Double>,
                        otherRadius: Double,
                        bodyDirection: SIMD3<Double>) -> ApsisFrame {
        let reach = simd_length(handOffset)
        guard reach > 1e-6 else { return self }
        let handHat = handOffset / reach

        var result = self

        if otherRadius.isFinite && otherRadius > 0 {
            // Bound: the other bead pins one end; the arithmetic decides which is which.
            let heldIsNear = reach <= otherRadius
            result.periapsisRadius = min(reach, otherRadius)
            result.apoapsisRadius = max(reach, otherRadius)
            result.periapsisDirection = heldIsNear ? handHat : -handHat
        } else {
            // Unbound: no far bead — the hand is periapsis by definition and eccentricity
            // holds, the only reading that keeps the orbit recognisably the same orbit.
            let e = eccentricity
            result.periapsisRadius = reach
            result.periapsisDirection = handHat
            result.apoapsisRadius = abs(1 - e) > 1e-12
                ? reach * (1 + e) / (1 - e)
                : .infinity
        }

        // The plane, carried across.
        let axis = result.periapsisDirection
        let tilt = simd_dot(orbitNormal, axis)
        if abs(tilt) < 1e-14 {
            // Already perpendicular: keep it bit-exact. Projecting + renormalising costs
            // ~an ulp per frame — a random walk that measurably tilts the plane over a
            // minute of in-plane dragging.
            result.orbitNormal = orbitNormal
        } else {
            let transported = orbitNormal - tilt * axis
            let transportedLength = simd_length(transported)
            guard transportedLength > 1e-6 else {
                // Hand on the orbit's pole: every plane fits equally, so change nothing.
                return self
            }
            result.orbitNormal = transported / transportedLength
        }

        // Where the body ends up on the new conic.
        let planar = bodyDirection
            - simd_dot(bodyDirection, result.orbitNormal) * result.orbitNormal
        let planarLength = simd_length(planar)
        if planarLength > 1e-6 {
            result.trueAnomaly = OrbitalElements.signedAngle(
                from: result.periapsisDirection, to: planar / planarLength,
                about: result.orbitNormal)
        }
        return result
    }

    // MARK: Drawing

    /// The conic as a polyline relative to the focus. Sampled uniformly in eccentric
    /// anomaly, not ν: equal-ν steps facet the periapsis nose; equal-E spaces points
    /// evenly along the arc at any eccentricity, so 256 points serve e = 0 and e = 0.97 alike.
    public func sampled(count: Int = 256) -> [SIMD3<Double>] {
        let n = max(count, 8)
        let e = eccentricity
        let p = semiLatusRectum
        let q = alongTrack

        func point(trueAnomaly nu: Double) -> SIMD3<Double> {
            let denominator = 1 + e * cos(nu)
            guard denominator > 1e-9 else { return .zero }
            let r = p / denominator
            return r * (cos(nu) * periapsisDirection + sin(nu) * q)
        }

        guard e < 1 - 1e-9 else {
            // Open conic: walk ν toward the asymptotes, stopping short of infinity.
            let limit = e > 1 ? acos(min(max(-1 / e, -1), 1)) : .pi
            let sweep = (limit - 0.06) * 2
            return (0..<n).map { index in
                point(trueAnomaly: -sweep / 2 + sweep * Double(index) / Double(n - 1))
            }
        }

        let a = p / (1 - e * e)
        let rootRatio = ((1 + e) / (1 - e)).squareRoot()
        var points: [SIMD3<Double>] = []
        points.reserveCapacity(n + 1)
        for index in 0...n {
            let anomaly = 2 * Double.pi * Double(index) / Double(n)
            // ν from E in the half-angle form that stays exact near π.
            let nu = 2 * atan2(rootRatio * sin(anomaly / 2), cos(anomaly / 2))
            let r = a * (1 - e * cos(anomaly))
            points.append(r * (cos(nu) * periapsisDirection + sin(nu) * q))
        }
        return points
    }
}
