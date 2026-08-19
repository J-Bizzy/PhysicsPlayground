//
//  FieldInstrumentLayout.swift
//  Physics Playground — Electric Fields module
//
//  Where the module's instruments stand, as arithmetic rather than numbers
//  typed into a view. Every anchor is also a bounding box: no instrument may
//  shield a physics object from a pinch, and hit-testing uses colliders (not
//  visible geometry), so a layout mistake is invisible until the module stops
//  working. `FieldInstrumentLayoutTests` checks the invariants.
//
//  THE MARGIN IS 0.12 m AND IS NOT AESTHETIC: `FieldSpaceView.resolveCharge`
//  grabs the nearest charge within 12 cm of an unnameable pinch, so any
//  instrument closer than that to the station wall could contend with a
//  legally-placed charge. Keeping every instrument a fallback-radius clear
//  makes contention geometrically impossible.
//
//  Layout: what EXISTS is on the left (layers bank + the field strength it
//  summons), what you MAKE is on the right (the wells). Anchors are DERIVED
//  from two `InstrumentRail`s; the generic invariants live in
//  `InstrumentClearance`. Which flank/depth/facing each rail takes is a
//  judgement about this room and stays here.
//

import Foundation
import PhysicsCore
import simd

enum FieldInstrumentLayout {

    // Re-exported from `InstrumentClearance`, which the module's own tests name.
    static var stationMargin: Double { InstrumentClearance.stationMargin }
    static var viewer: SIMD3<Double> { InstrumentClearance.viewer }
    static var maximumReach: Double { InstrumentClearance.maximumReach }

    /// The physics volume the instruments must stay out of.
    static var station: StationBox {
        StationBox(center: FieldModel.regionCenter,
                   halfExtents: FieldModel.regionHalfExtents)
    }

    // MARK: The two rails

    /// LEFT — what exists: the layers bank, and under it the field strength
    /// its bottom plate summons. At the station's own depth (z = −0.9), so
    /// the instruments sit in the same band as the apparatus. The 0.07 gap
    /// (vs the default 0.03) is because these two are a pair a hand works
    /// between, not a stack.
    static let leftRail = InstrumentRail(
        head: SIMD3(-1.05, 1.42, -0.90),
        gap: 0.07,
        items: [
            // A declared box larger than the bank only makes clearance
            // checks stricter, so it stays the wider size.
            .init(name: "layers bank", halfExtents: SIMD3(0.15, 0.20, 0.15)),
            // Forward and a millimetre out — see `InstrumentRail.Item.inset`
            // for why this one is allowed to break the column.
            .init(name: "B rail", halfExtents: SIMD3(0.16, 0.05, 0.07),
                  inset: SIMD2(-0.01, 0.08)),
        ])

    /// RIGHT — what you make: the Clear plate caps a column of well mouths.
    /// The wells made every charge in the room, so the control that removes
    /// them all heads the same column. Above rather than below or level:
    /// below drops off the bottom of frame, level-and-out runs past
    /// `maximumReach`. The fit is tight — the 2 cm of slack the header warns of.
    static let rightRail = InstrumentRail(
        head: SIMD3(1.02, 1.71, -0.90),
        gap: 0.04,
        items: [
            // Sized on the ARMED label too: a confirming plate swaps its
            // nameplate to "Tap again", and a box sized only to "Clear all"
            // would grow on arming into what it just cleared.
            .init(name: "clear plate", halfExtents: SIMD3(0.13, 0.06, 0.08)),
            // The four mouths as ONE object. Four at 0.095 pitch span 0.285,
            // so 0.1425 + a 0.06 mouth radius = 0.2025 half-height. NOT 0.21:
            // rounding up left 2.75 cm against a 3 cm margin.
            .init(name: "wells", halfExtents: SIMD3(0.06, 0.2025, 0.06),
                  inset: SIMD2(-0.06, 0)),
        ])

    // MARK: Derived anchors
    //
    // Read out of the rails, kept as named statics because the SpaceView asks
    // by name — reaching `leftRail.items[1]` by index silently retargets when
    // an instrument is inserted.

    static var bankAnchor: SIMD3<Double> { leftRail.anchor("layers bank")! }
    static let bankHalfExtents = SIMD3<Double>(0.15, 0.20, 0.15)

    static var fieldTrackAnchor: SIMD3<Double> { leftRail.anchor("B rail")! }
    static let fieldTrackHalfExtents = SIMD3<Double>(0.16, 0.05, 0.07)
    /// Faces the user across the station's corner, so the rail runs
    /// horizontally across their view rather than edge-on.
    static let fieldTrackNormal = SIMD3<Double>(0.93, 0, 0.50)

    static var clearPlateAnchor: SIMD3<Double> { rightRail.anchor("clear plate")! }
    static let clearPlateHalfExtents = SIMD3<Double>(0.13, 0.06, 0.08)

    /// The well mouths, spaced within the column the right rail places.
    /// FOUR mouths: + charge, − charge, and one test charge of each sign —
    /// the probe's polarity is chosen by which mouth you pull from.
    static let wellPitch = 0.095
    static let wellHalfExtents = SIMD3<Double>(0.06, 0.2025, 0.06)

    static func wellAnchor(index: Int) -> SIMD3<Double> {
        let column = rightRail.anchor("wells")!
        // Hung from the top of the column's box, so a fifth mouth grows it
        // downward from a fixed head rather than sliding all four.
        let top = column.y + wellHalfExtents.y - 0.06
        return SIMD3(column.x, top - Double(index) * wellPitch, column.z)
    }

    // MARK: On the apparatus

    /// The ΔV rail, bolted under the capacitor and carried with it — the one
    /// instrument INSIDE the station, since a voltage belongs to its plates.
    /// A free charge can drift within its fallback radius, so its collider is
    /// a thin box (see `SpatialTrackControl`) and it exists only with the
    /// capacitor.
    ///
    /// How far above the capacitor's centre the rail is mounted. Three terms:
    /// half the plate height (0.25), half the rail's box (0.05), and 5 cm of
    /// daylight — clearance measured from the rail's surface, not its centre.
    static let voltageTrackRise = 0.35
    static let voltageTrackHalfExtents = SIMD3<Double>(0.15, 0.05, 0.04)

    /// ON TOP OF THE APPARATUS, not under it: the plates are 0.5 m tall at
    /// chest height, so a rail beneath them sits 36° down and out of frame,
    /// while above them it sits ~10° up where a bench supply keeps its
    /// controls. No forward offset — that would put it over the gap the
    /// field lives in.
    static func voltageTrackCenter(capacitorCenter: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3(capacitorCenter.x,
              capacitorCenter.y + voltageTrackRise,
              capacitorCenter.z)
    }

    // MARK: The boxes, for the tests and for anyone adding an instrument

    /// Every instrument that stands OUTSIDE the station, by name — straight
    /// off the rails, so a new instrument is checked by every invariant for
    /// free. The ΔV rail is deliberately absent: it moves with the capacitor
    /// and is checked separately over the capacitor's whole travel.
    static var standingInstruments: [(name: String, box: StationBox)] {
        leftRail.boxes + rightRail.boxes
    }

    static func voltageTrackBox(capacitorCenter: SIMD3<Double>) -> StationBox {
        StationBox(center: voltageTrackCenter(capacitorCenter: capacitorCenter),
                   halfExtents: voltageTrackHalfExtents)
    }
}
