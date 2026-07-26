//
//  RoomBox.swift
//  PhysicsCore — Math
//
//  An axis-aligned box standing in for the user's room, and the
//  clipping the renderers need so a field line, a ray, or a predicted
//  trajectory STOPS at the walls instead of driving out through them
//  and off to infinity.
//
//  This is pure geometry — no RealityKit, no ARKit. The app fills the
//  box in from detected planes (or a sane default when nothing has been
//  scanned), and every module clips its polylines through here, so
//  "virtual light stops at the real wall" is one tested function rather
//  than eleven ad-hoc guesses.
//

import Foundation
import simd

/// An axis-aligned room volume in immersive-space (world) coordinates.
public struct RoomBox: Equatable, Sendable {
    public var center: SIMD3<Double>
    public var halfExtents: SIMD3<Double>

    public init(center: SIMD3<Double>, halfExtents: SIMD3<Double>) {
        self.center = center
        self.halfExtents = SIMD3(abs(halfExtents.x), abs(halfExtents.y), abs(halfExtents.z))
    }

    /// The fallback when nothing has been scanned: a generous room the
    /// user is standing in the middle of, floor at y = 0.
    public static let unscanned = RoomBox(
        center: SIMD3(0, 1.35, -0.4),
        halfExtents: SIMD3(1.9, 1.35, 1.9))

    public var minimum: SIMD3<Double> { center - halfExtents }
    public var maximum: SIMD3<Double> { center + halfExtents }
    public var floorHeight: Double { center.y - halfExtents.y }

    public func contains(_ point: SIMD3<Double>) -> Bool {
        let low = minimum, high = maximum
        return point.x >= low.x && point.x <= high.x
            && point.y >= low.y && point.y <= high.y
            && point.z >= low.z && point.z <= high.z
    }

    /// Shrinks (or grows, with a negative inset) the box on every side.
    /// Never collapses past a millimetre so clipping stays well-defined.
    public func inset(by amount: Double) -> RoomBox {
        RoomBox(center: center,
                halfExtents: simd_max(halfExtents - SIMD3(repeating: amount),
                                      SIMD3(repeating: 0.001)))
    }

    // MARK: Ray / segment clipping

    /// The slab method: the parametric interval of `origin + t·direction`
    /// (t ≥ 0 unbounded) that lies inside the box, or nil if the ray
    /// misses it entirely.
    public func rayInterval(origin: SIMD3<Double>,
                            direction: SIMD3<Double>) -> (enter: Double, exit: Double)? {
        var enter = -Double.infinity
        var exit = Double.infinity
        let low = minimum, high = maximum
        for axis in 0..<3 {
            let d = direction[axis]
            if abs(d) < 1e-12 {
                // Parallel to this slab: inside it, or nothing to clip.
                if origin[axis] < low[axis] || origin[axis] > high[axis] { return nil }
                continue
            }
            var near = (low[axis] - origin[axis]) / d
            var far = (high[axis] - origin[axis]) / d
            if near > far { swap(&near, &far) }
            enter = max(enter, near)
            exit = min(exit, far)
            if enter > exit { return nil }
        }
        return (enter, exit)
    }

    /// Where a segment leaves the box, if it does. `a` is assumed inside
    /// (or on) the box; returns the exit point on the boundary.
    public func exitPoint(from a: SIMD3<Double>, towards b: SIMD3<Double>) -> SIMD3<Double>? {
        let direction = b - a
        let length = simd_length(direction)
        guard length > 1e-12 else { return nil }
        guard let interval = rayInterval(origin: a, direction: direction / length) else { return nil }
        let t = interval.exit
        guard t >= 0, t <= length else { return nil }
        return a + (direction / length) * t
    }

    // MARK: Polyline clipping

    /// Clips a polyline to the box, returning the pieces that lie inside.
    /// A line that wanders out and back in comes back as two runs, so a
    /// field line threading past a doorway doesn't get silently joined
    /// across the gap. Boundary crossings land exactly on the wall.
    public func clip(polyline: [SIMD3<Double>]) -> [[SIMD3<Double>]] {
        guard polyline.count >= 2 else {
            return polyline.count == 1 && contains(polyline[0]) ? [polyline] : []
        }
        var runs: [[SIMD3<Double>]] = []
        var current: [SIMD3<Double>] = []

        for index in 0..<(polyline.count - 1) {
            let a = polyline[index]
            let b = polyline[index + 1]
            let aIn = contains(a)
            let bIn = contains(b)

            if aIn && bIn {
                if current.isEmpty { current.append(a) }
                current.append(b)
            } else if aIn && !bIn {
                if current.isEmpty { current.append(a) }
                if let crossing = exitPoint(from: a, towards: b) { current.append(crossing) }
                if current.count >= 2 { runs.append(current) }
                current = []
            } else if !aIn && bIn {
                // Enter: the crossing found looking back from b.
                if let crossing = exitPoint(from: b, towards: a) {
                    current = [crossing, b]
                } else {
                    current = [b]
                }
            } else {
                // Both outside: the segment may still cut a corner of the
                // box. Keep that piece rather than dropping the whole span.
                let direction = b - a
                let length = simd_length(direction)
                if length > 1e-12,
                   let interval = rayInterval(origin: a, direction: direction / length) {
                    let enter = max(interval.enter, 0)
                    let exit = min(interval.exit, length)
                    if exit - enter > 1e-9 {
                        let unit = direction / length
                        runs.append([a + unit * enter, a + unit * exit])
                    }
                }
                if current.count >= 2 { runs.append(current) }
                current = []
            }
        }
        if current.count >= 2 { runs.append(current) }
        return runs
    }

    /// Clips every polyline in a set, flattening the runs. The common
    /// call for a renderer holding a bundle of field lines or rays.
    public func clip(polylines: [[SIMD3<Double>]]) -> [[SIMD3<Double>]] {
        polylines.flatMap { clip(polyline: $0) }
    }

    // MARK: Building one from scanned planes

    /// Estimates the room from detected plane centres: the tightest box
    /// containing them all, floored at the lowest horizontal plane and
    /// never smaller than `minimumHalfExtents` (a scan that only caught
    /// one wall must not squash the room to a sliver).
    public static func enclosing(points: [SIMD3<Double>],
                                 minimumHalfExtents: SIMD3<Double> = SIMD3(1.2, 1.0, 1.2),
                                 fallback: RoomBox = .unscanned) -> RoomBox {
        guard let first = points.first else { return fallback }
        var low = first, high = first
        for point in points.dropFirst() {
            low = simd_min(low, point)
            high = simd_max(high, point)
        }
        let center = (low + high) / 2
        let half = simd_max((high - low) / 2, minimumHalfExtents)
        return RoomBox(center: center, halfExtents: half)
    }
}
