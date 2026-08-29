//
//  CircuitsPartsLayout.swift
//  Physics Playground — Circuit Workshop
//
//  Where the parts palette stands. Pure arithmetic, no RealityKit, so
//  reach and off-axis placement are testable on a Mac.
//

import Foundation
import simd

enum CircuitsPartsLayout {

    /// A standing user's head, for reach checks — same viewer
    /// `FieldInstrumentLayout` uses (a property of people, not modules).
    static let viewer = SIMD3<Float>(0, 1.5, 0)

    /// Furthest a source may sit from the viewer before reaching becomes
    /// stepping. Shared with `FieldInstrumentLayout.maximumReach`.
    static let maximumReach: Float = 1.25

    /// Widest off the forward axis a source may sit, in degrees. THE
    /// BINDING CONSTRAINT here, not `maximumReach`: reach and angle pull
    /// opposite ways (nearer in z buys reach, spends angle). 48° is the
    /// shipped layers bank's own angle.
    static let maximumOffAxisAngle: Float = 48

    /// Furniture may stand outside `buildHalfExtents` (0.60) and some of
    /// it stands inside — the box is where a reset LAYS PARTS OUT and
    /// where instruments take their bearings, not a wall. The layers bank
    /// (−0.62) still overlaps it; the rack (0.74) clears it by the
    /// station margin. Both are correct.

    /// ORDER within the one column, not geography: the racks merged into
    /// a single right-hand column, and the flanks survive only as the
    /// grouping that keeps sources-and-interrupters above loads.
    enum Flank: CaseIterable {
        case left, right
    }

    /// What DRIVES or INTERRUPTS a circuit first, then what the current
    /// DOES. Exhaustive by construction — a test fails any unassigned
    /// kind, so no `ComponentKind` can be authored but unbuildable.
    static func kinds(on flank: Flank) -> [CircuitsModel.ComponentKind] {
        switch flank {
        case .left: [.battery, .acSource, .switcher, .fuse]
        case .right: [.resistor, .capacitor, .inductor, .bulb, .led, .motor]
        }
    }

    /// One scrolling column on the right, cleared of the build volume by
    /// `InstrumentClearance.stationMargin`. Every number is a constraint,
    /// not taste.
    ///
    /// **x 0.74** clears `buildHalfExtents.x` (0.60) by 0.14, against a
    /// `stationMargin` of 0.12. NOT 0.72, which is the margin exactly:
    /// `InstrumentReachCriterionTests` states the rule — *"Exactly at the
    /// limit is not clearance, it is a coincidence."*
    ///
    /// **z −0.77** shrinks the off-axis angle: `atan2(0.74, 0.77)` = 43.9°
    /// against the 48° limit. It was 46.8° at x 0.82, two-tenths of a
    /// degree off the margin line — narrowing the bench on 2026-08-26 is
    /// what bought that budget back.
    ///
    /// **Six rows, and six is the ceiling.** Reach to the worst visible
    /// slot from the viewer at (0, 1.5, 0), by row count:
    ///
    ///     5 rows (Δy 0.42):  1.145 m
    ///     6 rows (Δy 0.525): 1.190 m   ← ships
    ///     7 rows (Δy 0.63):  1.240 m   ← fails the 1.23 margin line
    ///
    /// The comment here used to read *"No depth satisfies reach and angle
    /// with SIX rows on screen, so the window is five"* — true at x 0.82,
    /// where six rows reached 1.246 m and all but touched the hard 1.25.
    /// Do not try seven. `CircuitsPartsLayoutTests` checks the window and
    /// asserts the seventh row would fail.
    static let rightColumnX: Float = 0.74
    static let rightTopY: Float = 1.50
    static let rightRowPitch: Float = 0.105
    static let rightZ: Float = -0.77
    /// How many are on screen at once; the rest are a drag away.
    static let rightVisibleRows = 6

    /// Where slot `index` stands, in world coordinates. Every slot has a
    /// position, including ones scrolled out — `Well` hides what falls
    /// outside the window.
    static func rightSlot(index: Int) -> SIMD3<Float> {
        SIMD3(rightColumnX,
              rightTopY - Float(index) * rightRowPitch,
              rightZ)
    }

    /// How far a slot is from the viewer — the number `maximumReach` governs.
    static func reach(to slot: SIMD3<Float>) -> Float {
        simd_distance(slot, viewer)
    }

    /// How far a slot sits off the forward axis, in degrees — the number
    /// `maximumOffAxisAngle` governs. Horizontal only; height is what
    /// `maximumReach` catches.
    static func offAxisAngle(to slot: SIMD3<Float>) -> Float {
        let across = abs(slot.x - viewer.x)
        let away = abs(slot.z - viewer.z)
        return atan2(across, away) * 180 / .pi
    }
}
