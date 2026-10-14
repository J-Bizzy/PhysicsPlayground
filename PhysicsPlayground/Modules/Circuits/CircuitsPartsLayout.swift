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

    /// A standing user's head, for reach checks — the same viewer
    /// `FieldInstrumentLayout` uses.
    static let viewer = SIMD3<Float>(0, 1.5, 0)

    /// Furthest a source may sit from the viewer before reaching becomes
    /// stepping.
    static let maximumReach: Float = 1.25

    /// Widest off the forward axis a source may sit, degrees. The binding
    /// constraint: nearer in z buys reach and spends angle.
    static let maximumOffAxisAngle: Float = 48

    /// Order within the one column, not geography: sources and interrupters
    /// above loads.
    enum Flank: CaseIterable {
        case left, right
    }

    /// What drives or interrupts a circuit first, then what the current
    /// does. Exhaustive by construction; a test fails any unassigned kind.
    static func kinds(on flank: Flank) -> [CircuitsModel.ComponentKind] {
        switch flank {
        case .left: [.battery, .acSource, .switcher, .fuse]
        case .right: [.resistor, .capacitor, .inductor, .bulb, .led, .motor]
        }
    }

    /// One scrolling column on the right, clear of the build volume by more
    /// than `InstrumentClearance.stationMargin` (x 0.74 against 0.60 +
    /// 0.12). z −0.77 keeps the column 43.9° off axis against the 48° limit.
    /// Six rows reach 1.190 m from the viewer; a seventh would reach 1.240 m
    /// and fail the margin line, so six is the ceiling
    /// (`CircuitsPartsLayoutTests`).
    static let rightColumnX: Float = 0.74
    static let rightTopY: Float = 1.50
    static let rightRowPitch: Float = 0.105
    static let rightZ: Float = -0.77
    /// How many are on screen at once; the rest are a drag away.
    static let rightVisibleRows = 6

    /// Where slot `index` stands, in world coordinates; `Well` hides what
    /// falls outside the window.
    static func rightSlot(index: Int) -> SIMD3<Float> {
        SIMD3(rightColumnX,
              rightTopY - Float(index) * rightRowPitch,
              rightZ)
    }

    /// How far a slot is from the viewer — the number `maximumReach` governs.
    static func reach(to slot: SIMD3<Float>) -> Float {
        simd_distance(slot, viewer)
    }

    /// How far a slot sits off the forward axis, degrees. Horizontal only;
    /// height is what `maximumReach` catches.
    static func offAxisAngle(to slot: SIMD3<Float>) -> Float {
        let across = abs(slot.x - viewer.x)
        let away = abs(slot.z - viewer.z)
        return atan2(across, away) * 180 / .pi
    }
}
