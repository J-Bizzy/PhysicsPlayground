//
//  HandGrabs.swift
//  RenderKit — one grab per hand.
//
//  SwiftUI runs one instance of a DragGesture, so while one hand holds
//  something the other hand's pinch is never delivered to it: a lab built
//  on one drag can hold one thing. A raw `SpatialEventGesture` reports every
//  pinch with its own id, so this table gives each pinch its own session —
//  what it took, and the relative drag anchored where it took it.
//  Magnetism and Light & Optics wrote this table by hand first; the other
//  labs share this one (2026-11-02). What a lab lets a hand take, and what
//  letting go does, stay the lab's: `begin`, `move` and `end`.
//

import QuartzCore
import RealityKit
import SwiftUI

@MainActor
public final class HandGrabs<Target> {
    public struct Session {
        public let target: Target
        public let drag: RelativeDrag
        /// The hand where it was last reported, in the frame the lab's
        /// objects move in.
        public fileprivate(set) var hand: SIMD3<Double>
        fileprivate var lastSeen: Double
    }

    /// How long a session survives without a report: a hand that leaves the
    /// tracking volume mid-carry sends no ending event, and what it held
    /// would stay held forever. The same half-second as the pinch ledger's.
    public static var staleAfter: Double { PinchLedger.staleAfter }

    private var sessions: [AnyHashable: Session] = [:]
    /// Pinches the lab turned down, and when each was last heard from. A
    /// pinch is judged once, where it closed: one turned away (the second
    /// hand of a resize, say) does not take the object mid-pinch when the
    /// other hand lets go of it.
    private var declined: [AnyHashable: Double] = [:]

    public init() {}

    public var isEmpty: Bool { sessions.isEmpty }
    public var count: Int { sessions.count }
    public var sessionsInHand: [Session] { Array(sessions.values) }

    /// Whether a hand holds a target that `test` accepts.
    public func holds(where test: (Target) -> Bool) -> Bool {
        sessions.values.contains { test($0.target) }
    }

    /// One update of the pinches in flight. `locate` places an event's hand in
    /// the frame the lab's objects move in; `begin` resolves a fresh pinch on
    /// what it landed on to a target and where that target stands — or nil,
    /// to leave the pinch to the lab's other recognisers; `move` carries a
    /// target to where its drag puts it; `end` lets one go.
    public func handle(_ events: SpatialEventCollection,
                       now: Double = CACurrentMediaTime(),
                       locate: (SpatialEventCollection.Event) -> SIMD3<Double>?,
                       begin: (Entity?, SIMD3<Double>) -> (Target, SIMD3<Double>)?,
                       move: (Target, SIMD3<Double>) -> Void,
                       end: (Session) -> Void) {
        for event in events {
            let active = event.phase == .active
            report(event.id, active: active, on: event.targetedEntity,
                   hand: active ? locate(event) : nil, now: now,
                   begin: begin, move: move, end: end)
        }
        expire(now: now, end: end)
    }

    /// One pinch's report, as `handle` reads it from an event. Public so the
    /// table can be tested without a hand.
    public func report(_ id: AnyHashable, active: Bool, on entity: Entity?,
                       hand: SIMD3<Double>?, now: Double,
                       begin: (Entity?, SIMD3<Double>) -> (Target, SIMD3<Double>)?,
                       move: (Target, SIMD3<Double>) -> Void,
                       end: (Session) -> Void) {
        guard active else {
            declined[id] = nil
            if let ended = sessions.removeValue(forKey: id) { end(ended) }
            return
        }
        guard let hand else { return }
        if var session = sessions[id] {
            session.lastSeen = now
            session.hand = hand
            sessions[id] = session
            move(session.target, session.drag.position(forHand: hand))
        } else if declined[id] != nil {
            declined[id] = now
        } else if let (target, standing) = begin(entity, hand) {
            sessions[id] = Session(target: target,
                                   drag: RelativeDrag(name: "hand", target: standing, hand: hand),
                                   hand: hand, lastSeen: now)
        } else {
            declined[id] = now
        }
    }

    /// Ends every session that has not been heard from for `staleAfter`.
    public func expire(now: Double = CACurrentMediaTime(), end: (Session) -> Void) {
        for (id, session) in sessions where now - session.lastSeen >= Self.staleAfter {
            sessions.removeValue(forKey: id)
            end(session)
        }
        declined = declined.filter { now - $0.value < Self.staleAfter }
    }

    /// Lets go of everything: leaving the lab, or a reset under a hand.
    public func releaseAll(_ end: (Session) -> Void) {
        let held = Array(sessions.values)
        sessions.removeAll()
        declined.removeAll()
        held.forEach(end)
    }
}
