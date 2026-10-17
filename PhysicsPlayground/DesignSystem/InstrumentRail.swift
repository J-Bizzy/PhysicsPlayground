//
//  InstrumentRail.swift
//  Physics Playground — Design System
//
//  Where an instrument may stand: shared clearance rules, and a rail that
//  spaces a column of instruments so they cannot overlap. The rail decides
//  spacing only — where it stands is the module's room judgement.
//

import Foundation
import PhysicsCore
import RealityKit
import simd

/// Something that stands in the room beside the physics.
/// `footprint` is half-extents and must include the labels — measuring only
/// the switch makes every clearance wrong in the dangerous direction.
@MainActor
protocol Instrument: AnyObject {
    var root: Entity { get }
    var footprint: SIMD3<Double> { get }
}

/// A vertical column of instruments, spaced so they cannot overlap.
struct InstrumentRail {
    /// One entry: what it is called, and how big it is.
    struct Item {
        let name: String
        /// Half-extents including labels — see `Instrument.footprint`.
        let halfExtents: SIMD3<Double>

        /// A nudge in x and z only — never y, which the rail computes.
        /// x/z stay a room judgement (e.g. pulling a deep item forward
        /// to keep it within reach).
        let inset: SIMD2<Double>

        init(name: String, halfExtents: SIMD3<Double>,
             inset: SIMD2<Double> = .zero) {
            self.name = name
            self.halfExtents = halfExtents
            self.inset = inset
        }
    }

    /// The centre of the first item. Hung from the top so the first
    /// instrument stays at eye level however many items are added.
    let head: SIMD3<Double>

    /// The gap between one item's bottom face and the next one's top face.
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

    /// The whole column as one box — what a neighbouring rail has to keep
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
enum InstrumentClearance {

    /// Clearance from the physics. A default: pass the module's own
    /// proximity radius, or 0 if it has none — overlap is still checked.
    static let stationMargin = 0.12

    /// Where a standing user's head is taken to be.
    nonisolated static let viewer = SIMD3<Double>(0, 1.5, 0)

    /// Past this you are stepping toward your own controls.
    static let maximumReach = 1.25

    /// The band furniture is allowed to occupy: above the knee, below a
    /// raised arm.
    static let workingHeight: ClosedRange<Double> = 0.70...1.80

    /// The gap two instruments must keep from each other.
    static let separation = 0.03

    /// What is wrong with a layout, if anything; empty means legal.
    /// Returns the full list so a test reports every violation at once.
    static func violations(instruments: [(name: String, box: StationBox)],
                           station: StationBox,
                           margin: Double = stationMargin) -> [String] {
        var found: [String] = []

        for (name, box) in instruments {
            if !box.isSeparated(from: station, margin: margin) {
                found.append(String(
                    format: "%@ is %.3f m from the physics (needs %.2f) — a pinch "
                          + "aimed at it could also be inside grabbing range of a "
                          + "real object", name, box.separation(from: station),
                    margin))
            }
            // Nearest point, not the far corner — you can reach an
            // instrument if any of it is within reach.
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
