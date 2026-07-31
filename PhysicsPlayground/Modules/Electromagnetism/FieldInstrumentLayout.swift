//
//  FieldInstrumentLayout.swift
//  Physics Playground — Electric Fields module
//
//  Where the module's instruments stand, as arithmetic rather than as
//  numbers typed into a view.
//
//  Every anchor here is also a bounding box, because the thing that has to
//  be TRUE of this layout is not "it looked right in a screenshot" — it is
//  that no instrument can shield a physics object from a pinch. This module
//  has already been broken once by exactly that (`SpatialScaleHandle`, a
//  metre-wide invisible collider over the whole region; DECISIONS.md,
//  2026-07-29, "the invisible scale plate is banned"), and the user's report
//  was "I can't even move them". Hit-testing uses colliders, not visible
//  geometry, so a layout mistake here is invisible until the module stops
//  working. `FieldInstrumentLayoutTests` checks the invariants.
//
//  THE MARGIN IS 0.12 m AND THAT NUMBER IS NOT AESTHETIC. When a pinch
//  lands on nothing nameable, `FieldSpaceView.resolveCharge` grabs the
//  nearest charge within 12 cm of the hand — an affordance that exists
//  because charges hide inside the capacitor and inside the bubble, both of
//  which carry colliders far bigger than they look. So any instrument
//  closer than 12 cm to the station wall could be pinched at a spot that is
//  also within grabbing distance of a legally-placed charge, and the two
//  would contend. Keeping every instrument a fallback-radius clear of the
//  station makes that contention geometrically impossible, which is worth
//  more than any amount of care about gesture ordering.
//
//  Layout in one sentence: what EXISTS is on the left (the layers bank, and
//  the strength of the field it summons), what you MAKE is on the right
//  (the wells, and what the test particle is).
//

import Foundation
import PhysicsCore
import simd

enum FieldInstrumentLayout {

    /// The clearance every instrument keeps from the station, equal to
    /// `resolveCharge`'s proximity-fallback radius. See the file comment.
    static let stationMargin = 0.12

    /// Where a standing user's head is taken to be, for reach checks.
    static let viewer = SIMD3<Double>(0, 1.5, 0)

    /// The furthest an instrument may sit from the viewer: past this you
    /// are stepping toward your own controls rather than reaching.
    static let maximumReach = 1.25

    /// The physics volume the instruments must stay out of.
    static var station: StationBox {
        StationBox(center: FieldModel.regionCenter,
                   halfExtents: FieldModel.regionHalfExtents)
    }

    // MARK: Left — what exists

    /// The layers bank: five plates in a column (`StackLayout` pitch 0.066,
    /// so 0.264 m of plates), standing off the station's −x flank.
    ///
    /// AT THE STATION'S OWN DEPTH (z = −0.9), not at its near edge. The
    /// first attempt put the furniture at z = −0.5, which is 61° off the
    /// forward axis — out at the edge of vision, where a screenshot showed
    /// the bank half out of frame. The station is 1.24 m wide, so nothing
    /// outside it can be closer than about 40°; matching its depth is what
    /// brings the instruments back into the same band as the apparatus
    /// they belong to. Circuits' bank sits beside its bench for exactly
    /// this reason, and says so.
    static let bankAnchor = SIMD3<Double>(-0.91, 1.38, -0.90)
    static let bankHalfExtents = SIMD3<Double>(0.15, 0.15, 0.15)

    /// The B-strength rail, directly under the bank's bottom plate —
    /// under the very switch that summons it, so the pair reads as one
    /// instrument: turn the field on here, set its strength immediately
    /// below. (The bank's plates span y 1.25…1.51.)
    static let fieldTrackAnchor = SIMD3<Double>(-0.93, 1.13, -0.90)
    static let fieldTrackHalfExtents = SIMD3<Double>(0.16, 0.05, 0.07)
    /// Faces the user across the station's corner, so the rail runs
    /// horizontally across their view rather than edge-on.
    static let fieldTrackNormal = SIMD3<Double>(0.93, 0, 0.50)

    // MARK: Right — what you make

    /// The three well mouths, in a column: +, −, and the test charge.
    ///
    /// The column is hung from the TOP rather than centred, because the
    /// particle bank sits under it and the pair has to fit between the
    /// user's eye height and the bottom of their comfortable view. A first
    /// attempt put the bank at y = 0.98 and a screenshot found it below
    /// the frame entirely — reachable by the arithmetic, invisible in
    /// practice, which is the standard's "visible without being looked
    /// for" failing quietly.
    static let wellColumnX = 0.85
    static let wellColumnZ = -0.90
    static let wellPitch = 0.11
    static let wellTopY = 1.55
    static let wellHalfExtents = SIMD3<Double>(0.06, 0.17, 0.06)

    static func wellAnchor(index: Int) -> SIMD3<Double> {
        SIMD3(wellColumnX, wellTopY - Double(index) * wellPitch, wellColumnZ)
    }

    /// The particle bank: four discs in a shallow row under the wells.
    static let particlePickerAnchor = SIMD3<Double>(0.92, 1.15, -0.92)
    static let particlePickerHalfExtents = SIMD3<Double>(0.16, 0.07, 0.16)

    // MARK: On the apparatus

    /// The ΔV rail, bolted under the capacitor and carried with it.
    ///
    /// The one instrument INSIDE the station, and it earns that: a voltage
    /// belongs to the plates it is across, and a rail parked on the far
    /// side of the room would be a slider with extra steps. The price is
    /// stated rather than hidden — a free charge can drift within the
    /// fallback radius of this rail, so the rail's collider is a thin box
    /// (see `SpatialTrackControl`) and it only exists while the capacitor
    /// does. It cannot be made impossible without cutting the coupling that
    /// makes the instrument worth having.
    /// How far above the capacitor's centre the rail is mounted.
    ///
    /// Three terms, and leaving one out is what the layout test caught:
    /// half the plate's height (0.25), half the rail's own box (0.05), and
    /// 5 cm of daylight between them. At 0.30 the rail's bottom edge
    /// landed exactly ON the plate's top edge — clearance measured from
    /// the rail's CENTRE rather than its surface, which is the same class
    /// of error as sizing a collider by its visual radius.
    static let voltageTrackRise = 0.35
    static let voltageTrackHalfExtents = SIMD3<Double>(0.15, 0.05, 0.04)

    /// ON TOP OF THE APPARATUS, not under it, and both halves of that were
    /// learned the hard way.
    ///
    /// It started BELOW the plates with a `max(y, 0.85)` floor to keep it
    /// off the ground. The floor was a bug: the capacitor can legitimately
    /// be carried down to y = 0.40 (`movePlate` clamps to `plateSize/2 +
    /// 0.15`), and there the floor stopped the rail descending and left it
    /// 45 cm ABOVE the capacitor's centre — threaded through the plates,
    /// exactly where a rail must never be. It only misbehaved when the
    /// apparatus was carried, so the default view never showed it.
    ///
    /// Removing the floor fixed that and revealed the real problem: the
    /// plates are 0.5 m tall and centred at chest height, so their bottom
    /// edge is already 0.4 m below the eye. A rail under them sat 36° down
    /// at 0.6 m — out of frame in the simulator, and a neck angle nobody
    /// would hold on device. Above the plates it sits about 10° UP, which
    /// is where a bench supply keeps its controls anyway.
    ///
    /// No forward offset either. Pulling the rail toward the user put it
    /// between them and the gap the field lives in — the one volume this
    /// apparatus exists to show.
    static func voltageTrackCenter(capacitorCenter: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3(capacitorCenter.x,
              capacitorCenter.y + voltageTrackRise,
              capacitorCenter.z)
    }

    // MARK: The boxes, for the tests and for anyone adding an instrument

    /// Every instrument that stands OUTSIDE the station, by name.
    /// The ΔV rail is deliberately absent — it moves with the capacitor, so
    /// it is checked separately over the capacitor's whole travel.
    static var standingInstruments: [(name: String, box: StationBox)] {
        var boxes: [(String, StationBox)] = [
            ("layers bank", StationBox(center: bankAnchor,
                                       halfExtents: bankHalfExtents)),
            ("B rail", StationBox(center: fieldTrackAnchor,
                                  halfExtents: fieldTrackHalfExtents)),
            ("particle bank", StationBox(center: particlePickerAnchor,
                                         halfExtents: particlePickerHalfExtents)),
        ]
        // The three wells share one column; as a group they are one object
        // to keep clear of everything else.
        let top = wellAnchor(index: 0)
        let bottom = wellAnchor(index: 2)
        boxes.append(("wells", StationBox(center: (top + bottom) / 2,
                                          halfExtents: wellHalfExtents)))
        // (The column's own box: `wellHalfExtents.y` must cover the pitch
        // plus a mouth's radius and halo, or the separation checks below
        // are measuring a smaller object than the one in the room.)
        return boxes.map { (name: $0.0, box: $0.1) }
    }

    static func voltageTrackBox(capacitorCenter: SIMD3<Double>) -> StationBox {
        StationBox(center: voltageTrackCenter(capacitorCenter: capacitorCenter),
                   halfExtents: voltageTrackHalfExtents)
    }
}
