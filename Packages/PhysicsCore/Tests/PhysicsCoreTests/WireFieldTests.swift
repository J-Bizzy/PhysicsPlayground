//
//  WireFieldTests.swift
//  PhysicsCoreTests
//
//  The straight-segment field, checked against the two closed forms
//  every physics student already knows — because a Biot–Savart
//  implementation that is merely self-consistent is worth nothing. Both
//  limits below are analytic results this code does not share any
//  arithmetic with.
//

import XCTest
import simd
@testable import PhysicsCore

final class WireFieldTests: XCTestCase {

    /// A long segment must reproduce the infinite wire, μ₀I/2πd.
    ///
    /// This is the headline check. At 2000 m of wire and 5 cm of standoff
    /// the finite correction is of order (d/L)², i.e. ~10⁻⁹, so agreement
    /// to a part in a million is a real test of the formula rather than a
    /// loose one.
    func testALongSegmentRecoversTheInfiniteWireLaw() {
        let current = 3.0
        let d = 0.05
        let half = 1000.0
        let field = WireField.field(
            at: SIMD3(d, 0, 0),
            from: SIMD3(0, -half, 0), to: SIMD3(0, half, 0),
            current: current)

        let expected = WireField.infiniteWireMagnitude(current: current, distance: d)
        XCTAssertEqual(simd_length(field), expected, accuracy: expected * 1e-6,
                       "a 2 km segment is not behaving like an infinite wire")
    }

    /// Half of that wire gives exactly half the field — the cleanest
    /// consequence of the cos θ₁ − cos θ₂ form, since one end contributes
    /// cos 0 = 1 and the perpendicular foot contributes cos 90° = 0.
    func testAHalfInfiniteWireGivesHalfTheField() {
        let current = 3.0
        let d = 0.05
        let full = WireField.infiniteWireMagnitude(current: current, distance: d)
        let field = WireField.field(
            at: SIMD3(d, 0, 0),
            from: SIMD3(0, 0, 0), to: SIMD3(0, 1000, 0),
            current: current)
        XCTAssertEqual(simd_length(field), full / 2, accuracy: full * 1e-6)
    }

    /// Direction: right-hand rule. Current up +y, field point out on +x,
    /// so B must point along +z (Î × r̂ = ŷ × x̂ = −ẑ … which is exactly
    /// the sign this test exists to pin rather than to assume).
    func testTheFieldCirclesTheWireByTheRightHandRule() {
        let field = WireField.field(
            at: SIMD3(0.05, 0, 0),
            from: SIMD3(0, -1, 0), to: SIMD3(0, 1, 0),
            current: 1)
        // Perpendicular to both the wire and the standoff.
        XCTAssertEqual(field.x, 0, accuracy: 1e-15)
        XCTAssertEqual(field.y, 0, accuracy: 1e-15)
        XCTAssertEqual(field.z, -simd_length(field), accuracy: 1e-15,
                       "B should circle the wire; ŷ × x̂ = −ẑ")

        // Reversing the current reverses the field, exactly.
        let reversed = WireField.field(
            at: SIMD3(0.05, 0, 0),
            from: SIMD3(0, -1, 0), to: SIMD3(0, 1, 0),
            current: -1)
        XCTAssertEqual(reversed.z, -field.z, accuracy: 1e-18)
    }

    /// Field falls as 1/d.
    func testTheFieldFallsAsOneOverDistance() {
        func magnitude(at d: Double) -> Double {
            simd_length(WireField.field(at: SIMD3(d, 0, 0),
                                        from: SIMD3(0, -500, 0),
                                        to: SIMD3(0, 500, 0),
                                        current: 2))
        }
        let near = magnitude(at: 0.04)
        let far = magnitude(at: 0.08)
        XCTAssertEqual(near / far, 2, accuracy: 1e-5,
                       "doubling the distance should halve the field")
    }

    /// A many-sided polygon of segments approaches the circular loop's
    /// centre field, μ₀I/2R. This is the check that superposition and the
    /// direction convention agree with each other around a closed path —
    /// a sign error in `field` that survived the single-wire tests would
    /// show up here as cancellation.
    func testAPolygonApproachesTheCircularLoopCentreField() {
        let radius = 0.05
        let current = 4.0
        let sides = 720
        var segments: [WireField.Segment] = []
        for i in 0..<sides {
            let t0 = 2 * Double.pi * Double(i) / Double(sides)
            let t1 = 2 * Double.pi * Double(i + 1) / Double(sides)
            segments.append(.init(
                a: SIMD3(radius * cos(t0), 0, radius * sin(t0)),
                b: SIMD3(radius * cos(t1), 0, radius * sin(t1)),
                current: current))
        }
        let centre = WireField.field(at: .zero, segments: segments)
        let expected = WireField.mu0 * current / (2 * radius)
        XCTAssertEqual(simd_length(centre), expected, accuracy: expected * 1e-4,
                       "a 720-gon should be a circle to a part in 10⁴")
        // …and it points along the loop's axis, not somewhere in its plane.
        XCTAssertEqual(abs(centre.y), simd_length(centre), accuracy: expected * 1e-6)
    }

    /// The same current, expressed as one segment or as two collinear
    /// halves, is the same field. Superposition has to survive being
    /// chopped up, because a renderer will chop wires wherever the
    /// geometry happens to have vertices.
    func testSplittingASegmentDoesNotChangeItsField() {
        let point = SIMD3(0.03, 0.01, 0.02)
        let whole = WireField.field(at: point,
                                    from: SIMD3(0, -0.2, 0), to: SIMD3(0, 0.2, 0),
                                    current: 1.5)
        let halves = WireField.field(at: point, segments: [
            .init(a: SIMD3(0, -0.2, 0), b: SIMD3(0, 0.05, 0), current: 1.5),
            .init(a: SIMD3(0, 0.05, 0), b: SIMD3(0, 0.2, 0), current: 1.5),
        ])
        XCTAssertEqual(simd_length(whole - halves), 0,
                       accuracy: simd_length(whole) * 1e-12)
    }

    // MARK: The guards

    /// On the axis the exact solution diverges, and a renderer WILL sample
    /// there. Zero is the deliberate answer; a NaN would ride a transform
    /// into the scene graph and freeze it.
    func testAPointOnTheWireReturnsZeroRatherThanNaN() {
        let onAxis = WireField.field(at: SIMD3(0, 0.5, 0),
                                     from: SIMD3(0, -1, 0), to: SIMD3(0, 1, 0),
                                     current: 10)
        XCTAssertEqual(onAxis, .zero)
        XCTAssertFalse(onAxis.x.isNaN || onAxis.y.isNaN || onAxis.z.isNaN)

        // Also beyond the ends, still on the line.
        let offEnd = WireField.field(at: SIMD3(0, 5, 0),
                                     from: SIMD3(0, -1, 0), to: SIMD3(0, 1, 0),
                                     current: 10)
        XCTAssertEqual(offEnd, .zero)
    }

    func testDegenerateAndDeadSegmentsContributeNothing() {
        XCTAssertEqual(WireField.field(at: SIMD3(1, 1, 1),
                                       from: .zero, to: .zero, current: 5), .zero)
        XCTAssertEqual(WireField.field(at: SIMD3(1, 1, 1),
                                       from: .zero, to: SIMD3(0, 1, 0),
                                       current: 0), .zero)
        XCTAssertEqual(WireField.field(at: SIMD3(1, 1, 1), segments: []), .zero)
    }
}
