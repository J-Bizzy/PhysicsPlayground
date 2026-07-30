//
//  WavesDoubleSlitTests.swift
//  PhysicsPlaygroundTests
//
//  The fringe screen's geometry. `DoubleSlit` itself is already tested in
//  PhysicsCore against the closed forms; what is new here is the bridge —
//  deciding where the screen stands from where the user has put two
//  sources, and refusing to draw when there is no double slit to draw.
//

import XCTest
import simd
import PhysicsCore
@testable import PhysicsPlayground

@MainActor
final class WavesDoubleSlitTests: XCTestCase {

    /// A pair of sources straddling the region centre, separated along x.
    ///
    /// Built by moving whatever the module opens with rather than by
    /// creating from scratch: `addSource()` places on a spawn ring of its
    /// own choosing, and `removeSelectedSource()` refuses to go below one
    /// source, so those are the real constraints a caller works within.
    private func twoSourceModel(separation: Double = 0.4) -> WavesModel {
        let model = WavesModel()
        while model.sources.count > 2 {
            model.select(id: model.sources[0].id)
            model.removeSelectedSource()
        }
        while model.sources.count < 2 { model.addSource() }
        model.moveSource(id: model.sources[0].id,
                         to: WavesModel.regionCenter + SIMD3(-separation / 2, 0, 0))
        model.moveSource(id: model.sources[1].id,
                         to: WavesModel.regionCenter + SIMD3(separation / 2, 0, 0))
        return model
    }

    /// Trims to a single source — the floor the model enforces.
    private func oneSourceModel() -> WavesModel {
        let model = WavesModel()
        while model.sources.count > 1 {
            model.select(id: model.sources[0].id)
            model.removeSelectedSource()
        }
        return model
    }

    // MARK: When there is a double slit at all

    /// Two sources ARE a double slit; one or three are not, and the screen
    /// must not paint a two-slit formula over a field that is not one.
    func testGeometryExistsOnlyForExactlyTwoSources() {
        let model = twoSourceModel()
        XCTAssertNotNil(model.fringeGeometry)

        model.addSource()
        XCTAssertEqual(model.sources.count, 3)
        XCTAssertNil(model.fringeGeometry, "three sources are not a double slit")

        XCTAssertNil(oneSourceModel().fringeGeometry,
                     "one source has nothing to interfere with")
    }

    /// Coincident sources are one slit. Normalising that zero baseline
    /// would spray NaN through every band's transform.
    func testCoincidentSourcesProduceNoGeometryRatherThanNaN() {
        let model = twoSourceModel()
        // Both slits stacked on the same point.
        model.moveSource(id: model.sources[0].id, to: WavesModel.regionCenter)
        model.moveSource(id: model.sources[1].id, to: WavesModel.regionCenter)
        XCTAssertNil(model.fringeGeometry)
        XCTAssertEqual(model.fringeIntensity(atOffset: 0.1), 0,
                       "no geometry means no light, not NaN")
    }

    // MARK: Where the screen stands

    /// The fringe coordinate runs along the slit baseline and the screen
    /// stands off perpendicular to it — otherwise the pattern would be
    /// painted across the wrong axis.
    func testScreenAxisIsPerpendicularToTheBaseline() {
        let geometry = twoSourceModel().fringeGeometry!
        XCTAssertEqual(simd_dot(geometry.along, geometry.axis), 0, accuracy: 1e-9)
        XCTAssertEqual(simd_length(geometry.along), 1, accuracy: 1e-9)
        XCTAssertEqual(simd_length(geometry.axis), 1, accuracy: 1e-9)
    }

    func testScreenSitsAtTheChosenDistanceFromTheMidpoint() {
        let model = twoSourceModel()
        model.screenDistance = 0.7
        let geometry = model.fringeGeometry!
        XCTAssertEqual(simd_distance(geometry.centre, geometry.midpoint), 0.7,
                       accuracy: 1e-9)
    }

    /// The screen must stand BEYOND the slits, not behind the viewer — the
    /// axis is flipped to face away from the room's origin.
    func testScreenStandsAwayFromTheUser() {
        let geometry = twoSourceModel().fringeGeometry!
        XCTAssertGreaterThan(simd_length(geometry.centre),
                             simd_length(geometry.midpoint),
                             "the screen should be further out than the slits")
    }

    func testSeparationMatchesTheSourcesTheUserPlaced() {
        let geometry = twoSourceModel(separation: 0.55).fringeGeometry!
        XCTAssertEqual(geometry.separation, 0.55, accuracy: 1e-9)
    }

    // MARK: The pattern itself

    /// The central maximum is at the centre and is the brightest thing on
    /// the screen — if it is not, the screen is painted about the wrong
    /// point and every order is misplaced.
    func testCentralMaximumIsBrightestAndCentred() {
        let model = twoSourceModel()
        XCTAssertEqual(model.fringeIntensity(atOffset: 0), 1, accuracy: 1e-9)
        for offset in stride(from: -0.7, through: 0.7, by: 0.05) where abs(offset) > 1e-9 {
            XCTAssertLessThanOrEqual(model.fringeIntensity(atOffset: offset),
                                     1 + 1e-9)
        }
    }

    /// Point-like slits mean pure cos² with NO single-slit envelope, so the
    /// orders stay equally bright right across the screen. This is the
    /// honesty check: an envelope here would dim fringes that the walkable
    /// field still shows at full strength.
    func testOrdersAreEquallyBrightBecauseTheSlitsArePoints() {
        let model = twoSourceModel()
        let geometry = model.fringeGeometry!
        let orders = DoubleSlit.brightFringes(
            distance: model.screenDistance, separation: geometry.separation,
            wavelength: model.wavelength, count: 5)
        for offset in orders {
            XCTAssertEqual(model.fringeIntensity(atOffset: offset), 1, accuracy: 1e-6,
                           "order at \(offset) should be a full maximum")
        }
    }

    /// The bright orders the model reports really are maxima of the
    /// intensity it paints — the two must agree or the tick marks would sit
    /// beside the bands rather than on them.
    func testReportedOrdersLandOnPaintedMaxima() {
        let model = twoSourceModel()
        let offsets = model.brightFringeOffsets(count: 5)
        XCTAssertGreaterThan(offsets.count, 2)
        for offset in offsets {
            XCTAssertGreaterThan(model.fringeIntensity(atOffset: offset), 0.99)
        }
        XCTAssertTrue(offsets.contains { abs($0) < 1e-9 }, "m = 0 is an order")
    }

    /// Δy = λL/d: widening the slits pulls the fringes together, and
    /// moving the screen back spreads them out. Both are the relationships
    /// an intro lab is built to measure.
    func testFringeSpacingFollowsLambdaLOverD() {
        let narrow = twoSourceModel(separation: 0.2)
        let wide = twoSourceModel(separation: 0.6)
        XCTAssertGreaterThan(narrow.fringeSpacing!, wide.fringeSpacing!)

        let near = twoSourceModel(separation: 0.4)
        near.screenDistance = 0.4
        let far = twoSourceModel(separation: 0.4)
        far.screenDistance = 1.2
        XCTAssertEqual(far.fringeSpacing! / near.fringeSpacing!, 3, accuracy: 1e-9,
                       "spacing is linear in screen distance")
    }

    func testNoSpacingWithoutADoubleSlit() {
        let model = oneSourceModel()
        XCTAssertNil(model.fringeSpacing)
        XCTAssertTrue(model.brightFringeOffsets().isEmpty)
    }

    /// The screen is off on a reset — it is the second bench, not the one
    /// the module opens on.
    func testResetHidesTheScreen() {
        let model = twoSourceModel()
        model.showFringeScreen = true
        model.reset()
        XCTAssertFalse(model.showFringeScreen)
        XCTAssertEqual(model.screenDistance, 0.85, accuracy: 1e-9)
    }
}
