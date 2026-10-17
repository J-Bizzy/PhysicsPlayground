//
//  FieldInstrumentLayout.swift
//  Physics Playground — Electric Fields module
//
//  Where the module's wells stand, as arithmetic. An anchor is also a
//  bounding box: a well must never shield a physics object from a pinch,
//  and the 0.12 m margin is `resolveCharge`'s fallback radius, so
//  contention is geometrically impossible. Its layers, ΔV, B and verbs
//  are in More (2026-10-14), so the wells are all that stands outside the
//  station. `FieldInstrumentLayoutTests` holds the invariants.
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

    // MARK: The well column

    /// Off the left shoulder, fore of the station's plane: what you make.
    /// x −1.02 matches Circuits' Clear plate, so the column stands where a
    /// hand already reaches in both labs.
    /// The head sits at the column's centre; it moved down half a pitch when
    /// the third mouth came, so the first two stayed where hands had learned
    /// them and the new one hangs below.
    static let foreRail = InstrumentRail(
        head: SIMD3(-1.02, 1.5325 - wellPitch / 2, -0.60),
        gap: 0.04,
        items: [
            // The mouths as one object: their pitches plus a 0.06 mouth radius.
            .init(name: "wells", halfExtents: wellHalfExtents),
        ])

    /// The mouths' pitch. Three mouths: a positive charge, a negative one
    /// and a test charge.
    static let wellPitch = 0.095
    static let wellCount = 3
    static let wellHalfExtents = SIMD3<Double>(0.06, 0.06 + wellPitch * Double(wellCount - 1) / 2, 0.06)

    static func wellAnchor(index: Int) -> SIMD3<Double> {
        let column = foreRail.anchor("wells")!
        // Hung from the top of the column's box, so a third mouth would grow
        // it downward from a fixed head rather than sliding both.
        let top = column.y + wellHalfExtents.y - 0.06
        return SIMD3(column.x, top - Double(index) * wellPitch, column.z)
    }

    // MARK: The boxes, for the tests and for anyone adding an instrument

    /// Everything that stands outside the station, by name.
    static var standingInstruments: [(name: String, box: StationBox)] {
        foreRail.boxes
    }
}
