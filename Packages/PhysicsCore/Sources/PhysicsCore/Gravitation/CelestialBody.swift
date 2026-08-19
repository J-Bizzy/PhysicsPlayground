//  CelestialBody.swift — a gravitating body in SI units, with real solar-system presets (checkable against an almanac).

import Foundation
import simd

public struct CelestialBody: Equatable, Sendable {
    public var name: String
    /// kg
    public var mass: Double
    /// Physical radius in m (display code may inflate for visibility).
    public var radius: Double
    /// m, heliocentric-style coordinates (+y up; orbits live in the xz plane).
    public var position: SIMD3<Double>
    /// m/s
    public var velocity: SIMD3<Double>

    public init(name: String, mass: Double, radius: Double,
                position: SIMD3<Double> = .zero, velocity: SIMD3<Double> = .zero) {
        self.name = name
        self.mass = mass
        self.radius = radius
        self.position = position
        self.velocity = velocity
    }

    // MARK: Real values

    /// Astronomical unit, m.
    public static let astronomicalUnit = 1.495978707e11

    public static let sun = CelestialBody(
        name: "Sun", mass: 1.989e30, radius: 6.957e8)
    public static let mercury = CelestialBody(
        name: "Mercury", mass: 3.301e23, radius: 2.4397e6)
    public static let venus = CelestialBody(
        name: "Venus", mass: 4.867e24, radius: 6.0518e6)
    public static let earth = CelestialBody(
        name: "Earth", mass: 5.972e24, radius: 6.371e6)
    public static let moon = CelestialBody(
        name: "Moon", mass: 7.342e22, radius: 1.7374e6)
    public static let mars = CelestialBody(
        name: "Mars", mass: 6.417e23, radius: 3.3895e6)
    public static let jupiter = CelestialBody(
        name: "Jupiter", mass: 1.898e27, radius: 6.9911e7)
    public static let saturn = CelestialBody(
        name: "Saturn", mass: 5.683e26, radius: 5.8232e7)
    public static let uranus = CelestialBody(
        name: "Uranus", mass: 8.681e25, radius: 2.5362e7)
    public static let neptune = CelestialBody(
        name: "Neptune", mass: 1.024e26, radius: 2.4622e7)
    /// Ceres, standing in for every asteroid.
    public static let asteroid = CelestialBody(
        name: "Asteroid", mass: 9.38e20, radius: 4.73e5)

    /// Mean orbital distance from the Sun, AU (asteroid = Ceres).
    public static func meanOrbitAU(of name: String) -> Double? {
        switch name {
        case "Mercury": 0.387
        case "Venus": 0.723
        case "Earth": 1.0
        case "Mars": 1.524
        case "Jupiter": 5.204
        case "Saturn": 9.537
        case "Uranus": 19.19
        case "Neptune": 30.07
        case "Asteroid": 2.77
        default: nil
        }
    }

    /// Circular prograde orbit of `central` at `distance`, xz plane (+x offset, −z motion).
    /// Speed is √(G(M+m)/r), NOT √(GM/r): this is the relative two-body orbit; GM alone leaves it slightly elliptical (1.2% for the Moon).
    public func onCircularOrbit(
        of central: CelestialBody,
        distance: Double,
        gravitationalConstant G: Double = NBody.gravitationalConstant
    ) -> CelestialBody {
        var body = self
        let speed = NBody.circularOrbitSpeed(
            centralMass: central.mass + mass, distance: distance,
            gravitationalConstant: G)
        body.position = central.position + SIMD3(distance, 0, 0)
        body.velocity = central.velocity + SIMD3(0, 0, -speed)
        return body
    }

    /// This body at PERIHELION of an inclined elliptical orbit. Exact vis-viva: v_p = √(G(M+m)(1+e)/(a(1−e))),
    /// M+m so it agrees with `onCircularOrbit` at e = 0. Plane = ecliptic tilted by `inclination` about +x.
    /// - Parameters: semiMajorAxis a (m); eccentricity e, 0..<1; inclination (rad).
    public func onEllipticalOrbit(
        of central: CelestialBody,
        semiMajorAxis: Double,
        eccentricity: Double,
        inclination: Double,
        gravitationalConstant G: Double = NBody.gravitationalConstant
    ) -> CelestialBody {
        var body = self
        let e = min(max(eccentricity, 0), 0.999)
        let perihelion = semiMajorAxis * (1 - e)
        let speed = (G * (central.mass + mass) * (1 + e) / perihelion).squareRoot()
        // In-plane basis: radius +x, velocity −z, tilted about +x.
        let cosI = cos(inclination), sinI = sin(inclination)
        let radial = SIMD3<Double>(1, 0, 0)
        let along = SIMD3<Double>(0, sinI, -cosI)
        body.position = central.position + radial * perihelion
        body.velocity = central.velocity + along * speed
        return body
    }

    /// Halley's comet to scale: a = 17.834 AU, e = 0.967, retrograde 162° inclination.
    public static let comet = CelestialBody(
        name: "Comet", mass: 2.2e14, radius: 5.5e3)
}
