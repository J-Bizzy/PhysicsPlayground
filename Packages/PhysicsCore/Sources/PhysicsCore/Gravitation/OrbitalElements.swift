//
//  OrbitalElements.swift
//  PhysicsCore — Gravitation
//
//  The conic an orbiting body is on right now, both as the classical six
//  elements and as a shape you can take hold of.
//
//  WHY TWO TYPES AND NOT ONE. They answer different questions and they
//  fail in different places, so conflating them would make one of them
//  bad at its job:
//
//  · `OrbitalElements` is the READOUT — a, e, i, Ω, ω, ν in the textbook
//    conventions, so a number here can be checked against an almanac.
//    Those conventions are also singular: ω is undefined for a circular
//    orbit and Ω is undefined for an equatorial one, and a UI that reads
//    them has to be told so rather than shown a NaN. Hence `degeneracy`.
//
//  · `ApsisFrame` is the HANDLE — (p̂, ĥ, r_p, r_a, ν). Every member is a
//    vector or a distance, nothing is an angle measured from a reference
//    direction that might not exist, and so nothing in it is singular.
//    This is the type a hand manipulates.
//
//  Both convert to and from state vectors in closed form, and to and from
//  each other. NO KEPLER'S EQUATION ANYWHERE IN THIS FILE, and that is
//  worth stating: solving Kepler's equation answers "where is the body at
//  time t", which is iterative and which nothing here needs. Every
//  question asked of this file is geometry — what shape is this orbit,
//  and what state vector produces that shape — and geometry is exact.
//
//  THE FRAME CONVENTION, AND IT IS THE FIRST THING THAT GOES WRONG.
//  Every textbook writes these formulas with +z as the reference normal.
//  This project is +Y UP WITH ORBITS IN THE XZ PLANE (see CelestialBody),
//  so ŷ substitutes for ẑ throughout. The consequence to check against:
//  `CelestialBody.onCircularOrbit` puts a body at +x moving along −z, and
//  x̂ × (−ẑ) = +ŷ, so PROGRADE MEANS h ALONG +ŷ AND i = 0. Get that
//  backwards and every orbit in the app is built retrograde while looking
//  perfectly correct in a still frame.
//
//  In-plane angles are measured with a signed, quadrant-safe form —
//  `∠(a, b; n̂) = atan2((a × b)·n̂, a·b)` — rather than `acos` plus a sign
//  test. It is one expression, it never needs clamping, and it cannot
//  lose a quadrant.
//

import Foundation
import simd

// MARK: - Which end of the orbit

/// The two apsides — the near and far ends of the apse line. `far` does
/// not exist on an unbound orbit; see `ApsisFrame.hasApoapsis`.
public enum Apsis: String, Sendable, CaseIterable {
    case near, far
}

// MARK: - Where the classical elements stop being defined

/// Which of the classical ANGLES this orbit leaves undetermined.
///
/// These are not error cases. A circular orbit is a perfectly good orbit;
/// it simply has no periapsis, so ω is a choice rather than a measurement.
/// The conventions below are deterministic, which is what lets the round
/// trip be exact even where the physics is indifferent.
///
/// Deliberately says nothing about the orbit's SHAPE — see `ConicKind`.
/// The first draft of this enum carried `.parabolic` and `.hyperbolic`
/// alongside `.circular` and `.equatorial`, and an equatorial hyperbola
/// then had to report one fact and hide the other. They are independent
/// questions: "which angles can I trust" and "does this orbit come back".
public enum OrbitDegeneracy: String, Sendable, Equatable, CaseIterable {
    /// Everything is determined.
    case none
    /// e ≈ 0: no periapsis, so ω is undefined. ν becomes the argument of
    /// latitude (angle from the ascending node).
    case circular
    /// i ≈ 0 or π: no node line, so Ω is undefined. ω is measured from x̂.
    case equatorial
    /// Both. ν is the true longitude, measured from x̂.
    case circularEquatorial
}

/// What shape the conic is — the question `degeneracy` deliberately does
/// not answer.
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
    /// p = h²/μ, metres. ALWAYS finite and always defined — prefer it to
    /// `a` anywhere a formula allows the choice, because it is the one
    /// size parameter no conic degenerates.
    public var semiLatusRectum: Double
    public var eccentricity: Double
    /// i, radians, 0…π. Measured from +ŷ, so i = 0 is prograde in the xz
    /// plane and i = π is retrograde in it.
    public var inclination: Double
    /// Ω, radians. Zero when equatorial.
    public var longitudeOfAscendingNode: Double
    /// ω, radians. Measured from the ascending node, or from x̂ when
    /// equatorial.
    public var argumentOfPeriapsis: Double
    /// ν, radians. Measured from periapsis, or from the node / x̂ when the
    /// orbit is circular.
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

    /// r_a = p/(1−e): positive on an ellipse, +∞ on a parabola, and
    /// NEGATIVE on a hyperbola.
    ///
    /// The negative branch is not a bug and it is load-bearing. With
    /// `a < 0` for a hyperbola, `r_a = a(1+e) < 0`, and then
    ///
    ///     e = (r_a − r_p)/(r_a + r_p)   and   p = 2·r_p·r_a/(r_p + r_a)
    ///
    /// hold uniformly across ellipse, parabola and hyperbola with no
    /// branching at all. One parameterisation, three conics. Anything
    /// that wants to DRAW a far end should ask `hasApoapsis`.
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

    /// The osculating elements of a body at `position` moving at
    /// `velocity`, both RELATIVE TO THE FOCUS.
    ///
    /// Returns nil only for a radial trajectory (r × v = 0), where no
    /// orbital plane exists and there is genuinely nothing to report.
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

        // The node line, n = ŷ × ĥ, points at the ascending node. It
        // vanishes exactly when the orbit lies in the reference plane.
        let node = simd_cross(Self.referenceNormal, hHat)
        let nodeMagnitude = simd_length(node)
        let isEquatorial = nodeMagnitude < Self.degeneracyTolerance
        let isCircular = e < Self.degeneracyTolerance

        let nodeHat = isEquatorial ? Self.referenceDirection : node / nodeMagnitude
        // With no periapsis to point at, the node (or x̂) stands in — a
        // choice, made the same way every time so the round trip closes.
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

    /// The state vector these elements describe, RELATIVE TO THE FOCUS.
    public func state() -> (position: SIMD3<Double>, velocity: SIMD3<Double>) {
        frame.state()
    }

    /// The same orbit as a handle. This is the conversion the drag path
    /// uses, and it is exact both ways.
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
        // p̂ is the node turned through ω about ĥ (Rodrigues, with the
        // n̂·ĥ = 0 term dropped because it is zero by construction).
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

    /// How close to zero counts as "this element is not determined". At
    /// 1e-10 an orbit has to be circular or equatorial to about a
    /// nanoradian before its conventions kick in, which no orbit reaches
    /// by accident and every deliberately-built one reaches exactly.
    static let degeneracyTolerance = 1e-10
    /// e within this of 1 is treated as parabolic, where a is infinite.
    static let parabolicTolerance = 1e-8

    /// Signed angle from `a` to `b` about `axis`, in (−π, π].
    ///
    /// One `atan2` rather than an `acos` plus a quadrant test: it needs
    /// no clamping against floating-point overshoot, and it cannot pick
    /// the wrong half of the circle.
    static func signedAngle(from a: SIMD3<Double>, to b: SIMD3<Double>,
                            about axis: SIMD3<Double>) -> Double {
        atan2(simd_dot(simd_cross(a, b), axis), simd_dot(a, b))
    }
}

// MARK: - The handle

/// An orbit as two directions and two distances — the form a hand takes
/// hold of.
///
/// Nothing here is singular. `p̂` always points somewhere (at the body
/// itself, if the orbit is circular and has no periapsis of its own), `ĥ`
/// always names the plane, and the two radii are just lengths. That is
/// the whole reason this type exists next to `OrbitalElements`: a control
/// cannot be allowed to stop working at e = 0, which is precisely the
/// value a user tuning an orbit will spend the most time near.
public struct ApsisFrame: Sendable, Equatable {
    /// Unit vector from the focus toward periapsis — the apse line.
    public var periapsisDirection: SIMD3<Double>
    /// Unit angular-momentum direction. Perpendicular to the apse line,
    /// and the invariant this type works hardest to preserve.
    public var orbitNormal: SIMD3<Double>
    /// r_p, metres. Always positive.
    public var periapsisRadius: Double
    /// r_a, metres — negative on a hyperbola, +∞ on a parabola. See
    /// `OrbitalElements.apoapsisRadius` for why that is deliberate.
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

        // CIRCULAR FALLBACK, AND IT DIFFERS FROM `OrbitalElements` ON
        // PURPOSE. There the convention is the node line, because that is
        // what the textbook says and what an almanac can be checked
        // against. Here it is the BODY'S OWN DIRECTION, because these two
        // vectors are where the beads go: putting the near bead on the
        // planet and the far bead at the antipode gives the user two
        // handles that are both exactly where they expect to find them.
        // (When r_p = r_a the two beads do the same thing anyway, so the
        // one hidden behind its planet costs nothing.)
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

    /// The in-plane direction 90° ahead of periapsis: p̂, ĥ, q̂ is a
    /// right-handed perifocal basis.
    public var alongTrack: SIMD3<Double> {
        simd_cross(orbitNormal, periapsisDirection)
    }

    /// e = (r_a − r_p)/(r_a + r_p). Handles the infinite far end without
    /// a branch, because the ratio tends to 1.
    public var eccentricity: Double {
        guard apoapsisRadius.isFinite else { return 1 }
        let sum = apoapsisRadius + periapsisRadius
        guard abs(sum) > 1e-12 else { return 1 }
        return (apoapsisRadius - periapsisRadius) / sum
    }

    /// p = 2·r_p·r_a/(r_p + r_a) — the harmonic mean of the two apsis
    /// radii, which tends to 2·r_p as the far end runs off to infinity
    /// and so gives the parabola exactly.
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

    /// The state vector this frame describes, relative to the focus.
    ///
    /// Check it against `CelestialBody.onEllipticalOrbit`, which has
    /// shipped for months: at ν = 0 this reduces to r = a(1−e) and
    /// |v| = √(μ(1+e)/(a(1−e))), which is that function's formula
    /// character for character.
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
            // Unreachable in practice: this frame was built from a state
            // that had an angular momentum, so reading it back always
            // finds one. The fallback exists so the property is not
            // optional for every caller.
            ?? OrbitalElements(
                semiMajorAxis: nil, semiLatusRectum: semiLatusRectum,
                eccentricity: eccentricity, inclination: 0,
                longitudeOfAscendingNode: 0, argumentOfPeriapsis: 0,
                trueAnomaly: trueAnomaly, mu: mu)
    }

    // MARK: The drag
    //
    // The entire manipulation, as one pure function of a hand position.
    // It lives here rather than in the module for two reasons: it is the
    // part most likely to be wrong, and `swift test` runs it in three
    // seconds without a simulator.

    /// This orbit, reshaped by a hand at `handOffset` (relative to the
    /// focus, in metres) holding one bead while the other stays at
    /// `otherRadius`.
    ///
    /// THREE THINGS MAKE THIS WELL-POSED, and none of them is obvious.
    ///
    /// 1. THE BEADS ARE NOT INDEPENDENT, AND THE HELD ONE IS NOT LABELLED.
    ///    Periapsis and apoapsis are collinear through the focus, so both
    ///    report the same apse line. The bead you hold is therefore just
    ///    "the end at distance ρ", and which apsis that IS follows from
    ///    the arithmetic: whichever of ρ and `otherRadius` is smaller is
    ///    the near end. This makes "what if I drag periapsis out past
    ///    apoapsis" evaporate rather than needing a rule — the labels
    ///    swap exactly at ρ = otherRadius, which is where the orbit is
    ///    circular and the two ends are physically interchangeable. The
    ///    state passes through smoothly because the two velocities differ
    ///    by 2e·q̂ and e is zero at precisely that crossing.
    ///
    /// 2. THE PLANE IS TRANSPORTED, NOT SET. Two collinear points and a
    ///    focus define a PENCIL of planes, not one — the roll about the
    ///    apse line is a degree of freedom neither bead can reach. So it
    ///    is carried: ĥ is projected perpendicular to the new apse line
    ///    and renormalised. In-plane drags leave it bit-exact (the
    ///    projection is the identity); out-of-plane drags tilt it by
    ///    exactly the minimum rotation, so the plane follows the apse
    ///    line the way a hoop follows its diameter, with no mode and
    ///    nothing to discover.
    ///
    ///    That rule is parallel transport, which means it has HOLONOMY:
    ///    walk a bead around a closed loop and the plane comes back
    ///    rotated by the solid angle you enclosed. Two beads are
    ///    instantaneously one degree of freedom short and globally
    ///    complete, which is the licence for not adding a third.
    ///
    /// 3. THE BODY KEEPS ITS BEARING, NOT ITS TRUE ANOMALY. Preserving ν
    ///    would fling a planet across the room when the apse line swings.
    ///    Instead its direction from the focus is held and its distance
    ///    follows the new conic, so an apse rotation slides it along its
    ///    own sightline. For a straight radial pull — the common case —
    ///    the two rules are identical.
    ///
    /// Degenerate hands are NO-OPS, never snaps: a hand at the focus has
    /// no direction, and a hand on the orbit's pole describes every plane
    /// equally well. Both leave the orbit exactly as it was, which is the
    /// same answer the Gauss-surface tilt gives for the same reason.
    public func dragged(handOffset: SIMD3<Double>,
                        otherRadius: Double,
                        bodyDirection: SIMD3<Double>) -> ApsisFrame {
        let reach = simd_length(handOffset)
        guard reach > 1e-6 else { return self }
        let handHat = handOffset / reach

        var result = self

        if otherRadius.isFinite && otherRadius > 0 {
            // Bound: the other bead pins one end, and the arithmetic
            // decides which end each of them is.
            let heldIsNear = reach <= otherRadius
            result.periapsisRadius = min(reach, otherRadius)
            result.apoapsisRadius = max(reach, otherRadius)
            result.periapsisDirection = heldIsNear ? handHat : -handHat
        } else {
            // Unbound: there is no far bead to pin anything, so the hand
            // is on periapsis by definition and the SHAPE is what holds.
            // Pull it in or out and the hyperbola keeps its eccentricity,
            // which is the only reading of the gesture that leaves the
            // orbit recognisably the same orbit.
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
            // ALREADY PERPENDICULAR, SO LEAVE IT ALONE — do not project
            // and renormalise a vector that is already the answer.
            //
            // This is not a micro-optimisation, it is the difference
            // between a plane that holds and a plane that creeps. An
            // in-plane drag is the commonest gesture there is, it runs at
            // ninety frames a second for as long as the hand is moving,
            // and projecting-then-normalising costs about an ulp each
            // time. Left in, those ulps are a random walk: drag a bead
            // back and forth for a minute and the orbit is measurably
            // tilted, with nothing in the gesture to explain it.
            result.orbitNormal = orbitNormal
        } else {
            let transported = orbitNormal - tilt * axis
            let transportedLength = simd_length(transported)
            guard transportedLength > 1e-6 else {
                // The hand is on the orbit's pole. Every plane through
                // this apse line is equally described, so describe none.
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

    /// The conic as a polyline of points relative to the focus.
    ///
    /// Sampled uniformly in ECCENTRIC anomaly, not true anomaly. A conic
    /// crowds its curvature near periapsis, so equal steps in ν draw a
    /// coarse, faceted nose on an eccentric orbit and waste most of the
    /// budget out at the slow end; equal steps in E space the points
    /// evenly along the arc for any eccentricity, which is why 256 points
    /// is enough for a circle and for e = 0.97 alike.
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
            // Open conic: walk ν out toward the asymptotes and stop short
            // of them, since the curve runs to infinity there and a tube
            // to infinity is not a drawing.
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
            // ν from E, in the half-angle form that stays exact near π.
            let nu = 2 * atan2(rootRatio * sin(anomaly / 2), cos(anomaly / 2))
            let r = a * (1 - e * cos(anomaly))
            points.append(r * (cos(nu) * periapsisDirection + sin(nu) * q))
        }
        return points
    }
}
