//
//  SpatialScale.swift
//  RenderKit — two-handed scale and turn of a module's display root.
//
//  A pure presentation transform: it scales and turns a display root and
//  never touches the model. The physics keeps running in true SI units at
//  its own scale — the user changes their viewpoint, not the universe.

import QuartzCore
import RealityKit
import SwiftUI
import simd

/// Scale/turn state for one module's display root. Hold it in the
/// renderer (or as @State beside the RealityView) and apply it to the
/// root entity every frame.
@MainActor
@Observable
public final class SpatialScaleRig {
    /// The pivot the world grows around, in world coordinates. Usually
    /// the centre of the module's region, so the physics stays in front
    /// of the user instead of sliding off as it grows.
    public var pivot: SIMD3<Float>

    public let range: ClosedRange<Float>
    /// Whether two-handed turn is allowed as well as scale.
    public let allowsTurn: Bool

    /// Committed scale, updated when a gesture ends.
    private(set) public var scale: Float = 1
    /// Committed turn about the vertical axis, radians.
    private(set) public var turn: Float = 0

    /// How far apart or together the hands must move, as a factor, before
    /// the view grows or shrinks at all: a held pinch wobbles by a few
    /// per cent, and the rig used to follow every bit of it.
    public static let scaleDeadBand: Float = 1.08
    /// How far the hands must turn about each other before the view
    /// turns: 10°, so a resize does not bring a twist along with it.
    public static let turnDeadBand: Float = 10 * .pi / 180

    private var gestureStartScale: Float = 1
    private var gestureStartTurn: Float = 0
    private var isGesturing = false
    /// The hands' magnification and turn at the moment each cleared its
    /// dead band; nil until then. The view moves by what the hands do
    /// after that moment, so it never jumps by the band it waited out.
    private var scaleBaseline: Float?
    private var turnBaseline: Float?

    /// Live values including the in-flight gesture.
    private(set) public var liveScale: Float = 1
    private(set) public var liveTurn: Float = 0

    public init(pivot: SIMD3<Float>,
                range: ClosedRange<Float> = 0.35...3.0,
                allowsTurn: Bool = true) {
        self.pivot = pivot
        self.range = range
        self.allowsTurn = allowsTurn
    }

    // MARK: Gesture plumbing

    public func beginGesture() {
        guard !isGesturing else { return }
        isGesturing = true
        gestureStartScale = scale
        gestureStartTurn = turn
        scaleBaseline = nil
        turnBaseline = nil
    }

    /// Applies a magnification exactly, relative to the view at the
    /// gesture's start. For a caller that knows the scale it wants (a
    /// launch argument); the hands go through `handMagnification`.
    public func updateMagnification(_ magnification: Float) {
        beginGesture()
        liveScale = min(max(gestureStartScale * magnification, range.lowerBound),
                        range.upperBound)
    }

    public func updateRotation(radians: Float) {
        guard allowsTurn else { return }
        beginGesture()
        liveTurn = gestureStartTurn + radians
    }

    /// The hands' magnification, through the dead band: nothing moves
    /// until they have spread or closed by `scaleDeadBand`.
    public func handMagnification(_ magnification: Float) {
        beginGesture()
        if scaleBaseline == nil {
            guard magnification > Self.scaleDeadBand
                || magnification < 1 / Self.scaleDeadBand else { return }
            scaleBaseline = magnification
        }
        updateMagnification(magnification / (scaleBaseline ?? 1))
    }

    /// The hands' turn, through its own dead band, independently of the
    /// scale's: spreading the hands never turns the view on the way.
    public func handRotation(radians: Float) {
        guard allowsTurn else { return }
        beginGesture()
        if turnBaseline == nil {
            guard abs(radians) > Self.turnDeadBand else { return }
            turnBaseline = radians
        }
        updateRotation(radians: radians - (turnBaseline ?? 0))
    }

    /// Commits the in-flight gesture: whatever the hands did becomes the
    /// new view. Call this when a gesture genuinely finishes.
    public func endGesture() {
        guard isGesturing else { return }
        isGesturing = false
        scale = liveScale
        turn = liveTurn
    }

    /// Abandons the in-flight gesture, restoring the view to where it
    /// stood when the hands closed. Not interchangeable with endGesture,
    /// which would keep whatever the hands had done.
    public func cancelGesture() {
        guard isGesturing else { return }
        isGesturing = false
        liveScale = gestureStartScale
        liveTurn = gestureStartTurn
        scale = gestureStartScale
        turn = gestureStartTurn
    }

    /// Snaps back to 1× / no turn. Wired to the module's reset.
    public func reset() {
        isGesturing = false
        scale = 1; liveScale = 1
        turn = 0; liveTurn = 0
    }

    /// Applies the current view transform to a display root. Call once
    /// per frame from the module's SceneEvents.Update tick.
    ///
    /// Scaling about a pivot means translating so the pivot is fixed:
    /// p' = pivot + R·s·(p − pivot), which as an entity transform is a
    /// scale, a rotation, and a compensating position.
    public func apply(to root: Entity) {
        let s = liveScale
        let rotation = simd_quatf(angle: liveTurn, axis: [0, 1, 0])
        root.scale = SIMD3(repeating: s)
        root.orientation = rotation
        root.position = pivot - rotation.act(pivot * s)
    }

    /// True once the user has actually changed the view — modules use
    /// this to show a "1×" reset affordance only when it's meaningful.
    public var isTransformed: Bool {
        abs(liveScale - 1) > 0.02 || abs(liveTurn) > 0.02
    }

    /// Human-readable for a readout: "1.8×".
    public var label: String { String(format: "%.1f×", liveScale) }
}

/// Tracks every live pinch — what it landed on and when it closed — so a
/// two-hand gesture is a resize only when it was meant as one: both hands
/// closing on ONE object at about the same moment. One object in each
/// hand, a hand that closes on nothing, or a second hand joining one that
/// is already carrying something are all something else, and the rig
/// stays out. Until 2026-11-02 anything short of two different objects
/// resized, so a second pinch that missed scaled the lab. Fed from a
/// passive `SpatialEventGesture` that carries each pinch's targeted
/// entity.
@MainActor
public final class PinchLedger {
    /// How long an unmentioned pinch stays on the books. A hand that
    /// leaves the tracking volume mid-pinch never emits its removing
    /// event, so without expiry it would stay held forever. Longer than a
    /// frame gap, far shorter than a user notices.
    public static let staleAfter: Double = 0.5

    /// How near together the two hands must close for their pinch to be a
    /// resize. Looking at one thing and pinching with both hands closes
    /// them well inside this; reaching for a second object means first
    /// looking at it, which takes longer.
    public static let togetherWithin: Double = 0.4

    /// What the pinches on the books add up to.
    public enum Verdict: Equatable, Sendable {
        /// Fewer than two pinches reported yet: the other hand's may still
        /// be on its way.
        case undecided
        /// Both hands closed on one object together.
        case resize
        /// Anything else two hands do.
        case refuse
    }

    private struct Pinch {
        /// What the pinch landed on, kept from its first report: nil for a
        /// pinch on nothing nameable.
        let owner: Entity?
        let began: Double
        var seen: Double
    }

    private var pinches: [AnyHashable: Pinch] = [:]
    /// The verdict on the two-hand gesture in hand, once one is given.
    private var latched = Verdict.undecided

    public init() {}

    /// `now` is injectable so the rule can be tested; production callers
    /// use the media clock.
    public func update(_ events: SpatialEventCollection,
                       now: Double = CACurrentMediaTime()) {
        for event in events {
            record(event.id, active: event.phase == .active,
                   on: event.targetedEntity, now: now)
        }
        expire(now: now)
    }

    /// One pinch's report, as `update` reads it from an event. Public so the
    /// rule can be tested without a hand.
    public func record(_ id: AnyHashable, active: Bool, on target: Entity?,
                       now: Double = CACurrentMediaTime()) {
        guard active else {
            pinches[id] = nil
            return
        }
        if pinches[id] != nil {
            pinches[id]?.seen = now
        } else {
            pinches[id] = Pinch(owner: target.map(Self.owner(of:)), began: now, seen: now)
        }
    }

    private func expire(now: Double) {
        pinches = pinches.filter { now - $0.value.seen < Self.staleAfter }
    }

    /// The live pinches judged as they stand.
    public func verdict(now: Double = CACurrentMediaTime()) -> Verdict {
        expire(now: now)
        let live = Array(pinches.values)
        guard live.count >= 2 else { return .undecided }
        let owners = live.compactMap(\.owner)
        guard owners.count == live.count,
              Self.distinctOwnerCount(of: owners) == 1 else { return .refuse }
        let closes = live.map(\.began)
        guard let first = closes.min(), let last = closes.max(),
              last - first <= Self.togetherWithin else { return .refuse }
        return .resize
    }

    /// The verdict for the gesture in progress, kept once given: a resize
    /// that has begun runs to its end even while a still hand's pinch goes
    /// quiet, and a refused one never starts halfway through.
    public func decide(now: Double = CACurrentMediaTime()) -> Verdict {
        if latched == .undecided { latched = verdict(now: now) }
        return latched
    }

    /// The two-hand gesture is over; the next is judged afresh. The pinches
    /// stay on the books — a hand still carrying something closed when it
    /// closed, and must not look as though it had just closed again.
    public func gestureEnded() { latched = .undecided }

    /// A pinch lands on whatever collider was hit — a glyph, a halo, a
    /// terminal — so it is walked up to the nearest named ancestor,
    /// which is how every object in the app identifies itself.
    public static func owner(of entity: Entity) -> Entity {
        entity.nearestAncestor { !$0.name.isEmpty } ?? entity
    }

    /// How many mutually unrelated objects the given owners represent.
    /// Ancestor-related entities count as one object (two parts of the
    /// same magnet are the same magnet).
    public static func distinctOwnerCount(of owners: [Entity]) -> Int {
        var distinct: [Entity] = []
        for owner in owners {
            let related = distinct.contains {
                $0 === owner || $0.isDescendant(of: owner)
                    || owner.isDescendant(of: $0)
            }
            if !related { distinct.append(owner) }
        }
        return distinct.count
    }
}

public extension View {
    /// Attaches two-handed scale (and optional turn) to a module scene:
    /// look at one object, pinch it with both hands together, and spread
    /// or close them. Deliberately no region-covering input plate:
    /// hit-testing uses colliders, so a plate would shield every object
    /// inside it from every pinch. `PinchLedger` decides whether the
    /// hands meant a resize; anything else they do leaves the rig alone.
    /// (A multi-rig variant routed by station went on 2026-11-02, unused
    /// since the merged worlds and resizing on any two pinches.)
    func spatialScale(_ rig: SpatialScaleRig) -> some View {
        modifier(SpatialScaleModifier(rig: rig))
    }
}

/// The single-rig implementation. A struct modifier rather than an
/// inline chain because the pinch ledger needs stable per-view storage.
public struct SpatialScaleModifier: ViewModifier {
    let rig: SpatialScaleRig
    @State private var ledger = PinchLedger()

    public init(rig: SpatialScaleRig) { self.rig = rig }

    public func body(content: Content) -> some View {
        content
            // Passive observer: reports each pinch with its targeted
            // entity — the fact MagnifyGesture cannot see (it reports one
            // entity for a two-hand gesture).
            .simultaneousGesture(
                SpatialEventGesture()
                    .onChanged { events in ledger.update(events) }
                    .onEnded { events in ledger.update(events) }
            )
            .simultaneousGesture(
                MagnifyGesture()
                    .targetedToAnyEntity()
                    .onChanged { value in
                        // Nothing moves until the hands are judged a resize,
                        // so a refused gesture has nothing to take back.
                        guard ledger.decide() == .resize else { return }
                        rig.handMagnification(Float(value.magnification))
                    }
                    .onEnded { _ in
                        rig.endGesture()
                        ledger.gestureEnded()
                    }
            )
            .simultaneousGesture(
                RotateGesture3D(constrainedToAxis: .y)
                    .targetedToAnyEntity()
                    .onChanged { value in
                        guard ledger.decide() == .resize else { return }
                        // The rotation arrives as a 3-D rotation about Y;
                        // its angle carries the sign we want.
                        let rotation = value.rotation
                        let angle = Float(rotation.angle.radians)
                        let sign: Float = rotation.axis.y < 0 ? -1 : 1
                        rig.handRotation(radians: angle * sign)
                    }
                    .onEnded { _ in
                        rig.endGesture()
                        ledger.gestureEnded()
                    }
            )
    }
}

public extension Entity {
    /// The nearest ancestor (starting with self) that `test` accepts.
    /// The scene's gestures arrive on whatever collider was hit — a
    /// terminal, a petal, a magnet's halo — so every routing decision
    /// in a multi-apparatus scene starts by walking up to the owner.
    func nearestAncestor(where test: (Entity) -> Bool) -> Entity? {
        var current: Entity? = self
        while let candidate = current {
            if test(candidate) { return candidate }
            current = candidate.parent
        }
        return nil
    }

    /// Whether `ancestor` is this entity or anywhere above it.
    func isDescendant(of ancestor: Entity) -> Bool {
        nearestAncestor { $0 === ancestor } != nil
    }
}

