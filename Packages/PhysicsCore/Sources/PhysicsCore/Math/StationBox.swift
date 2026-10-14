//
//  StationBox.swift
//  PhysicsCore — Math: the volume one apparatus may occupy; pure geometry
//  for layout assertions. Two invariants for two station kinds: benches
//  side by side must be disjoint (`separation`); benches inside a
//  room-sized apparatus are checked for containment (`distanceRange`).
//

import Foundation
import simd

/// An axis-aligned volume belonging to one apparatus, world coordinates.
public struct StationBox: Equatable, Sendable {
    public var center: SIMD3<Double>
    public var halfExtents: SIMD3<Double>

    public init(center: SIMD3<Double>, halfExtents: SIMD3<Double>) {
        self.center = center
        self.halfExtents = SIMD3(abs(halfExtents.x),
                                 abs(halfExtents.y),
                                 abs(halfExtents.z))
    }

    public var minimum: SIMD3<Double> { center - halfExtents }
    public var maximum: SIMD3<Double> { center + halfExtents }

    /// The eight corners.
    public var corners: [SIMD3<Double>] {
        let lo = minimum, hi = maximum
        return [
            SIMD3(lo.x, lo.y, lo.z), SIMD3(hi.x, lo.y, lo.z),
            SIMD3(lo.x, hi.y, lo.z), SIMD3(hi.x, hi.y, lo.z),
            SIMD3(lo.x, lo.y, hi.z), SIMD3(hi.x, lo.y, hi.z),
            SIMD3(lo.x, hi.y, hi.z), SIMD3(hi.x, hi.y, hi.z),
        ]
    }

    // MARK: Disjointness — the invariant for benches side by side

    /// Widest per-axis gap between the boxes, negative when overlapping on
    /// every axis. Max over axes (one clear axis proves AABB disjointness).
    public func separation(from other: StationBox) -> Double {
        var widest = -Double.greatestFiniteMagnitude
        for axis in 0..<3 {
            let gap = Swift.max(minimum[axis] - other.maximum[axis],
                                other.minimum[axis] - maximum[axis])
            widest = Swift.max(widest, gap)
        }
        return widest
    }

    /// Whether the two boxes keep at least `margin` between them.
    public func isSeparated(from other: StationBox, margin: Double = 0) -> Bool {
        separation(from: other) >= margin
    }

    // MARK: Containment — the invariant for clamps, grids and plates

    public func contains(_ point: SIMD3<Double>, tolerance: Double = 1e-9) -> Bool {
        let lo = minimum, hi = maximum
        for axis in 0..<3
        where point[axis] < lo[axis] - tolerance
            || point[axis] > hi[axis] + tolerance {
            return false
        }
        return true
    }

    /// Whether `other` sits wholly inside this box.
    public func contains(_ other: StationBox, tolerance: Double = 1e-9) -> Bool {
        let lo = minimum, hi = maximum
        let oLo = other.minimum, oHi = other.maximum
        for axis in 0..<3
        where oLo[axis] < lo[axis] - tolerance || oHi[axis] > hi[axis] + tolerance {
            return false
        }
        return true
    }

    /// This box translated by a station's display offset.
    public func offset(by delta: SIMD3<Double>) -> StationBox {
        StationBox(center: center + delta, halfExtents: halfExtents)
    }

    // MARK: Radial reach — the invariant for an apparatus you stand inside

    /// Near = point-to-AABB distance (0 inside), far = most distant corner.
    /// Both are needed to place a bench inside an annulus between orbits.
    public func distanceRange(from point: SIMD3<Double>)
    -> (nearest: Double, farthest: Double) {
        let lo = minimum, hi = maximum
        var nearSquared = 0.0
        for axis in 0..<3 {
            let outside = Swift.max(lo[axis] - point[axis],
                                    point[axis] - hi[axis], 0)
            nearSquared += outside * outside
        }
        let farthest = corners.reduce(0.0) {
            Swift.max($0, simd_distance($1, point))
        }
        return (nearSquared.squareRoot(), farthest)
    }
}
