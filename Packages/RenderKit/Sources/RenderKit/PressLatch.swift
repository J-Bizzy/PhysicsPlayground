//
//  PressLatch.swift
//  RenderKit
//
//  A press that becomes a drag only once it has actually moved.
//
//  Three modules needed this and each learned it separately, the third
//  time from a bug report. The shape is always the same: one
//  `DragGesture(minimumDistance: 0)` carries every verb in the scene,
//  because a second recogniser over the same entities is ambiguous and
//  costs the module its drags — Pendulums lost the ability to re-hang a
//  rig that way, and lost every plate, disc and rail in the room the
//  time before. So the gesture fires on a bare press, and any branch
//  that ACTS on the press acts on a tap.
//
//  Where the action is positional that is harmless: a tap on the
//  launcher moves it by zero. Where the action is destructive it is not:
//
//  · Gravity Lab — a tap on a planet ran grab → hold → release, and a
//    tap carries no hand motion for the throw sampler, so the planet
//    was released at rest and fell into the Sun. Fixed 2026-08 by
//    raising `minimumDistance`, which that module could afford because
//    nothing else in it needs the first frame.
//  · Pendulums — a tap on a bob cleared EVERY trail in the room, zeroed
//    the swing and released it dead. The collar beside it had a
//    hand-rolled moved/not-moved discriminator; the bob had none.
//  · Projectiles — a tap on a ball in flight froze it in mid-air, where
//    it hung permanently, having lost its strobe trail and its flight
//    record.
//
//  Pendulums and Projectiles cannot use Gravity Lab's fix, because both
//  have branches on the same recogniser that must claim the very first
//  frame (pulling a new object out of a well, seizing a rail). They need
//  the discriminator per-branch, which is what this is.
//
//  WHAT THE LATCH DELIBERATELY DOES NOT CARRY is where the object was
//  when the press landed, and that is worth stating because carrying it
//  is the obvious thing to do and it is wrong twice over.
//
//  `RelativeDrag(target:hand:)` moves the object by the hand's
//  displacement FROM the pair it was built with, so anchoring it at the
//  press — the object's old position and the old hand — replays the
//  12 mm the hand has already travelled and the object catches up in
//  one frame. And in Pendulums the object is a bob still swinging at
//  around a metre a second, so its position at press time is stale by
//  more than the threshold by the time the threshold is crossed: the
//  bob would jump BACKWARDS to where it was when you pinched.
//
//  So a promotion carries only identity, and the caller reads the
//  object's CURRENT position and pairs it with the CURRENT hand. The
//  object does not move at all at the moment of pickup and thereafter
//  tracks the hand exactly, 12 mm behind — which nobody can perceive,
//  and which is precisely what Gravity Lab already gets from
//  `minimumDistance: 0.012` (SwiftUI withholds the first `onChanged`
//  until the threshold is crossed, so its `beginDrag` reads the current
//  position and the current hand too). Three modules, one behaviour.
//

import simd

/// Holds a press until it has travelled far enough to mean a drag.
public struct PressLatch<Payload>: Sendable where Payload: Sendable {
    /// How far a press may wander and still count as a tap, metres.
    /// A hand held still in mid-air drifts a few millimetres; a finger
    /// is about 15 mm wide. Shared with the hub's carry and the
    /// placement puck's recentre.
    public static var tapTravel: Double { 0.012 }

    private var pending: (payload: Payload, hand: SIMD3<Double>)?

    public init() {}

    /// Whether a press is waiting to see whether it is a drag.
    public var isPending: Bool { pending != nil }

    /// Records a press. Takes no action on the pressed object — taking
    /// action is exactly what a tap must not do.
    ///
    /// THE FIRST PRESS WINS, and a second one while it is still pending
    /// is IGNORED rather than replacing it. That guard belongs here
    /// rather than at the call sites, because both call sites got it
    /// wrong and the resulting failure is total and silent.
    ///
    /// A `targetedToAnyEntity` gesture reports the same entity on every
    /// frame, so a handler shaped
    ///
    ///     if drag == nil {
    ///         if let press = press(on: value.entity) { latch.press(press, at: hand) }
    ///     }
    ///     if drag == nil, latch.isPending { … latch.promote(hand: hand) … }
    ///
    /// re-presses before every promote. `pending.hand` becomes the
    /// CURRENT hand, `promote` measures a distance of exactly zero, and
    /// `drag` is never assigned — so the outer guard stays true and the
    /// cycle repeats for the life of the gesture. The threshold is
    /// never crossed at any speed, and the object simply cannot be
    /// picked up. Shipped for one commit on 2026-08-07 in both
    /// Pendulums and Projectiles.
    public mutating func press(_ payload: Payload, at hand: SIMD3<Double>) {
        guard pending == nil else { return }
        pending = (payload, hand)
    }

    /// Reports the press as a drag the first time the hand has carried
    /// it past `tapTravel`, and nil until then.
    ///
    /// Consumes the press, so it fires once — a promotion that fired
    /// every frame would re-grab the object on every frame of the carry.
    /// Returns identity only; see the header for why the caller reads
    /// the object's position itself, at this instant.
    public mutating func promote(hand: SIMD3<Double>) -> Payload? {
        guard let pending,
              simd_distance(hand, pending.hand) > Self.tapTravel else { return nil }
        self.pending = nil
        return pending.payload
    }

    /// Abandons a press without acting on it — it was a tap, or the
    /// gesture went away.
    public mutating func cancel() { pending = nil }
}
