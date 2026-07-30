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
import PhysicsCore
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

    /// The arc's shape, asserted rather than described: circuits left,
    /// charges straight ahead, magnets right, in that order along x and
    /// never overlapping.
    func testTheStationsRunLeftToRightInTheOrderTheWorldClaims() {
        let bench = EMStationLayout.bounds(.bench)
        let charges = EMStationLayout.bounds(.charges)
        let field = EMStationLayout.bounds(.field)
        XCTAssertLessThan(bench.max.x, charges.min.x,
                          "the circuit bench reaches into the charges")
        XCTAssertLessThan(charges.max.x, field.min.x,
                          "the charges reach into the magnetic field")
    }

    /// Every station has to be worth walking to: its NEAR face within
    /// reach of a user who takes one step toward it.
    ///
    /// This is the invariant the arc was traded for. Keeping all three
    /// benches at full size means their centres land ~1.5 m out, so the
    /// bound here is on the near face, not the centre — you turn and
    /// step, and then the apparatus is under your hands.
    func testEveryStationHasAFaceWithinOneStep() {
        // Eye height, standing at the room's origin.
        let user = SIMD3<Double>(0, 1.5, 0)
        for station in EMStation.allCases {
            let (near, _) = EMStationLayout.box(station).distanceRange(from: user)
            XCTAssertLessThanOrEqual(
                near, 1.25,
                "\(station.rawValue) is more than a step away — its nearest "
                + "face is \(String(format: "%.2f", near)) m from the user")
        }
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

    // MARK: The clamps that back each station's declared box
    //
    // Every one of these boxes used to be a promise the apparatus was
    // trusted to keep. Two of the three were not keeping it: Electric
    // Fields clamped only `y`, so a charge could be dragged across the
    // room, and Circuits clamped to a 3 m SPHERE. Alone in a room that
    // cost nothing. These are the assertions that make the footprints
    // real.

    /// The charges bench's own clamp must not promise more room than
    /// its station has.
    func testTheChargeClampMatchesTheChargesStation() {
        XCTAssertEqual(
            FieldModel.regionHalfExtents,
            EMStationLayout.halfExtents(.charges),
            "FieldModel's clamp and the charges station's box have "
            + "drifted apart — the layout may not promise a footprint "
            + "the model does not enforce")
    }

    /// The capacitor is up to a metre wide at full separation. Its
    /// clamp is inset by its own half-size, so even wide open it stays
    /// inside — this is the one that would otherwise put a charged
    /// plate inside the circuit bench.
    func testTheWidestCapacitorStaysInsideTheChargesStation() {
        let model = FieldModel()
        model.plateSeparation = FieldModel.plateSeparationRange.upperBound
        // Shove it hard at the wall the circuit bench is behind.
        model.movePlate(1, toWorld: SIMD3(50, 1.35, -0.9))
        let half = SIMD3(model.plateSeparation / 2,
                         FieldModel.plateSize / 2, FieldModel.plateSize / 2)
        assertInsideChargesStation(
            StationBox(center: model.capacitorCenter, halfExtents: half),
            "the capacitor at full separation")
    }

    /// Same for the flux meter, which is a 1.1 m sphere at full radius.
    func testTheWidestGaussSurfaceStaysInsideTheChargesStation() {
        let model = FieldModel()
        model.gaussSurfaceRadius = FieldModel.gaussRadiusRange.upperBound
        model.moveGaussSurface(to: SIMD3(-50, 1.35, -0.9))
        assertInsideChargesStation(
            StationBox(center: model.gaussSurfaceCenter,
                       halfExtents: SIMD3(repeating: model.gaussSurfaceRadius)),
            "the Gauss surface at full radius")
    }

    /// And a dragged charge, which is what a user actually does.
    func testADraggedChargeCannotLeaveTheChargesStation() {
        let model = FieldModel()
        guard let id = model.charges.first?.id else {
            return XCTFail("a fresh field model should open with charges")
        }
        model.moveCharge(id: id, to: SIMD3(-50, 90, 50))
        guard let moved = model.charges.first(where: { $0.id == id }) else {
            return XCTFail("the charge vanished")
        }
        assertInsideChargesStation(
            StationBox(center: moved.position,
                       halfExtents: SIMD3(repeating: FieldModel.chargeContact)),
            "a charge dragged at the room")
    }

    private func assertInsideChargesStation(
        _ box: StationBox, _ what: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        // The station's box lives in world coordinates; the model works
        // in its own, so compare in the model's frame.
        let station = EMStationLayout.box(.charges)
            .offset(by: -SIMD3<Double>(EMStationLayout.offset(.charges)))
        XCTAssertTrue(
            station.contains(box, tolerance: 1e-6),
            "\(what) escapes the charges station: "
            + "\(box.minimum)…\(box.maximum) is not inside "
            + "\(station.minimum)…\(station.maximum)",
            file: file, line: line)
    }

    /// The circuit bench's build volume must sit inside its station too
    /// — it was a 3 m sphere until the world stood two other benches
    /// within 1.4 m of it.
    func testTheBenchBuildVolumeStaysInsideTheBenchStation() {
        let build = StationBox(center: CircuitsModel.buildCenter,
                               halfExtents: CircuitsModel.buildHalfExtents)
        let station = EMStationLayout.box(.bench)
            .offset(by: -SIMD3<Double>(EMStationLayout.offset(.bench)))
        XCTAssertTrue(
            station.contains(build, tolerance: 1e-6),
            "a circuit part can be dragged outside the bench's station")
    }

    /// Side furniture hangs outboard so the two flanking benches' sides
    /// don't collide with the middle of the world.
    func testBuiltStationsFaceTheirFurnitureAwayFromTheCentre() {
        XCTAssertEqual(EMStationLayout.outboard(.bench),
                       EMStationLayout.center(.bench).x < 0 ? -1 : 1)
        XCTAssertEqual(EMStationLayout.outboard(.field),
                       EMStationLayout.center(.field).x < 0 ? -1 : 1)
    }
}
