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
    /// module's existing practice: the layers bank stands at x = −0.62
    /// and the meter starts at 0.62 (handed 2026-08-04 — buttons on the
    /// left in every module), both inside the same 0.70 wall, and both
    /// ship. The bench's parts do not fill their box — the box
    /// is a clamp on where a part MAY be dropped, not a description of
    /// where parts are — and the palette clears the row those two stand
    /// in vertically instead. A column far enough out to clear the box
    /// in x is 50°+ off axis and out of reach both.
    // THE FOUR COLUMN CONSTANTS WERE DELETED 2026-08-09, and the
    // paragraph above is kept because it is the finding, not the
    // decoration: `innerColumnX` 0.66, `outerColumnX` 0.86, `columnZ`
    // −0.80 and `bottomRowY` 1.50 are the two-flank geometry, and the
    // rack went two flanks → cabinet → one block on the right (see
    // `CircuitsSpaceView`'s note on the drawer that was built and
    // reverted). They had no readers left in any of those moves.
    //
    // The reason to keep the argument and drop the numbers: the next
    // person to want a second column will re-derive 0.66 and 0.86 in an
    // afternoon, and will not re-derive that a column far enough out to
    // clear the box in x is 50°+ off axis AND out of reach. The
    // constants were the cheap half.

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
        case .left: [.battery, .acSource, .switcher, .fuse]
        case .right: [.resistor, .capacitor, .inductor, .bulb, .led, .motor]
        }
    }

    /// How far apart this flank's rows must sit, given the tallest part

    /// The slot for the `index`th part of a flank, in reading order:
    /// left to right, top row first.
    ///
    /// Reading order is per-flank and mirrored, which is the one thing
    /// here that is a judgement rather than arithmetic. On the left the
    /// outer column comes first, on the right the inner one does, so
    /// both blocks read outward-in and inward-out respectively — i.e.
    /// both read left to right, the way the labels under them do.
    /// ONE BLOCK, ON THE RIGHT, IN THE OPENING VIEW — owner's call,
    /// 2026-08-08, replacing both the two-flank split and the parts
    /// cabinet that briefly replaced it.
    ///
    /// The cabinet was the right answer to "eleven components standing
    /// in the room permanently" and the wrong answer to what the bench
    /// is FOR: building. Parts you have to open something to reach are
    /// parts you reach for less, and a workshop with its components in a
    /// drawer is tidier and slower. Tidy was not the goal.
    ///
    /// TWO COLUMNS OF SIX, and every number here is a constraint rather
    /// than a preference:
    ///
    /// - x 0.80 and 0.94 puts the block's near face 0.04 m clear of the
    ///   bench's build volume (`buildHalfExtents.x` is 0.70). Any closer
    ///   and a part dragged to the bench's right edge would sit inside a
    ///   well's collider, which is the shielding failure that cost this
    ///   module its interactivity once already.
    /// - z −0.75, and the two numbers it sits between are the whole
    ///   design. Pulling the block FORWARD of the bench's −0.9 buys
    ///   reach: at the bench's own depth the bottom of the window is
    ///   1.31 m from a standing viewer, past the 1.25 limit. But
    ///   forward spends ANGLE for that distance, and this module has
    ///   already been bitten by exactly that trade — the first parts
    ///   palette passed the reach check with 3 cm to spare and still put
    ///   half its labels off the edge of the screen.
    ///
    ///   I repeated it. z −0.55 measures 55.5° off axis against a 48°
    ///   limit, and it shipped because the test that would have caught
    ///   it described the two-flank layout and was not carried forward.
    ///   −0.75 is 46.8° and 1.216 m: inside both, with margin on each.
    ///   `CircuitsPartsLayoutTests` checks them of the WINDOW now, not
    ///   of a flank.
    /// - Six rows at 0.105 span y 0.975…1.50, inside the working band
    ///   and inside the opening frame.
    /// ONE COLUMN, SIX AT A TIME, SCROLLING — owner's refinement,
    /// 2026-08-08: twelve slots at once is a lot to look past.
    ///
    /// The block was two columns of six. A window of six in ONE column
    /// halves the width as well as the count, and it is the arrangement
    /// where scrolling is legible: a rack sliding past a hole reads as a
    /// rack, where two columns half-filled reads as a mistake. The
    /// twelfth slot is the multimeter, which now lives here rather than
    /// standing beside the bench — see `CircuitsSpaceView`.
    /// OUTSIDE THE BUILD VOLUME BY `InstrumentClearance.stationMargin`,
    /// and that is what fixes the number rather than taste.
    ///
    /// It was 0.80 against a build volume that ends at
    /// `CircuitsModel.buildHalfExtents.x` = 0.70 — a 0.10 m gap inside a
    /// 0.12 m margin, so the rack was standing in the space the rule
    /// reserves. Measured 2026-08-09; the audit's P1-28 had noticed the
    /// consequence (parts jump inward the instant they are born) and
    /// attributed it to the old two-flank arrangement, which no longer
    /// exists. The violation survived the rewrite.
    ///
    /// Moving out to 0.82 spends the other two budgets, and
    /// `testTheWindowClearsBothLimitsWithMargin` caught it immediately:
    /// at the old depth the sixth row scraped 47.55 degrees against a
    /// 47 degree working limit. There is NO depth that satisfies all
    /// three with six rows on screen — solved numerically over z from
    /// 0.72 to 0.95, and every one fails on reach or on angle.
    ///
    /// So the window is five. z = −0.77 (further away, which is what
    /// shrinks the angle) gives reach 1.201 m against 1.23 and 46.8
    /// degrees against 47. Nothing is lost: the well scrolls, and the
    /// sixth part is one drag away — that is what the scroll is for.
    ///
    /// A part born here still enters the build volume — `add(_:at:)`
    /// clamps to 0.70, so it travels 0.12 m inward. That is not a defect
    /// to remove: the rack is furniture and the volume is where circuits
    /// live, and the clearance rule requires them to be apart.
    static let rightColumnX: Float = 0.82
    static let rightTopY: Float = 1.50
    static let rightRowPitch: Float = 0.105
    static let rightZ: Float = -0.77
    /// How many are on screen at once. FIVE, spanning y 1.08…1.50 — six
    /// put the bottom row past the reach budget once the column moved
    /// out to clear the build volume (2026-08-09). The rest are a drag
    /// away.
    static let rightVisibleRows = 5

    /// Where slot `index` stands, in world coordinates.
    ///
    /// EVERY slot has a position, including the ones currently scrolled
    /// out of the window — `Well` moves the whole rack and hides what
    /// falls outside, so the layout stays the one thing that decides
    /// where a part is.
    static func rightSlot(index: Int) -> SIMD3<Float> {
        SIMD3(rightColumnX,
              rightTopY - Float(index) * rightRowPitch,
              rightZ)
    }

    // GRAVES, 2026-08-08. `slot(_:index:rowPitch:)` and
    // `rowPitch(tallestPart:)` described the two-flank arrangement:
    // inner and outer columns, a pitch derived from the tallest part in
    // a block, and a mirrored left and right. That arrangement is gone
    // twice over — first to one right-hand block, then to a single
    // scrolling column — and code describing a room that no longer
    // exists is the thing this project keeps convicting.
    //
    // `reach(to:)` and `offAxisAngle(to:)` STAY, and are the reason this
    // is a deletion rather than a purge: they measure any slot against
    // the viewer, they are what the surviving tests use, and letting
    // them lapse with their old callers is exactly how the new column
    // shipped 7° outside a limit this file already knew about.

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
