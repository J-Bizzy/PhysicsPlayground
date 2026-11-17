//
//  StellarPhotometry.swift
//  PhysicsCore — Astronomy
//
//  How bright, and how big, a star of magnitude m is drawn. Magnitudes are
//  logarithmic — five steps is a factor of 100 in flux — so flux is
//  10^(−0.4 m). A star is a point: on a display, as in an eye or a
//  camera, it is a small blur whose BRIGHTNESS carries its light until the
//  blur's centre is as bright as the display can go; past that the blur
//  widens, and the light the eye itself scatters — its glare — shows
//  round it. So a faint star is a dim point, a bright one a brilliant one
//  in a soft glow of its own colour, and the order is exact throughout.
//
//  A display cannot show the sky's whole range (Sirius is 1,500 times a
//  sixth-magnitude star), so the peak follows a power of the flux, stated
//  below. Until 2026-11-13 that power was 0.35 from a floor of 0.2, which
//  drew the faintest star mid-grey and 8,100 of the 9,096 stars within a
//  quarter of one another: a sky of equal dots.
//

import Foundation

public enum StellarPhotometry {

    /// The faintest magnitude drawn — the naked-eye limit, and the
    /// catalogue's.
    public static let limitingMagnitude = 6.5

    /// Flux relative to a star at the limit: 10^(−0.4 (m − 6.5)).
    public static func relativeFlux(magnitude m: Double) -> Double {
        pow(10, -0.4 * (m - limitingMagnitude))
    }

    // MARK: Brightness

    /// The limiting star's peak, in linear light: a twentieth of the
    /// display's white, plain against black and no more.
    public static let faintestPeak = 0.05
    /// The magnitude at which the peak reaches the display's white. The 22
    /// stars brighter than this are the ones that widen instead.
    public static let saturationMagnitude = 1.5
    /// The power of the flux the peak follows, fixed by the two numbers
    /// above: ln(1 / 0.05) / ln(100) ≈ 0.65. (1 would be the truth, and
    /// would put the limiting star at a hundredth of white: invisible.)
    public static let peakExponent = log(1 / faintestPeak)
        / log(relativeFlux(magnitude: saturationMagnitude))

    /// A star's drawn peak brightness in linear light, 0.05…1:
    /// 0.05 · f^0.65, reaching 1 at magnitude 1.5.
    public static func peakBrightness(magnitude m: Double) -> Double {
        min(max(faintestPeak * pow(relativeFlux(magnitude: m), peakExponent), faintestPeak), 1)
    }

    // MARK: Size

    /// A faint star's core, radians: 4′ — about 2.3 pixels on a display of
    /// 1.7′ per pixel, so it is a point and never a single shimmering pixel.
    public static let minimumSize = 4.0 / 60 * Double.pi / 180
    /// No star wider than 14′, under half the Moon.
    public static let maximumSize = 14.0 / 60 * Double.pi / 180
    /// The magnitude from which the core begins to widen (flux 10).
    public static let wideningMagnitude = 4.0

    /// A star's drawn angular size, radians: 4′ to magnitude 4, then
    /// widening as f^0.15 — and as f^0.3 once the peak has saturated, where
    /// the width is all that is left to carry the light. Sirius is 12.8′.
    public static func angularSize(magnitude m: Double) -> Double {
        let flux = relativeFlux(magnitude: m)
        let widening = max(flux / relativeFlux(magnitude: wideningMagnitude), 1)
        let saturated = max(flux / relativeFlux(magnitude: saturationMagnitude), 1)
        return min(minimumSize * pow(widening, 0.15) * pow(saturated, 0.15), maximumSize)
    }

    // MARK: Glare

    /// The glow round a bright star: the light the eye's own optics
    /// scatter. Its luminance falls as about 1/θ² from the star (the CIE
    /// disability-glare function, Vos 1984), so the angle out to which it
    /// can be seen grows as the square root of the flux.
    public struct Glare: Sendable, Equatable {
        /// How far out it reaches, radians.
        public var radius: Double
        /// Its level at the star, in linear light, against the star's 1.
        public var level: Double
    }

    /// The faintest star with a glare drawn (flux 25): the 174 brightest.
    public static let glareMagnitude = 3.0
    /// That star's glare: 0.16° out, a twentieth of white at its centre.
    public static let faintestGlareRadius = 0.16 * Double.pi / 180
    public static let faintestGlareLevel = 0.05
    /// No glare brighter than this at its centre: it is a veil, not a disc.
    public static let brightestGlareLevel = 0.42

    /// A star's glare, or nil for a star too faint to show one. The radius
    /// is 0.16° · √(f/25) — Sirius's reaches 1.25° — and the level
    /// 0.05 · (f/25)^0.45, compressed as the peak is, never over 0.42.
    public static func glare(magnitude m: Double) -> Glare? {
        let over = relativeFlux(magnitude: m) / relativeFlux(magnitude: glareMagnitude)
        guard over >= 1 else { return nil }
        return Glare(radius: faintestGlareRadius * over.squareRoot(),
                     level: min(faintestGlareLevel * pow(over, 0.45), brightestGlareLevel))
    }

    // MARK: The atlas a star is drawn from

    /// Temperature columns, evenly spaced in mireds (10⁶/T) — the scale on
    /// which equal steps look like equal steps of colour — from 30,000 K to
    /// 2,400 K.
    public static let temperatureColumns = 16
    public static let hottest = 30_000.0
    public static let coolest = 2_400.0
    /// Brightness rows, in equal RATIOS from the faintest peak to white —
    /// a factor of 1.22 a row, so no star is drawn more than a tenth off
    /// its own brightness.
    public static let brightnessRows = 16
    /// Glare rows, in equal ratios from the faintest glare to the brightest.
    public static let glareRows = 8

    /// The temperature a column is drawn at.
    public static func temperature(column: Int) -> Double {
        let hot = 1e6 / hottest, cool = 1e6 / coolest
        let t = Double(column) / Double(temperatureColumns - 1)
        return 1e6 / (hot + (cool - hot) * t)
    }

    /// The column nearest a temperature.
    public static func column(temperature t: Double) -> Int {
        let hot = 1e6 / hottest, cool = 1e6 / coolest
        let mired = min(max(1e6 / t, hot), cool)
        return Int(((mired - hot) / (cool - hot) * Double(temperatureColumns - 1)).rounded())
    }

    /// The peak brightness a row is drawn at.
    public static func brightness(row: Int) -> Double {
        faintestPeak * pow(1 / faintestPeak, Double(row) / Double(brightnessRows - 1))
    }

    /// The row nearest a peak brightness, by ratio.
    public static func row(brightness b: Double) -> Int {
        let share = log(min(max(b, faintestPeak), 1) / faintestPeak) / log(1 / faintestPeak)
        return Int((share * Double(brightnessRows - 1)).rounded())
    }

    /// The glare level a glare row is drawn at.
    public static func glareLevel(row: Int) -> Double {
        faintestGlareLevel * pow(brightestGlareLevel / faintestGlareLevel,
                                 Double(row) / Double(glareRows - 1))
    }

    /// The glare row nearest a level, by ratio.
    public static func glareRow(level: Double) -> Int {
        let clamped = min(max(level, faintestGlareLevel), brightestGlareLevel)
        let share = log(clamped / faintestGlareLevel) / log(brightestGlareLevel / faintestGlareLevel)
        return Int((share * Double(glareRows - 1)).rounded())
    }
}
