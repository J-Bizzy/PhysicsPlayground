//
//  StreamlineTracer.swift
//  PhysicsCore — Math: streamlines of any vector field, RK4 on the
//  Normalized field dr/ds = F/|F| — unit-speed arc-length steps, so it
//  neither blows up near singularities nor crawls in weak regions.
//

import Foundation
import simd

public enum StreamlineTracer {
    public struct Config: Sendable {
        /// Arc length advanced per RK4 step, in meters.
        public var stepSize = 0.008
        public var maxSteps = 320
        /// A line ends within `stopRadius` of any of these (e.g. charges).
        public var stopCenters: [SIMD3<Double>] = []
        public var stopRadius = 0.04
        /// Lines also end past `boundsRadius` from here ("off to infinity").
        public var boundsCenter: SIMD3<Double> = .zero
        public var boundsRadius = 0.85
        /// Termination test for surface sites (a plate is a rectangle; a stop
        /// sphere misses its corners or swallows the gap).
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
        // Unit tangent; nil where the field vanishes (equilibria, guarded singularity).
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
            guard let k1 = tangent(at: p) else { break }
            guard let k2 = tangent(at: p + halfStep * k1) else { break }
            guard let k3 = tangent(at: p + halfStep * k2) else { break }
            guard let k4 = tangent(at: p + h * k3) else { break }
            var blended = k1 + k4
            blended += 2 * k2
            blended += 2 * k3
            p += (h / 6) * blended
            points.append(p)

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

    /// One source: where it is, and how many lines it earns.
    public struct Seeded: Sendable {
        public var position: SIMD3<Double>
        public var seeds: Int
        /// +1 out, −1 in. Ignored by `loopedLines`, which traces both ways.
        public var sign: Double
        /// Seed directions; nil = uniform over the sphere (right for a point
        /// charge). Axial sources supply their own — uniform over-seeds the
        /// weak equator and re-draws loops the near hemisphere already drew.
        public var directions: [SIMD3<Double>]?

        public init(position: SIMD3<Double>, seeds: Int, sign: Double = 1,
                    directions: [SIMD3<Double>]? = nil) {
            self.position = position
            self.seeds = seeds
            self.sign = sign
            self.directions = directions
        }
    }

    /// One line per seed, traced one direction — the electric case: each
    /// charge's sign sets its bundle's direction (negatives trace backwards).
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

    /// Both halves from each seed, spliced into one curve — the magnetic
    /// case: no monopoles, so one-way tracing would imply magnetic charge.
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
                // Backward reversed, dropping the shared seed — one continuous curve, no kink.
                var line = Array(backward.reversed().dropLast())
                line.append(contentsOf: forward)
                if line.count > 2 { lines.append(line) }
            }
        }
        return lines
    }

    /// `count` near-uniform unit directions (Fibonacci sphere lattice).
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
