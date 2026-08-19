//
//  RoomBox.swift
//  PhysicsCore — Math: axis-aligned box standing in for the user's room;
//  clips rays/segments/polylines so traced curves stop at the walls. Pure geometry.
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

    /// Fallback when nothing has been scanned; floor at y = 0.
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

    /// The same box expressed in a frame shifted by `delta`.
    public func translated(by delta: SIMD3<Double>) -> RoomBox {
        RoomBox(center: center + delta, halfExtents: halfExtents)
    }

    /// Insets every side; never collapses below 1 mm so clipping stays defined.
    public func inset(by amount: Double) -> RoomBox {
        RoomBox(center: center,
                halfExtents: simd_max(halfExtents - SIMD3(repeating: amount),
                                      SIMD3(repeating: 0.001)))
    }

    // MARK: Ray / segment clipping

    /// Slab method: t-interval of `origin + t·direction` inside the box, or nil on a miss.
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

    /// Exit point of a→b on the boundary (`a` assumed inside/on); nil if none.
    public func exitPoint(from a: SIMD3<Double>, towards b: SIMD3<Double>) -> SIMD3<Double>? {
        let direction = b - a
        let length = simd_length(direction)
        guard length > 1e-12 else { return nil }
        guard let interval = rayInterval(origin: a, direction: direction / length) else { return nil }
        let t = interval.exit
        guard t >= 0, t <= length else { return nil }
        return a + (direction / length) * t
    }

    /// A point at `reach` along a ray, clamped to the box's [enter, exit]; nil on a miss.
    public func point(onRay origin: SIMD3<Double>,
                      direction: SIMD3<Double>,
                      reach: Double) -> SIMD3<Double>? {
        let length = simd_length(direction)
        guard length > 1e-12 else { return nil }
        let unit = direction / length
        guard let interval = rayInterval(origin: origin, direction: unit) else { return nil }
        let enter = max(interval.enter, 0)
        guard interval.exit > enter else { return nil }
        let t = min(max(reach, enter), interval.exit)
        return origin + unit * t
    }

    // MARK: Polyline clipping

    /// Clips a polyline to the box. A line that leaves and re-enters returns
    /// as SEPARATE runs, never joined; crossings land exactly on the wall.
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
                if let crossing = exitPoint(from: b, towards: a) {
                    current = [crossing, b]
                } else {
                    current = [b]
                }
            } else {
                // Both ends outside: the segment may still cut a corner — keep that piece.
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

    /// Clips every polyline in a set, flattening the runs.
    public func clip(polylines: [[SIMD3<Double>]]) -> [[SIMD3<Double>]] {
        polylines.flatMap { clip(polyline: $0) }
    }

    // MARK: Building one from scanned planes

    /// Tightest box containing the detected plane centres, never smaller
    /// than `minimumHalfExtents` (a one-wall scan must not squash the room).
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
