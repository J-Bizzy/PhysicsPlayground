//
//  CelestialBody.swift
//  PhysicsCore — Gravitation
//
//  A gravitating body in real SI units: kilograms, meters, m/s. The
//  presets are the actual solar system — real masses, radii, orbital
//  distances, and mean orbital speeds — so every number a panel shows
//  can be checked against an almanac.
//

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

    /// This body placed on a circular prograde orbit of `central` at
    /// `distance`, in the xz plane (offset along +x, moving along −z).
    public func onCircularOrbit(
        of central: CelestialBody,
        distance: Double,
        gravitationalConstant G: Double = NBody.gravitationalConstant
    ) -> CelestialBody {
        var body = self
        let speed = NBody.circularOrbitSpeed(
            centralMass: central.mass, distance: distance, gravitationalConstant: G)
        body.position = central.position + SIMD3(distance, 0, 0)
        body.velocity = central.velocity + SIMD3(0, 0, -speed)
        return body
    }
}
