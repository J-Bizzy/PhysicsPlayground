//
//  PlateField.swift
//  PhysicsCore — Electromagnetism
//
//  The EXACT field of a uniformly charged rectangle, in closed form —
//  and on top of it, the parallel-plate capacitor as two real finite
//  plates rather than a hard-edged uniform box.
//
//  WHY CLOSED FORM. The house rule is exact solutions where they exist,
//  and this one exists: integrating Coulomb's law over a rectangle
//  gives corner-alternated arctangents for the normal component and
//  logarithms for the tangential ones. The alternative — a grid of
//  point-charge patches — is what the verification TEST uses, precisely
//  because the two are independent derivations of the same field: the
//  patch sum converges on the closed form as the grid refines, and
//  `PlateFieldTests` holds them together at a dozen random points.
//
//  THE ARCTANGENT IS `atan`, NOT `atan2`, and that is load-bearing: the
//  corner term is the principal value of the RATIO ηζ/(ξR). `atan2`
//  wraps to ±π when ξ goes negative and the field on the back side of
//  the plate comes out wrong by whole turns — found numerically before
//  this was ever Swift, which is the only place a branch cut like that
//  is cheap to find.
//
//  WHAT CALIBRATION IS FOR. A capacitor bench sets a VOLTAGE, but a
//  charged-rectangle model takes a CHARGE DENSITY, and for finite
//  plates the two are not related by the textbook σ = ε₀V/d: at this
//  bench's geometry (0.5 m plates, gaps to 1 m) the field leaks out the
//  sides, and holding the set ΔV across the gap's centre line takes up
//  to twice the ideal density. `Capacitor.calibrated` solves for the
//  densities that make the line integral of the REAL field equal the
//  set voltage — region by region when a dielectric covers part of the
//  plate, which is also where the charge visibly crowds under the slab.
//

import Foundation
import simd

public enum PlateField {

    /// A uniformly charged rectangle in a plane of constant x — the
    /// capacitor's plates face each other along x, matching the bench.
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

    /// Points closer to the plate's PLANE than this are nudged off it:
    /// the normal component is discontinuous across the sheet and the
    /// tangential logs are singular on its edges. A tenth of a
    /// millimetre is far below anything the bench renders or the probe
    /// survives.
    public static let planeEpsilon = 1e-4

    /// Exact field of one rectangle at `point`.
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
                // The log arguments vanish only on the plate's own
                // edges, which planeEpsilon keeps us off.
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

    /// A parallel-plate capacitor with real finite plates, optionally
    /// part-covered by a dielectric slab that fills the gap.
    ///
    /// Geometry: square plates of side `plateSize`, centred on
    /// `center`, facing each other along x with the POSITIVE plate on
    /// the −x side — the same handedness the bench has always had. The
    /// dielectric covers the plate from the −z edge up to
    /// `dielectricCoverage` of its depth, which is the fraction a hand
    /// has slid the slab in.
    public struct Capacitor: Sendable, Equatable {
        public var center: SIMD3<Double>
        public var separation: Double
        public var plateSize: Double
        public var voltage: Double
        /// Relative permittivity of the slab; 1 with no slab in play.
        public var dielectricConstant: Double
        /// 0 = slab out, 1 = slab covering the whole plate, measured
        /// from the −z edge.
        public var dielectricCoverage: Double

        /// The four charged rectangles of the calibrated model — the
        /// covered and uncovered portions of each plate, each with the
        /// density the calibration solved for. Two entries when nothing
        /// is covered or everything is.
        public var rectangles: [Rectangle]

        /// Total charge on the positive plate, C. With part of the
        /// plate covered this is the sum of two densities — the covered
        /// portion carries visibly more, which is the slab's whole
        /// story.
        public var chargeOnPositivePlate: Double {
            rectangles.filter { $0.sigma > 0 }.map(\.charge).reduce(0, +)
        }

        /// Capacitance, farads, honestly measured as Q/V — for these
        /// open plates it exceeds the textbook ε₀A/d, because holding
        /// the set ΔV against the side leakage takes extra charge.
        public var capacitance: Double {
            voltage > 0 ? chargeOnPositivePlate / voltage : 0
        }

        /// Stored energy U = ½CV², joules.
        public var storedEnergy: Double {
            0.5 * capacitance * voltage * voltage
        }

        /// Field at `point` from the calibrated plates, with the slab's
        /// polarization applied as a 1/κ factor inside the slab volume.
        ///
        /// ONLY THE NORMAL COMPONENT is attenuated. Continuity of D
        /// reduces E along the plate normal (x) by κ inside the slab;
        /// the tangential components are continuous across the
        /// interface and pass through unchanged. Dividing the whole
        /// vector — the first version did — refracted traced lines in
        /// y and z at the slab's faces, a bend the physics does not
        /// have. The calibration is indifferent either way: its line
        /// integral runs along x, so it only ever consumed the one
        /// component this factor legitimately touches.
        public func field(at point: SIMD3<Double>) -> SIMD3<Double> {
            var field = PlateField.vector(at: point, dueTo: rectangles)
            if insideDielectric(point) { field.x /= dielectricConstant }
            return field
        }

        /// Whether `point` is inside the slab (the slab fills the gap's
        /// x extent and the plate's y extent, over the covered z range).
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

        /// One midpoint quadrature for every line integral this type
        /// takes. The calibration PINS the set ΔV on this
        /// discretization, so a readout that re-integrates the same
        /// field on a different grid disagrees with it by exactly the
        /// difference in step counts — which is how the first build's
        /// 24-step `potential` failed to read the 32-step ΔV back.
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

        /// Potential relative to the capacitor's centre, by integrating
        /// the real field along the straight path from the centre —
        /// the same datum the bench's readouts have always used.
        public func potential(at point: SIMD3<Double>) -> Double {
            -Self.lineIntegral(of: { field(at: $0) }, from: center, to: point)
        }

        /// Builds the calibrated capacitor: solves for the surface
        /// densities that make the line integral of the REAL field
        /// across the gap equal `voltage` — through the air on the
        /// uncovered portion, and κ-scaled through the slab on the
        /// covered one. With both regions present that is a 2×2 linear
        /// system, because each region's charge contributes to the
        /// other's gap integral.
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

            /// The two z-bands: covered (from −half up to the split)
            /// and open (split to +half). Either may be empty.
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

            /// Gap drop along the centre line of band `target`, due to
            /// unit density on band `source`, in the vacuum field. The
            /// κ scaling belongs to the CONDITION, not the geometry.
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
                // A band inside the slab sees its drop divided by κ, so
                // holding the same ΔV takes κ× the density.
                let effective = bands[0].inSlab ? drop / kappa : drop
                sigmas = [voltage / max(effective, 1e-12)]
            } else {
                // [a b; c d]·σ = V·[1, 1], with the covered row's
                // coefficients κ-scaled: the drop that row measures runs
                // through the slab.
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
