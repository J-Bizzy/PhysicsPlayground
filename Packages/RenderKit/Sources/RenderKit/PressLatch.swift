//
//  PressLatch.swift
//  RenderKit — a press that becomes a drag only once it has moved.
//
//  One `DragGesture(minimumDistance: 0)` carries every verb in a scene,
//  so the gesture fires on a bare press; this discriminator keeps a
//  press from acting until it travels. A promotion carries only
//  identity, never the press-time position: `RelativeDrag` moves by
//  displacement, and a swinging object's press-time position is stale.
//

import simd

/// Holds a press until it has travelled far enough to mean a drag.
public struct PressLatch<Payload>: Sendable where Payload: Sendable {
    /// How far a press may wander and still count as a tap, metres. A
    /// still hand drifts a few mm; a finger is ~15 mm wide.
    public static var tapTravel: Double { 0.012 }

    private var pending: (payload: Payload, hand: SIMD3<Double>)?

    public init() {}

    /// Whether a press is waiting to see whether it is a drag.
    public var isPending: Bool { pending != nil }

    /// Records a press without acting on the pressed object. The first
    /// press wins: a `targetedToAnyEntity` gesture reports the same entity
    /// every frame, and re-pressing would reset the anchor so `promote`
    /// always measured zero.
    public mutating func press(_ payload: Payload, at hand: SIMD3<Double>) {
        guard pending == nil else { return }
        pending = (payload, hand)
    }

    /// Reports the press as a drag the first time the hand carries it past
    /// `tapTravel`, nil until then. Consumes the press so it fires once
    /// (else it would re-grab every frame). Returns identity only.
    public mutating func promote(hand: SIMD3<Double>) -> Payload? {
        guard let pending,
              simd_distance(hand, pending.hand) > Self.tapTravel else { return nil }
        self.pending = nil
        return pending.payload
    }

    /// Resolves a press that never became a drag — anything still pending
    /// at gesture end stayed within `tapTravel`. Returns and clears the
    /// payload; nil if nothing was pending or the press already promoted.
    public mutating func settle() -> Payload? {
        defer { pending = nil }
        return pending?.payload
    }

    /// Abandons a press without acting on it — it was a tap, or the
    /// gesture went away.
    public mutating func cancel() { pending = nil }
}
