//
//  StationBox.swift
//  PhysicsCore — Math
//
//  The volume one apparatus is allowed to occupy, and the questions a
//  multi-station module has to ask about it.
//
//  A world that stands several apparatus in one room has exactly one
//  class of silent failure: two things authored to own the space in
//  front of the user quietly sharing it. A magnet clamped to a box that
//  reaches into the circuit bench does not crash — it drifts through a
//  battery. So each station declares a box, and the layouts assert
//  against these functions rather than eyeballing coordinates.
//
//  Two different invariants are needed, because two different kinds of
//  station exist. Benches standing side by side must be DISJOINT. An
//  apparatus larger than the room — an orrery fifteen metres across —
//  cannot be disjoint from anything, so the benches inside it are
//  checked for CONTAINMENT in the empty shell between its orbits
//  instead. `separation` answers the first; `distanceRange` answers the
//  second.
//
//  Pure geometry, deliberately: it lives here so the layout tests run
//  in `swift test` in three seconds rather than booting a simulator.
//

import Foundation
import simd

/// An axis-aligned volume belonging to one apparatus, in world
/// coordinates.
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

    /// The eight corners — what you iterate when the question is about
    /// the box's extremes rather than its faces.
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

    /// The widest gap between the two boxes on any single axis, negative
    /// when they overlap on every axis.
    ///
    /// These are axis-aligned, so clearance on ONE axis is enough to
    /// prove no overlap — which is why this is a max over axes and not a
    /// distance. Returning the number rather than a Bool lets a failing
    /// test say how far short it fell.
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

    /// Whether `other` sits wholly inside this box — the shape of every
    /// "does the clamp escape its station?" assertion.
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

    /// How near and how far this box reaches from `point`.
    ///
    /// The near end is the standard point-to-AABB distance (zero when
    /// the point is inside); the far end is the most distant corner.
    /// Both ends are needed to place a bench inside an annulus: near
    /// must clear the inner orbit, far must stay within the outer one.
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
