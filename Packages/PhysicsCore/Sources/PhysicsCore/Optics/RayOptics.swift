//
//  RayOptics.swift
//  PhysicsCore — Optics
//
//  Geometric optics for the ray bench: Snell refraction and mirror
//  reflection in vector form, the thin-lens equation, and a segment
//  tracer that carries rays through lenses, mirrors, and screens on an
//  optical axis. Lenses use the exact paraxial transfer (slope' =
//  slope − y/f), so images form where the traced rays actually cross —
//  the thin-lens equation is verified by the trace, not assumed.
//
//  SI units, no RealityKit.
//

import Foundation
import simd

public enum RayOptics {
    // MARK: Vector laws

    /// Mirror reflection: d − 2(d·n)n.
    public static func reflect(_ direction: SIMD3<Double>, normal: SIMD3<Double>) -> SIMD3<Double> {
        direction - 2 * simd_dot(direction, normal) * normal
    }

    /// Snell refraction from index n1 into n2; nil on total internal
    /// reflection. `normal` points back toward the incoming side.
    public static func refract(_ direction: SIMD3<Double>, normal: SIMD3<Double>,
                               n1: Double, n2: Double) -> SIMD3<Double>? {
        let ratio = n1 / n2
        let cosIncident = -simd_dot(direction, normal)
        let sinTransmittedSquared = ratio * ratio * (1 - cosIncident * cosIncident)
        guard sinTransmittedSquared <= 1 else { return nil }
        let cosTransmitted = (1 - sinTransmittedSquared).squareRoot()
        return ratio * direction + (ratio * cosIncident - cosTransmitted) * normal
    }

    /// The critical angle for total internal reflection (n1 > n2), rad.
    public static func criticalAngle(n1: Double, n2: Double) -> Double? {
        guard n1 > n2 else { return nil }
        return asin(n2 / n1)
    }

    /// Thin lens: 1/f = 1/dₒ + 1/dᵢ → image distance (negative = virtual).
    public static func imageDistance(objectDistance: Double, focalLength: Double) -> Double {
        let inverse = 1 / focalLength - 1 / objectDistance
        return 1 / inverse
    }

    public static func magnification(objectDistance: Double, imageDistance: Double) -> Double {
        -imageDistance / objectDistance
    }

    // MARK: Bench elements & the segment tracer

    public enum BenchElement: Sendable, Equatable {
        /// Thin lens at `x` with signed focal length (+ converging).
        case lens(x: Double, focalLength: Double)
        /// Flat mirror at `x`, perpendicular to the axis.
        case mirror(x: Double)
        /// Absorbing screen at `x`.
        case screen(x: Double)

        public var x: Double {
            switch self {
            case .lens(let x, _), .mirror(let x), .screen(let x): x
            }
        }
    }

    /// A ray in the bench plane: height y above the axis, and slope
    /// dy/dx measured along its travel direction (±x).
    public struct BenchRay: Sendable, Equatable {
        public var x: Double
        public var y: Double
        public var slope: Double
        /// +1 rightward, −1 leftward.
        public var direction: Double

        public init(x: Double, y: Double, slope: Double, direction: Double = 1) {
            self.x = x
            self.y = y
            self.slope = slope
            self.direction = direction
        }
    }

    /// Traces one ray through the elements, returning the polyline of
    /// (x, y) points it visits. Ends at a screen, after `maxBounces`
    /// interactions, or at the bench bounds.
    public static func trace(
        _ start: BenchRay, elements: [BenchElement],
        bounds: ClosedRange<Double>, maxBounces: Int = 8
    ) -> [SIMD2<Double>] {
        var ray = start
        var points: [SIMD2<Double>] = [SIMD2(ray.x, ray.y)]

        for _ in 0..<maxBounces {
            // The nearest element ahead in the travel direction.
            let ahead = elements
                .filter { ray.direction > 0 ? $0.x > ray.x + 1e-9 : $0.x < ray.x - 1e-9 }
                .min { abs($0.x - ray.x) < abs($1.x - ray.x) }

            guard let element = ahead else {
                // Run out to the bench edge.
                let edge = ray.direction > 0 ? bounds.upperBound : bounds.lowerBound
                let run = abs(edge - ray.x)
                points.append(SIMD2(edge, ray.y + ray.slope * run))
                return points
            }

            let run = abs(element.x - ray.x)
            ray.y += ray.slope * run
            ray.x = element.x
            points.append(SIMD2(ray.x, ray.y))

            switch element {
            case .lens(_, let focalLength):
                // Exact paraxial transfer: height unchanged, slope bends
                // toward (or away from) the axis by y/f.
                ray.slope -= ray.y / focalLength
            case .mirror:
                ray.direction = -ray.direction
            case .screen:
                return points
            }
        }
        return points
    }

    /// Where two traced rays from the same object point cross (the
    /// image), if they do: returns the crossing x, or nil for parallel
    /// exit rays (image at infinity).
    public static func crossing(of a: BenchRay, and b: BenchRay) -> Double? {
        let slopeDifference = a.slope - b.slope
        guard abs(slopeDifference) > 1e-12 else { return nil }
        return a.x + (b.y - a.y + b.slope * (a.x - b.x)) / slopeDifference
    }
}
