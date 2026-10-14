//
//  PlateField.swift
//  Exact closed-form field of a uniformly charged rectangle (SI), and the finite-plate capacitor built on it.
//  Derivation: corner-alternated arctangents (normal) + logs (tangential); verified against an independent point-charge patch sum in PlateFieldTests.
//  `Capacitor.calibrated` solves for the densities that make the line integral of the real field equal the set ΔV — the textbook σ = ε₀V/d is wrong for finite plates.
//

import Foundation
import simd

public enum PlateField {

    /// A uniformly charged rectangle in a plane of constant x — plates face each other along x.
    public struct Rectangle: Sendable, Equatable {
        /// The plane's x.
        public var x: Double
        public var yRange: ClosedRange<Double>
        public var zRange: ClosedRange<Double>
        /// Surface charge density, C/m².
        public var sigma: Double

        public init(x: Double, yRange: ClosedRange<Double>,
                    zRange: ClosedRange<Double>, sigma: Double) {
            self.x = x
            self.yRange = yRange
            self.zRange = zRange
            self.sigma = sigma
        }

        public var area: Double {
            (yRange.upperBound - yRange.lowerBound)
                * (zRange.upperBound - zRange.lowerBound)
        }

        /// Total charge, C.
        public var charge: Double { sigma * area }
    }

    /// Points nearer the plate's plane than this (m) are nudged off it — the normal component is
    /// discontinuous across the sheet and the tangential logs are singular on its edges.
    public static let planeEpsilon = 1e-4

    /// Exact field of one rectangle at `point` (N/C).
    /// The corner term uses `atan`, not `atan2`: it is the principal value of ηζ/(ξR), and atan2 wraps to ±π when ξ goes negative — wrong by whole turns behind the plate.
    public static func vector(at point: SIMD3<Double>,
                              dueTo plate: Rectangle) -> SIMD3<Double> {
        var xi = point.x - plate.x
        if abs(xi) < planeEpsilon { xi = xi < 0 ? -planeEpsilon : planeEpsilon }

        var ex = 0.0, ey = 0.0, ez = 0.0
        let ys = [plate.yRange.lowerBound, plate.yRange.upperBound]
        let zs = [plate.zRange.lowerBound, plate.zRange.upperBound]
        for i in 0..<2 {
            for j in 0..<2 {
                let sign = (i + j) % 2 == 0 ? 1.0 : -1.0
                let eta = point.y - ys[i]
                let zeta = point.z - zs[j]
                let r = (xi * xi + eta * eta + zeta * zeta).squareRoot()
                ex += sign * atan(eta * zeta / (xi * r))
                // Log arguments vanish only on the plate's own edges, which planeEpsilon keeps us off.
                ey -= sign * log(max(r + zeta, 1e-12))
                ez -= sign * log(max(r + eta, 1e-12))
            }
        }
        return ElectricField.k * plate.sigma * SIMD3(ex, ey, ez)
    }

    /// Field of a set of rectangles.
    public static func vector(at point: SIMD3<Double>,
                              dueTo plates: [Rectangle]) -> SIMD3<Double> {
        plates.reduce(SIMD3<Double>.zero) { $0 + vector(at: point, dueTo: $1) }
    }

    // MARK: The capacitor

    /// Finite-plate capacitor, optionally part-covered by a gap-filling dielectric slab. Square
    /// plates side `plateSize`, facing along x, positive plate on the −x side; the slab covers from the −z edge up to `dielectricCoverage` of the depth.
    public struct Capacitor: Sendable, Equatable {
        public var center: SIMD3<Double>
        public var separation: Double
        public var plateSize: Double
        public var voltage: Double
        /// Relative permittivity of the slab; 1 with no slab in play.
        public var dielectricConstant: Double
        /// 0 = slab out, 1 = covering the whole plate, measured from the −z edge.
        public var dielectricCoverage: Double

        /// Charged rectangles of the calibrated model — covered/uncovered portions of each plate
        /// with solved densities; two entries when nothing or everything is covered.
        public var rectangles: [Rectangle]

        /// Total charge on the positive plate, C — the covered portion carries visibly more.
        public var chargeOnPositivePlate: Double {
            rectangles.filter { $0.sigma > 0 }.map(\.charge).reduce(0, +)
        }

        /// Capacitance, F, measured as Q/V — exceeds the textbook ε₀A/d for these open plates.
        public var capacitance: Double {
            voltage > 0 ? chargeOnPositivePlate / voltage : 0
        }

        /// Stored energy U = ½CV², joules.
        public var storedEnergy: Double {
            0.5 * capacitance * voltage * voltage
        }

        /// Field at `point` from the calibrated plates, 1/κ applied inside the slab. Only the normal
        /// (x) component is attenuated — continuity of D; tangential components pass through unchanged, or traced lines refract in y/z with a bend the physics does not have.
        public func field(at point: SIMD3<Double>) -> SIMD3<Double> {
            var field = PlateField.vector(at: point, dueTo: rectangles)
            if insideDielectric(point) { field.x /= dielectricConstant }
            return field
        }

        /// Whether `point` is inside the slab (gap's x extent, plate's y extent, covered z range).
        public func insideDielectric(_ point: SIMD3<Double>) -> Bool {
            guard dielectricCoverage > 0, dielectricConstant > 1 else {
                return false
            }
            let offset = point - center
            let half = plateSize / 2
            let coveredTop = -half + plateSize * dielectricCoverage
            return abs(offset.x) < separation / 2
                && abs(offset.y) < half
                && offset.z > -half && offset.z < coveredTop
        }

        /// One midpoint quadrature for every line integral here: the calibration pins the set ΔV on
        /// this discretization, so any readout re-integrating on a different grid fails to read the ΔV back.
        static let quadratureSteps = 32

        static func lineIntegral(of field: (SIMD3<Double>) -> SIMD3<Double>,
                                 from a: SIMD3<Double>,
                                 to b: SIMD3<Double>) -> Double {
            let delta = (b - a) / Double(quadratureSteps)
            var sum = 0.0
            for step in 0..<quadratureSteps {
                let mid = a + delta * (Double(step) + 0.5)
                sum += simd_dot(field(mid), delta)
            }
            return sum
        }

        /// Potential (V) relative to the capacitor's centre — line integral of the real field along the straight path.
        public func potential(at point: SIMD3<Double>) -> Double {
            -Self.lineIntegral(of: { field(at: $0) }, from: center, to: point)
        }

        /// Builds the calibrated capacitor: solves the densities that make the gap line integral of
        /// the real field equal `voltage` (κ-scaled under the slab) — a 2×2 system when both regions exist, since each region's charge feeds the other's integral.
        public static func calibrated(center: SIMD3<Double>,
                                      separation: Double,
                                      plateSize: Double,
                                      voltage: Double,
                                      dielectricConstant: Double = 1,
                                      dielectricCoverage: Double = 0)
        -> Capacitor {
            let half = plateSize / 2
            let coverage = min(max(dielectricCoverage, 0), 1)
            let kappa = max(dielectricConstant, 1)
            let split = -half + plateSize * coverage

            /// The two z-bands: covered (−half…split) and open (split…+half); either may be empty.
            var bands: [(zRange: ClosedRange<Double>, inSlab: Bool)] = []
            if split - -half > 1e-6 {
                bands.append((-half...split, true))
            }
            if half - split > 1e-6 {
                bands.append((split...half, false))
            }

            /// Unit-density rectangle pair (±) for one band.
            func unitPair(_ band: ClosedRange<Double>) -> [Rectangle] {
                [Rectangle(x: center.x - separation / 2,
                           yRange: (center.y - half)...(center.y + half),
                           zRange: (center.z + band.lowerBound)...(center.z + band.upperBound),
                           sigma: 1),
                 Rectangle(x: center.x + separation / 2,
                           yRange: (center.y - half)...(center.y + half),
                           zRange: (center.z + band.lowerBound)...(center.z + band.upperBound),
                           sigma: -1)]
            }

            /// Gap drop along a band's centre line from unit density on `source`, in the vacuum
            /// field — the κ scaling belongs to the condition, not the geometry.
            func unitDrop(from source: [Rectangle],
                          throughBandAt z: Double) -> Double {
                lineIntegral(of: { PlateField.vector(at: $0, dueTo: source) },
                             from: SIMD3(center.x - separation / 2, center.y, z),
                             to: SIMD3(center.x + separation / 2, center.y, z))
            }

            let pairs = bands.map { unitPair($0.zRange) }
            let centres = bands.map {
                center.z + ($0.zRange.lowerBound + $0.zRange.upperBound) / 2
            }

            var sigmas: [Double]
            if bands.count == 1 {
                let drop = unitDrop(from: pairs[0], throughBandAt: centres[0])
                // A band inside the slab sees its drop divided by κ — holding the same ΔV takes κ× the density.
                let effective = bands[0].inSlab ? drop / kappa : drop
                sigmas = [voltage / max(effective, 1e-12)]
            } else {
                // [a b; c d]·σ = V·[1, 1], the covered row's coefficients κ-scaled (its drop runs through the slab).
                var a = unitDrop(from: pairs[0], throughBandAt: centres[0])
                var b = unitDrop(from: pairs[1], throughBandAt: centres[0])
                let c = unitDrop(from: pairs[0], throughBandAt: centres[1])
                let d = unitDrop(from: pairs[1], throughBandAt: centres[1])
                if bands[0].inSlab { a /= kappa; b /= kappa }
                let determinant = a * d - b * c
                if abs(determinant) > 1e-15 {
                    sigmas = [(voltage * d - voltage * b) / determinant,
                              (voltage * a - voltage * c) / determinant]
                } else {
                    sigmas = [0, 0]
                }
            }

            var rectangles: [Rectangle] = []
            for (index, pair) in pairs.enumerated() {
                for var rectangle in pair {
                    rectangle.sigma *= sigmas[index]
                    rectangles.append(rectangle)
                }
            }
            return Capacitor(center: center, separation: separation,
                             plateSize: plateSize, voltage: voltage,
                             dielectricConstant: kappa,
                             dielectricCoverage: coverage,
                             rectangles: rectangles)
        }
    }
}
