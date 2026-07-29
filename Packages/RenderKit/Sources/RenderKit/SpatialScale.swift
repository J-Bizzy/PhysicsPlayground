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
    func spatialScale(_ rig: SpatialScaleRig) -> some View {
        self
            .simultaneousGesture(
                MagnifyGesture()
                    .targetedToAnyEntity()
                    .onChanged { value in
                        rig.updateMagnification(Float(value.magnification))
                    }
                    .onEnded { _ in rig.endGesture() }
            )
            .simultaneousGesture(
                RotateGesture3D(constrainedToAxis: .y)
                    .targetedToAnyEntity()
                    .onChanged { value in
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

