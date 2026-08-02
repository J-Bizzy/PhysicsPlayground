//
//  MagneticFieldLineTracer.swift
//  PhysicsCore — Magnetism
//
//  Magnetic field lines are streamlines of B. Unlike electric lines they
//  form CLOSED LOOPS (no monopoles): a line leaving the north pole curves
//  back to the south. So each seed is traced BOTH ways along B and the two
//  halves joined into one continuous loop. The RK4 integration is Math's
//  shared StreamlineTracer; this file owns only the magnetism policy.
//
//  That policy was rewritten on 2026-07-31, after an on-device pass
//  reported the loops as "a little off". They were, in four separate
//  ways, and none of them was the integrator:
//
//  1. THE LINES WERE BORN INSIDE THE MAGNET. Seeds sat 6 cm from centre
//     and lines died at 5 cm, on a bar 16 cm long — so every loop
//     emerged from the middle of the bar's FLANK and vanished into it
//     again, leaving a dead sphere where the poles should be. The one
//     thing a bar magnet's field picture has to show is flux leaving one
//     end and entering the other.
//  2. THEY WERE TRACED THROUGH THE WRONG FIELD. See `MagneticField`'s
//     note on `barVector`: a point dipole is not a bar magnet at one
//     bar-length's range, and one bar-length is exactly where these
//     curves live.
//  3. THE SEEDS WERE SPREAD BY AREA, NOT BY FLUX. A Fibonacci sphere is
//     uniform in solid angle; a dipole's outward flux is not. Equal-area
//     seeding draws as many lines out of the equator — where the field
//     is weak and tangential — as out of the poles, so line density said
//     nothing. Density IS the classical encoding, and the electric
//     tracer next door has argued this in its own header for months.
//  4. HALF OF THEM WERE THE SAME LOOP TWICE. A loop through (R, θ)
//     passes through (R, π−θ) as well, so seeding both hemispheres and
//     then tracing each seed BOTH WAYS drew every curve about twice —
//     at random offsets, which is what made some loops read as thick
//     and others as thin for no reason.
//
//  And one consequence worth stating plainly, because the module's own
//  comments promised it and it was false: the strength bead now changes
//  the picture. It could not before. `StreamlineTracer` integrates the
//  NORMALIZED field, so a single magnet's traced geometry is completely
//  invariant to |m| — the loops were pixel-identical at strength 1 and
//  strength 12, and the bead you pulled rebuilt an unchanged mesh.
//

import Foundation
import simd

public enum MagneticFieldLineTracer {
    public struct Config: Sendable {
        public var stepSize = 0.01
        public var maxSteps = 260
        /// The bar's physical length (m) — what makes this a bar magnet
        /// rather than a point. Seeds, terminations and the field model
        /// itself are all derived from it.
        public var magnetLength = 0.16
        /// Seeds start this far out from the magnet's CENTRE. Must clear
        /// the bar's own half-length or the lines start underground.
        public var seedRadius: Double { magnetLength * seedStandoff }
        /// …and a line ends when it comes this close to a magnet centre.
        /// Just inside the seed sphere: any closer and short loops never
        /// close, any further and every line stops on the step it was
        /// born.
        public var terminationRadius: Double { seedRadius * 0.90 }
        /// Seed sphere radius as a multiple of the bar's length. 0.72
        /// puts it 15 % clear of the pole tips at 0.5.
        public var seedStandoff = 0.72
        public var boundsCenter: SIMD3<Double> = .zero
        public var boundsRadius = 1.1
        /// Lines drawn for a magnet of `referenceStrength`. A magnet
        /// twice as strong gets twice as many — see the header.
        public var seedsPerMagnet = 12
        public var referenceStrength = 6.0
        /// Proportional, but bounded: one loop does not read as a field,
        /// and a maxed-out magnet must not blow the frame budget.
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

    /// Seed directions on the NORTH half of a sphere around a dipole,
    /// one per equal slice of outward flux.
    ///
    /// The rule falls straight out of the dipole field. Its radial part
    /// is B_r ∝ cos θ, so the flux through a cap of half-angle θ is
    ///
    ///     Φ(θ) ∝ ∫₀^θ cos θ′ sin θ′ dθ′ ∝ sin²θ
    ///
    /// — the classical r = C sin²θ result, read as a seeding rule
    /// instead of a curve. Equal flux per line therefore means equal
    /// steps in sin²θ, which is what the square root below does. The
    /// azimuth is spread by the golden angle so the loops do not stack
    /// into a fan on one plane.
    ///
    /// North half only, and that is not an optimisation: each of these
    /// seeds is traced in BOTH directions and comes back a closed loop,
    /// and that loop already crosses the southern hemisphere. Seeding
    /// there too would redraw curves that are already on screen.
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

    /// Traces loops seeded EVENLY THROUGH A VOLUME rather than off a
    /// small sphere around each magnet.
    ///
    /// **This is a deliberate trade, and the thing it trades away is
    /// real.** `trace(magnets:config:)` above seeds by equal slices of
    /// outward flux, which is the classical encoding: line density means
    /// field strength, and that is why the flanks are sparse and the
    /// poles are dense. Seeding by VOLUME instead makes the picture even
    /// across the room and breaks that encoding — density here tells you
    /// where there was room to draw a line, not how strong the field is.
    ///
    /// It is still an honest picture, because every curve is a true
    /// streamline of B and the arrowheads still carry direction. It is
    /// just a picture of the field's SHAPE rather than of its strength,
    /// and the module's legend has to say so. Requested by the owner on
    /// 2026-08-01, who wanted the field to fill the room it is in.
    ///
    /// **Dedup is not optional here.** Seeds scattered through a volume
    /// land on the same closed loop over and over — the naive version
    /// draws a handful of curves many times each, at random offsets,
    /// which is precisely the "some loops read thick and others thin for
    /// no reason" defect the 2026-07-31 pass removed. A candidate whose
    /// path mostly retraces one already accepted is rejected.
    ///
    /// - Parameters:
    ///   - center/halfExtents: the room box to fill.
    ///   - spacing: how close two loops may come before they count as
    ///     the same loop.
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
        /// Each accepted line's samples, kept PER LINE rather than in one
        /// pooled set. Two reasons, and the first was a bug the tests
        /// caught rather than a precaution:
        ///
        /// · Overlap is NOT symmetric. A short loop lying entirely along
        ///   a longer one is ~100 % retraced by it, while the long one is
        ///   only partly retraced by the short. Testing one direction let
        ///   a curve through that was three-quarters a duplicate.
        /// · Against a pooled set, a candidate could be "mostly covered"
        ///   by fragments of several different loops without duplicating
        ///   any of them, and be rejected for it.
        ///
        /// So each candidate is compared with each accepted line on its
        /// own, BOTH ways, and rejected if either direction says the same
        /// curve. Subsampled because this is an O(n·m) sweep and full
        /// resolution buys nothing: two loops 11 cm apart are 11 cm apart
        /// at every eighth point too.
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
            // Mostly-overlapping means the same loop. Not ALL of it,
            // because every loop in a dipole field crowds through the
            // poles — two genuinely different curves share that
            // neighbourhood and diverge everywhere else.
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

    /// Points spread through a box with no clumping and no randomness.
    ///
    /// A jittered grid would need a random source, and this runs on a
    /// worker whose output has to be reproducible for tests. The
    /// additive-recurrence (R₃ / plastic-constant) sequence is the
    /// standard low-discrepancy answer: deterministic, and it fills a
    /// volume far more evenly than a lattice, which would put every seed
    /// on a plane and draw the field in slabs.
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
