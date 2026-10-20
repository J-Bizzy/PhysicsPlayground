//
//  StellarColour.swift
//  PhysicsCore — Astronomy
//
//  A star's colour from its catalogue B−V: the temperature by
//  Ballesteros' blackbody fit, then that blackbody's light as the eye's
//  three cone-weighted responses — Planck's law integrated against the CIE
//  1931 2° colour-matching functions — and those as sRGB. Betelgeuse
//  comes out orange and Rigel blue-white because that is what a 3,600 K
//  and an 11,000 K blackbody look like, not because anyone chose it.
//

import Foundation
import simd

public enum StellarColour {

    /// Effective temperature, K, from the B−V colour index (Ballesteros
    /// 2012, a blackbody fit): T = 4600 [1/(0.92 c + 1.7) + 1/(0.92 c + 0.62)].
    public static func temperature(bMinusV c: Double) -> Double {
        4600 * (1 / (0.92 * c + 1.7) + 1 / (0.92 * c + 0.62))
    }

    /// Planck's spectral radiance, W·sr⁻¹·m⁻³, at wavelength `lambda` (m).
    public static func planck(wavelength lambda: Double, temperature t: Double) -> Double {
        let h = Constants.planck, c = Constants.speedOfLight, k = Constants.boltzmann
        let exponent = h * c / (lambda * k * t)
        return 2 * h * c * c / pow(lambda, 5) / expm1(exponent)
    }

    /// The CIE 1931 2° colour-matching functions at `nanometres`: the
    /// multi-lobe Gaussian fit of Wyman, Sloan & Shirley (2013), within a
    /// few thousandths of the tabulated functions.
    public static func colourMatching(nanometres l: Double) -> SIMD3<Double> {
        func lobe(_ mu: Double, _ below: Double, _ above: Double) -> Double {
            let t = (l - mu) / (l < mu ? below : above)
            return exp(-0.5 * t * t)
        }
        let x = 1.056 * lobe(599.8, 37.9, 31.0) + 0.362 * lobe(442.0, 16.0, 26.7)
            - 0.065 * lobe(501.1, 20.4, 26.2)
        let y = 0.821 * lobe(568.8, 46.9, 40.5) + 0.286 * lobe(530.9, 16.3, 31.1)
        let z = 1.217 * lobe(437.0, 11.8, 36.0) + 0.681 * lobe(459.0, 26.0, 13.8)
        return SIMD3(x, y, z)
    }

    /// The tristimulus XYZ of a blackbody at `t` kelvin, normalised to
    /// Y = 1: its spectrum integrated over 380–780 nm in 1 nm steps.
    public static func tristimulus(temperature t: Double) -> SIMD3<Double> {
        var sum = SIMD3<Double>.zero
        for nm in stride(from: 380.0, through: 780.0, by: 1) {
            sum += planck(wavelength: nm * 1e-9, temperature: t) * colourMatching(nanometres: nm)
        }
        return sum / sum.y
    }

    /// CIE xy chromaticity of a blackbody at `t` kelvin.
    public static func chromaticity(temperature t: Double) -> SIMD2<Double> {
        let xyz = tristimulus(temperature: t)
        let total = xyz.x + xyz.y + xyz.z
        return SIMD2(xyz.x / total, xyz.y / total)
    }

    /// XYZ → linear sRGB (D65 white).
    static let xyzToLinearSRGB = simd_double3x3(rows: [
        SIMD3(3.2404542, -1.5371385, -0.4985314),
        SIMD3(-0.9692660, 1.8760108, 0.0415560),
        SIMD3(0.0556434, -0.2040259, 1.0572252),
    ])

    /// How much of a blackbody's chroma a star is drawn with. Even at full
    /// chroma a 3,600 K blackbody is only a light orange (Betelgeuse comes
    /// out 255/195/130), and real stars, seen by eye, are paler still — the
    /// cones barely engage at starlight. Stated, not hidden: 0.8 of it,
    /// where Betelgeuse reads orange beside a blue-white Rigel; the first
    /// stills at 0.35 and 0.5 left it beige.
    public static let displayChroma = 0.8

    /// The gamma-encoded sRGB colour a star of temperature `t` is drawn
    /// in, brightest channel at 1.
    public static func displayColour(temperature t: Double,
                                     chroma: Double = displayChroma) -> SIMD3<Double> {
        var linear = xyzToLinearSRGB * tristimulus(temperature: t)
        linear = simd_max(linear, .zero)
        linear /= max(linear.max(), 1e-12)
        // Toward white by (1 − chroma), in linear light.
        linear = SIMD3<Double>(repeating: 1) - chroma * (SIMD3<Double>(repeating: 1) - linear)
        return SIMD3(encode(linear.x), encode(linear.y), encode(linear.z))
    }

    /// The sRGB transfer function.
    static func encode(_ c: Double) -> Double {
        c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055
    }
}
