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
//  (the wells).
//
//  TWO RAILS SINCE 2026-08-08, and the anchors below are now DERIVED
//  rather than typed. The goal for this arc said to delete this file and
//  replace it with a generic `InstrumentRail`; the code disagreed, and
//  the code was right. What is generic here is the four invariants — and
//  they were generic all along, sitting in the one module that had
//  already been broken by a layout mistake while five others placed their
//  furniture with bare literals and no check at all. Those moved to
//  `InstrumentClearance`. What is NOT generic is which flank of the
//  station each rail stands on, at what depth, facing which way; that is
//  a judgement about this room and it stays here.
//
//  So the rail took the arithmetic and left the judgement, which is
//  exactly the split the errors argue for: every mistake this file's
//  tests ever caught was spacing between neighbours (half-extents
//  rounded 0.21 instead of 0.2025, leaving 2.75 cm against a 3 cm
//  margin; a rail held still while the bank above it grew downward).
//  None of them was about which side of the room something was on.
//
//  NOTHING MOVED. The two rails reproduce every previous anchor to the
//  millimetre, and `testTheRailsReproduceTheHandPlacedLayout` pins that
//  — this was a change of authorship, not of arrangement, and a pilot
//  that quietly shifted the furniture would have made the invariant
//  tests meaningless as a safety net for it.
//
//  EVERY ANCHOR MOVED OUTWARD ON 2026-07-31, and none of them moved
//  because they looked better there. The station widened from 0.62 to
//  0.78 (see `FieldModel.regionHalfExtents`), and these four boxes are
//  what a station is allowed to widen INTO — every one of them has to
//  stay `stationMargin` clear of the new wall, so all four followed it
//  out by the same 0.14 m. That runs the two invariants in this file
//  straight at each other: separation pushes furniture away from the
//  physics, `maximumReach` pulls it back toward the user, and there is
//  now about 2 cm of slack between them. Anything further and something
//  becomes a walk rather than a reach.
//
//  The B rail also came 8 cm nearer in z, which is the one anchor here
//  that is not simply the old one plus 0.14. It is the lowest and
//  deepest instrument in the room, so it was the first to run out of
//  reach; pulling it forward to z = −0.82 buys back the distance its
//  outward move cost. It is still under the bank plate that summons it,
//  which is the only thing about its position that carries meaning.
//

import Foundation
import PhysicsCore
import simd

enum FieldInstrumentLayout {

    // GRAVES, 2026-08-08. `stationMargin`, `viewer` and `maximumReach`
    // moved to `InstrumentClearance` — they were never facts about
    // Electric Fields. Re-exported here because the module's own tests
    // and comments name them, and because a reader arriving at this file
    // should not have to know where they went.
    static var stationMargin: Double { InstrumentClearance.stationMargin }
    static var viewer: SIMD3<Double> { InstrumentClearance.viewer }
    static var maximumReach: Double { InstrumentClearance.maximumReach }

    /// The physics volume the instruments must stay out of.
    static var station: StationBox {
        StationBox(center: FieldModel.regionCenter,
                   halfExtents: FieldModel.regionHalfExtents)
    }

    // MARK: The two rails

    /// LEFT — what exists. The layers bank, and under it the strength of
    /// the field its bottom plate summons, so the pair reads as one
    /// instrument: turn the field on here, set it immediately below.
    ///
    /// At the station's own depth (z = −0.9), not at its near edge. A
    /// first attempt put the furniture at z = −0.5, which is 61° off the
    /// forward axis — out at the edge of vision, where a screenshot
    /// showed the bank half out of frame. The station is 1.24 m wide, so
    /// nothing outside it can be closer than about 40°; matching its
    /// depth brings the instruments into the same band as the apparatus
    /// they belong to.
    ///
    /// The gap is 0.07 rather than the default 0.03 because these two
    /// are a pair a hand works between, not a stack.
    static let leftRail = InstrumentRail(
        head: SIMD3(-1.05, 1.42, -0.90),
        gap: 0.07,
        items: [
            // The box stays the six-plate size deliberately (four plates
            // since 2026-08-03): a declared box larger than the bank only
            // makes every clearance check stricter, and shrinking it buys
            // nothing.
            .init(name: "layers bank", halfExtents: SIMD3(0.15, 0.20, 0.15)),
            // Forward and a millimetre out — see `InstrumentRail.Item.inset`
            // for why this one is allowed to break the column.
            .init(name: "B rail", halfExtents: SIMD3(0.16, 0.05, 0.07),
                  inset: SIMD2(-0.01, 0.08)),
        ])

    /// RIGHT — what you make. The Clear plate caps a column of well
    /// mouths.
    ///
    /// Unmaking belongs with making: the wells are where every charge in
    /// the room came from, so the one control that removes them all
    /// stands at the head of the same column. ABOVE rather than below,
    /// and the two alternatives both fail on arithmetic this file already
    /// has — below the column lands under y ≈ 1.05, which a screenshot
    /// once found off the bottom of the frame; level with it and further
    /// out in x runs past `maximumReach`, since the wells' own near face
    /// is already only 0.14 clear of the station wall.
    ///
    /// The fit is genuinely tight. This is the 2 cm of slack the file
    /// header warns about, being spent.
    static let rightRail = InstrumentRail(
        head: SIMD3(1.02, 1.71, -0.90),
        gap: 0.04,
        items: [
            // Sized on the ARMED label as well as the resting one: a
            // confirming plate swaps its nameplate to "Tap again", and a
            // box sized only to "Clear all" grows on arming — straight
            // into whatever it was carefully cleared of.
            .init(name: "clear plate", halfExtents: SIMD3(0.13, 0.06, 0.08)),
            // The four mouths as ONE object. Four at 0.095 pitch span
            // 0.285, so 0.1425 + a 0.06 mouth radius = 0.2025 half-height.
            // NOT 0.21: rounding it up left 2.75 cm against a 3 cm margin,
            // invisible in any screenshot, and the exact class of error
            // these boxes exist to make impossible.
            .init(name: "wells", halfExtents: SIMD3(0.06, 0.2025, 0.06),
                  inset: SIMD2(-0.06, 0)),
        ])

    // MARK: Derived anchors
    //
    // Everything below is read out of the rails. They are kept as named
    // statics because the SpaceView asks for them by name, and because a
    // caller reaching into `leftRail.items[1]` by index is the sort of
    // thing that silently retargets when somebody inserts an instrument.

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
    ///
    /// FOUR mouths: + charge, − charge, and one test charge of each sign.
    /// The probe's polarity used to be a choice made on a particle bank
    /// after the fact, which meant the thing you pulled out of the well
    /// was whatever the bank happened to be set to. Two mouths put the
    /// choice in the act of creation, the way the ± charge mouths already
    /// did.
    static let wellPitch = 0.095
    static let wellHalfExtents = SIMD3<Double>(0.06, 0.2025, 0.06)

    static func wellAnchor(index: Int) -> SIMD3<Double> {
        let column = rightRail.anchor("wells")!
        // Hung from the top of the column's own box, so adding a fifth
        // mouth grows it downward from a fixed head rather than sliding
        // all four.
        let top = column.y + wellHalfExtents.y - 0.06
        return SIMD3(column.x, top - Double(index) * wellPitch, column.z)
    }

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
    /// Every instrument that stands OUTSIDE the station, by name.
    ///
    /// Straight off the rails now, so an instrument added to a rail is
    /// checked by every invariant for free — where the old list had to be
    /// remembered, which is the failure mode this project keeps naming.
    /// The ΔV rail is deliberately absent: it moves with the capacitor,
    /// so it is checked separately over the capacitor's whole travel.
    static var standingInstruments: [(name: String, box: StationBox)] {
        leftRail.boxes + rightRail.boxes
    }

    static func voltageTrackBox(capacitorCenter: SIMD3<Double>) -> StationBox {
        StationBox(center: voltageTrackCenter(capacitorCenter: capacitorCenter),
                   halfExtents: voltageTrackHalfExtents)
    }
}
