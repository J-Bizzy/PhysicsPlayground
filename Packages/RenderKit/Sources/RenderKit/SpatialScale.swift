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

    private var gestureStartScale: Float = 1
    private var gestureStartTurn: Float = 0
    private var isGesturing = false

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
    }

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

    /// Commits the in-flight gesture: whatever the hands did becomes the
    /// new view. Call this when a gesture genuinely finishes.
    public func endGesture() {
        guard isGesturing else { return }
        isGesturing = false
        scale = liveScale
        turn = liveTurn
    }

    /// Abandons the in-flight gesture, restoring the view to where it
    /// stood when the hands closed. Not interchangeable with endGesture:
    /// the same-object rule must cancel (not commit) a suppressed pinch,
    /// or grabbing two objects leaves the bench permanently scaled.
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

/// Tracks which entities are currently being pinched, so a two-hand
/// gesture can tell "both hands on one object" (resize) from "one object
/// in each hand" (two grabs — rig stays out). Fed from a passive
/// `SpatialEventGesture` that carries each pinch's targeted entity.
@MainActor
public final class PinchLedger {
    /// How long an unmentioned pinch stays on the books. A hand that
    /// leaves the tracking volume mid-pinch never emits its removing
    /// event, so without expiry its owner sticks forever and two-hand
    /// zoom silently dies for the session. Longer than a frame gap, far
    /// shorter than a user notices.
    public static let staleAfter: Double = 0.5

    private var owners: [SpatialEventCollection.Event.ID: (owner: Entity, seen: Double)] = [:]

    public init() {}

    /// `now` is injectable so the expiry can be tested; production
    /// callers use the media clock.
    public func update(_ events: SpatialEventCollection,
                       now: Double = CACurrentMediaTime()) {
        for event in events {
            if event.phase == .active, let target = event.targetedEntity {
                owners[event.id] = (Self.owner(of: target), now)
            } else {
                owners[event.id] = nil
            }
        }
        expire(now: now)
    }

    public func clear() { owners.removeAll() }

    private func expire(now: Double) {
        owners = owners.filter { now - $0.value.seen < Self.staleAfter }
    }

    /// Whether a two-hand scale may run: true while the live pinches
    /// rest on at most one distinct object (or on nothing nameable).
    public func allowsScale(now: Double = CACurrentMediaTime()) -> Bool {
        expire(now: now)
        return Self.distinctOwnerCount(of: owners.values.map(\.owner)) < 2
    }

    /// The same question, asked at the current instant.
    public var allowsScale: Bool { allowsScale() }

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
    /// Attaches two-handed scale (and optional turn) to a module scene,
    /// firing on any two grabbable objects the hands pinch. Deliberately
    /// No region-covering input plate: hit-testing uses colliders, so a
    /// plate would shield every object inside it from every pinch. The
    /// same-object rule (via `PinchLedger`) suppresses the rig while two
    /// pinches rest on two different objects — that is two grabs.
    func spatialScale(_ rig: SpatialScaleRig) -> some View {
        modifier(SpatialScaleModifier(rig: rig))
    }

    /// The same gesture for a scene holding more than one apparatus:
    /// `route` walks the pinched entity up to the station that owns it and
    /// only that rig moves. A gesture end is applied to all `rigs` (a
    /// no-op on any not gesturing), so a hand drifting off its start
    /// entity can't leave the original rig stuck mid-gesture.
    func spatialScale(
        rigs: [SpatialScaleRig],
        routing route: @escaping (Entity) -> SpatialScaleRig?
    ) -> some View {
        self
            .simultaneousGesture(
                MagnifyGesture()
                    .targetedToAnyEntity()
                    .onChanged { value in
                        route(value.entity)?
                            .updateMagnification(Float(value.magnification))
                    }
                    .onEnded { _ in rigs.forEach { $0.endGesture() } }
            )
            .simultaneousGesture(
                RotateGesture3D(constrainedToAxis: .y)
                    .targetedToAnyEntity()
                    .onChanged { value in
                        let rotation = value.rotation
                        let angle = Float(rotation.angle.radians)
                        let sign: Float = rotation.axis.y < 0 ? -1 : 1
                        route(value.entity)?.updateRotation(radians: angle * sign)
                    }
                    .onEnded { _ in rigs.forEach { $0.endGesture() } }
            )
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
                        // Cancel, not end — `endGesture` would commit the
                        // partial swell this guard exists to reject.
                        guard ledger.allowsScale else {
                            rig.cancelGesture()
                            return
                        }
                        rig.updateMagnification(Float(value.magnification))
                    }
                    .onEnded { _ in
                        rig.endGesture()
                        ledger.clear()
                    }
            )
            .simultaneousGesture(
                RotateGesture3D(constrainedToAxis: .y)
                    .targetedToAnyEntity()
                    .onChanged { value in
                        guard ledger.allowsScale else {
                            rig.cancelGesture()
                            return
                        }
                        // The rotation arrives as a 3-D rotation about Y;
                        // its angle carries the sign we want.
                        let rotation = value.rotation
                        let angle = Float(rotation.angle.radians)
                        let sign: Float = rotation.axis.y < 0 ? -1 : 1
                        rig.updateRotation(radians: angle * sign)
                    }
                    .onEnded { _ in
                        rig.endGesture()
                        ledger.clear()
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

