//
//  FanLayout.swift
//  RenderKit
//
//  Pure arithmetic for where an unfolding picker fan's petals sit — the
//  app's only picker shape, split out to be testable.
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

    /// Where item `index` of `count` sits at fan `openness` 0…1; each item
    /// subtracts its stagger and renormalises. A single item sits dead centre.
    public func placement(index: Int, count: Int, openness: Double) -> Placement {
        let clampedOpenness = min(max(openness, 0), 1)
        let delay = Double(index) * stagger
        let progress = min(max((clampedOpenness - delay) / max(1 - delay, 0.01), 0), 1)

        // One item goes to the middle; count−1 = 0 would be NaN downstream.
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
        // Slight overshoot easing back to exactly 1 — the item lands.
        let pop = 1 + 0.14 * sin(progress * .pi)
        return Placement(offset: offset,
                         scale: max(progress, 0.001) * pop,
                         progress: progress,
                         isVisible: progress > 0.02)
    }

    /// Closest adjacent centre-to-centre spacing at full openness — the
    /// fan is convex, so no farther-apart pair is closer in space.
    public func minimumAdjacentSpacing(count: Int) -> Double {
        guard count > 1 else { return .infinity }
        let offsets = (0..<count).map {
            placement(index: $0, count: count, openness: 1).offset
        }
        return zip(offsets, offsets.dropFirst())
            .map { simd_distance($0, $1) }
            .min() ?? .infinity
    }

    /// The narrowest fan keeping `count` items of `itemSpan` metres from
    /// overlapping — derived from the count so a grown bank cannot silently
    /// overlap. Widens the arc first (keeps the fan the same distance from
    /// the hand), then grows `reach` when even `maxSpan` cannot fit.
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

        // Spacing grows with span, so bisection finds the narrowest fit.
        var low = 0.0, high = maxSpan
        if layout(span: high, reach: reach).minimumAdjacentSpacing(count: count) < required {
            // Widest legal arc still too tight — push reach out by the shortfall.
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

}
