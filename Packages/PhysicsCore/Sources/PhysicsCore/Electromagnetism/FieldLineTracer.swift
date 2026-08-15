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
        /// Lines drawn for a charge of `referenceCharge` magnitude.
        public var seedsPerCharge = 14
        /// The magnitude `seedsPerCharge` is quoted for. A charge twice
        /// this big gets twice as many lines.
        ///
        /// This is what makes a field-line diagram READ as a field.
        /// Every charge used to get the same fixed number of lines
        /// regardless of its size, so a 5 µC charge and a 0.5 µC charge
        /// drew identical bundles and the picture carried no information
        /// about strength at all — only brightness did. Line DENSITY is
        /// the classical encoding, and it is not a stylistic choice: the
        /// number of lines crossing a closed surface is proportional to
        /// the charge it encloses, which is Gauss's law drawn rather
        /// than written.
        public var referenceCharge = 1e-6
        /// Density is proportional, but bounded: one line is never
        /// enough to read as a source, and a huge charge must not blow
        /// the frame budget.
        public var seedRange: ClosedRange<Int> = 4...48

        /// Inner-face seeds the + plate's bands share, σ·A-weighted —
        /// see `trace(charges:capacitor:config:)`.
        public var plateSeedBudget = 24

        public init() {}

        /// How many lines a given charge earns.
        public func seedCount(forCharge magnitude: Double) -> Int {
            guard referenceCharge > 0 else { return seedsPerCharge }
            let proportional = Double(seedsPerCharge) * abs(magnitude) / referenceCharge
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

    /// Traces all field lines for the given charges. Each returned line is a
    /// polyline of points spaced ~stepSize apart.
    ///
    /// The seeding and integration are `StreamlineTracer.directedLines`,
    /// shared with the magnetic tracer; what stays here is the only
    /// genuinely electrostatic part — a charge's sign decides which way
    /// its lines run, and its magnitude decides how many it gets.
    public static func trace(charges: [PointCharge], config: Config) -> [[SIMD3<Double>]] {
        StreamlineTracer.directedLines(
            from: charges.map {
                StreamlineTracer.Seeded(
                    position: $0.position,
                    seeds: config.seedCount(forCharge: $0.charge),
                    sign: $0.isPositive ? 1 : -1)
            },
            seedRadius: config.seedRadius,
            stopCenters: charges.map(\.position),
            config: config.streamlineConfig,
            field: { ElectricField.vector(at: $0, dueTo: charges) })
    }

    /// Traces the FULL picture: point charges plus the calibrated
    /// capacitor, in each other's field — a charge near the gap bends
    /// the gap's lines and the plates bend the charge's, which is the
    /// whole reason the capacitor belongs in the same trace rather
    /// than drawn as its own decoration.
    ///
    /// Plate seeding is Gauss's law drawn, the same argument
    /// `seedCount(forCharge:)` makes for charges: seeds on the + plate
    /// are budgeted PER BAND in proportion to σ·A, so when a dielectric
    /// crowds the charge under itself, the crowding shows up as line
    /// density with no styling involved. A handful of outer-face seeds
    /// draw the wrap-around fringe every real capacitor has and the
    /// old uniform box never did.
    ///
    /// Lines END on conductors: every polyline is cut where it crosses
    /// a plate's rectangle, whichever side it arrives from.
    public static func trace(charges: [PointCharge],
                             capacitor: PlateField.Capacitor?,
                             config: Config) -> [[SIMD3<Double>]] {
        guard let capacitor else {
            return trace(charges: charges, config: config)
        }
        let field: (SIMD3<Double>) -> SIMD3<Double> = {
            ElectricField.vector(at: $0, dueTo: charges) + capacitor.field(at: $0)
        }

        var streamlineConfig = config.streamlineConfig
        // The plates are termination SURFACES, told to the integrator
        // rather than only to `cut`: without this a line that lands on
        // a plate integrates on through the far side at full RK4 cost
        // — up to `maxSteps` behind the conductor — for `cut` to throw
        // away afterwards. The predicate fires just PAST the plane
        // (depth under a step), so `cut` still finds the crossing and
        // trims to the exact hit; anything the predicate stops, `cut`
        // would have trimmed at the same point. The depth ceiling also
        // keeps it off the outer-face fringe seeds, which stand a
        // clearance (0.012) behind their plate by construction.
        let landingDepth = config.stepSize + 0.002
        streamlineConfig.stopWhere = { point in
            for rectangle in capacitor.rectangles {
                let outward: Double = rectangle.x < capacitor.center.x ? -1 : 1
                let depth = (point.x - rectangle.x) * outward
                if depth > 0, depth < landingDepth,
                   rectangle.yRange.lowerBound - 0.01 <= point.y,
                   point.y <= rectangle.yRange.upperBound + 0.01,
                   rectangle.zRange.lowerBound - 0.01 <= point.z,
                   point.z <= rectangle.zRange.upperBound + 0.01 {
                    return true
                }
            }
            return false
        }

        var lines = StreamlineTracer.directedLines(
            from: charges.map {
                StreamlineTracer.Seeded(
                    position: $0.position,
                    seeds: config.seedCount(forCharge: $0.charge),
                    sign: $0.isPositive ? 1 : -1)
            },
            seedRadius: config.seedRadius,
            stopCenters: charges.map(\.position),
            config: streamlineConfig,
            field: field)

        streamlineConfig.stopCenters = charges.map(\.position)
        for seed in plateSeeds(for: capacitor, config: config) {
            lines.append(StreamlineTracer.streamline(
                from: seed, sign: 1, field: field, config: streamlineConfig))
        }

        return lines.compactMap { cut($0, atPlatesOf: capacitor) }
    }

    /// Seed points just off the + plate's faces. Inner-face seeds carry
    /// the gap; a small fixed set of outer-face seeds carries the
    /// wrap-around fringe.
    static func plateSeeds(for capacitor: PlateField.Capacitor,
                           config: Config) -> [SIMD3<Double>] {
        let positives = capacitor.rectangles.filter { $0.sigma > 0 }
        let weights = positives.map { $0.sigma * $0.area }
        let totalWeight = weights.reduce(0, +)
        guard totalWeight > 0 else { return [] }

        var seeds: [SIMD3<Double>] = []
        let clearance = 0.012
        for (rectangle, weight) in zip(positives, weights) {
            let share = max(Int((Double(config.plateSeedBudget)
                                 * weight / totalWeight).rounded()), 2)
            // A near-square grid over the band, seeded at cell centres.
            let ySpan = rectangle.yRange.upperBound - rectangle.yRange.lowerBound
            let zSpan = rectangle.zRange.upperBound - rectangle.zRange.lowerBound
            let columns = max(Int((Double(share) * zSpan
                                   / max(ySpan, 1e-6)).squareRoot().rounded()), 1)
            let rows = max((share + columns - 1) / columns, 1)
            for row in 0..<rows {
                for column in 0..<columns where seeds.count < 4 * config.plateSeedBudget {
                    let y = rectangle.yRange.lowerBound
                        + ySpan * (Double(row) + 0.5) / Double(rows)
                    let z = rectangle.zRange.lowerBound
                        + zSpan * (Double(column) + 0.5) / Double(columns)
                    // Inner face — into the gap (+x: the + plate is on
                    // the −x side).
                    seeds.append(SIMD3(rectangle.x + clearance, y, z))
                }
            }
            // The outer face's fringe, a sparse 2×2 per band.
            for row in 0..<2 {
                for column in 0..<2 {
                    let y = rectangle.yRange.lowerBound
                        + ySpan * (Double(row) + 0.5) / 2
                    let z = rectangle.zRange.lowerBound
                        + zSpan * (Double(column) + 0.5) / 2
                    seeds.append(SIMD3(rectangle.x - clearance, y, z))
                }
            }
        }
        return seeds
    }

    /// Cuts a polyline where it lands on a plate — a field line ends on
    /// a conductor, whichever side it arrives from.
    static func cut(_ line: [SIMD3<Double>],
                    atPlatesOf capacitor: PlateField.Capacitor)
    -> [SIMD3<Double>]? {
        guard line.count > 1 else { return nil }
        let pad = 0.01
        var kept: [SIMD3<Double>] = [line[0]]
        for (a, b) in zip(line, line.dropFirst()) {
            var landed = false
            for rectangle in capacitor.rectangles {
                let da = a.x - rectangle.x
                let db = b.x - rectangle.x
                guard da == 0 || db == 0 || (da < 0) != (db < 0),
                      abs(da) + abs(db) > 1e-12 else { continue }
                let t = abs(da) / (abs(da) + abs(db))
                let hit = a + (b - a) * t
                if rectangle.yRange.lowerBound - pad <= hit.y,
                   hit.y <= rectangle.yRange.upperBound + pad,
                   rectangle.zRange.lowerBound - pad <= hit.z,
                   hit.z <= rectangle.zRange.upperBound + pad {
                    kept.append(hit)
                    landed = true
                    break
                }
            }
            if landed { break }
            kept.append(b)
        }
        return kept.count > 2 ? kept : nil
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
