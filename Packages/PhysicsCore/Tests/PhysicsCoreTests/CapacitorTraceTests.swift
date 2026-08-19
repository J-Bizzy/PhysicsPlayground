//  CapacitorTraceTests.swift
//  Capacitor in the traced field picture: σ·A-weighted seeding, real fringing, lines end on conductors.

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

    /// No charges in the room: a healthy finite bundle, most lines landing on the − plate.
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

    /// At least one line reaches past the plate edges — the fringe a uniform box cannot show.
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

    /// Half-inserted slab: the covered band's seeds outnumber the open band's, because its σ does.
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

    /// A point charge and the capacitor trace through one combined field.
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
