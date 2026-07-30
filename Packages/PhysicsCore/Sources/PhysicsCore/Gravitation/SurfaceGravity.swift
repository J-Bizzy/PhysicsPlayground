//
//  SurfaceGravity.swift
//  PhysicsCore — Gravitation
//
//  "What if this were the Moon?" — the one question two different labs
//  exist to answer, and the numbers behind it had been written out three
//  separate times: as four buttons in Projectiles, as three buttons in
//  Pendulums, and as a G-multiplier slider in Gravity Lab. One place now.
//
//  These are the quoted surface values, and they agree with `GM/R²` from
//  `CelestialBody` — but for Jupiter only if you use the right R, which
//  is the whole reason this note exists.
//
//  Earth and the Moon come out within a fraction of a percent of GM/R²
//  on `CelestialBody`'s radii. Jupiter appears not to: those radii are
//  VOLUMETRIC MEAN radii, and Jupiter's mean radius (69,911 km) is 2%
//  smaller than its equatorial one (71,492 km) because it is visibly
//  oblate — a 9.9-hour day flattens it. GM/R_mean² gives 25.9 m/s²;
//  GM/R_equatorial² gives 24.78, which is the quoted 24.79. So the
//  standard figure is equatorial, and nothing here is rotation-corrected
//  — the first draft of this comment claimed centrifugal cancellation
//  and `SurfaceGravityTests` disproved it: the shortfall is 1.13 m/s²
//  where ω²R would be 2.16.
//
//  Values: IAU / NASA planetary fact sheets (equatorial surface gravity).
//

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

    /// Not a world, but the most instructive setting in either lab: with
    /// no gravity a projectile is a straight line and a pendulum does not
    /// swing at all, which is the point.
    public static let zeroG = World(name: "Zero-g", gravity: 0)
    public static let moon = World(name: "Moon", gravity: 1.62)
    public static let earth = World(name: "Earth", gravity: 9.81)
    public static let jupiter = World(name: "Jupiter", gravity: 24.79)

    /// Real bodies only — for benches where zero gravity has nothing to
    /// show (a pendulum in free fall hangs slack; there is no period).
    public static let bodies: [World] = [moon, earth, jupiter]

    /// Every setting, zero-g included.
    public static let all: [World] = [zeroG] + bodies
}
