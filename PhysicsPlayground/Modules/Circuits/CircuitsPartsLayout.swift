//
//  CircuitsPartsLayout.swift
//  Physics Playground — Circuit Workshop
//
//  Where the parts palette stands. Pure arithmetic with no RealityKit in
//  it, so the placement that decides whether a wearer can reach their own
//  components is a thing a test can check on a Mac.
//
//  THE TRAY IS GONE (2026-08-03, owner's call). What stood here was a
//  0.93 m pale-glass slab at y = 1.02 m, dead centre, carrying all eleven
//  parts in two rows. Three things were wrong with it and only the third
//  was visible:
//
//    • It was a CONTAINER, and this app decided against containers. Every
//      other lab makes its objects with a `Well` — the thing itself,
//      standing free at the size it will be, with its name under it —
//      after the glass came off on 2026-08-01. Circuits was the one
//      module that never got that pass, so the one surface a visitor
//      touches first was the one surface still built the old way.
//    • It sat at the BOTTOM OF THE FRAME. `CircuitsSpaceView.clearAnchor`
//      already records this, in the note about why the Clear plate is not
//      allowed to stand beside the tray: "tray height is the bottom of
//      the frame — the plate sat half out of shot".
//    • It was parented to `viewRoot`, so it SCALED WITH THE ZOOM. At the
//      two-hand maximum of 8× the slab was eight times oversized and its
//      centre had travelled to y ≈ −0.59 m, which is under the floor. The
//      meter, the layer bank and the selected-part readout all
//      compensate for the rig and say so; the tray never did, and the
//      8× item in `ON_DEVICE_TESTS.md` lists the other three by name.
//      The palette hangs off `root` now and cannot inflate.
//
//  THE SHAPE: two blocks of six, one per flank, each two columns wide and
//  three rows tall, standing ABOVE the bench's furniture row. The room
//  reads in three bands now — the palette overhead on both sides, the
//  furniture at 1.2 m (Clear plate, meter, bench, layers), and the bench
//  itself in the middle.
//
//  TWO COLUMNS, NOT THREE, AND THE REASON IS REACH. The bench is 1.40 m
//  wide (`CircuitsModel.buildHalfExtents.x` = 0.70), so a palette must
//  start outside 0.70 plus a margin, and it must finish inside
//  `maximumReach` of a standing viewer. That leaves about 20 cm of usable
//  x per flank. A third column lands at |x| ≈ 1.2, which measures 1.32 m
//  from the viewer — past the line where reaching becomes stepping.
//
//  ROW PITCH IS MEASURED, NOT CHOSEN. It comes from the tallest part
//  actually in that flank plus `plateAndGap`, because these previews are
//  the renderer's own bodies at final size and a battery is 11 cm while
//  an LED is 4. The tray hardcoded its row separation and had to be
//  corrected twice — once by arithmetic and once by a screenshot, when
//  "the motor is a fat cylinder rather than the 4 cm the arithmetic
//  assumed, and it was still standing on 'Source'". A measured pitch
//  cannot make that mistake, and it costs one `visualBounds` per part at
//  build time.
//

import Foundation
import simd

enum CircuitsPartsLayout {

    /// Where a standing user's head is taken to be, for reach checks.
    /// The same viewer `FieldInstrumentLayout` uses — this is a property
    /// of people, not of a module.
    static let viewer = SIMD3<Float>(0, 1.5, 0)

    /// The furthest a source may sit from the viewer: past this you are
    /// stepping toward your own parts rather than reaching for them.
    /// Borrowed deliberately from `FieldInstrumentLayout.maximumReach`,
    /// which states the rule; two modules disagreeing about how far an
    /// arm goes would be two different arms.
    static let maximumReach: Float = 1.25

    /// The widest a source may sit off the forward axis, measured at the
    /// viewer, in degrees.
    ///
    /// **This, not `maximumReach`, is the binding constraint here, and
    /// the first build of this palette got that backwards.** Columns at
    /// |x| = 1.02, z = −0.62 measure 1.22 m from the viewer — comfortably
    /// inside reach — and sit 59° off the forward axis, which put them
    /// hard against the edge of the frame with "Battery" reading "…ery"
    /// and "Capacitor" reading "Caps…". `FieldInstrumentLayout` says the
    /// same thing about the same mistake, made at z = −0.5: "61° off the
    /// forward axis — out at the edge of vision, where a screenshot
    /// showed the bank half out of frame."
    ///
    /// Reach and angle pull in opposite directions — pulling an
    /// instrument nearer in z buys reach and spends angle — so both have
    /// to be checked, and the one that bites is the one nobody thought
    /// to write down. 48° is the shipped layers bank's own angle, which
    /// is the only empirical evidence in this module of a flank position
    /// that reads well.
    static let maximumOffAxisAngle: Float = 48

    /// The two column centres, as distances from the room's midline.
    ///
    /// Both sit INSIDE `buildHalfExtents.x`, which looks like a
    /// violation of "keep clear of the physics" and is in fact the
    /// module's existing practice: the layers bank stands at x = 0.62
    /// and the meter starts at −0.62, both inside the same 0.70 wall,
    /// and both ship. The bench's parts do not fill their box — the box
    /// is a clamp on where a part MAY be dropped, not a description of
    /// where parts are — and the palette clears the row those two stand
    /// in vertically instead. A column far enough out to clear the box
    /// in x is 50°+ off axis and out of reach both.
    static let innerColumnX: Float = 0.66
    static let outerColumnX: Float = 0.86

    /// At the bench's own depth, near enough. Matching the apparatus's
    /// depth is what keeps an instrument in the same band as the thing
    /// it belongs to; the first build pulled this in to −0.62 to buy
    /// reach and spent the whole gain on angle.
    static let columnZ: Float = -0.80

    /// The bottom row's centre. Set by what is UNDER it, not by what
    /// looks balanced: the layers bank's topmost plate reaches y ≈ 1.36,
    /// and the palette's lowest NAMEPLATE — which hangs below its part,
    /// not level with it — has to clear that.
    static let bottomRowY: Float = 1.50

    static let rows = 3
    static let columns = 2

    /// Vertical room a part needs beyond its own height: the nameplate
    /// `Well` hangs 0.034 below it, the plate itself, and a gap so two
    /// rows do not read as one object.
    ///
    /// Tight, and it has to be. The band between the furniture row below
    /// and the reach limit above is about 37 cm, and three rows of the
    /// tallest part have to fit inside it — the gap between rows is the
    /// only term in that sum with any slack in it at all.
    static let plateAndGap: Float = 0.066

    /// Which side of the room a block stands on.
    enum Flank: CaseIterable {
        case left, right
    }

    /// Which parts stand on which side.
    ///
    /// The split is the one `ComponentKind`'s own declaration order
    /// already states — "power, passives, outputs, control, wire" — cut
    /// down the middle of it: what DRIVES or INTERRUPTS a circuit on the
    /// left, what the current DOES on the right. It is not alphabetical
    /// and it is not five-and-six for balance; those would put the
    /// battery and the switch on opposite flanks, and those two are the
    /// pair a first circuit is built from.
    ///
    /// Exhaustive by construction, and a test holds it to that: a new
    /// `ComponentKind` that nobody assigned would otherwise simply not
    /// appear in the room, which is this project's "authored but never
    /// rendered" defect in the one place where it means a part you
    /// cannot build with.
    static func kinds(on flank: Flank) -> [CircuitsModel.ComponentKind] {
        switch flank {
        case .left: [.battery, .acSource, .switcher, .fuse, .wire]
        case .right: [.resistor, .capacitor, .inductor, .bulb, .led, .motor]
        }
    }

    /// How far apart this flank's rows must sit, given the tallest part
    /// standing in it.
    static func rowPitch(tallestPart: Float) -> Float {
        tallestPart + plateAndGap
    }

    /// The slot for the `index`th part of a flank, in reading order:
    /// left to right, top row first.
    ///
    /// Reading order is per-flank and mirrored, which is the one thing
    /// here that is a judgement rather than arithmetic. On the left the
    /// outer column comes first, on the right the inner one does, so
    /// both blocks read outward-in and inward-out respectively — i.e.
    /// both read left to right, the way the labels under them do.
    static func slot(_ flank: Flank, index: Int, rowPitch: Float) -> SIMD3<Float> {
        let column = index % columns
        let row = index / columns
        let magnitude: Float
        switch flank {
        case .left: magnitude = column == 0 ? outerColumnX : innerColumnX
        case .right: magnitude = column == 0 ? innerColumnX : outerColumnX
        }
        let x = flank == .left ? -magnitude : magnitude
        // Row 0 is the TOP one, so it sits `rows - 1` pitches up.
        let y = bottomRowY + Float(rows - 1 - row) * rowPitch
        return SIMD3(x, y, columnZ)
    }

    /// How far a slot is from the viewer — the number `maximumReach`
    /// governs.
    static func reach(to slot: SIMD3<Float>) -> Float {
        simd_distance(slot, viewer)
    }

    /// How far a slot sits off the forward axis, in degrees — the number
    /// `maximumOffAxisAngle` governs, and the one that decides whether a
    /// thing is in the frame or half out of it.
    ///
    /// Horizontal only. Height is what `maximumReach` already catches,
    /// and a wearer looks up and down far more freely than they turn.
    static func offAxisAngle(to slot: SIMD3<Float>) -> Float {
        let across = abs(slot.x - viewer.x)
        let away = abs(slot.z - viewer.z)
        return atan2(across, away) * 180 / .pi
    }
}
