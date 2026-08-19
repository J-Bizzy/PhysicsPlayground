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

    /// The two column centres sit INSIDE `buildHalfExtents.x` (0.70) —
    /// existing practice (layers bank at −0.62, meter at 0.62); the box
    /// clamps where a part MAY drop, not where furniture stands, and the
    /// palette clears their row vertically. A column far enough out to
    /// clear the box in x is 50°+ off axis and out of reach.

    static let rows = 3
    static let columns = 2

    /// Vertical room a part needs beyond its own height (nameplate 0.034
    /// below, plate, inter-row gap). Tight: three rows of the tallest
    /// part must fit the ~37 cm band, and the gap is the only slack.
    static let plateAndGap: Float = 0.066

    /// Which side of the room a block stands on.
    enum Flank: CaseIterable {
        case left, right
    }

    /// Which parts stand on which side: what DRIVES or INTERRUPTS a
    /// circuit on the left, what the current DOES on the right.
    /// Exhaustive by construction — a test fails any unassigned kind, so
    /// no `ComponentKind` can be authored but unbuildable.
    static func kinds(on flank: Flank) -> [CircuitsModel.ComponentKind] {
        switch flank {
        case .left: [.battery, .acSource, .switcher, .fuse]
        case .right: [.resistor, .capacitor, .inductor, .bulb, .led, .motor]
        }
    }

    /// One scrolling column on the right, cleared of the build volume by
    /// `InstrumentClearance.stationMargin`. Every number is a constraint,
    /// not taste: x 0.82 clears the volume (`buildHalfExtents.x` 0.70);
    /// z −0.77 shrinks the off-axis angle (reach 1.201 m, 46.8°). No
    /// depth satisfies reach and angle with SIX rows on screen, so the
    /// window is five. `CircuitsPartsLayoutTests` checks the window.
    static let rightColumnX: Float = 0.82
    static let rightTopY: Float = 1.50
    static let rightRowPitch: Float = 0.105
    static let rightZ: Float = -0.77
    /// How many are on screen at once; the rest are a drag away.
    static let rightVisibleRows = 5

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
