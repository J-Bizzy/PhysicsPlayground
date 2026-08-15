//
//  StreamlineTracer.swift
//  PhysicsCore — Math
//
//  Domain-agnostic streamline integration: traces curves that follow the
//  direction of any vector field F(r), by 4th-order Runge–Kutta on the
//  *normalized* field, dr/ds = F(r)/|F(r)|. Normalizing gives unit-speed
//  (arc-length) parametrization: every step advances ~stepSize meters along
//  the curve regardless of the field's magnitude, so integration neither
//  blows up near singularities nor crawls in weak regions.
//
//  Electric field lines, magnetic field lines, and flow visualizations are
//  all streamlines — each module supplies its own field closure, seeding
//  policy, and termination sites.
//

import Foundation
import simd

public enum StreamlineTracer {
    public struct Config: Sendable {
        /// Arc length advanced per RK4 step, in meters.
        public var stepSize = 0.008
        public var maxSteps = 320
        /// A line ends when it comes this close to any of `stopCenters`
        /// (e.g. the charges field lines terminate on).
        public var stopCenters: [SIMD3<Double>] = []
        public var stopRadius = 0.04
        /// Lines also end when they wander this far from `boundsCenter`
        /// ("off to infinity" as far as the room is concerned).
        public var boundsCenter: SIMD3<Double> = .zero
        public var boundsRadius = 0.85
        /// Lines also end where this says they have landed — for
        /// termination sites that are SURFACES rather than points
        /// (a capacitor plate is a rectangle, and a sphere around its
        /// centre either misses the corners or swallows the gap).
        /// Without it a line that reaches a conductor integrates on
        /// through the far side at full step cost until `maxSteps` or
        /// the bounds catch it, for a caller to trim afterwards.
        public var stopWhere: (@Sendable (SIMD3<Double>) -> Bool)?

        public init() {}
    }

    /// Integrates a single streamline from `seed`, following sign·F/|F|.
    /// Returns points spaced ~stepSize apart.
    public static func streamline(
        from seed: SIMD3<Double>,
        sign: Double,
        field: (SIMD3<Double>) -> SIMD3<Double>,
        config: Config
    ) -> [SIMD3<Double>] {
        // Unit tangent of the streamline at a point; nil where the field
        // vanishes (equilibrium points, or a guarded singularity).
        func tangent(at point: SIMD3<Double>) -> SIMD3<Double>? {
            let value = field(point)
            let magnitude = simd_length(value)
            guard magnitude > 1e-12 else { return nil }
            return (sign / magnitude) * value
        }

        var points = [seed]
        var p = seed
        let h = config.stepSize
        let halfStep = h / 2

        for _ in 0..<config.maxSteps {
            // RK4: sample the direction at four staged points and blend.
            guard let k1 = tangent(at: p) else { break }
            guard let k2 = tangent(at: p + halfStep * k1) else { break }
            guard let k3 = tangent(at: p + halfStep * k2) else { break }
            guard let k4 = tangent(at: p + h * k3) else { break }
            var blended = k1 + k4
            blended += 2 * k2
            blended += 2 * k3
            p += (h / 6) * blended
            points.append(p)

            // Landed on a termination site or left the room.
            if config.stopCenters.contains(where: { simd_distance($0, p) < config.stopRadius }) {
                break
            }
            if simd_distance(p, config.boundsCenter) > config.boundsRadius {
                break
            }
            if config.stopWhere?(p) == true {
                break
            }
        }
        return points
    }

    /// One source's contribution to a field-line picture: where it is,
    /// and how many lines it earns.
    public struct Seeded: Sendable {
        public var position: SIMD3<Double>
        public var seeds: Int
        /// Which way lines run from this source: +1 out, −1 in. Ignored
        /// by `loopedLines`, which traces both ways regardless.
        public var sign: Double
        /// Where on the seed sphere this source's lines start.
        ///
        /// `nil` spreads them evenly over the whole sphere, which is
        /// right for a source with no preferred axis — a point charge
        /// radiates the same in every direction. A source that DOES have
        /// an axis supplies its own, because for those "evenly over the
        /// sphere" is the wrong distribution twice over: it draws as
        /// many lines out of the weak equator as out of the strong
        /// poles, and it does not know that the far hemisphere's seeds
        /// lie on loops the near hemisphere's have already drawn.
        public var directions: [SIMD3<Double>]?

        public init(position: SIMD3<Double>, seeds: Int, sign: Double = 1,
                    directions: [SIMD3<Double>]? = nil) {
            self.position = position
            self.seeds = seeds
            self.sign = sign
            self.directions = directions
        }
    }

    /// One line per seed, each traced a single direction.
    ///
    /// The electric case: lines begin on positive charges and end on
    /// negative ones, so a charge's own sign says which way its bundle
    /// runs. Tracing negatives backwards draws the same curves the
    /// incoming lines follow, which is why every charge radiates lines
    /// all the way around instead of showing them on one side only.
    public static func directedLines(
        from sources: [Seeded],
        seedRadius: Double,
        stopCenters: [SIMD3<Double>],
        config: Config,
        field: (SIMD3<Double>) -> SIMD3<Double>
    ) -> [[SIMD3<Double>]] {
        var config = config
        config.stopCenters = stopCenters
        var lines: [[SIMD3<Double>]] = []
        for source in sources {
            for direction in source.directions ?? fibonacciSphere(count: source.seeds) {
                let line = streamline(from: source.position + seedRadius * direction,
                                      sign: source.sign, field: field, config: config)
                if line.count > 1 { lines.append(line) }
            }
        }
        return lines
    }

    /// Both halves from each seed, spliced through it into one curve.
    ///
    /// The magnetic case, and the reason it needs its own function: with
    /// no monopoles there is nowhere for a line to start or stop, so a
    /// line leaving a north pole has to be followed *backwards* as well
    /// to close it. Tracing one direction only would draw half a loop
    /// and imply magnetic charge.
    public static func loopedLines(
        from sources: [Seeded],
        seedRadius: Double,
        stopCenters: [SIMD3<Double>],
        config: Config,
        field: (SIMD3<Double>) -> SIMD3<Double>
    ) -> [[SIMD3<Double>]] {
        var config = config
        config.stopCenters = stopCenters
        var lines: [[SIMD3<Double>]] = []
        for source in sources {
            for direction in source.directions ?? fibonacciSphere(count: source.seeds) {
                let seed = source.position + seedRadius * direction
                let forward = streamline(from: seed, sign: 1, field: field, config: config)
                let backward = streamline(from: seed, sign: -1, field: field, config: config)
                // Backward reversed, minus the seed it shares with
                // forward, then forward — one continuous curve through
                // the seed rather than two lines meeting at a kink.
                var line = Array(backward.reversed().dropLast())
                line.append(contentsOf: forward)
                if line.count > 2 { lines.append(line) }
            }
        }
        return lines
    }

    /// `count` directions spread nearly uniformly over a unit sphere
    /// (Fibonacci lattice — the standard trick for even spherical coverage).
    /// The usual seeding pattern for streamlines radiating from a point.
    public static func fibonacciSphere(count: Int) -> [SIMD3<Double>] {
        let goldenAngle = Double.pi * (3 - 5.0.squareRoot())
        return (0..<count).map { i in
            let y = 1 - 2 * (Double(i) + 0.5) / Double(count)
            let ringRadius = (1 - y * y).squareRoot()
            let phi = Double(i) * goldenAngle
            return SIMD3(ringRadius * cos(phi), y, ringRadius * sin(phi))
        }
    }
}
