//
//  PlateFieldTests.swift
//  PhysicsCore tests
//
//  The charged rectangle's closed form, held against an INDEPENDENT
//  derivation: a brute-force grid of point-charge patches. The two
//  agree only if every corner sign, every branch cut and the constant
//  out front are right — the `atan2` version of the normal component
//  passes on one side of the plate and is wrong by whole turns on the
//  other, which is exactly the kind of defect a single-sided test
//  blesses. So the points here straddle the plate.
//

import XCTest
import simd
@testable import PhysicsCore

final class PlateFieldTests: XCTestCase {

    private let plate = PlateField.Rectangle(
        x: 0, yRange: -0.25...0.25, zRange: -0.2...0.3, sigma: 3e-6)

    /// The independent derivation: Coulomb sum over a fine patch grid.
    private func brute(at point: SIMD3<Double>, grid: Int = 240) -> SIMD3<Double> {
        let ySpan = plate.yRange.upperBound - plate.yRange.lowerBound
        let zSpan = plate.zRange.upperBound - plate.zRange.lowerBound
        let dy = ySpan / Double(grid), dz = zSpan / Double(grid)
        let patchCharge = plate.sigma * dy * dz
        var field = SIMD3<Double>.zero
        for i in 0..<grid {
            let y = plate.yRange.lowerBound + (Double(i) + 0.5) * dy
            for j in 0..<grid {
                let z = plate.zRange.lowerBound + (Double(j) + 0.5) * dz
                let r = point - SIMD3(plate.x, y, z)
                let r3 = pow(simd_length_squared(r), 1.5)
                field += ElectricField.k * patchCharge * r / r3
            }
        }
        return field
    }

    func testClosedFormMatchesThePatchSumOnBothSides() {
        // Fixed points rather than random ones, chosen to straddle the
        // plate (±x), to sit off every symmetry axis, and to include
        // one point nearly in the plate's own plane — where the atan2
        // branch cut failed before this was ever Swift.
        let points: [SIMD3<Double>] = [
            SIMD3(0.35, 0.1, -0.05),
            SIMD3(-0.35, 0.1, -0.05),
            SIMD3(0.06, 0.5, 0.4),
            SIMD3(-0.49, 0.099, -0.011),
            SIMD3(0.2, -0.4, 0.55),
            SIMD3(-0.12, -0.3, -0.45),
        ]
        for point in points {
            let exact = PlateField.vector(at: point, dueTo: plate)
            let summed = brute(at: point)
            let scale = max(simd_length(summed), 1e-9)
            XCTAssertLessThan(simd_length(exact - summed) / scale, 5e-3,
                              "closed form and patch sum disagree at \(point)")
        }
    }

    func testTheFieldPointsAwayFromAPositivePlateOnBothSides() {
        let front = PlateField.vector(at: SIMD3(0.2, 0, 0.05), dueTo: plate)
        let back = PlateField.vector(at: SIMD3(-0.2, 0, 0.05), dueTo: plate)
        XCTAssertGreaterThan(front.x, 0)
        XCTAssertLessThan(back.x, 0)
    }

    // MARK: The calibrated capacitor

    private func bench(voltage: Double = 20_000, separation: Double = 0.44,
                       kappa: Double = 1, coverage: Double = 0)
    -> PlateField.Capacitor {
        PlateField.Capacitor.calibrated(
            center: SIMD3(0, 1.3, -1.0), separation: separation,
            plateSize: 0.5, voltage: voltage,
            dielectricConstant: kappa, dielectricCoverage: coverage)
    }

    /// The whole point of calibration: the REAL field's line integral
    /// across the gap equals the set voltage — not the textbook σ that
    /// pretends the field stays between the plates.
    func testTheGapDropIsTheSetVoltage() {
        let capacitor = bench()
        let steps = 200
        let a = capacitor.center + SIMD3(-capacitor.separation / 2, 0, 0)
        let b = capacitor.center + SIMD3(capacitor.separation / 2, 0, 0)
        let delta = (b - a) / Double(steps)
        var drop = 0.0
        for step in 0..<steps {
            let mid = a + delta * (Double(step) + 0.5)
            drop += simd_dot(capacitor.field(at: mid), delta)
        }
        XCTAssertEqual(drop, capacitor.voltage,
                       accuracy: capacitor.voltage * 0.01)
    }

    /// Finite plates leak: holding the set ΔV takes MORE charge than
    /// ε₀A/d says, so the honest capacitance exceeds the textbook one —
    /// at this bench's open geometry, by a lot. If these ever come out
    /// equal the model has quietly become the ideal one again.
    func testHonestCapacitanceExceedsTheTextbookFormula() {
        let capacitor = bench()
        let ideal = Constants.vacuumPermittivity * 0.5 * 0.5
            / capacitor.separation
        XCTAssertGreaterThan(capacitor.capacitance, ideal * 1.3)
        XCTAssertLessThan(capacitor.capacitance, ideal * 4)
    }

    /// Fringing is real now: just past the plate edges the field is
    /// alive — weaker than the gap's, but not the hard zero the old
    /// box cutoff drew.
    func testTheFieldFringesPastThePlateEdges() {
        let capacitor = bench()
        let inside = capacitor.field(at: capacitor.center)
        let fringe = capacitor.field(
            at: capacitor.center + SIMD3(0, 0.35, 0))
        XCTAssertGreaterThan(simd_length(fringe), 0.02 * simd_length(inside),
                             "no fringe — the hard cutoff is back")
        XCTAssertLessThan(simd_length(fringe), simd_length(inside),
                          "the fringe should be weaker than the gap field")
    }

    /// And the centre field still points + → −, in the ballpark the
    /// rail's V/d line claims — below it, because the plates are open.
    func testTheGapFieldPointsAcrossAndNearTheIdealScale() {
        let capacitor = bench()
        let centre = capacitor.field(at: capacitor.center)
        let ideal = capacitor.voltage / capacitor.separation
        XCTAssertGreaterThan(centre.x, 0.4 * ideal)
        XCTAssertLessThan(centre.x, 1.1 * ideal)
        XCTAssertLessThan(abs(centre.y), 0.05 * centre.x)
        XCTAssertLessThan(abs(centre.z), 0.05 * centre.x)
    }

    /// A slab covering the whole gap multiplies the capacitance by
    /// exactly κ: the drop scales linearly in σ, so holding V through
    /// the slab takes κ× the charge. This is exact in the model, not
    /// approximate, which is why the accuracy is tight.
    func testAFullDielectricMultipliesCapacitanceByKappa() {
        let bare = bench()
        let slabbed = bench(kappa: 3, coverage: 1)
        XCTAssertEqual(slabbed.capacitance, bare.capacitance * 3,
                       accuracy: bare.capacitance * 3 * 1e-6)
    }

    /// Half in, the classic demo: capacitance between the bare and
    /// fully-covered values, and the charge CROWDS under the slab —
    /// the covered band's density beats the open band's.
    func testPartialInsertionCrowdsChargeUnderTheSlab() {
        let bare = bench()
        let half = bench(kappa: 3, coverage: 0.5)
        XCTAssertGreaterThan(half.capacitance, bare.capacitance)
        XCTAssertLessThan(half.capacitance, bare.capacitance * 3)

        let positives = half.rectangles.filter { $0.sigma > 0 }
        XCTAssertEqual(positives.count, 2)
        let covered = positives.min { $0.zRange.lowerBound < $1.zRange.lowerBound }!
        let open = positives.max { $0.zRange.lowerBound < $1.zRange.lowerBound }!
        XCTAssertGreaterThan(covered.sigma, open.sigma * 1.5,
                             "the slab should visibly crowd the charge")
    }

    /// Inside the slab the field is the vacuum field over κ — weaker,
    /// not stronger, whatever the crowded charge suggests.
    func testTheFieldInsideTheSlabIsReduced() {
        let half = bench(kappa: 3, coverage: 0.5)
        let inSlab = half.center + SIMD3(0, 0, -0.12)
        let inAir = half.center + SIMD3(0, 0, 0.12)
        XCTAssertTrue(half.insideDielectric(inSlab))
        XCTAssertFalse(half.insideDielectric(inAir))
        XCTAssertLessThan(half.field(at: inSlab).x, half.field(at: inAir).x)
    }

    /// Only the NORMAL component drops inside the slab. Continuity of
    /// D reduces E along the plate normal by κ; the tangential
    /// components are continuous across the interface, so a hair to
    /// either side of the slab's face they must match — the version
    /// that divided the whole vector refracted traced lines in y and z
    /// at this face, a bend the physics does not have.
    func testTangentialFieldIsContinuousAcrossTheSlabFace() {
        let half = bench(kappa: 3, coverage: 0.5)
        // Off both symmetry axes so the tangential components are
        // real, straddling the covered/open split (z = the centre for
        // half coverage) by far less than the field varies over.
        let face = half.center + SIMD3(0.05, 0.08, 0)
        let inSlab = face + SIMD3(0, 0, -1e-4)
        let inAir = face + SIMD3(0, 0, 1e-4)
        XCTAssertTrue(half.insideDielectric(inSlab))
        XCTAssertFalse(half.insideDielectric(inAir))

        let slabField = half.field(at: inSlab)
        let airField = half.field(at: inAir)
        let scale = simd_length(airField)
        XCTAssertEqual(slabField.y, airField.y, accuracy: scale * 1e-3)
        XCTAssertEqual(slabField.z, airField.z, accuracy: scale * 1e-3)
        // And the normal component genuinely drops by κ.
        XCTAssertEqual(slabField.x * 3, airField.x, accuracy: scale * 1e-2)
        // The tangential assertion is about something: the z component
        // is alive here (the crowded band pulls sideways at the split).
        XCTAssertGreaterThan(abs(airField.z), scale * 1e-3)
    }

    /// The readout and the calibration walk the SAME quadrature, so
    /// the potential the model reports at a plate face is the half-gap
    /// drop — ±V/2 — for the bare bench and the fully slabbed one
    /// alike. With mismatched step counts these disagree by the
    /// difference in discretization, not by physics.
    func testThePotentialAtThePlateFacesReadsHalfTheSetVoltage() {
        for capacitor in [bench(), bench(kappa: 3, coverage: 1)] {
            let positiveFace = capacitor.center
                + SIMD3(-capacitor.separation / 2, 0, 0)
            let negativeFace = capacitor.center
                + SIMD3(capacitor.separation / 2, 0, 0)
            XCTAssertEqual(capacitor.potential(at: positiveFace),
                           capacitor.voltage / 2,
                           accuracy: capacitor.voltage * 1e-3)
            XCTAssertEqual(capacitor.potential(at: negativeFace),
                           -capacitor.voltage / 2,
                           accuracy: capacitor.voltage * 1e-3)
        }
    }

    /// U = ½CV², in real joules.
    func testStoredEnergyIsHalfCVSquared() {
        let capacitor = bench()
        XCTAssertEqual(capacitor.storedEnergy,
                       0.5 * capacitor.capacitance * 20_000 * 20_000,
                       accuracy: capacitor.storedEnergy * 1e-9)
    }
}
