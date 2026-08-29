//
//  PressLatch.swift
//  RenderKit — a press that becomes a drag only once it has moved.
//
//  One `DragGesture(minimumDistance: 0)` carries every verb in a scene (a
//  second recogniser over the same entities is ambiguous and costs the
//  drags), so the gesture fires on a bare press and any branch that ACTS
//  on the press acts on a tap. This per-branch discriminator gates the
//  destructive ones.
//
//  A promotion carries ONLY IDENTITY — deliberately not the object's
//  press-time position: `RelativeDrag` moves by displacement from its
//  build pair, so anchoring at the press replays the travelled 12 mm in
//  one frame, and a still-swinging bob's press-time position is already
//  stale. The caller reads the object's CURRENT position paired with the
//  CURRENT hand, so pickup moves nothing and then tracks 12 mm behind.

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

    /// Records a press without acting on the pressed object.
    ///
    /// THE FIRST PRESS WINS: a second while one is still pending is
    /// IGNORED, not replacing it. A `targetedToAnyEntity` gesture reports
    /// the same entity every frame, so without this guard a re-press each
    /// frame resets `pending.hand` to the current hand, `promote` always
    /// measures zero, and the object can never be picked up.
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

    /// Resolves a press that never became a drag — by construction,
    /// anything still pending at gesture end stayed within `tapTravel`
    /// (a travelled press was consumed by `promote` in `onChanged`).
    /// Returns and clears the payload, so the caller can treat the
    /// settled press as the tap it was; nil if nothing was pending or
    /// the press already promoted.
    public mutating func settle() -> Payload? {
        defer { pending = nil }
        return pending?.payload
    }

    /// Abandons a press without acting on it — it was a tap, or the
    /// gesture went away.
    public mutating func cancel() { pending = nil }
}
