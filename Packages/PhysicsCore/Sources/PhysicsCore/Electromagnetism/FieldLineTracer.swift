//
//  FieldLineTracer.swift
//  PhysicsCore — Electromagnetism
//
//  Electric field lines are streamlines of E, so this wrapper owns only the
//  electrostatics *policy* — where lines seed and where they terminate —
//  and delegates the RK4 integration to Math's StreamlineTracer.
//
//  Seeding: every charge gets a small Fibonacci sphere of seed points.
//  Positives are traced along +E (field lines begin there); negatives are
//  traced backwards along −E (field lines end there), which draws the same
//  curves the incoming lines follow — so every charge radiates lines all
//  around. In a dipole this draws some curves twice, which is harmless
//  overdraw, and it guarantees no charge ever shows lines on one side only.
//

import Foundation
import simd

public enum FieldLineTracer {
    public struct Config: Sendable {
        /// Arc length advanced per RK4 step, in meters.
        public var stepSize = 0.008
        public var maxSteps = 320
        /// Seeds start this far from the charge center…
        public var seedRadius = 0.05
        /// …and a line ends when it comes this close to any charge.
        /// Must be smaller than seedRadius or lines would die at birth.
        public var terminationRadius = 0.04
        /// Lines also end when they wander this far from `boundsCenter`.
        public var boundsCenter: SIMD3<Double> = .zero
        public var boundsRadius = 0.85
        public var seedsPerCharge = 14

        public init() {}

        var streamlineConfig: StreamlineTracer.Config {
            var config = StreamlineTracer.Config()
            config.stepSize = stepSize
            config.maxSteps = maxSteps
            config.stopRadius = terminationRadius
            config.boundsCenter = boundsCenter
            config.boundsRadius = boundsRadius
            return config
        }
    }

    /// Traces all field lines for the given charges. Each returned line is a
    /// polyline of points spaced ~stepSize apart.
    public static func trace(charges: [PointCharge], config: Config) -> [[SIMD3<Double>]] {
        var lines: [[SIMD3<Double>]] = []
        for charge in charges {
            let direction: Double = charge.isPositive ? 1 : -1
            for seedDir in fibonacciSphere(count: config.seedsPerCharge) {
                let seed = charge.position + config.seedRadius * seedDir
                let line = traceLine(from: seed, sign: direction, charges: charges, config: config)
                if line.count > 1 { lines.append(line) }
            }
        }
        return lines
    }

    /// Integrates a single line from `seed`, following sign·E/|E|.
    public static func traceLine(
        from seed: SIMD3<Double>,
        sign: Double,
        charges: [PointCharge],
        config: Config
    ) -> [SIMD3<Double>] {
        var streamlineConfig = config.streamlineConfig
        streamlineConfig.stopCenters = charges.map(\.position)
        return StreamlineTracer.streamline(
            from: seed,
            sign: sign,
            field: { ElectricField.vector(at: $0, dueTo: charges) },
            config: streamlineConfig
        )
    }

    public static func fibonacciSphere(count: Int) -> [SIMD3<Double>] {
        StreamlineTracer.fibonacciSphere(count: count)
    }
}
