//
//  SpatialScale.swift
//  RenderKit
//
//  Two-handed scale and turn — the gesture the whole app was missing.
//
//  Every module had exactly one verb: gaze, pinch, drag one object.
//  That is the verb of a mouse. The verb that only exists in a headset
//  is BOTH HANDS: pinch with two hands and pull apart to grow the solar
//  system from a tabletop orrery into an orrery you stand inside, or
//  turn your hands to look at a magnetic loop from the side.
//
//  The rig is deliberately a pure *presentation* transform: it scales
//  and turns a display root, and never touches the model. The physics
//  keeps running in true SI units at its own scale — the user is
//  changing their viewpoint, not the universe. Modules that publish
//  numbers in metres therefore need no changes at all.
//

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

    public func endGesture() {
        guard isGesturing else { return }
        isGesturing = false
        scale = liveScale
        turn = liveTurn
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
/// gesture can tell "both hands on ONE object" from "one object in each
/// hand". The distinction is the owner's same-object rule (2026-08-03):
/// two hands pinching the same object (or empty space) mean resize; two
/// hands each holding a different object mean two grabs, and the scale
/// rig must stay out of it — grabbing two magnets used to swell the
/// whole bench.
///
/// Fed from a passive `SpatialEventGesture` that the `spatialScale`
/// modifier attaches alongside the magnify/rotate pair: each spatial
/// event carries the entity it targeted, and the ledger resolves every
/// live pinch to its owning object.
@MainActor
public final class PinchLedger {
    private var owners: [SpatialEventCollection.Event.ID: Entity] = [:]

    public init() {}

    public func update(_ events: SpatialEventCollection) {
        for event in events {
            if event.phase == .active, let target = event.targetedEntity {
                owners[event.id] = Self.owner(of: target)
            } else {
                owners[event.id] = nil
            }
        }
    }

    public func clear() { owners.removeAll() }

    /// Whether a two-hand scale may run: true while the live pinches
    /// rest on at most one distinct object (or on nothing nameable).
    public var allowsScale: Bool {
        Self.distinctOwnerCount(of: Array(owners.values)) < 2
    }

    /// A pinch lands on whatever collider was hit — a glyph, a halo, a
    /// terminal — so it is walked up to the nearest NAMED ancestor,
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
    /// Attaches two-handed scale (and optional turn) to a module scene.
    /// Target it at the whole scene: MagnifyGesture and RotateGesture3D
    /// both need an entity with an InputTargetComponent under the hands,
    /// which every module's grabbable objects already provide — the
    /// gesture works when the user pinches any two physics objects.
    /// (There is deliberately NO region-covering invisible input plate:
    /// hit-testing uses colliders, not visible geometry, so a plate
    /// shields every object inside it from every pinch. One shipped;
    /// it silently killed all interaction in two modules.)
    ///
    /// THE SAME-OBJECT RULE: the modifier also watches raw spatial
    /// events through a `PinchLedger`, and while two live pinches rest
    /// on two different objects the rig is suppressed — that gesture is
    /// two grabs, not a resize.
    func spatialScale(_ rig: SpatialScaleRig) -> some View {
        modifier(SpatialScaleModifier(rig: rig))
    }

    /// The same gesture for a scene holding MORE THAN ONE apparatus.
    ///
    /// `spatialScale(_:)` targets any entity, so two of them stacked on
    /// one view both fire on every two-handed pinch — grab the circuit
    /// bench and the magnets across the room would swell with it. Here
    /// the pinched entity chooses: `route` walks whatever was hit up to
    /// the station that owns it and returns that station's rig, and only
    /// that rig moves.
    ///
    /// `rigs` is every rig the scene owns. A gesture that ends is ended
    /// on all of them rather than on the re-resolved one — if the hands
    /// drift off the entity they started on, re-resolving would leave
    /// the original rig stuck mid-gesture, with its committed scale
    /// never catching up to the live one. `endGesture()` on a rig that
    /// is not gesturing is already a no-op, so the sweep is free.
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
            // Passive observer: SpatialEventGesture does not claim the
            // pinches, it only reports them — each with the entity it
            // targeted, which is exactly the fact the magnify gesture
            // cannot see (it reports one entity for a two-hand gesture).
            .simultaneousGesture(
                SpatialEventGesture()
                    .onChanged { events in ledger.update(events) }
                    .onEnded { events in ledger.update(events) }
            )
            .simultaneousGesture(
                MagnifyGesture()
                    .targetedToAnyEntity()
                    .onChanged { value in
                        guard ledger.allowsScale else {
                            rig.endGesture()
                            return
                        }
                        rig.updateMagnification(Float(value.magnification))
                    }
                    .onEnded { _ in rig.endGesture() }
            )
            .simultaneousGesture(
                RotateGesture3D(constrainedToAxis: .y)
                    .targetedToAnyEntity()
                    .onChanged { value in
                        guard ledger.allowsScale else {
                            rig.endGesture()
                            return
                        }
                        // The rotation arrives as a 3-D rotation about Y;
                        // its angle carries the sign we want.
                        let rotation = value.rotation
                        let angle = Float(rotation.angle.radians)
                        let sign: Float = rotation.axis.y < 0 ? -1 : 1
                        rig.updateRotation(radians: angle * sign)
                    }
                    .onEnded { _ in rig.endGesture() }
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

