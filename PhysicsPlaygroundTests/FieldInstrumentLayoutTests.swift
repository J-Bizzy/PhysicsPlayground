//
//  FieldInstrumentLayoutTests.swift
//  PhysicsPlaygroundTests
//
//  Electric Fields' controls moved out of a window panel and into the room
//  (2026-07-31), which means the module now has furniture standing around
//  its physics. This file is what stops that furniture becoming the bug it
//  became last time.
//
//  The failure mode is specific and it has happened here: `SpatialScaleHandle`
//  put a metre-wide invisible collider over the whole region, hit-testing
//  uses colliders rather than visible geometry, and so every pinch struck
//  the plate before reaching the charge behind it. The module was silently
//  non-interactive and the report was "I can't even move them" (DECISIONS,
//  2026-07-29). Nothing in a screenshot shows this. Arithmetic does.
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

    // MARK: Labels are part of the object

    /// A label is as much a part of an instrument as its switch, and the
    /// declared bounding box has to include it — otherwise every clearance
    /// checked in this file is measuring a smaller object than the one in
    /// the room. The bank's widest label reaches ~0.147 m from a plate's
    /// centre, which is most of its footprint.
    func testTheBanksBoxIncludesItsLabels() {
        // The bank's ACTUAL labels. "Parallel plates" stood here after
        // the plate was renamed to "Capacitor", so this measured a label
        // the room does not have — longer than the real one, which is the
        // safe direction, but still a test checking a different app.
        let reach = SpatialLayerBank.reach(forLabels: [
            "Field lines", "Free charges", "Capacitor", "Uniform B"])
        XCTAssertLessThanOrEqual(
            Double(reach), FieldInstrumentLayout.bankHalfExtents.x,
            """
            A bank label reaches \(reach) m from the plate centre but the \
            declared half-extent is \(FieldInstrumentLayout.bankHalfExtents.x). \
            Every clearance in this file is then measuring the switches \
            without their names.
            """)
    }

    /// The Clear plate's box has to cover its nameplate too — AND the
    /// "Tap again" it swaps to when armed.
    ///
    /// This is the failure mode that is unique to a confirming plate: a
    /// box sized to the resting label is correct until the moment
    /// somebody arms it, at which point the instrument silently grows
    /// into whatever it was carefully cleared of. Sizing on the longer of
    /// the two makes the armed state the one that was measured.
    func testTheClearPlatesBoxIncludesItsLabelsInBothStates() {
        let reach = SpatialActionBank.reach(forLabels: [
            "Clear all", SpatialActionBank.armedLabel])
        XCTAssertLessThanOrEqual(
            Double(reach), FieldInstrumentLayout.clearPlateHalfExtents.x,
            """
            The Clear plate's label reaches \(reach) m from the plate \
            centre but its declared half-extent is \
            \(FieldInstrumentLayout.clearPlateHalfExtents.x). Every \
            clearance checked in this file is then measuring a plate \
            without its name — and this one stands 0.13 m from a station \
            wall whose proximity fallback is 0.12.
            """)
    }

    // MARK: Nothing stands where the physics is

    /// The invariant the whole layout exists to satisfy.
    ///
    /// The margin is the proximity-fallback radius, not a taste: when a
    /// pinch lands on nothing nameable, `resolveCharge` grabs the nearest
    /// charge within 12 cm. An instrument closer than that to the station
    /// wall could be grabbed at a point that is ALSO within grabbing
    /// distance of a legally-clamped charge, and the two would contend.
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

    /// Instruments must not shield each other either. The wells and the
    /// Clear plate share a column, so that is the pair that goes wrong.
    func testInstrumentsDoNotOverlapEachOther() {
        let all = FieldInstrumentLayout.standingInstruments
        for i in all.indices {
            for j in (i + 1)..<all.count {
                XCTAssertTrue(
                    all[i].box.isSeparated(from: all[j].box, margin: 0.03),
                    "The \(all[i].name) and the \(all[j].name) are touching.")
            }
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

    // MARK: The one instrument inside the station

    /// The ΔV rail rides the capacitor, so it has to be checked over
    /// everywhere the capacitor can legally BE — not at its default. A
    /// layout that is only correct at the opening position is a layout that
    /// breaks the first time somebody carries the apparatus.
    func testTheVoltageRailStaysClearOfThePlatesWhereverTheCapacitorGoes() {
        let model = FieldModel()
        model.capacitorOn = true

        // Every corner of the station, both ends of the separation range:
        // the clamp pulls each back to the furthest legal spot, so this
        // sweeps everywhere the apparatus can actually be carried.
        for separation in [FieldModel.plateSeparationRange.lowerBound,
                           FieldModel.plateSeparationRange.upperBound] {
            for corner in station.corners {
                model.plateSeparation = separation
                // Carrying the assembly is a plate drag; its y/z take the
                // whole capacitor along.
                model.movePlate(1, toWorld: corner)
                let centre = model.capacitorCenter
                let rail = FieldInstrumentLayout.voltageTrackBox(
                    capacitorCenter: centre)

                // Never inside the plates. This is the assertion that
                // caught a `max(y, 0.85)` floor on the old under-mounted
                // position: at the capacitor's lowest legal carry height
                // the floor stopped the rail descending and left it 45 cm
                // above the capacitor's centre — threaded through the gap.
                // It was correct at the default height and wrong only when
                // carried, which is precisely the defect a screenshot
                // never shows.
                XCTAssertGreaterThan(
                    rail.minimum.y, centre.y + FieldModel.plateSize / 2,
                    "The rail is down inside the plates at \(centre).")

                // Reachable RELATIVE TO ITS APPARATUS, which is the honest
                // claim for an instrument bolted to something portable. A
                // capacitor carried overhead takes its rail with it, and
                // demanding the rail stay at chest height would be
                // demanding it stop being attached — the thing that makes
                // it better than a slider.
                let railReach = rail.distanceRange(
                    from: FieldInstrumentLayout.viewer).nearest
                let apparatusReach = simd_distance(centre, FieldInstrumentLayout.viewer)
                XCTAssertLessThanOrEqual(
                    railReach, apparatusReach + FieldInstrumentLayout.voltageTrackRise,
                    "The rail is further away than the capacitor it belongs to, at \(centre).")
            }
        }
    }

    /// The two rails are the pair most likely to collide, because the B
    /// rail is fixed and the ΔV rail travels. They are separated on x in
    /// the worst case, which is only true while neither yaws to face the
    /// viewer — see the note in `SpatialTrackControl` about why a rail
    /// bolted to an apparatus does not swivel.
    func testTheTwoRailsNeverOccupyTheSameSpace() {
        let model = FieldModel()
        model.capacitorOn = true
        let fieldRail = StationBox(
            center: FieldInstrumentLayout.fieldTrackAnchor,
            halfExtents: FieldInstrumentLayout.fieldTrackHalfExtents)

        for corner in station.corners {
            model.movePlate(1, toWorld: corner)
            let voltageRail = FieldInstrumentLayout.voltageTrackBox(
                capacitorCenter: model.capacitorCenter)
            XCTAssertTrue(
                voltageRail.isSeparated(from: fieldRail, margin: 0.03),
                "The ΔV rail reaches the B rail with the capacitor at \(model.capacitorCenter).")
        }
    }
}
