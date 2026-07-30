//
//  EMStationLayoutTests.swift
//  Physics Playground — app tests
//
//  The merged E&M world puts two apparatus that were each authored to
//  own the room into the room together. Everything that can go wrong
//  with that is geometry, and all of it is silent: a magnet clamped to
//  a box that reaches into the circuit bench does not crash, it just
//  drifts through a battery. These are the assertions that would have
//  caught it.
//

import XCTest
import simd
@testable import PhysicsPlayground

@MainActor
final class EMStationLayoutTests: XCTestCase {

    // MARK: The anchors the layout was computed from

    /// EMStationLayout hard-codes each module's own anchor so it can
    /// stay free of RealityKit. That duplication is only safe if it is
    /// checked — move `benchPivot` and the world silently stops lining
    /// up with the bench it is placing.
    func testNativeAnchorsMatchTheModulesTheyDescribe() {
        // The bench pivot is authored as Float, so it only round-trips
        // to Double to within single precision — hence a tolerance
        // rather than equality. It is loose enough to survive the cast
        // and far tighter than any drift that would matter.
        assertAnchor(.bench, matches: SIMD3<Double>(CircuitsRenderer.benchPivot),
                     "CircuitsRenderer.benchPivot")
        assertAnchor(.field, matches: MagnetismModel.regionCenter,
                     "MagnetismModel.regionCenter")
        assertAnchor(.charges, matches: FieldModel.regionCenter,
                     "FieldModel.regionCenter")
    }

    private func assertAnchor(
        _ station: EMStation, matches source: SIMD3<Double>, _ name: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(
            simd_distance(EMStationLayout.nativeAnchor(station), source), 0,
            accuracy: 1e-6, "\(station.rawValue) anchor drifted from \(name)",
            file: file, line: line)
    }

    /// The offset is what actually moves the display root, so it has to
    /// be exactly the difference — not a separately maintained number.
    func testOffsetCarriesTheNativeAnchorToTheStationCentre() {
        for station in EMStation.allCases {
            let moved = EMStationLayout.nativeAnchor(station)
                + SIMD3<Double>(EMStationLayout.offset(station))
            let target = EMStationLayout.center(station)
            XCTAssertEqual(simd_distance(moved, target), 0, accuracy: 1e-6,
                           "\(station.rawValue) offset misses its centre")
        }
    }

    // MARK: The invariant the whole layout exists to guarantee

    /// No two stations may share space. Boxes are axis-aligned, so
    /// clearance on any one axis is enough — but there must be some.
    func testEveryPairOfStationsIsDisjoint() {
        let stations = EMStation.allCases
        for i in 0..<stations.count {
            for j in (i + 1)..<stations.count {
                XCTAssertTrue(
                    EMStationLayout.areSeparated(stations[i], stations[j],
                                                 margin: 0.05),
                    "\(stations[i].rawValue) and \(stations[j].rawValue) "
                    + "overlap, or sit closer than the 5 cm clearance")
            }
        }
    }

    /// The two built stations are the ones a user actually stands
    /// between, so they get the stricter check: separated along x
    /// specifically, one either side of the centre line.
    func testBuiltStationsSitOnOppositeSidesOfTheCentreLine() {
        let bench = EMStationLayout.bounds(.bench)
        let field = EMStationLayout.bounds(.field)
        XCTAssertLessThanOrEqual(bench.max.x, 0,
                                 "the circuit bench crosses to the right")
        XCTAssertGreaterThanOrEqual(field.min.x, 0,
                                    "the magnet field crosses to the left")
    }

    // MARK: The clamps and grids that draw inside those boxes

    /// The magnet clamp is the thing that can actually put a body
    /// outside its station, so the box has to contain the whole clamp.
    func testMagnetClampStaysInsideTheFieldStation() {
        let (lo, hi) = EMStationLayout.bounds(.field)
        let offset = SIMD3<Double>(EMStationLayout.offset(.field))
        let clampLo = MagnetismModel.regionCenter
            - MagnetismModel.regionHalfExtents + offset
        let clampHi = MagnetismModel.regionCenter
            + MagnetismModel.regionHalfExtents + offset
        for axis in 0..<3 {
            XCTAssertGreaterThanOrEqual(clampLo[axis], lo[axis] - 1e-9,
                                        "clamp escapes the field station on axis \(axis)")
            XCTAssertLessThanOrEqual(clampHi[axis], hi[axis] + 1e-9,
                                     "clamp escapes the field station on axis \(axis)")
        }
    }

    /// The compass grid is drawn from `regionHalfExtent` (the scalar),
    /// not from the clamp — the two are easy to change apart, and the
    /// grid is what reached into the bench before the world existed.
    func testCompassGridStaysInsideTheFieldStation() {
        let (lo, hi) = EMStationLayout.bounds(.field)
        let offset = SIMD3<Double>(EMStationLayout.offset(.field))
        // MagnetismRenderer lays the grid out as a cube of this span,
        // centred on the region centre.
        let reach = MagnetismModel.regionHalfExtent * 1.7 / 2
        let gridLo = MagnetismModel.regionCenter - SIMD3(repeating: reach) + offset
        let gridHi = MagnetismModel.regionCenter + SIMD3(repeating: reach) + offset
        for axis in 0..<3 {
            XCTAssertGreaterThanOrEqual(gridLo[axis], lo[axis] - 1e-9,
                                        "compass grid escapes on axis \(axis)")
            XCTAssertLessThanOrEqual(gridHi[axis], hi[axis] + 1e-9,
                                     "compass grid escapes on axis \(axis)")
        }
    }

    // MARK: The reserved seat

    func testOnlyTheChargesStationIsUnbuilt() {
        XCTAssertTrue(EMStation.bench.isBuilt)
        XCTAssertTrue(EMStation.field.isBuilt)
        XCTAssertFalse(EMStation.charges.isBuilt,
                       "Electric Fields is reserved, not built — building "
                       + "it means giving it a station, not flipping a flag")
    }

    /// Side furniture hangs outboard so the two benches' flanks don't
    /// collide across the middle of the world.
    func testBuiltStationsFaceTheirFurnitureAwayFromTheCentre() {
        XCTAssertEqual(EMStationLayout.outboard(.bench),
                       EMStationLayout.center(.bench).x < 0 ? -1 : 1)
        XCTAssertEqual(EMStationLayout.outboard(.field),
                       EMStationLayout.center(.field).x < 0 ? -1 : 1)
    }
}
