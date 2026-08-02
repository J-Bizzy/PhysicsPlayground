//
//  BobCollision.swift
//  PhysicsCore
//
//  Elastic collisions between pendulum bobs — the physics behind
//  Newton's cradle, and behind two swinging bobs that meet.
//
//  ONE DIMENSION, ALONG THE LINE OF CENTRES. Two bobs hanging from
//  neighbouring pivots meet moving almost exactly along the line joining
//  them, so the collision is the 1-D elastic problem every textbook
//  solves, applied to the velocity component along that line. The
//  perpendicular components pass through untouched, which is what a
//  frictionless contact does.
//
//  SEQUENTIAL, PAIRWISE, AND THAT IS THE WHOLE TRICK OF THE CRADLE.
//
//  A five-ball cradle sends exactly one ball out the far side, and the
//  reason is not "momentum and energy are conserved" — a simultaneous
//  five-body solve conserving both admits other answers, including two
//  balls leaving at reduced speed, which is not what real cradles do.
//  What picks the right answer is that the balls are not truly touching:
//  the impulse crosses the line as a compression wave, one contact at a
//  time. Resolving pairs in order along the line reproduces that, and it
//  is why `resolve` sweeps rather than solving a system.
//
//  So the "one ball out" behaviour here is a CONSEQUENCE of the model
//  rather than a special case in it. Nothing anywhere counts balls.
//

import Foundation

public enum BobCollision {

    /// How much slop counts as "touching", metres.
    ///
    /// Balls laid out at exactly one diameter apart are NOT reliably one
    /// diameter apart in floating point: five balls at `index * 0.04`
    /// puts the fourth gap at 0.04000000000000002, and an exact
    /// `gap <= radius + radius` silently declares that last pair out of
    /// contact. Not a test artifact — it is what a cradle at rest looks
    /// like in Double, and without this the impulse crossed four balls
    /// and stopped one short of the end.
    ///
    /// A nanometre is twelve orders of magnitude below anything this
    /// model resolves, so it cannot make two genuinely separated balls
    /// collide; it only stops arithmetic noise pulling a contact apart.
    public static let contactSlop = 1e-9

    /// One bob, as a collision cares about it.
    public struct Bob: Equatable, Sendable {
        /// Position along the line the bobs are strung out on, m.
        public var position: Double
        /// Velocity along that line, m/s.
        public var velocity: Double
        public var mass: Double
        public var radius: Double

        public init(position: Double, velocity: Double,
                    mass: Double, radius: Double) {
            self.position = position
            self.velocity = velocity
            self.mass = mass
            self.radius = radius
        }
    }

    /// The 1-D elastic collision, exact.
    ///
    ///     v₁' = ((m₁ − m₂)v₁ + 2m₂v₂) / (m₁ + m₂)
    ///     v₂' = ((m₂ − m₁)v₂ + 2m₁v₁) / (m₁ + m₂)
    ///
    /// Equal masses swap velocities exactly — which is the cradle, and
    /// which is why the cradle is made of identical balls.
    ///
    /// `restitution` of 1 is perfectly elastic. Below 1 the approach
    /// speed is scaled on rebound, conserving momentum but shedding
    /// energy: still exact, just for a different collision.
    public static func exchange(
        _ a: (velocity: Double, mass: Double),
        _ b: (velocity: Double, mass: Double),
        restitution: Double = 1
    ) -> (Double, Double) {
        let total = a.mass + b.mass
        guard total > 0 else { return (a.velocity, b.velocity) }
        let e = min(max(restitution, 0), 1)
        // Momentum-conserving form written around the centre of mass, so
        // restitution enters exactly once and momentum is conserved for
        // every value of it.
        let centreOfMass = (a.mass * a.velocity + b.mass * b.velocity) / total
        return (centreOfMass + e * (b.mass / total) * (b.velocity - a.velocity),
                centreOfMass + e * (a.mass / total) * (a.velocity - b.velocity))
    }

    /// Resolves every touching, approaching pair along a line, in order.
    ///
    /// `bobs` must be sorted by position. Returns the updated velocities
    /// and how many contacts were resolved — the count is what a caller
    /// uses to decide whether to play a click.
    ///
    /// The sweep repeats until no approaching contact remains, because
    /// one exchange can create another further along; the iteration cap
    /// is a safety net against a pathological arrangement, not an
    /// expected path, and it is generous enough that a real cradle never
    /// reaches it.
    @discardableResult
    public static func resolve(_ bobs: inout [Bob],
                               restitution: Double = 1) -> Int {
        guard bobs.count > 1 else { return 0 }
        var contacts = 0
        let maximumSweeps = 8 * bobs.count

        for _ in 0..<maximumSweeps {
            var touched = false
            for i in 0..<(bobs.count - 1) {
                let a = bobs[i]
                let b = bobs[i + 1]
                let gap = b.position - a.position
                let contact = a.radius + b.radius + contactSlop
                // Overlapping AND closing. The second half matters: a
                // pair still overlapping on the frame AFTER an exchange
                // is now separating, and resolving it again would reverse
                // a collision that already happened — the classic way to
                // make a cradle jitter and gain energy.
                guard gap <= contact, b.velocity - a.velocity < 0 else { continue }
                let (va, vb) = exchange((a.velocity, a.mass),
                                        (b.velocity, b.mass),
                                        restitution: restitution)
                bobs[i].velocity = va
                bobs[i + 1].velocity = vb
                contacts += 1
                touched = true
            }
            if !touched { break }
        }
        return contacts
    }

    /// Total momentum along the line, kg·m/s.
    public static func momentum(_ bobs: [Bob]) -> Double {
        bobs.reduce(0) { $0 + $1.mass * $1.velocity }
    }

    /// Total kinetic energy along the line, J.
    public static func kineticEnergy(_ bobs: [Bob]) -> Double {
        bobs.reduce(0) { $0 + 0.5 * $1.mass * $1.velocity * $1.velocity }
    }
}
