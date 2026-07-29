//
//  RoomWalls.swift
//  PhysicsCore — Kinematics
//
//  Finite wall rectangles a projectile can bounce off — the geometry
//  side of "the room is part of the experiment." Walls come from ARKit
//  plane detection on device (or a synthetic room in tests); the bounce
//  itself is the same impulse law the floor uses: the normal component
//  reverses scaled by restitution, the tangential component survives.
//
//  Walls are two-sided: a ball strikes whichever face it approaches,
//  so plane-anchor normal conventions never matter.
//

import Foundation
import simd

public enum RoomWalls {
    public struct Wall: Sendable, Equatable {
        public var center: SIMD3<Double>
        /// Unit normal (either face — strikes are two-sided).
        public var normal: SIMD3<Double>
        /// Unit in-plane axes spanning the rectangle.
        public var uAxis: SIMD3<Double>
        public var vAxis: SIMD3<Double>
        public var halfU: Double
        public var halfV: Double

        public init(center: SIMD3<Double>, normal: SIMD3<Double>,
                    uAxis: SIMD3<Double>, vAxis: SIMD3<Double>,
                    halfU: Double, halfV: Double) {
            self.center = center
            self.normal = normal
            self.uAxis = uAxis
            self.vAxis = vAxis
            self.halfU = halfU
            self.halfV = halfV
        }
    }

    public struct Hit: Sendable {
        /// Ball-center position at contact (its radius off the wall).
        public var position: SIMD3<Double>
        /// Velocity after the bounce.
        public var velocity: SIMD3<Double>
        /// How fast it hit, along the wall normal (for sound volume).
        public var impactSpeed: Double
    }

    /// The four vertical rectangles and the ceiling of an axis-aligned
    /// room box — the walls every ball can count on even before (or
    /// without) plane detection finding the real ones. The floor is the
    /// caller's own contact law.
    public static func box(of bounds: RoomBox) -> [Wall] {
        let c = bounds.center
        let h = bounds.halfExtents
        return [
            Wall(center: SIMD3(c.x + h.x, c.y, c.z), normal: SIMD3(-1, 0, 0),
                 uAxis: SIMD3(0, 0, 1), vAxis: SIMD3(0, 1, 0), halfU: h.z, halfV: h.y),
            Wall(center: SIMD3(c.x - h.x, c.y, c.z), normal: SIMD3(1, 0, 0),
                 uAxis: SIMD3(0, 0, 1), vAxis: SIMD3(0, 1, 0), halfU: h.z, halfV: h.y),
            Wall(center: SIMD3(c.x, c.y, c.z + h.z), normal: SIMD3(0, 0, -1),
                 uAxis: SIMD3(1, 0, 0), vAxis: SIMD3(0, 1, 0), halfU: h.x, halfV: h.y),
            Wall(center: SIMD3(c.x, c.y, c.z - h.z), normal: SIMD3(0, 0, 1),
                 uAxis: SIMD3(1, 0, 0), vAxis: SIMD3(0, 1, 0), halfU: h.x, halfV: h.y),
            Wall(center: SIMD3(c.x, c.y + h.y, c.z), normal: SIMD3(0, -1, 0),
                 uAxis: SIMD3(1, 0, 0), vAxis: SIMD3(0, 0, 1), halfU: h.x, halfV: h.z),
        ]
    }

    /// Checks the step segment `previous → current` against every wall
    /// and returns the earliest strike, or nil if the ball misses them
    /// all. `radius` inflates each wall so contact happens at the ball's
    /// surface, matching the floor-contact convention.
    public static func strike(
        previous: SIMD3<Double>, current: SIMD3<Double>,
        velocity: SIMD3<Double>, radius: Double, restitution: Double,
        walls: [Wall]
    ) -> Hit? {
        var best: (t: Double, hit: Hit)?
        for wall in walls {
            let s0 = simd_dot(previous - wall.center, wall.normal)
            let s1 = simd_dot(current - wall.center, wall.normal)
            // The face being approached: the side the ball starts on. A
            // ball sitting exactly ON the plane — where a zero-radius
            // reflection leaves it — belongs to the side it is moving
            // toward; classifying it by s0's sign alone would read the
            // receding ball as striking the back face and undo the bounce.
            let side: Double
            if abs(s0) > 1e-12 {
                side = s0 >= 0 ? 1 : -1
            } else {
                side = s1 >= 0 ? 1 : -1
            }
            let face = side * wall.normal
            let into = simd_dot(velocity, face)
            guard into < 0 else { continue }  // moving away, not striking

            let p0 = s0 * side - radius
            let p1 = s1 * side - radius

            let t: Double
            let contact: SIMD3<Double>
            if p0 >= -1e-9, p1 <= 1e-12 {
                // Clean crossing within this step. Landing EXACTLY on
                // the contact surface counts — an integration step can
                // end right on the plane (e.g. 5 m/s at 1/240 s lands on
                // x = 2 to the bit), and "reached" must mean "struck" or
                // the next step walks through from the inside.
                t = max(p0, 0) / max(p0 - p1, 1e-12)
                contact = previous + t * (current - previous)
            } else if p0 < 0, p0 > -radius, p1 < p0 {
                // Started already inside the ball-radius shell (a spawn
                // near the wall, or numeric residue from a prior bounce)
                // and burrowing deeper: reflect immediately, pushed back
                // to the surface — nothing may tunnel through quietly.
                t = 0
                contact = current + face * (radius - s1 * side)
            } else {
                continue
            }
            guard abs(simd_dot(contact - wall.center, wall.uAxis)) <= wall.halfU + radius,
                  abs(simd_dot(contact - wall.center, wall.vAxis)) <= wall.halfV + radius
            else { continue }

            let bounced = velocity - (1 + restitution) * into * face
            let hit = Hit(position: contact, velocity: bounced, impactSpeed: -into)
            if best == nil || t < best!.t {
                best = (t, hit)
            }
        }
        return best?.hit
    }
}
