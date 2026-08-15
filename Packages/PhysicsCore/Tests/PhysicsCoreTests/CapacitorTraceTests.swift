//
//  CapacitorTraceTests.swift
//  PhysicsCore tests
//
//  The capacitor joining the traced field picture: lines seed on the
//  + plate by Gauss-honest σ·A weighting, run the REAL fringing field,
//  and end where they land on a conductor. The old bench drew the
//  capacitor as two slabs and no lines at all — the gap looked empty
//  while the probe visibly accelerated through it.
//

import XCTest
import simd
@testable import PhysicsCore

final class CapacitorTraceTests: XCTestCase {

    private func bench(coverage: Double = 0) -> PlateField.Capacitor {
        PlateField.Capacitor.calibrated(
            center: SIMD3(0, 1.3, -1.0), separation: 0.44,
            plateSize: 0.5, voltage: 20_000,
            dielectricConstant: 4.7, dielectricCoverage: coverage)
    }

    private func config() -> FieldLineTracer.Config {
        var config = FieldLineTracer.Config()
        config.boundsCenter = SIMD3(0, 1.3, -1.0)
        config.boundsRadius = 1.4
        config.stepSize = 0.012
        config.maxSteps = 220
        return config
    }

    /// With no charges in the room the capacitor still draws a field:
    /// a healthy bundle, every point finite, and most lines LANDING on
    /// the − plate — a field line ends on a conductor, not in mid-air.
    func testTheGapDrawsLinesThatLandOnTheNegativePlate() {
        let capacitor = bench()
        let lines = FieldLineTracer.trace(charges: [], capacitor: capacitor,
                                          config: config())
        XCTAssertGreaterThan(lines.count, 12, "the gap should be full of lines")

        let negativeX = capacitor.center.x + capacitor.separation / 2
        var landed = 0
        for line in lines {
            for point in line {
                XCTAssertTrue(point.x.isFinite && point.y.isFinite
                              && point.z.isFinite)
            }
            if let last = line.last, abs(last.x - negativeX) < 0.02 {
                landed += 1
            }
        }
        XCTAssertGreaterThan(landed, lines.count / 2,
                             "most of the bundle should terminate on the − plate")
    }

    /// The fringe is drawn: at least one line reaches past the plates'
    /// edges, which the uniform box's hard cutoff could never show.
    func testTheBundleIncludesFringeLines() {
        let capacitor = bench()
        let lines = FieldLineTracer.trace(charges: [], capacitor: capacitor,
                                          config: config())
        let half = capacitor.plateSize / 2
        let escapes = lines.contains { line in
            line.contains {
                abs($0.y - capacitor.center.y) > half * 1.2
                    || abs($0.z - capacitor.center.z) > half * 1.2
            }
        }
        XCTAssertTrue(escapes, "no line ever left the gap — the fringe is gone")
    }

    /// Gauss drawn: slide the slab half in and the covered band's seeds
    /// outnumber the open band's, because its σ does.
    func testTheSlabCrowdsTheSeeding() {
        let bare = FieldLineTracer.plateSeeds(for: bench(), config: config())
        let slabbed = FieldLineTracer.plateSeeds(for: bench(coverage: 0.5),
                                                 config: config())
        // Same budget either way, just redistributed.
        XCTAssertEqual(bare.count, slabbed.count, accuracy: 6)

        let centerZ = -1.0
        let covered = slabbed.filter { $0.z < centerZ }.count
        let open = slabbed.filter { $0.z >= centerZ }.count
        XCTAssertGreaterThan(covered, open,
                             "σ crowds under the slab and the seeding should show it")
    }

    /// A point charge parked beside the gap joins the same picture: the
    /// trace runs both sources through one field, so its lines exist
    /// and get cut where they land on a plate.
    func testAChargeAndTheCapacitorShareOneTrace() {
        let capacitor = bench()
        let charge = PointCharge(
            position: capacitor.center + SIMD3(0, 0, 0.5), charge: 1e-6)
        let lines = FieldLineTracer.trace(charges: [charge],
                                          capacitor: capacitor,
                                          config: config())
        let plateLess = FieldLineTracer.trace(charges: [], capacitor: capacitor,
                                              config: config())
        XCTAssertGreaterThan(lines.count, plateLess.count,
                             "the charge's own bundle should join the picture")
    }
}

private func XCTAssertEqual(_ a: Int, _ b: Int, accuracy: Int,
                            file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertLessThanOrEqual(abs(a - b), accuracy, file: file, line: line)
}
