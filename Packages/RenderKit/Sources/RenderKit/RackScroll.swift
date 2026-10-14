//
//  RackScroll.swift
//  RenderKit
//
//  The scroll state of a shelf that shows a window onto its slots: a
//  drag the strip follows 1:1, a flick that projects past the hand, a
//  rubber band past either end, a settle onto whole slots, and an
//  arrival that coasts into place. Pure arithmetic so every case is a
//  unit test rather than a headset session.
//

import Foundation

public struct RackScroll: Sendable, Equatable {
    public enum Phase: Sendable, Equatable {
        case resting, dragging, settling
    }

    /// Centre-to-centre slot spacing, metres.
    public let pitch: Float
    public let count: Int
    public let visible: Int

    /// How far the strip is lifted, metres. 0 puts the first slot at the
    /// head of the window; `maxOffset` puts the last slot at its foot.
    public private(set) var offset: Float = 0
    public private(set) var phase: Phase = .resting
    /// The hand's speed along the shelf during a drag, metres per second.
    public private(set) var velocity: Float = 0

    private var grabOffset: Float = 0
    private var target: Float = 0
    private var lastOffset: Float = 0
    /// How quickly the current settle closes, per second: `settleRate`
    /// after a hand, gentler for an arrival.
    private var closingRate: Float = RackScroll.settleRate

    /// How far a flick coasts: the release velocity divided by this, metres.
    public static let flickFriction: Float = 3.0
    /// How quickly a settle closes on its slot, per second.
    public static let settleRate: Float = 11
    /// The furthest the strip can be pushed past an end, as a fraction of a slot.
    public static let overscroll: Float = 0.6
    /// A settle this close to its slot is finished, metres.
    private static let settled: Float = 0.0004

    public init(pitch: Float, count: Int, visible: Int) {
        self.pitch = max(pitch, 0)
        self.count = max(count, 0)
        self.visible = max(visible, 0)
    }

    public var maxOffset: Float { Float(max(count - visible, 0)) * pitch }
    public var canScroll: Bool { count > visible && pitch > 0 }
    public var isDragging: Bool { phase == .dragging }
    public var isMoving: Bool { phase != .resting }

    /// The slot nearest the head of the window.
    public var index: Int {
        guard pitch > 0 else { return 0 }
        return min(max(Int((offset / pitch).rounded()), 0), max(count - visible, 0))
    }

    // MARK: Dragging

    public mutating func beginDrag() {
        guard canScroll else { return }
        grabOffset = offset
        lastOffset = offset
        velocity = 0
        phase = .dragging
    }

    /// `travel` is the hand's movement along the shelf since the grab,
    /// positive toward the later slots.
    public mutating func drag(travel: Float) {
        guard phase == .dragging else { return }
        offset = Self.rubberBanded(grabOffset + travel, limit: maxOffset,
                                   band: Self.overscroll * pitch)
    }

    /// Lets go: a strip past an end springs back to it, otherwise the
    /// flick is projected and the nearest whole slot to the landing wins.
    public mutating func endDrag(reduceMotion: Bool = false) {
        guard phase == .dragging else { return }
        let landing = offset < 0 || offset > maxOffset
            ? offset
            : offset + velocity / Self.flickFriction
        target = Self.nearestSlot(to: landing, pitch: pitch, limit: maxOffset)
        velocity = 0
        closingRate = Self.settleRate
        if reduceMotion {
            offset = target
            phase = .resting
        } else {
            phase = .settling
        }
    }

    /// Puts slot `index` at the head of the window at once.
    public mutating func jump(toIndex index: Int) {
        let clamped = min(max(index, 0), max(count - visible, 0))
        offset = Float(clamped) * pitch
        velocity = 0
        phase = .resting
    }

    /// Arrives coasting: puts the strip at `start`, no further out than
    /// the rubber band allows, and lets it settle onto the nearest slot
    /// at `rate` per second — so a shelf can be seen to move before a
    /// hand asks it to.
    public mutating func coast(from start: Float, rate: Float = RackScroll.settleRate) {
        guard canScroll else { return }
        let band = Self.overscroll * pitch
        offset = min(max(start, -band), maxOffset + band)
        target = Self.nearestSlot(to: offset, pitch: pitch, limit: maxOffset)
        velocity = 0
        closingRate = max(rate, 0.1)
        phase = .settling
    }

    /// Per frame. While dragging it measures the hand's speed; while
    /// settling it eases onto the target slot.
    public mutating func step(dt: Double, reduceMotion: Bool = false) {
        guard dt > 0 else { return }
        switch phase {
        case .dragging:
            let instantaneous = (offset - lastOffset) / Float(dt)
            velocity = velocity * 0.5 + instantaneous * 0.5
            lastOffset = offset
        case .settling:
            if reduceMotion {
                offset = target
            } else {
                let closing = 1 - exp(-closingRate * Float(dt))
                offset += (target - offset) * closing
            }
            if abs(target - offset) < Self.settled {
                offset = target
                phase = .resting
            }
        case .resting:
            break
        }
    }

    // MARK: Arithmetic

    /// Compresses travel past either end so the strip resists rather than
    /// stops: an overshoot of `x` shows as `band · x / (x + band)`.
    public static func rubberBanded(_ raw: Float, limit: Float, band: Float) -> Float {
        guard band > 0 else { return min(max(raw, 0), limit) }
        if raw < 0 {
            let over = -raw
            return -(band * over / (over + band))
        }
        if raw > limit {
            let over = raw - limit
            return limit + band * over / (over + band)
        }
        return raw
    }

    /// The whole slot nearest an offset, inside the strip's range.
    public static func nearestSlot(to offset: Float, pitch: Float, limit: Float) -> Float {
        guard pitch > 0 else { return 0 }
        let clamped = min(max(offset, 0), limit)
        return min((clamped / pitch).rounded() * pitch, limit)
    }
}
