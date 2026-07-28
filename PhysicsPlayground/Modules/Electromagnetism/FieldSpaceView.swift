//
//  FieldSpaceView.swift
//  Physics Playground — Electromagnetism module
//
//  The electrostatics immersive scene, hosted by PlaygroundSpaceView.
//  RealityView's make closure installs the entity tree; from then on
//  FieldRenderer is ticked every frame from SceneEvents.Update.
//
//  Manipulation events arrive through Core's ManipulationRouter: charges
//  are keyed by UUID name, the probe by its fixed name. The probe
//  simulation pauses while held and resumes from rest at the drop point.
//  The probe's clock is RealityKit's per-frame SceneEvents.Update.
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
    /// Two-hand scale: grow the dipole field until its lines arc over
    /// your head. Turn stays OFF here — the field lines clip against
    /// the real room's box, and an axis-aligned box cannot survive a
    /// yawed view without lying about where the walls are.
    @State private var scaleRig = SpatialScaleRig(
        pivot: SIMD3<Float>(0, 1.35, -0.55), range: 0.5...3.5, allowsTurn: false)

    var body: some View {
        RealityView { content, attachments in
            let renderer = FieldRenderer()
            content.add(renderer.root)


            // Simulation clock: step the probe every rendered frame, then
            // move its entity in the same tick — buttery motion that never
            // waits for the observation round-trip.
            renderer.subscriptions.append(
                content.subscribe(to: SceneEvents.Update.self) { [weak renderer] event in
                    model.stepProbe(dt: event.deltaTime)
                    model.stepFreeCharges(dt: event.deltaTime)
                    // Look-to-measure: with this on, the Gauss surface
                    // follows the direction the head is facing, so you
                    // carry the flux meter with your gaze rather than
                    // your hand.
                    if let renderer { scaleRig.apply(to: renderer.viewRoot) }
                    if model.gaussSurfaceOn, model.lookToPlace,
                       let ray = appModel.room.lookRay,
                       let renderer {
                        // The gaze ray lives in the room; the Gauss
                        // surface lives in the model. Under a scaled
                        // view they differ — convert the ray, and give
                        // the arm's reach in model metres too.
                        let origin = renderer.displayPoint(fromWorld: SIMD3<Float>(ray.origin))
                        let scale = Double(max(scaleRig.liveScale, 0.01))
                        if let point = model.lookRegion.point(
                            onRay: origin, direction: ray.direction,
                            reach: model.lookReach / scale) {
                            model.moveGaussSurface(to: point)
                        }
                    }
                    // The room's clip box, pulled into model space: at
                    // 2x the walls are HALF as far away in model metres.
                    let scale = Double(max(scaleRig.liveScale, 0.01))
                    let pivot = SIMD3<Double>(0, 1.35, -0.55)
                    let bounds = appModel.room.bounds
                    renderer?.tick(model, room: RoomBox(
                        center: pivot + (bounds.center - pivot) / scale,
                        halfExtents: bounds.halfExtents / scale))
                    // The lab's placement in the user's room — a pure
                    // display offset, safe because every grab in this app
                    // moves a body by hand DISPLACEMENT, which a constant
                    // translation leaves untouched.
                    renderer?.root.position = appModel.labPlacement.offset
                }
            )

            #if DEBUG
            // double(forKey:) coerces the string the launch-argument
            // domain actually stores; `object as? Double` does not.
            let forced = UserDefaults.standard.double(forKey: "viewScale")
            if forced > 0 {
                scaleRig.updateMagnification(Float(forced))
                scaleRig.endGesture()
            }
            #endif
            renderer.tick(model)
            self.renderer = renderer
        } attachments: {
        }
        // Relative dragging, no system manipulation: the charge (or
        // probe, or plate) moves by exactly the hand's displacement —
        // it never lurches toward the hand, and the per-frame tick
        // moves its field with it in the same frame.
        .spatialScale(scaleRig)
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
        var current: Entity? = entity
        while let candidate = current {
            let name = candidate.name
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
            if let id = UUID(uuidString: name),
               let charge = model.charges.first(where: { $0.id == id }) {
                model.select(id: id)
                return RelativeDrag(name: name, target: charge.position, hand: hand)
            }
            current = candidate.parent
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


}
