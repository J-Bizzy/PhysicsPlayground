//
//  FieldSpaceView.swift
//  Physics Playground — Electromagnetism module
//
//  The electrostatics immersive scene, hosted by PlaygroundSpaceView.
//  RealityView's make closure installs the entity tree; from then on
//  FieldRenderer is ticked every frame from SceneEvents.Update.
//
//  DELIBERATELY SIMPLE. This scene once carried gaze-revealed wells to
//  pull charges from, a bloom of petals on the charge you looked at,
//  and a two-hand scale rig with an invisible metre-wide input plate.
//  The plate shielded the whole field from every pinch (hit-testing
//  uses colliders, not visible geometry), the gaze-gated controls were
//  undiscoverable, and the module read as broken. Now there are exactly
//  two verbs: DRAG a thing to move it, TAP a thing to select it. Adding
//  and editing live on the window panel (FieldControlsPanel).
//

import PhysicsCore
import SwiftUI
import RealityKit
import RenderKit

struct FieldSpaceView: View {
    @Environment(FieldModel.self) private var model
    @Environment(AppModel.self) private var appModel
    @State private var renderer: FieldRenderer?
    @State private var drag: RelativeDrag?

    var body: some View {
        RealityView { content in
            let renderer = FieldRenderer()
            content.add(renderer.root)

            // Simulation clock: step the physics every rendered frame,
            // then move entities in the same tick.
            renderer.subscriptions.append(
                content.subscribe(to: SceneEvents.Update.self) { [weak renderer] event in
                    model.stepProbe(dt: event.deltaTime)
                    model.stepFreeCharges(dt: event.deltaTime)
                    // Look-to-measure: the Gauss surface follows the
                    // direction the head is facing (panel toggle;
                    // device-only, the simulator has no look ray).
                    if model.gaussSurfaceOn, model.lookToPlace,
                       let ray = appModel.room.lookRay,
                       let renderer {
                        let origin = renderer.displayPoint(
                            fromWorld: SIMD3<Float>(ray.origin))
                        if let point = model.lookRegion.point(
                            onRay: origin, direction: ray.direction,
                            reach: model.lookReach) {
                            model.moveGaussSurface(to: point)
                        }
                    }
                    renderer?.tick(model, room: appModel.room.bounds)
                    // The lab's placement in the user's room — a pure
                    // display offset, safe because every grab moves a
                    // body by hand DISPLACEMENT, which a constant
                    // translation leaves untouched.
                    renderer?.root.position = appModel.labPlacement.offset
                }
            )
            self.renderer = renderer
        }
        .simultaneousGesture(
            TapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    // A tap on a charge selects it — it wears the halo
                    // and the panel's sliders edit it.
                    for name in Self.ancestorNames(of: value.entity) {
                        if let id = UUID(uuidString: name),
                           model.charges.contains(where: { $0.id == id }) {
                            model.select(id: id)
                            return
                        }
                    }
                }
        )
        // Relative dragging, no system manipulation: the charge (or
        // probe, or plate) moves by exactly the hand's displacement —
        // it never lurches toward the hand, and the per-frame tick
        // moves its field with it in the same frame.
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .targetedToAnyEntity()
                .onChanged { value in
                    guard let renderer else { return }
                    let hand = renderer.displayPoint(fromWorld: SIMD3<Float>(value.convert(
                        value.location3D, from: .local, to: .scene)))
                    if drag == nil {
                        drag = beginDrag(entity: value.entity, hand: hand)
                    }
                    guard let drag else { return }
                    apply(drag: drag, hand: hand)
                }
                .onEnded { value in
                    guard let renderer else { return }
                    let hand = renderer.displayPoint(fromWorld: SIMD3<Float>(value.convert(
                        value.location3D, from: .local, to: .scene)))
                    if let drag {
                        apply(drag: drag, hand: hand)
                        if drag.name == FieldRenderer.probeEntityName {
                            model.releaseProbe()
                        }
                    }
                    drag = nil
                    model.heldChargeID = nil
                }
        )
    }

    /// Resolves what was pinched and anchors a relative-drag session.
    private func beginDrag(entity: Entity, hand: SIMD3<Double>) -> RelativeDrag? {
        let names = Self.ancestorNames(of: entity)
        for name in names {
            if name == "plate-0" || name == "plate-1" {
                let index = name == "plate-0" ? 0 : 1
                let offset = (index == 0 ? -1.0 : 1.0) * model.plateSeparation / 2
                return RelativeDrag(
                    name: name,
                    target: model.capacitorCenter + SIMD3(offset, 0, 0),
                    hand: hand)
            }
            if name == "gauss-surface" {
                return RelativeDrag(name: name, target: model.gaussSurfaceCenter, hand: hand)
            }
            if name == FieldRenderer.probeEntityName {
                let target = model.probe?.position ?? hand
                model.holdProbe(at: target)
                return RelativeDrag(name: name, target: target, hand: hand)
            }
        }
        if let id = Self.resolveCharge(
                names: names, hand: hand,
                charges: model.charges.map { ($0.id, $0.position) }),
           let charge = model.charges.first(where: { $0.id == id }) {
            model.select(id: id)
            return RelativeDrag(name: id.uuidString, target: charge.position, hand: hand)
        }
        return nil
    }

    private func apply(drag: RelativeDrag, hand: SIMD3<Double>) {
        let position = drag.position(forHand: hand)
        if drag.name == "plate-0" || drag.name == "plate-1" {
            model.movePlate(drag.name == "plate-0" ? 0 : 1, toWorld: position)
        } else if drag.name == "gauss-surface" {
            model.moveGaussSurface(to: position)
        } else if drag.name == FieldRenderer.probeEntityName {
            model.holdProbe(at: position)
        } else if let id = UUID(uuidString: drag.name) {
            model.heldChargeID = id
            model.moveCharge(id: id, to: position)
        }
    }

    /// Names of the entity and its ancestors, nearest first.
    private static func ancestorNames(of entity: Entity) -> [String] {
        var names: [String] = []
        var current: Entity? = entity
        while let candidate = current {
            names.append(candidate.name)
            current = candidate.parent
        }
        return names
    }

    /// Resolves a pinch to a charge. An ancestor named with a charge's
    /// UUID wins outright; failing that, the nearest charge within
    /// `fallbackRadius` of the hand — so a near-miss pinch on a charge
    /// still grabs it instead of silently doing nothing.
    static func resolveCharge(names: [String], hand: SIMD3<Double>,
                              charges: [(id: UUID, position: SIMD3<Double>)],
                              fallbackRadius: Double = 0.12) -> UUID? {
        for name in names {
            if let id = UUID(uuidString: name),
               charges.contains(where: { $0.id == id }) {
                return id
            }
        }
        return charges
            .map { ($0.id, simd_distance($0.position, hand)) }
            .filter { $0.1 <= fallbackRadius }
            .min { $0.1 < $1.1 }?
            .0
    }
}
