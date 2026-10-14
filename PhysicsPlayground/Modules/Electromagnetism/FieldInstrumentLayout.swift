//
//  FieldInstrumentLayout.swift
//  Physics Playground — Electric Fields module
//
//  Where the module's instruments stand, as arithmetic. Every anchor is
//  also a bounding box: an instrument must never shield a physics object
//  from a pinch, and the 0.12 m margin is `resolveCharge`'s fallback
//  radius, so contention is geometrically impossible. Every control
//  stands on the left, split by depth: what exists deep at the station's
//  own z, what you make fore of it. `FieldInstrumentLayoutTests` holds
//  the invariants.
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

    /// Deep — what exists: the layers bank, and under it the B rail its
    /// bottom plate summons, at the station's own depth. The 0.07 gap is
    /// because a hand works between the two.
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

    /// Fore — what you make: the well mouths with the Clear plate at the
    /// base. x −1.02 and y 1.23 match Circuits' Clear plate exactly, so the
    /// hand that learns one has learned the other, leaving 1 cm of slack
    /// against the station margin. z −0.60 is fore of the deep rail because
    /// a second column at −0.90 overlaps the bank, and deeper than −0.7
    /// shadows the bank's labels.
    static let foreRail = InstrumentRail(
        head: SIMD3(-1.02, 1.5325, -0.60),
        gap: 0.04,
        items: [
            // The four mouths as one object: 0.1425 + a 0.06 mouth radius, not
            // rounded up, which left 2.75 cm against a 3 cm margin.
            .init(name: "wells", halfExtents: SIMD3(0.06, 0.2025, 0.06)),
            // Sized on the armed label too: a confirming plate grows on arming.
            .init(name: "clear plate", halfExtents: SIMD3(0.13, 0.06, 0.08)),
        ])

    // MARK: Derived anchors
    // Read out of the rails by name: an index silently retargets when an
    // instrument is inserted.

    static var bankAnchor: SIMD3<Double> { leftRail.anchor("layers bank")! }
    static let bankHalfExtents = SIMD3<Double>(0.15, 0.20, 0.15)

    static var fieldTrackAnchor: SIMD3<Double> { leftRail.anchor("B rail")! }
    static let fieldTrackHalfExtents = SIMD3<Double>(0.16, 0.05, 0.07)
    /// Faces the user across the station's corner, so the rail runs
    /// horizontally across their view rather than edge-on.
    static let fieldTrackNormal = SIMD3<Double>(0.93, 0, 0.50)

    static var clearPlateAnchor: SIMD3<Double> { foreRail.anchor("clear plate")! }
    static let clearPlateHalfExtents = SIMD3<Double>(0.13, 0.06, 0.08)

    /// The well mouths' pitch. Four mouths: + charge, − charge, and one
    /// test charge of each sign.
    static let wellPitch = 0.095
    static let wellHalfExtents = SIMD3<Double>(0.06, 0.2025, 0.06)

    static func wellAnchor(index: Int) -> SIMD3<Double> {
        let column = foreRail.anchor("wells")!
        // Hung from the top of the column's box, so a fifth mouth grows it
        // downward from a fixed head rather than sliding all four.
        let top = column.y + wellHalfExtents.y - 0.06
        return SIMD3(column.x, top - Double(index) * wellPitch, column.z)
    }

    // MARK: On the apparatus

    /// The ΔV rail, bolted over the capacitor and carried with it — the one
    /// instrument inside the station, since a voltage belongs to its
    /// plates. Half the plate height, half the rail's box and 5 cm of
    /// daylight.
    static let voltageTrackRise = 0.35
    static let voltageTrackHalfExtents = SIMD3<Double>(0.15, 0.05, 0.04)

    /// On top of the apparatus: the plates are 0.5 m tall at chest height,
    /// so a rail beneath them sits out of frame. No forward offset, which
    /// would put it over the gap.
    static func voltageTrackCenter(capacitorCenter: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3(capacitorCenter.x,
              capacitorCenter.y + voltageTrackRise,
              capacitorCenter.z)
    }

    // MARK: The boxes, for the tests and for anyone adding an instrument

    /// Every instrument that stands outside the station, by name, straight
    /// off the rails. The ΔV rail is absent: it moves with the capacitor
    /// and is checked over the capacitor's whole travel.
    static var standingInstruments: [(name: String, box: StationBox)] {
        leftRail.boxes + foreRail.boxes
    }

    static func voltageTrackBox(capacitorCenter: SIMD3<Double>) -> StationBox {
        StationBox(center: voltageTrackCenter(capacitorCenter: capacitorCenter),
                   halfExtents: voltageTrackHalfExtents)
    }
}
