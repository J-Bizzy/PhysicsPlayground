//
//  StellarPhotometry.swift
//  PhysicsCore — Astronomy
//
//  How bright, and how big, a star of magnitude m is drawn. Magnitudes are
//  logarithmic — five steps is a factor of 100 in flux — so flux is
//  10^(−0.4 m). A display cannot show a range of 10⁷ (Sirius against a
//  sixth-magnitude star), so it is compressed the way any sky photograph
//  compresses it: a bright star is drawn both brighter and larger, each by
//  a small power of its flux, keeping the order exact and the faintest
//  star at least a few device pixels wide so it never shimmers.
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

    /// The faintest star's core, radians: 4.5′ — about 2.6 pixels on a
    /// display of 1.7′ per pixel, so it is never a single shimmering pixel.
    public static let minimumSize = 4.5 / 60 * Double.pi / 180
    /// No star wider than 18′, a little over half the Moon.
    public static let maximumSize = 18.0 / 60 * Double.pi / 180

    /// A star's drawn angular size, radians: 4.5′ · f^0.17, never under
    /// 4.5′ (the catalogue runs a little past the limit) nor over 18′.
    public static func angularSize(magnitude m: Double) -> Double {
        min(max(minimumSize * pow(relativeFlux(magnitude: m), 0.17), minimumSize), maximumSize)
    }

    /// A star's drawn peak brightness, 0.2…1: 0.2 · f^0.35, saturating at
    /// about magnitude 1.5.
    public static func peakBrightness(magnitude m: Double) -> Double {
        min(max(0.2 * pow(relativeFlux(magnitude: m), 0.35), 0.2), 1)
    }

    // MARK: The atlas a star is drawn from

    /// Temperature columns, evenly spaced in mireds (10⁶/T) — the scale on
    /// which equal steps look like equal steps of colour — from 30,000 K to
    /// 2,400 K.
    public static let temperatureColumns = 16
    public static let hottest = 30_000.0
    public static let coolest = 2_400.0
    /// Brightness rows.
    public static let brightnessRows = 8

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
        0.2 + 0.8 * Double(row) / Double(brightnessRows - 1)
    }

    /// The row nearest a peak brightness.
    public static func row(brightness b: Double) -> Int {
        Int(((min(max(b, 0.2), 1) - 0.2) / 0.8 * Double(brightnessRows - 1)).rounded())
    }
}
