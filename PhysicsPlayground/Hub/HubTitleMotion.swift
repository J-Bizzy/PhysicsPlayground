//
//  HubTitleMotion.swift
//  Physics Playground — Hub
//
//  How the wordmark's letters move, as pure functions of time (no
//  RealityKit, so they are tested on numbers). Every motion is physics,
//  because the title of a physics app should obey it:
//
//    Physics     each letter is dropped and bounces to rest — free fall
//                under g, then impacts with a coefficient of restitution,
//                every arc an exact parabola.
//    Playground  each letter hangs from its top edge like a sign and is
//                released from a tilt: a damped physical pendulum whose
//                frequency comes from the letter's own shape.
//    AT REST     a gentle travelling wave rolls along both lines; each
//                letter rises and falls with it and tilts with its slope.
//    THE GLINT   a highlight runs along the line, letter by letter —
//                first once the letters are down, then on a slow
//                repeat.
//    A TAP       hops the letter: thrown up, it falls and bounces like
//                the drop.
//
//  Distances are metres in the room and times seconds.
//

import Foundation

enum HubTitleMotion {

    /// The same g as everywhere in the app.
    static let g = Opening.g

    // MARK: Drop and bounce

    /// How high above its place each "Physics" letter is let go.
    static let dropHeight = 0.30
    /// The fraction of its speed a letter keeps at each impact.
    static let restitution = 0.42
    /// Bounces lower than this are not drawn: the letter is at rest.
    static let restHeight = 0.0008

    /// A body thrown straight up at `launchSpeed` from its resting place
    /// (0 for a body let go from rest at `height`), falling under g and
    /// bouncing with `restitution`: its height above the resting place
    /// `time` after release. Exactly 0 once the bounces die out.
    static func bounce(time: Double, height: Double = 0,
                       launchSpeed: Double = 0,
                       restitution e: Double = restitution) -> Double {
        guard time > 0 else { return height }
        // The first flight: from `height` with upward speed `launchSpeed`
        // until it reaches the resting place, y = h + v t − ½ g t².
        let v = launchSpeed
        let firstContact = (v + (v * v + 2 * g * height).squareRoot()) / g
        if time < firstContact {
            return height + v * time - 0.5 * g * time * time
        }
        // Then a train of parabolas, each launched at e times the speed
        // the last one landed with.
        var speed = e * (v * v + 2 * g * height).squareRoot()
        var start = firstContact
        while speed * speed / (2 * g) > restHeight {
            let flight = 2 * speed / g
            if time < start + flight {
                let t = time - start
                return speed * t - 0.5 * g * t * t
            }
            start += flight
            speed *= e
        }
        return 0
    }

    /// When a bounce is over: the time after release at which `bounce`
    /// first returns 0 for good.
    static func bounceDuration(height: Double = 0, launchSpeed: Double = 0,
                               restitution e: Double = restitution) -> Double {
        let v = launchSpeed
        var total = (v + (v * v + 2 * g * height).squareRoot()) / g
        var speed = e * (v * v + 2 * g * height).squareRoot()
        while speed * speed / (2 * g) > restHeight {
            total += 2 * speed / g
            speed *= e
        }
        return total
    }

    /// The upward speed a tap gives a letter: a 7 cm hop.
    static let hopSpeed = (2 * g * 0.07).squareRoot()

    // MARK: The swing

    /// How far each "Playground" letter is tilted when it is let go, radians.
    static let swingAmplitude = 0.55
    /// The swing's damping rate, 1/s: air and a stiff hinge, settling in
    /// about a second.
    static let swingDamping = 4.2

    /// A rectangle of `width` × `height` hung from the middle of its top
    /// edge, swinging in its own plane: ω₀² = m g d / I, with d = h/2 and
    /// I = m(h²/3 + w²/12) about the hinge.
    static func swingRate(width: Double, height: Double) -> Double {
        let d = height / 2
        let gyration = height * height / 3 + width * width / 12
        return (g * d / max(gyration, 1e-9)).squareRoot()
    }

    /// The letter's angle `time` after it is let go from rest at
    /// `amplitude`: an underdamped oscillator released from rest,
    /// θ = θ₀ e^(−γt) (cos ω_d t + (γ/ω_d) sin ω_d t).
    static func swing(time: Double, rate omega: Double,
                      amplitude: Double = swingAmplitude,
                      damping gamma: Double = swingDamping) -> Double {
        guard time > 0 else { return amplitude }
        let damped = (max(omega * omega - gamma * gamma, 1e-9)).squareRoot()
        return amplitude * exp(-gamma * time)
            * (cos(damped * time) + gamma / damped * sin(damped * time))
    }

    // MARK: The arrival's clock

    /// Seconds after the home's arrival starts that the first "Physics"
    /// letter is let go: after the breath, so the wordmark has its own
    /// beat, down before the labs rise (2026-11-02).
    static let dropStart = Opening.titleStart
    /// Between successive "Physics" letters.
    static let dropStagger = 0.055
    /// When the first "Playground" letter is let go, and between them.
    static let swingStart = Opening.titleStart + 0.25
    static let swingStagger = 0.045
    /// How long a letter takes to fade up once it is let go.
    static let fadeIn = 0.12

    static func dropRelease(_ index: Int) -> Double {
        dropStart + Double(index) * dropStagger
    }

    static func swingRelease(_ index: Int) -> Double {
        swingStart + Double(index) * swingStagger
    }

    /// How far above its i the i's particle is let go, and when: once the
    /// i itself has come to rest, so the dot is the last thing to land.
    static let dotHeight = 0.12

    static func dotRelease(after letterRelease: Double) -> Double {
        letterRelease + bounceDuration(height: dropHeight) + 0.05
    }

    /// When the swing has died to under a twentieth of a degree.
    static func swingSettles(after release: Double) -> Double {
        release + log(swingAmplitude / 0.0009) / swingDamping
    }

    // MARK: At rest: the wave

    /// The wave's height, metres — a few millimetres, felt more than seen.
    static let waveHeight = 0.0035
    /// Its period and wavelength: a slow swell, about one line long.
    static let wavePeriod = 5.5
    static let wavelength = 0.62

    /// The wave at `x` along the line, `time` seconds in: how far it lifts
    /// a letter, and the slope it tilts the letter to. A travelling wave
    /// y = A sin(ωt − kx), whose slope is −Ak cos(ωt − kx).
    static func wave(at x: Double, time: Double,
                     phase: Double = 0) -> (lift: Double, tilt: Double) {
        let k = 2 * Double.pi / wavelength
        let omega = 2 * Double.pi / wavePeriod
        let theta = omega * time - k * x + phase
        return (waveHeight * sin(theta), -waveHeight * k * cos(theta))
    }

    // MARK: The glint

    /// How often the glint runs once the title is up, seconds.
    static let glintPeriod = 9.0
    /// How fast it runs along the line, m/s, and how wide it is.
    static let glintSpeed = 0.75
    static let glintWidth = 0.06
    /// Where it starts and ends, metres from the line's centre.
    static let glintReach = 0.36

    /// How lit the edge at `x` is, 0…1, `time` seconds after a glint
    /// began: a Gaussian band running left to right, gone by the far end.
    static func glint(at x: Double, since time: Double) -> Double {
        guard time >= 0 else { return 0 }
        let centre = -glintReach + glintSpeed * time
        guard centre < glintReach + 3 * glintWidth else { return 0 }
        let offset = (x - centre) / glintWidth
        return exp(-offset * offset)
    }
}
