//
//  MeanElements.swift
//  PhysicsCore — Astronomy
//
//  A planet's place from JPL's Keplerian mean elements (E. M. Standish,
//  "Keplerian Elements for Approximate Positions of the Major Planets",
//  valid 1800–2050), and from it the Sun as seen from there — which is how
//  Deep space puts the Sun in its sky: the view from Pluto's distance, a
//  star of magnitude −19 too small to show a disc.
//

import Foundation
import simd

public struct MeanElements: Sendable, Equatable {
    /// Semi-major axis, AU; eccentricity; inclination, mean longitude,
    /// longitude of perihelion and longitude of the ascending node, degrees
    /// — each at J2000 with its rate per Julian century.
    public var a: (Double, Double)
    public var e: (Double, Double)
    public var inclination: (Double, Double)
    public var meanLongitude: (Double, Double)
    public var perihelionLongitude: (Double, Double)
    public var ascendingNode: (Double, Double)

    public static func == (l: MeanElements, r: MeanElements) -> Bool {
        l.a == r.a && l.e == r.e && l.inclination == r.inclination
            && l.meanLongitude == r.meanLongitude
            && l.perihelionLongitude == r.perihelionLongitude && l.ascendingNode == r.ascendingNode
    }

    /// Pluto (Standish, Table 1, 1800–2050).
    public static let pluto = MeanElements(
        a: (39.48211675, -0.00031596),
        e: (0.24882730, 0.00005170),
        inclination: (17.14001206, 0.00004818),
        meanLongitude: (238.92903833, 145.20780515),
        perihelionLongitude: (224.06891629, -0.04062942),
        ascendingNode: (110.30393684, -0.01183482))

    /// The Julian date at the start of a calendar day (Gregorian, 0h).
    public static func julianDate(year: Int, month: Int, day: Int) -> Double {
        var y = year, m = month
        if m <= 2 { y -= 1; m += 12 }
        let a = y / 100, b = 2 - a + a / 4
        return Double(Int(365.25 * Double(y + 4716))) + Double(Int(30.6001 * Double(m + 1)))
            + Double(day) + Double(b) - 1524.5
    }

    public static let j2000 = 2_451_545.0

    /// Heliocentric position, AU, in the J2000 ecliptic frame.
    public func heliocentricEcliptic(julianDate: Double) -> SIMD3<Double> {
        let t = (julianDate - Self.j2000) / 36525
        func at(_ v: (Double, Double)) -> Double { v.0 + v.1 * t }
        let deg = Double.pi / 180
        let a = at(self.a), e = at(self.e), i = at(inclination) * deg
        let node = at(ascendingNode) * deg
        let perihelion = at(perihelionLongitude) * deg
        let argument = perihelion - node
        let mean = remainder(at(meanLongitude) * deg - perihelion, 2 * .pi)
        let anomaly = KeplerOrbit.eccentricAnomaly(meanAnomaly: mean, eccentricity: e)
        let xp = a * (cos(anomaly) - e)
        let yp = a * (1 - e * e).squareRoot() * sin(anomaly)
        let co = cos(argument), so = sin(argument), cn = cos(node), sn = sin(node)
        let ci = cos(i), si = sin(i)
        return SIMD3((co * cn - so * sn * ci) * xp + (-so * cn - co * sn * ci) * yp,
                     (co * sn + so * cn * ci) * xp + (-so * sn + co * cn * ci) * yp,
                     (so * si) * xp + (co * si) * yp)
    }

    /// The Sun as seen from this body on `julianDate`: its direction (J2000
    /// equatorial unit vector), distance, apparent magnitude
    /// (−26.74 + 5 log₁₀ r) and angular diameter (1919.3″ / r).
    public func sunSeen(julianDate: Double)
    -> (direction: SIMD3<Double>, distance: Double, magnitude: Double, diameter: Double) {
        let place = heliocentricEcliptic(julianDate: julianDate)
        let distance = simd_length(place)
        let direction = CelestialSphere.equatorial(fromEcliptic: -place / distance)
        let arcsecond = Double.pi / (180 * 3600)
        return (direction, distance, -26.74 + 5 * log10(distance), 1919.3 / distance * arcsecond)
    }
}
