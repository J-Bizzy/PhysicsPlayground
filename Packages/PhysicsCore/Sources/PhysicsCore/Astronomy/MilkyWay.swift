//
//  MilkyWay.swift
//  PhysicsCore — Astronomy
//
//  The Milky Way's glow as a function of galactic longitude and latitude:
//  a MODEL, not a photograph — an exponential thin disc that thickens and
//  brightens toward the centre, the bulge in Sagittarius, the Great Rift's
//  dust lane from Cygnus to Sagittarius, and the two Magellanic Clouds
//  where they really are. Its course across the sky is exactly the galactic
//  plane, so it arches through Cassiopeia, Perseus and Cygnus as the real
//  one does.
//

import Foundation
import simd

public enum MilkyWay {

    /// Relative surface brightness at galactic (l, b), radians: 0 far from
    /// the plane, about 1 at the galactic centre.
    public static func brightness(longitude l: Double, latitude b: Double) -> Double {
        let ld = wrapDegrees(l * 180 / .pi), bd = b * 180 / .pi
        // The disc: brighter and thicker toward the centre.
        let width = 3.5 + 5 * exp(-sq(ld / 45))
        let disc = (0.35 + 0.65 * exp(-sq(ld / 70))) * exp(-abs(bd) / width)
        // The bulge: a flattened 7° Gaussian on the centre.
        let bulge = 0.55 * exp(-(sq(ld) + sq(bd / 0.7)) / (2 * 49))
        // The Great Rift: dust just north of the plane from l −5° to 75°.
        let span = smoothstep(-8, -3, ld) * (1 - smoothstep(70, 78, ld))
        let rift = 1 - 0.6 * span * exp(-sq((bd - 0.8) / 1.5))
        // The Magellanic Clouds.
        let large = 0.32 * blob(ld, bd, centre: (280.47, -32.89), radius: 4.0)
        let small = 0.18 * blob(ld, bd, centre: (302.80, -44.30), radius: 2.0)
        return (disc + bulge) * rift + large + small
    }

    /// The glow's tint: warm toward the bulge, cool along the disc.
    public static func tint(longitude l: Double, latitude b: Double) -> SIMD3<Double> {
        let ld = wrapDegrees(l * 180 / .pi), bd = b * 180 / .pi
        let warmth = exp(-(sq(ld) + sq(bd)) / (2 * 400))
        let warm = SIMD3<Double>(1.0, 0.86, 0.68), cool = SIMD3<Double>(0.80, 0.86, 1.0)
        return cool + (warm - cool) * warmth
    }

    static func blob(_ l: Double, _ b: Double, centre: (Double, Double), radius: Double) -> Double {
        let dl = wrapDegrees(l - centre.0) * cos(b * .pi / 180)
        return exp(-(sq(dl) + sq(b - centre.1)) / (2 * sq(radius)))
    }

    /// Degrees into (−180, 180].
    static func wrapDegrees(_ d: Double) -> Double {
        var x = d.truncatingRemainder(dividingBy: 360)
        if x > 180 { x -= 360 }
        if x <= -180 { x += 360 }
        return x
    }

    static func sq(_ x: Double) -> Double { x * x }

    static func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let t = min(max((x - a) / (b - a), 0), 1)
        return t * t * (3 - 2 * t)
    }
}
