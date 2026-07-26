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

    var body: some View {
        RealityView { content, attachments in
            let renderer = FieldRenderer()
            content.add(renderer.root)

            // The control constellation: five single-purpose pods in an
            // arc around the field region, plus the numbers card. Each
            // hangs from a grabbable bar; the pods orb clears them all.
            let podsRoot = PodMount.makeRoot(module: "electrostatics")
            renderer.root.addChild(podsRoot)
            // Four pods, one idea each: sources left, imposed fields and
            // the numbers right.
            PodMount.mount(attachments.entity(for: "pod-charges"), name: "Charges",
                           at: [-1.05, 1.72, -0.85], in: podsRoot)
            PodMount.mount(attachments.entity(for: "pod-probe"), name: "Test charge",
                           at: [-1.2, 1.12, -0.65], in: podsRoot)
            PodMount.mount(attachments.entity(for: "pod-fields"), name: "Uniform fields",
                           at: [1.05, 1.72, -0.85], in: podsRoot)
            PodMount.mount(attachments.entity(for: "pod-stats"), name: "Numbers",
                           at: [1.2, 1.08, -0.65], in: podsRoot)


            // Simulation clock: step the probe every rendered frame, then
            // move its entity in the same tick — buttery motion that never
            // waits for the observation round-trip.
            renderer.subscriptions.append(
                content.subscribe(to: SceneEvents.Update.self) { [weak renderer] event in
                    model.stepProbe(dt: event.deltaTime)
                    model.stepFreeCharges(dt: event.deltaTime)
                    renderer?.tick(model, room: appModel.room.bounds)
                    podsRoot.isEnabled = appModel.controlPodsVisible
                    PodMount.persistIfMoved(podsRoot)
                }
            )

            renderer.tick(model)
            self.renderer = renderer
        } attachments: {
            Attachment(id: "pod-charges") { ChargesPod() }
            Attachment(id: "pod-probe") { TestChargePod() }
            Attachment(id: "pod-fields") { UniformFieldsPod() }
            Attachment(id: "pod-stats") {
                ControlPod(title: "View & numbers", icon: "eye",
                           tint: .secondary, width: 330) {
                    FieldViewToggles()
                    PhysicsStatsView()
                }
            }
        }
        // Relative dragging, no system manipulation: the charge (or
        // probe, or plate) moves by exactly the hand's displacement —
        // it never lurches toward the hand, and the per-frame tick
        // moves its field with it in the same frame.
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .targetedToAnyEntity()
                .onChanged { value in
                    let hand = SIMD3<Double>(SIMD3<Float>(value.convert(
                        value.location3D, from: .local, to: .scene)))
                    if drag == nil {
                        drag = beginDrag(entity: value.entity, hand: hand)
                    }
                    guard let drag else { return }
                    apply(drag: drag, hand: hand)
                }
                .onEnded { value in
                    let hand = SIMD3<Double>(SIMD3<Float>(value.convert(
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
