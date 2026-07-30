//
//  FanLayout.swift
//  RenderKit
//
//  Where the petals of an unfolding fan sit, as pure arithmetic.
//
//  The Wind Tunnel's shape picker established the grammar the app now
//  uses for every N-way choice — pinch a petal, a fan of labelled discs
//  unfolds in the room, pick one, it folds — and it replaced a blind
//  "next shape" cycle button that walked the user through a flat disc and
//  a spinning cylinder with no warning of either. It read as the model
//  glitching rather than as a choice being offered.
//
//  That fan's geometry was welded into the Wind Tunnel. Split out here it
//  becomes testable and reusable: `SpatialPicker` builds the entities and
//  asks this where to put them. The interaction law (DECISIONS.md,
//  2026-07-29) makes the fan the app's ONLY picker, so its layout is worth
//  pinning — a fan that overlaps itself or opens through the floor is the
//  kind of thing that only shows up on device, late.
//

import Foundation
import simd

/// A fan of `count` items opening upward, staggered so they arrive in
/// sequence rather than all at once.
public struct FanLayout: Sendable {
    /// Total angular spread, radians. 150° matches the palette bead's ring.
    public var span: Double
    /// How far from the anchor a fully-open item sits, metres.
    public var reach: Double
    /// Vertical squash — the fan is wider than it is tall, so it clears
    /// the apparatus it hangs over instead of stacking on top of it.
    public var verticalScale: Double
    /// Lift, so the nearest item doesn't intersect what it decorates.
    public var lift: Double
    /// How much later each successive item begins to appear, in units of
    /// overall openness.
    public var stagger: Double

    public init(span: Double = 150 * .pi / 180,
                reach: Double = 0.27,
                verticalScale: Double = 0.8,
                lift: Double = 0.06,
                stagger: Double = 0.045) {
        self.span = span
        self.reach = reach
        self.verticalScale = verticalScale
        self.lift = lift
        self.stagger = stagger
    }

    /// One item's placement at a given overall openness.
    public struct Placement: Sendable, Equatable {
        /// Offset from the fan's anchor, in the fan's own frame: +x right,
        /// +y up, z always 0 (the fan is a plane that faces the viewer).
        public var offset: SIMD3<Double>
        /// Uniform scale, including the small overshoot that makes an item
        /// arrive rather than merely grow.
        public var scale: Double
        /// This item's own progress, 0…1 — its share of overall openness
        /// once its stagger delay is taken off.
        public var progress: Double
        /// Whether it is far enough along to be worth drawing at all.
        public var isVisible: Bool
    }

    /// Where item `index` of `count` sits when the fan is `openness` open.
    ///
    /// `openness` is the whole fan's 0…1 progress; each item subtracts its
    /// stagger from that and renormalises, so item 0 leads and the last
    /// arrives last. A single item sits dead centre rather than at one end
    /// of the span — an N-of-1 fan is still a legal fan.
    public func placement(index: Int, count: Int, openness: Double) -> Placement {
        let clampedOpenness = min(max(openness, 0), 1)
        let delay = Double(index) * stagger
        let progress = min(max((clampedOpenness - delay) / max(1 - delay, 0.01), 0), 1)

        // With one item there is no spread to divide, so it goes to the
        // middle. Dividing by count−1 = 0 would be a NaN through every
        // transform downstream.
        let angle: Double
        if count <= 1 {
            angle = 0
        } else {
            angle = -span / 2 + span * Double(index) / Double(count - 1)
        }

        let extended = reach * progress
        let offset = SIMD3(sin(angle) * extended,
                           cos(angle) * extended * verticalScale + lift,
                           0)
        // A touch of overshoot at the midpoint of the arrival, easing back
        // to exactly 1 — the item lands rather than inflating.
        let pop = 1 + 0.14 * sin(progress * .pi)
        return Placement(offset: offset,
                         scale: max(progress, 0.001) * pop,
                         progress: progress,
                         isVisible: progress > 0.02)
    }

    /// Eases overall openness toward its target, frame-rate independent.
    /// Snaps when close enough so a fan never sits fractionally open.
    public static func ease(_ openness: Double, toward target: Double,
                           dt: Double, rate: Double = 9) -> Double {
        var next = openness + (target - openness) * min(dt * rate, 1)
        if abs(next - target) < 0.004 { next = target }
        return min(max(next, 0), 1)
    }
}
