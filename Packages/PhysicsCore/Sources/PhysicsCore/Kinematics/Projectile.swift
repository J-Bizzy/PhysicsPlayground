//
//  Projectile.swift
//  PhysicsCore — Kinematics
//
//  A projectile's aerodynamic identity: mass, diameter, and drag
//  coefficient — everything quadratic drag needs. The presets are real
//  objects with sourced-order-of-magnitude values, chosen so drag matters
//  visibly differently for each: a table-tennis ball is drag-dominated
//  (terminal velocity ≈ 9 m/s), a basketball noticeably affected, a golf
//  ball mildly (dimples: Cd ≈ 0.25 vs ≈ 0.47 for a smooth sphere), and a
//  cannonball barely at all.
//
//  Deliberate simplifications (documented, not hidden): Cd is constant
//  (no Reynolds-number dependence) and there is no spin — no Magnus lift,
//  so no curveballs or golf backspin carry.
//

import Foundation

public struct Projectile: Equatable, Sendable {
    public var name: String
    /// kg
    public var mass: Double
    /// m
    public var diameter: Double
    /// Dimensionless quadratic-drag coefficient.
    public var dragCoefficient: Double

    public init(name: String, mass: Double, diameter: Double, dragCoefficient: Double) {
        self.name = name
        self.mass = mass
        self.diameter = diameter
        self.dragCoefficient = dragCoefficient
    }

    /// Frontal area A = πd²/4, in m².
    public var crossSectionalArea: Double {
        .pi * diameter * diameter / 4
    }

    // MARK: Presets (regulation values; Cd ≈ 0.47 is the smooth-sphere value)

    public static let tableTennisBall = Projectile(
        name: "Table-tennis ball", mass: 0.0027, diameter: 0.040, dragCoefficient: 0.47)
    public static let basketball = Projectile(
        name: "Basketball", mass: 0.625, diameter: 0.242, dragCoefficient: 0.47)
    public static let golfBall = Projectile(
        name: "Golf ball", mass: 0.0459, diameter: 0.0427, dragCoefficient: 0.25)
    public static let cannonball = Projectile(
        name: "Cannonball", mass: 5.44, diameter: 0.117, dragCoefficient: 0.47)
}
