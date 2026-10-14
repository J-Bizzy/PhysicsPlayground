//
//  StackLayout.swift
//  RenderKit
//
//  A vertical column of switches, as pure arithmetic: one layers bank
//  per module, for several independent on/off states that must also be
//  readable at a glance. A column rather than an arc, because a standing
//  instrument on an arc reads as debris.
//

import Foundation
import simd

/// A column of `count` switches hanging below an anchor.
public struct StackLayout: Sendable {
    /// Centre-to-centre spacing, metres.
    public var pitch: Double
    /// Where the first switch sits relative to the anchor. Positive lifts
    /// the whole column so a bank can hang beside an apparatus rather
    /// than under it.
    public var lift: Double
    /// How far the column slides in from as it appears.
    public var slide: Double

    public init(pitch: Double = 0.066, lift: Double = 0, slide: Double = 0.05) {
        self.pitch = pitch
        self.lift = lift
        self.slide = slide
    }

    public struct Placement: Sendable, Equatable {
        /// Offset from the anchor, in the bank's own frame.
        public var offset: SIMD3<Double>
        public var scale: Double
        public var isVisible: Bool
    }

    /// Where switch `index` of `count` sits at a given reveal progress. The
    /// column is centred vertically on the anchor, so a bank of three and a
    /// bank of seven hang off the same point.
    public func placement(index: Int, count: Int, reveal: Double) -> Placement {
        let progress = min(max(reveal, 0), 1)
        let centred = Double(index) - Double(max(count, 1) - 1) / 2
        let offset = SIMD3(0,
                           lift - centred * pitch,
                           slide * (1 - progress))
        return Placement(offset: offset,
                         scale: max(progress, 0.001),
                         isVisible: progress > 0.02)
    }

    /// Total height the column occupies — what a caller needs to know to
    /// place it clear of anything else.
    public func height(count: Int) -> Double {
        Double(max(count, 1) - 1) * pitch
    }
}
