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

    /// The closest any two ADJACENT items come, centre to centre, at
    /// full openness. Below the width of an item's touch target, the two
    /// cannot be aimed at separately however clearly they read.
    ///
    /// Adjacent is the only pair worth measuring: the fan is convex, so
    /// nothing further apart in index is closer in space.
    public func minimumAdjacentSpacing(count: Int) -> Double {
        guard count > 1 else { return .infinity }
        let offsets = (0..<count).map {
            placement(index: $0, count: count, openness: 1).offset
        }
        return zip(offsets, offsets.dropFirst())
            .map { simd_distance($0, $1) }
            .min() ?? .infinity
    }

    /// The narrowest fan that keeps `count` items whose touch targets are
    /// `itemSpan` metres across from overlapping.
    ///
    /// WHY THIS EXISTS RATHER THAN A HAND-TYPED SPAN. Gravity Lab's clock
    /// bank was tuned by eye and by screenshot for FOUR discs — "four
    /// discs at ±75° and ±25°", says the comment that is still there —
    /// and then the time scales grew to six on 2026-08-07. The layout
    /// did not, because a hand-typed span has no idea how many things
    /// are being laid out. End-pair centres landed 0.0494 m apart
    /// against a 0.068 m target: aim at 1×, hit −1×, and the solar
    /// system runs backwards.
    ///
    /// A span derived FROM the count cannot drift out of step with it.
    /// Add a seventh scale and the bank widens; take one away and it
    /// tightens. The one thing it will not do is silently overlap.
    ///
    /// Widening the arc is tried first, up to `maxSpan`, because that
    /// keeps the fan the same distance from the hand. Past that there is
    /// nowhere left to go but outward, so `reach` grows instead — six
    /// targets 68 mm across simply do not fit in a 25 cm row, and no
    /// choice of angle makes them.
    public static func spread(count: Int,
                              itemSpan: Double,
                              reach: Double,
                              verticalScale: Double = 0.8,
                              lift: Double = 0.06,
                              stagger: Double = 0.045,
                              clearance: Double = 0.1,
                              maxSpan: Double = 150 * .pi / 180) -> FanLayout {
        func layout(span: Double, reach: Double) -> FanLayout {
            FanLayout(span: span, reach: reach, verticalScale: verticalScale,
                      lift: lift, stagger: stagger)
        }
        guard count > 1, itemSpan > 0 else {
            return layout(span: maxSpan, reach: reach)
        }
        let required = itemSpan * (1 + clearance)

        // Spacing grows with span over the range a fan can legally
        // occupy, so bisection settles on the narrowest one that fits.
        var low = 0.0, high = maxSpan
        if layout(span: high, reach: reach).minimumAdjacentSpacing(count: count) < required {
            // Even the widest legal arc is too tight — push it outward
            // by exactly the shortfall.
            let widest = layout(span: high, reach: reach)
            let spacing = widest.minimumAdjacentSpacing(count: count)
            guard spacing > 0 else { return widest }
            return layout(span: high, reach: reach * required / spacing)
        }
        for _ in 0..<40 {
            let mid = (low + high) / 2
            if layout(span: mid, reach: reach).minimumAdjacentSpacing(count: count) < required {
                low = mid
            } else {
                high = mid
            }
        }
        return layout(span: high, reach: reach)
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
