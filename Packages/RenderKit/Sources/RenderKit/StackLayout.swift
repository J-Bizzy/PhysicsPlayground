//
//  StackLayout.swift
//  RenderKit
//
//  A vertical column of switches, as pure arithmetic.
//
//  The third control shape the app needs, and the one the 35 display
//  toggles resolve into: one **layers bank** per module (owner's call,
//  2026-07-29). A fan is for choosing ONE of many and folding away; a
//  dial is for a continuous quantity; a bank is for several independent
//  on/off states that must also be READABLE at a glance — which layer is
//  showing is itself information, so the bank never folds.
//
//  A column rather than an arc, deliberately. `FanLayout`'s spray is
//  right for a momentary menu and wrong for a standing instrument — a
//  screenshot of Gravity Lab's clock on a 150° arc showed four discs at
//  four different heights reading as debris rather than one object. With
//  three to seven switches a column is unambiguous: one thing, stacked,
//  the way a real panel of breakers is.
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

    /// Where switch `index` of `count` sits at a given reveal progress.
    ///
    /// The column is centred vertically on the anchor, so a bank of three
    /// and a bank of seven both hang off the same point without the
    /// caller compensating — otherwise every module would need its own
    /// fudge to keep the bank beside the apparatus instead of drifting
    /// down as switches were added.
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
