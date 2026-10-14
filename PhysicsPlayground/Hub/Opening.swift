//
//  Opening.swift
//  Physics Playground — Hub
//
//  The opening, as pure functions of time (no RealityKit, so it is
//  tested on numbers). About three seconds in which a field of glowing
//  particles visibly obeys physics, then settles into the six portals
//  that are the home screen:
//
//    1. GATHER   The room dims; the particles fade up at rest on a
//                horizontal sheet above eye level.
//    2. SWIRL    One system: uniform gravity crossed with a uniform
//                horizontal magnetic field. A charge released from rest
//                in crossed g and B traces an exact cycloid — it falls
//                with acceleration g, the Lorentz force curls it, and
//                after one cyclotron period it is at rest again at the
//                height it started, displaced sideways by 2πg/ω².
//                Positive and negative charges drift opposite ways, so
//                the cloud parts in two crossing streams. The magnetic
//                force does no work: ½v² = g·(drop), exactly.
//    3. RIPPLE   Every particle is at rest on the sheet again, which is
//                where the cycloid hands over. A deep-water gravity wave
//                crosses the sheet — Airy's linear solution, surface
//                particles on circles, the dispersion relation ω² = g·k
//                with the same g — swelling and dying under a sin²
//                envelope, so it, too, ends with everything at rest.
//    4. SETTLE   Each particle is drawn onto its portal's rim by a
//                critically damped spring (closed form, no overshoot),
//                landing as the portal's glass fades up under it.
//
//  Between phases nothing is eased: each hand-over happens at an instant
//  when every particle is at rest, so position and velocity are both
//  continuous. Any pinch skips to the end; under Reduce Motion there are
//  no particles at all and the portals simply fade in.
//

import Foundation
import simd

enum Opening {

    // MARK: The clock

    /// The particles fade up at rest.
    static let gatherDuration = 0.25
    static let swirlStart = gatherDuration
    /// One cyclotron period: the cycloid's full arch, rest to rest.
    static let swirlDuration = 0.9
    static let rippleStart = swirlStart + swirlDuration
    static let rippleDuration = 0.75
    static let settleStart = rippleStart + rippleDuration
    static let settleDuration = 0.75
    /// The instant the particles land on the rims — and the bell strikes.
    /// Pinned to `SoundPalette.calibrationLanding` by test.
    static let landingTime = settleStart + settleDuration
    /// The portals' glass fades up as the particles arrive.
    static let portalFadeStart = landingTime - 0.4
    static let portalFadeDuration = 0.5
    /// The particles go out once they have drawn the rims.
    static let particleFadeDuration = 0.35
    /// The labels and the wordmark come last.
    static let labelFadeStart = landingTime
    static let labelFadeDuration = 0.4
    /// When everything has landed and the per-frame path can go quiet.
    static let duration = max(landingTime + particleFadeDuration,
                              labelFadeStart + labelFadeDuration)

    // MARK: The physics

    /// Standard gravity, m/s² — the same g everywhere in the app.
    static let g = 9.80665
    /// |ω| = |q|B/m, rad/s: one full arch in `swirlDuration`.
    static let cyclotronRate = 2 * Double.pi / swirlDuration
    /// How far one arch carries a charge sideways: the drift speed g/ω
    /// times the period 2π/ω.
    static var driftPerArch: Double { 2 * .pi * g / (cyclotronRate * cyclotronRate) }
    /// How far below its start an arch dips at its lowest: 2g/ω².
    static var archDepth: Double { 2 * g / (cyclotronRate * cyclotronRate) }

    /// The ripple: a deep-water gravity wave across the sheet, travelling
    /// away from the viewer (−z).
    static let wavelength = 1.5
    static var waveNumber: Double { 2 * .pi / wavelength }
    /// ω² = g·k — deep water.
    static var waveFrequency: Double { (g * waveNumber).squareRoot() }
    /// Small against the wavelength (k·A ≈ 0.28), where the linear
    /// solution holds.
    static let waveAmplitude = 0.068

    /// The settling spring's rate, 1/s. Critically damped: the fastest
    /// approach with no overshoot.
    static let settleRate = 9.0

    // MARK: One particle

    struct Particle: Equatable {
        /// Where it rests on the sheet when the opening begins.
        let start: SIMD3<Double>
        /// +1 or −1: which way the field curls it.
        let charge: Double
        /// Which portal it ends on, in arc order.
        let portal: Int
        /// The point on that portal's rim it lands at.
        let target: SIMD3<Double>
    }

    /// Displacement from rest after `time` in crossed fields: gravity −y,
    /// B along +z, charge sign `charge`. From m·dv/dt = q·v×B + m·g with
    /// v(0) = 0:
    ///   vx = −(g/ω)(1 − cos ωt),   vy = −(g/ω) sin ωt,
    ///   x  = −(g/ω)t + (g/ω²) sin ωt,   y = (g/ω²)(cos ωt − 1),
    /// with ω signed by the charge.
    static func cycloid(time: Double, charge: Double) -> SIMD3<Double> {
        let omega = charge * cyclotronRate
        let x = -(g / omega) * time + (g / (omega * omega)) * sin(omega * time)
        let y = (g / (omega * omega)) * (cos(omega * time) - 1)
        return SIMD3(x, y, 0)
    }

    /// The cycloid's velocity, for the energy check.
    static func cycloidVelocity(time: Double, charge: Double) -> SIMD3<Double> {
        let omega = charge * cyclotronRate
        return SIMD3(-(g / omega) * (1 - cos(omega * time)),
                     -(g / omega) * sin(omega * time),
                     0)
    }

    /// Where a particle rests after its arch: exactly one drift sideways.
    static func afterSwirl(_ particle: Particle) -> SIMD3<Double> {
        particle.start + cycloid(time: swirlDuration, charge: particle.charge)
    }

    /// The ripple's envelope: zero, with zero slope, at both ends.
    static func rippleEnvelope(_ elapsed: Double) -> Double {
        let phase = min(max(elapsed / rippleDuration, 0), 1)
        let s = sin(.pi * phase)
        return s * s
    }

    /// Airy's surface orbit at a rest point, `elapsed` into the ripple.
    /// The wave runs along −z, so ξ = −z is the distance travelled.
    static func ripple(at rest: SIMD3<Double>, elapsed: Double) -> SIMD3<Double> {
        let amplitude = waveAmplitude * rippleEnvelope(elapsed)
        let phase = waveNumber * (-rest.z) - waveFrequency * elapsed
        // ξ = ξ₀ − A sin θ, so z = z₀ + A sin θ; η = A cos θ.
        return SIMD3(0, amplitude * cos(phase), amplitude * sin(phase))
    }

    /// A critically damped spring from rest at `from` toward `to`:
    /// x(τ) = to + (from − to)(1 + Ωτ)e^(−Ωτ).
    static func settle(from: SIMD3<Double>, to: SIMD3<Double>,
                       elapsed: Double) -> SIMD3<Double> {
        let tau = max(elapsed, 0)
        let decay = (1 + settleRate * tau) * exp(-settleRate * tau)
        return to + (from - to) * decay
    }

    /// Where `particle` is at `time` into the opening.
    static func position(of particle: Particle, at time: Double) -> SIMD3<Double> {
        switch time {
        case ..<swirlStart:
            return particle.start
        case ..<rippleStart:
            return particle.start + cycloid(time: time - swirlStart,
                                            charge: particle.charge)
        case ..<settleStart:
            let rest = afterSwirl(particle)
            return rest + ripple(at: rest, elapsed: time - rippleStart)
        case ..<landingTime:
            return settle(from: afterSwirl(particle), to: particle.target,
                          elapsed: time - settleStart)
        default:
            return particle.target
        }
    }

    // MARK: Light

    /// 0 → 1 over [start, start + span], eased at both ends.
    static func ramp(_ time: Double, from start: Double, over span: Double) -> Float {
        let x = min(max((time - start) / max(span, 1e-6), 0), 1)
        return Float(x * x * (3 - 2 * x))
    }

    static func particleOpacity(at time: Double) -> Float {
        ramp(time, from: 0, over: gatherDuration)
            * (1 - ramp(time, from: landingTime, over: particleFadeDuration))
    }

    static func portalOpacity(at time: Double) -> Float {
        ramp(time, from: portalFadeStart, over: portalFadeDuration)
    }

    static func labelOpacity(at time: Double) -> Float {
        ramp(time, from: labelFadeStart, over: labelFadeDuration)
    }

    static func isFinished(at time: Double) -> Bool { time >= duration }

    // MARK: The cloud

    /// The sheet's height above the floor: above eye level, so the arches
    /// dip toward the wearer's eyes and the portals are below it.
    static let sheetHeight = 1.95

    /// The particles for these portals: `perPortal` each, deterministic.
    /// Left-hand portals take positive charges (they drift −x), right-hand
    /// ones negative; each particle starts one drift upstream of its
    /// portal, so the arch delivers it overhead and the two streams cross.
    static func particles(for portals: [PortalLayout.Portal],
                          perPortal: Int = 30,
                          rimRadius: Double = PortalLayout.rimRadius) -> [Particle] {
        var state: UInt64 = 0x5DEECE66D
        func random() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / Double(UInt64.max >> 11)
        }
        var out: [Particle] = []
        for (index, portal) in portals.enumerated() {
            let charge: Double = portal.position.x < 0 ? 1 : -1
            for slot in 0..<perPortal {
                // Wide enough that neighbouring portals' particles meet, so
                // the sheet the wave crosses is one sheet, not six clusters.
                let start = SIMD3(
                    portal.position.x + charge * driftPerArch + (random() - 0.5) * 0.62,
                    sheetHeight + (random() - 0.5) * 0.10,
                    portal.position.z + (random() - 0.5) * 0.60)
                let angle = 2 * Double.pi * Double(slot) / Double(perPortal)
                let target = portal.position
                    + portal.right * (rimRadius * cos(angle))
                    + SIMD3(0, rimRadius * sin(angle), 0)
                out.append(Particle(start: start, charge: charge,
                                    portal: index, target: target))
            }
        }
        return out
    }
}

/// Where the six portals stand: one arc at eye level around the wearer,
/// facing them. Pure geometry, so it is tested on numbers.
enum PortalLayout {
    struct Portal: Equatable {
        /// The portal's centre, in the space's coordinates.
        let position: SIMD3<Double>
        /// Rotation about +y that turns the portal's face to the wearer.
        let yaw: Double
        /// The portal's own right, horizontal.
        let right: SIMD3<Double>
    }

    /// Far enough that six fit the field of view with a turn of the head,
    /// near enough to read a 30 cm portal.
    static let radius = 1.75
    /// Eye height for a standing wearer, a little low for a seated one.
    static let height = 1.35
    /// Between neighbouring portals, degrees.
    static let step = 20.0
    /// The portal's rim, metres: what the particles draw.
    static let rimRadius = 0.17

    static func portals(count: Int) -> [Portal] {
        (0..<count).map { index in
            let degrees = (Double(index) - Double(count - 1) / 2) * step
            let azimuth = degrees * .pi / 180
            let position = SIMD3(radius * sin(azimuth), height, -radius * cos(azimuth))
            return Portal(position: position,
                          yaw: -azimuth,
                          right: SIMD3(cos(azimuth), 0, sin(azimuth)))
        }
    }
}
