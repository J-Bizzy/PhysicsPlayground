//
//  FieldInstrumentLayoutTests.swift
//  PhysicsPlaygroundTests
//
//  Electric Fields' furniture stands around its physics, and hit-testing
//  uses colliders rather than visible geometry: a collider over the
//  region once made the whole module silently non-interactive. Nothing
//  in a screenshot shows this; arithmetic does.
//

import XCTest
import PhysicsCore
import RenderKit
import simd
@testable import PhysicsPlayground

@MainActor
final class FieldInstrumentLayoutTests: XCTestCase {

    private let station = FieldInstrumentLayout.station
    private let margin = FieldInstrumentLayout.stationMargin

    // MARK: Nothing stands where the physics is

    // MARK: The wells stand where the hands placed them

    /// The column stands where the hands placed it: the charge mouths hang
    /// at the middle of where the four stood until 2026-10-14, at the same
    /// x and depth, and since 2026-10-16 the negative charge's mouth stands
    /// where the test charge's was, the test charge's one pitch below. If a
    /// change means to move them, update the literal in the same commit.
    func testTheWellsStandWhereTheyWerePlaced() {
        func same(_ derived: SIMD3<Double>, _ historical: SIMD3<Double>,
                  _ what: String) {
            XCTAssertEqual(derived.x, historical.x, accuracy: 1e-9, "\(what) x")
            XCTAssertEqual(derived.y, historical.y, accuracy: 1e-9, "\(what) y")
            XCTAssertEqual(derived.z, historical.z, accuracy: 1e-9, "\(what) z")
        }
        same(FieldInstrumentLayout.wellAnchor(index: 0),
             SIMD3(-1.02, 1.58, -0.60), "positive charge well")
        same(FieldInstrumentLayout.wellAnchor(index: 1),
             SIMD3(-1.02, 1.58 - 0.095, -0.60), "negative charge well")
        same(FieldInstrumentLayout.wellAnchor(index: 2),
             SIMD3(-1.02, 1.58 - 2 * 0.095, -0.60), "test-charge well")
    }

    /// The spacing must now come from the neighbours' own sizes — that is
    /// the whole reason the rail exists, and a rail that ignored an
    /// item's height would reintroduce the arithmetic by hand.
    func testGrowingAnInstrumentPushesTheOneBelowIt() {
        let tall = InstrumentRail(
            head: SIMD3(0, 1.5, -1),
            gap: 0.05,
            items: [
                .init(name: "top", halfExtents: SIMD3(0.1, 0.30, 0.1)),
                .init(name: "bottom", halfExtents: SIMD3(0.1, 0.05, 0.1)),
            ])
        let short = InstrumentRail(
            head: SIMD3(0, 1.5, -1),
            gap: 0.05,
            items: [
                .init(name: "top", halfExtents: SIMD3(0.1, 0.10, 0.1)),
                .init(name: "bottom", halfExtents: SIMD3(0.1, 0.05, 0.1)),
            ])
        XCTAssertEqual(tall.anchor("bottom")!.y, 1.5 - 0.30 - 0.05 - 0.05,
                       accuracy: 1e-9)
        XCTAssertEqual(short.anchor("bottom")!.y, 1.5 - 0.10 - 0.05 - 0.05,
                       accuracy: 1e-9)
        // …and the gap between their faces is the gap, in both cases.
        for rail in [tall, short] {
            let boxes = rail.boxes.map(\.box)
            XCTAssertEqual(boxes[0].minimum.y - boxes[1].maximum.y, 0.05,
                           accuracy: 1e-9,
                           "the rail left a different gap than it was asked for")
        }
    }

    /// The shared checker has to agree with the four bespoke invariants
    /// below — otherwise the module keeps two definitions of "legal" and
    /// they drift.
    func testTheSharedClearanceCheckerPassesThisLayout() {
        let violations = InstrumentClearance.violations(
            instruments: FieldInstrumentLayout.standingInstruments,
            station: FieldInstrumentLayout.station)
        XCTAssertTrue(violations.isEmpty,
                      violations.joined(separator: "\n"))
    }

    /// …and has to be able to fail, or the line above is decoration.
    func testTheSharedClearanceCheckerCatchesAnInstrumentInThePhysics() {
        let inside = [(name: "trespasser",
                       box: StationBox(center: FieldModel.regionCenter,
                                       halfExtents: SIMD3(0.05, 0.05, 0.05)))]
        let violations = InstrumentClearance.violations(
            instruments: inside, station: FieldInstrumentLayout.station)
        XCTAssertFalse(violations.isEmpty,
                       "an instrument standing inside the station was called legal")
    }

    /// The invariant the layout exists to satisfy: the margin is the
    /// proximity-fallback radius, so an instrument closer than that to the
    /// station could be grabbed at a point also within grabbing distance of
    /// a charge.
    func testNoInstrumentStandsWithinGrabbingDistanceOfThePhysics() {
        for instrument in FieldInstrumentLayout.standingInstruments {
            XCTAssertTrue(
                instrument.box.isSeparated(from: station, margin: margin),
                """
                The \(instrument.name) is within \(margin) m of the charge \
                region. That is `resolveCharge`'s proximity-fallback radius, \
                so a pinch aimed at this instrument could also be inside \
                grabbing range of a charge — which is how this module was \
                broken before. Move it further out.
                """)
        }
    }

    // MARK: Everything is reachable without walking

    /// The replacement standard demands an instrument be "operable without
    /// being discovered". An instrument you have to step toward is one you
    /// have to notice you can reach.
    func testEveryInstrumentIsWithinReachOfAStandingUser() {
        for instrument in FieldInstrumentLayout.standingInstruments {
            let distance = instrument.box
                .distanceRange(from: FieldInstrumentLayout.viewer).nearest
            XCTAssertLessThanOrEqual(
                distance, FieldInstrumentLayout.maximumReach,
                "The \(instrument.name) is \(distance) m away — that is a step, not a reach.")
        }
    }

    /// Furniture below knee height or above a raised arm is furniture
    /// nobody uses. (The station itself spans 0.15–2.55 m; the instruments
    /// should sit in the comfortable band of that.)
    func testInstrumentsSitAtWorkingHeight() {
        for instrument in FieldInstrumentLayout.standingInstruments {
            XCTAssertGreaterThan(instrument.box.minimum.y, 0.70,
                                 "The \(instrument.name) hangs too low to use.")
            XCTAssertLessThan(instrument.box.maximum.y, 1.80,
                              "The \(instrument.name) is above a comfortable reach.")
        }
    }
}
