//
//  TrackLayout.swift
//  RenderKit
//
//  A bead on a rail: where the bead sits IS the value.
//
//  This replaces the dial (owner's call, 2026-07-29: "the dial does not do
//  it for me"), and the reason it works better is worth stating because it
//  applies to `Bloom`'s grip too. Both the dial and the grip are
//  RELATIVE — they accumulate a delta from wherever the gesture began, so
//  the value depends on the path your hand took and nothing about the
//  control's appearance tells you what it is set to until you read the
//  label. A twist has no home position.
//
//  A track is ABSOLUTE. The rail is the range, laid out in the room; the
//  bead is the current value, sitting at its place along it. You can see
//  the setting from across the room, you can grab the bead and put it
//  where you want, and half-way along means half-way through the range.
//  That is what every physical fader, thermostat and slide rule already
//  taught, and it is the one thing a rotary gauge cannot do.
//
//  Local frame: the rail runs along +x, centred on the anchor, so a track
//  can be dropped beside an apparatus without the caller compensating for
//  its length.
//

import Foundation
import simd

public struct TrackLayout: Sendable {
    /// Rail length in metres. Long enough to aim within a percent or so at
    /// arm's length, short enough to cross without stepping.
    public var length: Double

    public init(length: Double = 0.26) {
        self.length = length
    }

    /// Where the bead sits for a 0…1 fraction of the range.
    public func offset(forFraction fraction: Double) -> SIMD3<Double> {
        let clamped = min(max(fraction, 0), 1)
        return SIMD3(-length / 2 + clamped * length, 0, 0)
    }

    /// The fraction a hand is pointing at, from a position in the track's
    /// OWN frame.
    ///
    /// Only the along-rail component counts: a hand that drifts above or
    /// in front of the rail while dragging still sets the value it is
    /// level with, rather than sliding as the wrist wanders. Clamped, so
    /// reaching past either end pins to that end instead of running off.
    public func fraction(forHandInTrackSpace hand: SIMD3<Double>) -> Double {
        guard length > 1e-9 else { return 0 }
        return min(max((hand.x + length / 2) / length, 0), 1)
    }

    /// Value ↔ fraction, for a range that need not start at zero.
    public func fraction(forValue value: Double,
                         in range: ClosedRange<Double>) -> Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(max((value - range.lowerBound) / span, 0), 1)
    }

    public func value(forFraction fraction: Double,
                      in range: ClosedRange<Double>) -> Double {
        let clamped = min(max(fraction, 0), 1)
        return range.lowerBound + clamped * (range.upperBound - range.lowerBound)
    }
}
