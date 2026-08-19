//
//  MagneticFieldLineTracer.swift
//  PhysicsCore — Magnetism: closed-loop streamlines of B for a bar magnet.
//
//  No monopoles: each seed is traced BOTH ways along B and the halves
//  joined into one continuous loop. RK4 integration is Math's shared
//  StreamlineTracer; this file owns only the magnetism policy: seeds must
//  clear the bar's half-length, use the bar (not point-dipole) field, and
//  seed by equal flux so line density encodes strength.

import Foundation
import simd

public enum MagneticFieldLineTracer {
    public struct Config: Sendable {
        public var stepSize = 0.01
        public var maxSteps = 260
        /// The bar's physical length (m). Seeds, terminations and the
        /// field model are all derived from it.
        public var magnetLength = 0.16
        /// Seeds start this far from centre. Must clear the bar's
        /// half-length or the lines start underground.
        public var seedRadius: Double { magnetLength * seedStandoff }
        /// A line ends this close to a magnet centre. Just inside the seed
        /// sphere: closer and short loops never close, further and every
        /// line stops on the step it was born.
        public var terminationRadius: Double { seedRadius * 0.90 }
        public var seedStandoff = 0.72
        public var boundsCenter: SIMD3<Double> = .zero
        public var boundsRadius = 1.1
        /// Lines for a magnet of `referenceStrength`; twice as strong gets
        /// twice as many.
        public var seedsPerMagnet = 12
        public var referenceStrength = 6.0
        /// Bounded: one loop does not read as a field, and a maxed magnet
        /// must not blow the frame budget.
        public var seedRange: ClosedRange<Int> = 5...30

        public init() {}

        /// How many loops a magnet of this strength earns.
        public func seedCount(forStrength magnitude: Double) -> Int {
            guard referenceStrength > 0 else { return seedsPerMagnet }
            let proportional = Double(seedsPerMagnet) * abs(magnitude) / referenceStrength
            let rounded = Int(proportional.rounded())
            return min(max(rounded, seedRange.lowerBound), seedRange.upperBound)
        }

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

    /// Traces looping field lines for the given magnets. Each returned line
    /// is a polyline spaced ~stepSize apart.
    public static func trace(magnets: [BarMagnet], config: Config) -> [[SIMD3<Double>]] {
        guard !magnets.isEmpty else { return [] }
        let length = config.magnetLength
        return StreamlineTracer.loopedLines(
            from: magnets.map { magnet in
                let count = config.seedCount(forStrength: magnet.strength)
                return StreamlineTracer.Seeded(
                    position: magnet.position,
                    seeds: count,
                    directions: fluxSeedDirections(axis: magnet.axis, count: count))
            },
            seedRadius: config.seedRadius,
            stopCenters: magnets.map(\.position),
            config: config.streamlineConfig,
            field: { MagneticField.barVector(at: $0, dueTo: magnets, length: length) })
    }

    /// Seed directions on the NORTH half of a sphere around a dipole, one
    /// per equal slice of outward flux. Flux through a cap of half-angle θ
    /// is Φ ∝ sin²θ (from B_r ∝ cos θ), so equal flux per line means equal
    /// steps in sin²θ — the square root below. Azimuth spread by the
    /// golden angle. North half only: each seed traces both ways into a
    /// closed loop that already crosses the south, so seeding it too
    /// redraws existing curves.
    public static func fluxSeedDirections(axis: SIMD3<Double>,
                                          count: Int) -> [SIMD3<Double>] {
        let n = max(count, 1)
        let pole = simd_length(axis) > 1e-12
            ? simd_normalize(axis) : SIMD3<Double>(0, 1, 0)
        // Any two axes perpendicular to the pole. The seed is chosen
        // away from the pole so the cross product is well conditioned.
        var reference = SIMD3<Double>(1, 0, 0)
        if abs(simd_dot(reference, pole)) > 0.9 { reference = SIMD3(0, 0, 1) }
        let u = simd_normalize(simd_cross(pole, reference))
        let v = simd_cross(pole, u)

        let goldenAngle = Double.pi * (3 - 5.0.squareRoot())
        return (0..<n).map { k in
            let sinTheta = ((Double(k) + 0.5) / Double(n)).squareRoot()
            let cosTheta = (max(0, 1 - sinTheta * sinTheta)).squareRoot()
            let phi = Double(k) * goldenAngle
            return sinTheta * (cos(phi) * u + sin(phi) * v) + cosTheta * pole
        }
    }

    // MARK: Even through the room

    /// Traces loops seeded EVENLY THROUGH A VOLUME rather than off a small
    /// sphere per magnet. Deliberate trade: density here means where there
    /// was room to draw a line, not field strength (the module legend must
    /// say so). Every curve is still a true streamline of B. Dedup is
    /// mandatory — volume seeds land on the same closed loop repeatedly, so
    /// a candidate that mostly retraces an accepted line is rejected.
    ///
    /// - Parameters:
    ///   - center/halfExtents: the room box to fill.
    ///   - spacing: how close two loops may come before they count as one.
    ///   - budget: hard cap on returned lines.
    public static func traceThroughVolume(
        magnets: [BarMagnet],
        config: Config,
        center: SIMD3<Double>,
        halfExtents: SIMD3<Double>,
        spacing: Double = 0.11,
        budget: Int = 26
    ) -> [[SIMD3<Double>]] {
        guard !magnets.isEmpty, budget > 0 else { return [] }
        let length = config.magnetLength
        let field = { (point: SIMD3<Double>) in
            MagneticField.barVector(at: point, dueTo: magnets, length: length)
        }
        var streamConfig = config.streamlineConfig
        streamConfig.stopCenters = magnets.map(\.position)

        var accepted: [[SIMD3<Double>]] = []
        /// Samples kept PER LINE, not pooled: overlap is not symmetric (a
        /// short loop lying along a long one is ~100% retraced by it but
        /// not vice versa), so each candidate is compared with each
        /// accepted line BOTH ways. Subsampled — an O(n·m) sweep, and two
        /// loops 11 cm apart are 11 cm apart at every eighth point too.
        var acceptedSamples: [[SIMD3<Double>]] = []

        /// The fraction of `a` that runs within `spacing` of `b`.
        func retracedFraction(_ a: [SIMD3<Double>], _ b: [SIMD3<Double>]) -> Double {
            guard !a.isEmpty, !b.isEmpty else { return 0 }
            var near = 0
            for point in a {
                var best = Double.infinity
                for other in b {
                    best = min(best, simd_distance(other, point))
                    if best < spacing { break }
                }
                if best < spacing { near += 1 }
            }
            return Double(near) / Double(a.count)
        }

        for seed in volumeSeeds(center: center, halfExtents: halfExtents,
                                count: budget * 8) {
            if accepted.count >= budget { break }
            // Not from inside a magnet, and not from a dead spot where
            // the field has no direction to follow.
            let tooClose = magnets.contains {
                simd_distance($0.position, seed) < config.seedRadius
            }
            if tooClose { continue }
            guard simd_length(field(seed)) > 1e-14 else { continue }

            let forward = StreamlineTracer.streamline(
                from: seed, sign: 1, field: field, config: streamConfig)
            let backward = StreamlineTracer.streamline(
                from: seed, sign: -1, field: field, config: streamConfig)
            var line = Array(backward.reversed().dropLast())
            line.append(contentsOf: forward)
            guard line.count > 8 else { continue }

            let samples = stride(from: 0, to: line.count, by: 8).map { line[$0] }
            // Mostly-overlapping means the same loop — not all, since every
            // dipole loop crowds through the poles yet diverges elsewhere.
            let isDuplicate = acceptedSamples.contains { existing in
                retracedFraction(samples, existing) > 0.55
                    || retracedFraction(existing, samples) > 0.55
            }
            if isDuplicate { continue }
            accepted.append(line)
            acceptedSamples.append(samples)
        }
        return accepted
    }

    /// Points spread through a box, deterministic (no random source, for
    /// reproducible tests). Additive-recurrence (R₃ / plastic-constant)
    /// low-discrepancy sequence fills a volume far more evenly than a
    /// lattice, which would put every seed on a plane.
    public static func volumeSeeds(center: SIMD3<Double>,
                                   halfExtents: SIMD3<Double>,
                                   count: Int) -> [SIMD3<Double>] {
        guard count > 0 else { return [] }
        // Plastic constant: the real root of x³ = x + 1.
        let plastic = 1.324717957244746
        let a = SIMD3<Double>(1 / plastic, 1 / (plastic * plastic),
                              1 / (plastic * plastic * plastic))
        return (0..<count).map { index in
            let n = Double(index) + 0.5
            let fractional = SIMD3<Double>(
                (a.x * n).truncatingRemainder(dividingBy: 1),
                (a.y * n).truncatingRemainder(dividingBy: 1),
                (a.z * n).truncatingRemainder(dividingBy: 1))
            return center + (2 * fractional - SIMD3(repeating: 1)) * halfExtents
        }
    }
}
