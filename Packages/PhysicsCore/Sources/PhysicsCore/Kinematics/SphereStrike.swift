//  SphereStrike.swift — a ball against a moving sphere: an open hand
//  swatting it out of the air, or any round obstacle in the room.
//
//  The same contract as `RoomWalls.strike`: the earliest contact along
//  the step's segment, the velocity after it, how hard it hit, and `t`
//  so the caller can spend the rest of the frame along the new velocity
//  instead of freezing the ball at the contact. The sphere's own
//  velocity matters — a swat is a bounce off something that is moving,
//  so the reflection is of the RELATIVE velocity and the sphere's motion
//  is added back. A ball at rest hit by a hand at 3 m/s leaves at
//  3·(1 + e) m/s along the hand's line, which is what a swat is.

import Foundation
import simd

public enum SphereStrike {
    public struct Sphere: Sendable, Equatable {
        public var center: SIMD3<Double>
        public var radius: Double
        /// The sphere's own velocity, m/s.
        public var velocity: SIMD3<Double>

        public init(center: SIMD3<Double>, radius: Double,
                    velocity: SIMD3<Double> = .zero) {
            self.center = center
            self.radius = radius
            self.velocity = velocity
        }
    }

    public struct Hit: Sendable {
        /// Ball-centre position at contact: on the sphere's surface, its
        /// own radius out along the contact normal.
        public var position: SIMD3<Double>
        /// Velocity after the bounce, in the room's frame.
        public var velocity: SIMD3<Double>
        /// Closing speed along the contact normal (for sound volume).
        public var impactSpeed: Double
        /// How far along the step's segment the contact happened, 0…1.
        public var t: Double
    }

    /// Checks the step segment `previous → current` of a ball of `radius`
    /// against every sphere and returns the earliest strike, or nil if
    /// the ball meets none — or is already moving away from the one it
    /// touches. The sphere MOVES too: over a step of `dt` it is taken to
    /// have travelled `velocity · dt` to arrive at `center`, so the test
    /// runs in the sphere's own frame and a hand swung through a ball
    /// registers even when the two never overlap at a frame boundary
    /// (a hand at 4 m/s crosses more than a golf ball's reach in one
    /// 90 Hz frame). A ball that starts inside a sphere is resolved at
    /// t = 0: pushed to the surface and reflected if it was closing.
    public static func strike(
        previous: SIMD3<Double>, current: SIMD3<Double>,
        velocity: SIMD3<Double>, radius: Double, restitution: Double,
        spheres: [Sphere], dt: Double = 0
    ) -> Hit? {
        var best: (t: Double, hit: Hit)?
        for sphere in spheres {
            let reach = sphere.radius + radius
            // Where the sphere was when the step began, and the ball's
            // path relative to it.
            let sweep = sphere.velocity * max(dt, 0)
            let startCenter = sphere.center - sweep
            let offset = previous - startCenter
            let step = (current - sphere.center) - offset
            let a = simd_dot(step, step)
            let b = 2 * simd_dot(offset, step)
            let c = simd_dot(offset, offset) - reach * reach
            let t: Double
            if c <= 0 {
                t = 0
            } else {
                guard a > 1e-18 else { continue }
                let discriminant = b * b - 4 * a * c
                guard discriminant >= 0 else { continue }
                let candidate = (-b - discriminant.squareRoot()) / (2 * a)
                guard candidate >= 0, candidate <= 1 else { continue }
                t = candidate
            }
            let centerAtContact = startCenter + sweep * t
            let contact = previous + (current - previous) * t
            let toContact = contact - centerAtContact
            let distance = simd_length(toContact)
            guard distance > 1e-9 else { continue }
            let normal = toContact / distance
            let relative = velocity - sphere.velocity
            let approach = simd_dot(relative, normal)
            guard approach < 0 else { continue }
            let reflected = relative - (1 + restitution) * approach * normal
            let hit = Hit(position: centerAtContact + normal * reach,
                          velocity: reflected + sphere.velocity,
                          impactSpeed: -approach, t: t)
            if best == nil || t < best!.t { best = (t, hit) }
        }
        return best?.hit
    }
}
