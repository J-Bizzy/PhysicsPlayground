//
//  InstrumentRail.swift
//  Physics Playground — Design System
//
//  WHERE AN INSTRUMENT IS ALLOWED TO STAND, for every module rather than
//  for one.
//
//  `FieldInstrumentLayout` is the best file in this project and it is
//  also the argument for this one. It states four things that must be
//  true of any instrument standing in any lab:
//
//  1. It keeps `stationMargin` clear of the physics. The number is not
//     taste — it equals the proximity-fallback radius a module uses when
//     a pinch lands on nothing nameable, so anything closer could be
//     grabbed at a point that is ALSO within grabbing distance of a real
//     object, and the two would contend.
//  2. It stays within `maximumReach` of a standing user. Past that you
//     step toward your own controls rather than reaching for them.
//  3. It does not overlap another instrument. Hit-testing uses colliders,
//     not visible geometry, so an overlap is invisible until the module
//     stops working — this project has shipped that once already
//     (`SpatialScaleHandle`, DECISIONS 2026-07-29, and the user's report
//     was "I can't even move them").
//  4. It sits in the band a person actually uses, not below the knee or
//     above a raised arm.
//
//  Every one of those is a statement about instruments in general and
//  NONE of them was available to any module but Electric Fields.
//  `CircuitsPartsLayout` mentions `maximumReach` in a comment and cannot
//  reach the constant. Gravity Lab, Pendulums, Magnetism and Kinematics
//  place their banks and rails with bare literals and no check at all —
//  so the module that had already been broken by a layout mistake is the
//  only one that cannot be broken by one again.
//
//  THE RAIL, and why a container rather than a list of anchors. The
//  errors this file's ancestor kept catching were spacing errors: half
//  extents rounded 0.21 instead of 0.2025 and leaving 2.75 cm against a
//  3 cm margin; a rail held still while the bank above it grew downward.
//  Every one of them is arithmetic between neighbours, which is exactly
//  what a caller should not be doing by hand. A rail takes instruments in
//  order, asks each how big it is, and spaces them so they cannot touch —
//  so non-overlap WITHIN a rail stops being a test that catches mistakes
//  and becomes a property of having used the type.
//
//  What the rail deliberately does NOT decide is where it stands. That is
//  a judgement about the room — which flank of the apparatus, at what
//  depth, facing which way — and it belongs to the module. Rules 1, 2
//  and 4 stay tests, because they are about the room and the rail cannot
//  know the room.
//

import Foundation
import PhysicsCore
import RealityKit
import simd

/// Something that stands in the room beside the physics: a bank, a rail,
/// a well column, a verb plate.
///
/// `footprint` is HALF-EXTENTS and must include the labels. A box that
/// measures only the switch is measuring a smaller object than the one in
/// the room, and then every clearance computed from it is wrong in the
/// dangerous direction — `FieldInstrumentLayoutTests` has caught that
/// twice, once for the bank's labels and once for the Clear plate's
/// "Tap again".
@MainActor
protocol Instrument: AnyObject {
    var root: Entity { get }
    var footprint: SIMD3<Double> { get }
}

/// A column of instruments, spaced so they cannot overlap.
///
/// Vertical because that is what every instrument column in this app
/// already is, and because a horizontal one competes with the apparatus
/// for the width of the user's view.
struct InstrumentRail {
    /// One entry: what it is called, and how big it is.
    struct Item {
        let name: String
        /// Half-extents INCLUDING labels — see `Instrument.footprint`.
        let halfExtents: SIMD3<Double>

        /// A nudge in x and z only, applied after the column position.
        ///
        /// NOT y, and that restriction is the point: y is the axis the
        /// rail computes, and letting a caller adjust it would hand back
        /// the exact arithmetic this type exists to take away. x and z
        /// are a different kind of decision — Electric Fields' B rail
        /// sits 8 cm forward of the bank above it because it is the
        /// lowest, deepest instrument in that room and was the first to
        /// run out of reach. At the column's own depth it measures
        /// 1.266 m from the viewer against a 1.25 limit; pulling it
        /// forward buys that back. No amount of vertical spacing
        /// arithmetic can know that, so it stays a room judgement.
        let inset: SIMD2<Double>

        init(name: String, halfExtents: SIMD3<Double>,
             inset: SIMD2<Double> = .zero) {
            self.name = name
            self.halfExtents = halfExtents
            self.inset = inset
        }
    }

    /// The top of the column: the centre of the FIRST item.
    ///
    /// Hung from the top rather than centred, because a column that grows
    /// downward from a fixed head keeps its first instrument at eye level
    /// however many are added — and a centred one walks the whole group
    /// down toward the floor as it grows. The wells learned this: a first
    /// attempt centred a column and a screenshot found the bottom of it
    /// below the frame entirely.
    let head: SIMD3<Double>

    /// The gap left between one item's bottom face and the next one's
    /// top face. Not a pitch — a pitch has to be recomputed by hand every
    /// time an item changes size, which is the arithmetic that kept going
    /// wrong.
    let gap: Double

    let items: [Item]

    init(head: SIMD3<Double>, gap: Double = 0.03, items: [Item]) {
        self.head = head
        self.gap = gap
        self.items = items
    }

    /// Where each item's centre lands, in order from the head downward.
    ///
    /// Spacing is derived from the neighbours' own heights, so an item
    /// that grows pushes the ones below it instead of quietly overlapping
    /// them.
    var anchors: [SIMD3<Double>] {
        var result: [SIMD3<Double>] = []
        var y = head.y
        for (index, item) in items.enumerated() {
            if index > 0 {
                y -= items[index - 1].halfExtents.y + gap + item.halfExtents.y
            }
            result.append(SIMD3(head.x + item.inset.x, y, head.z + item.inset.y))
        }
        return result
    }

    /// The anchor of the item with this name, if the rail carries one.
    func anchor(_ name: String) -> SIMD3<Double>? {
        guard let index = items.firstIndex(where: { $0.name == name }) else {
            return nil
        }
        return anchors[index]
    }

    /// Every item as a named box, for the clearance checks.
    var boxes: [(name: String, box: StationBox)] {
        zip(items, anchors).map {
            (name: $0.name,
             box: StationBox(center: $1, halfExtents: $0.halfExtents))
        }
    }

    /// The whole column as one box — what a NEIGHBOURING rail has to keep
    /// clear of.
    var bounds: StationBox? {
        let all = boxes.map(\.box)
        guard let first = all.first else { return nil }
        var lo = first.minimum, hi = first.maximum
        for box in all.dropFirst() {
            lo = simd_min(lo, box.minimum)
            hi = simd_max(hi, box.maximum)
        }
        return StationBox(center: (lo + hi) / 2, halfExtents: (hi - lo) / 2)
    }
}

/// The rules an instrument's position has to satisfy, wherever it stands.
///
/// These were `FieldInstrumentLayout`'s private constants. They are not
/// private facts about Electric Fields — `stationMargin` is a statement
/// about how every module's proximity fallback works, and the reach and
/// height bands are statements about people.
enum InstrumentClearance {

    /// Clearance from the physics, equal to the proximity-fallback radius
    /// a module uses when a pinch lands on nothing nameable. See the file
    /// header, rule 1.
    static let stationMargin = 0.12

    /// Where a standing user's head is taken to be.
    static let viewer = SIMD3<Double>(0, 1.5, 0)

    /// Past this you are stepping toward your own controls.
    static let maximumReach = 1.25

    /// The band furniture is allowed to occupy: above the knee, below a
    /// raised arm.
    static let workingHeight: ClosedRange<Double> = 0.70...1.80

    /// The gap two instruments must keep from each other.
    static let separation = 0.03

    /// What is wrong with a layout, if anything. Empty means it is legal.
    ///
    /// RETURNS THE LIST rather than asserting, so a test can report every
    /// violation at once and a caller could in principle repair one. A
    /// check that stops at the first failure turns a layout pass into as
    /// many build-run cycles as there are mistakes.
    static func violations(instruments: [(name: String, box: StationBox)],
                           station: StationBox) -> [String] {
        var found: [String] = []

        for (name, box) in instruments {
            if !box.isSeparated(from: station, margin: stationMargin) {
                found.append(String(
                    format: "%@ is %.3f m from the physics (needs %.2f) — a pinch "
                          + "aimed at it could also be inside grabbing range of a "
                          + "real object", name, box.separation(from: station),
                    stationMargin))
            }
            // NEAREST point, not the far corner. You can reach an
            // instrument if any of it is within reach; measuring to the
            // far corner would fail a wide bank whose near edge is right
            // in front of you. (Written the wrong way round first, and
            // caught by running it against a layout already known good —
            // every one of the four instruments "failed".)
            let reach = box.distanceRange(from: viewer).nearest
            if reach > maximumReach {
                found.append(String(
                    format: "%@ is %.3f m away (limit %.2f) — that is a step, "
                          + "not a reach", name, reach, maximumReach))
            }
            if box.minimum.y < workingHeight.lowerBound
                || box.maximum.y > workingHeight.upperBound {
                found.append(String(
                    format: "%@ spans y %.3f…%.3f, outside the working band "
                          + "%.2f…%.2f", name, box.minimum.y, box.maximum.y,
                    workingHeight.lowerBound, workingHeight.upperBound))
            }
        }

        for i in instruments.indices {
            for j in (i + 1)..<instruments.count {
                let a = instruments[i], b = instruments[j]
                if !a.box.isSeparated(from: b.box, margin: separation) {
                    found.append(String(
                        format: "%@ and %@ are %.4f m apart (needs %.2f) — one "
                              + "shields the other from every pinch",
                        a.name, b.name, a.box.separation(from: b.box), separation))
                }
            }
        }

        return found
    }
}
