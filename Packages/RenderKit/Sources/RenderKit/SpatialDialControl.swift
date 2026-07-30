//
//  SpatialDialControl.swift
//  RenderKit
//
//  A `SpatialDial` bound to a number, and the drag lifecycle that turns
//  it. This is the instrument that replaces a slider.
//
//  `SpatialDial` has been in this package, complete and unused, since it
//  was built for the Optics bench that got cut. What it never had was
//  glue: nothing carried a value, mapped a hand's angle onto it, or drove
//  the needle from a model. So every module reached for a `Slider`
//  instead, eight times, and the app ended up with 19 of them.
//
//  The interaction law (DECISIONS.md, 2026-07-29) asks for an instrument
//  that is "visible without being looked for, operable without being
//  discovered, and reachable in the simulator" — the bar a slider clears
//  and a gaze-revealed control does not. A dial standing on the apparatus
//  clears it too: it is always there, it looks like a thing you turn, and
//  a mouse drag in the simulator turns it.
//
//  The value lives in the MODEL, as everything in this app does. This
//  object holds no state between gestures except the in-flight twist —
//  `refresh()` reads the model every frame, so a value changed anywhere
//  else moves the needle.
//

import Foundation
import RealityKit
import SwiftUI
import simd

@MainActor
public final class SpatialDialControl {
    public let dial: SpatialDial
    public var root: Entity { dial.root }
    public var name: String { dial.name }

    private let range: ClosedRange<Double>
    private let read: () -> Double
    private let write: (Double) -> Void
    private let format: (Double) -> String
    private let turnsForFullSweep: Double
    private var twist: DialDrag?

    /// - normal: the dial's face direction — the axis you twist about,
    ///   pointing back at the reader.
    /// - center: position within the entity this dial gets added to.
    /// - turnsForFullSweep: how much of a full turn covers the whole
    ///   range. 0.75 is gauge-like and the default; a coarse control can
    ///   afford less, a precise one wants more.
    public init(name: String,
                center: SIMD3<Float>,
                normal: SIMD3<Float>,
                radius: Float = 0.05,
                accent: UIColor,
                range: ClosedRange<Double>,
                turnsForFullSweep: Double = 0.75,
                read: @escaping () -> Double,
                write: @escaping (Double) -> Void,
                format: @escaping (Double) -> String) {
        self.dial = SpatialDial(name: name, center: center, normal: normal,
                                radius: radius, accent: accent)
        self.range = range
        self.read = read
        self.write = write
        self.format = format
        self.turnsForFullSweep = turnsForFullSweep
        refresh()
    }

    /// Whether `entity` is this dial — walk-up included, so a tap landing
    /// on the needle or a tick still counts as the dial.
    public func owns(_ entity: Entity) -> Bool {
        var current: Entity? = entity
        while let candidate = current {
            if candidate === dial.root { return true }
            current = candidate.parent
        }
        return false
    }

    public var isTwisting: Bool { twist != nil }

    /// Starts a twist. `hand` is in the dial's parent space — see
    /// `SpatialDial.handAngle(inParentSpace:)` for why that matters.
    public func beginTwist(hand: SIMD3<Double>) {
        twist = DialDrag(name: dial.name,
                         startValue: read(),
                         startAngle: dial.handAngle(inParentSpace: hand),
                         range: range,
                         turnsForFullSweep: turnsForFullSweep)
    }

    /// Feeds the hand's new position. Returns false when no twist is in
    /// flight, so a caller can fall through to its other drag handling.
    @discardableResult
    public func updateTwist(hand: SIMD3<Double>) -> Bool {
        guard var twist else { return false }
        let value = twist.advance(toAngle: dial.handAngle(inParentSpace: hand))
        self.twist = twist
        write(value)
        refresh()
        return true
    }

    public func endTwist() { twist = nil }

    /// Points the needle and writes the label from the model's current
    /// value. Cheap enough to call every frame — the label is cached on
    /// its string, and the needle is one quaternion.
    public func refresh() {
        let value = read()
        let span = range.upperBound - range.lowerBound
        let fraction = span > 0 ? (value - range.lowerBound) / span : 0
        dial.setValueFraction(fraction)
        dial.setLabel(format(value))
    }
}
