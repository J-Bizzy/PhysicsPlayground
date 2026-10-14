//  SurfaceGravity.swift — quoted surface gravities (m/s²), one shared place.
//  Values: IAU/NASA fact sheets, equatorial surface gravity. They agree with GM/R² from
//  CelestialBody only via the equatorial R — Jupiter's stored radius is the 2%-smaller
//  volumetric mean (oblate) — and nothing is rotation-corrected (tests disprove
//  centrifugal cancellation).

import Foundation

public enum SurfaceGravity {
    public struct World: Sendable, Identifiable, Equatable {
        public let name: String
        /// Surface gravitational acceleration, m/s².
        public let gravity: Double
        public var id: String { name }

        public init(name: String, gravity: Double) {
            self.name = name
            self.gravity = gravity
        }
    }

    /// Zero gravity: a projectile is a straight line and a pendulum does not swing — the point.
    public static let zeroG = World(name: "Zero-g", gravity: 0)
    public static let moon = World(name: "Moon", gravity: 1.62)
    public static let earth = World(name: "Earth", gravity: 9.81)
    public static let jupiter = World(name: "Jupiter", gravity: 24.79)

    /// Real bodies only — for benches where zero-g has nothing to show.
    public static let bodies: [World] = [moon, earth, jupiter]

    /// Every setting, zero-g included.
    public static let all: [World] = [zeroG] + bodies
}
