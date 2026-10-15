//
//  Spectrum.swift
//  RenderKit
//
//  The colour of light of one wavelength, as a display can show it. The
//  CIE 1931 colour-matching functions (Wyman, Sloan & Shirley's
//  multi-lobe fit, accurate to about 1 % of their peak) give the light's
//  XYZ; that converts to linear sRGB. A pure spectral colour lies outside
//  every display's gamut, so it is brought inside by adding the least
//  white that clears the negative channel — the hue is kept, only the
//  saturation gives — and normalised to full brightness.
//

import UIKit
import simd

public enum Spectrum {
    /// CIE 1931 2° observer at `nanometers`.
    public static func xyz(nanometers l: Double) -> SIMD3<Double> {
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

    /// Linear sRGB, each channel 0…1, brightest channel 1.
    public static func linearRGB(nanometers: Double) -> SIMD3<Double> {
        linearRGB(xyz: xyz(nanometers: nanometers))
    }

    /// Light of any spectrum, given its XYZ (the sum of its wavelengths'),
    /// as linear sRGB brought into gamut and to full brightness. Mixing in
    /// XYZ is what makes the whole spectrum together come out white.
    public static func linearRGB(xyz c: SIMD3<Double>) -> SIMD3<Double> {
        var rgb = SIMD3(3.2406 * c.x - 1.5372 * c.y - 0.4986 * c.z,
                        -0.9689 * c.x + 1.8758 * c.y + 0.0415 * c.z,
                        0.0557 * c.x - 0.2040 * c.y + 1.0570 * c.z)
        let lowest = rgb.min()
        if lowest < 0 { rgb -= SIMD3(repeating: lowest) }
        let highest = rgb.max()
        return highest > 0 ? rgb / highest : SIMD3(repeating: 1)
    }

    /// The colour to draw light of `nanometers` in.
    public static func color(nanometers: Double) -> UIColor {
        let rgb = linearRGB(nanometers: nanometers)
        func encode(_ v: Double) -> CGFloat {
            CGFloat(v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055)
        }
        return UIColor(red: encode(rgb.x), green: encode(rgb.y), blue: encode(rgb.z), alpha: 1)
    }
}
