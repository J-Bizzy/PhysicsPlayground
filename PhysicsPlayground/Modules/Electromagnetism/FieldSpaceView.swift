//
//  FieldSpaceView.swift
//  Physics Playground — Electromagnetism module
//
//  The electrostatics immersive scene, hosted by PlaygroundSpaceView.
//  RealityView's make closure installs the entity tree; from then on
//  FieldRenderer's RenderLoop re-renders on every model change.
//
//  Manipulation events arrive through Core's ManipulationRouter: charges
//  are keyed by UUID name, the probe by its fixed name. The probe
//  simulation pauses while held and resumes from rest at the drop point.
//  The probe's clock is RealityKit's per-frame SceneEvents.Update.
//

import SwiftUI
import RealityKit
import RenderKit

struct FieldSpaceView: View {
    @Environment(FieldModel.self) private var model
    @Environment(AppModel.self) private var appModel
    @State private var renderer: FieldRenderer?
    @State private var router = ManipulationRouter()

    var body: some View {
        RealityView { content, attachments in
            let renderer = FieldRenderer()
            content.add(renderer.root)

            // The control constellation: five single-purpose pods in an
            // arc around the field region, plus the numbers card. Each
            // hangs from a grabbable bar; the pods orb clears them all.
            let podsRoot = Entity()
            renderer.root.addChild(podsRoot)
            PodMount.mount(attachments.entity(for: "pod-charges"), name: "Charges",
                           at: [-1.05, 1.72, -0.85], in: podsRoot)
            PodMount.mount(attachments.entity(for: "pod-probe"), name: "Test charge",
                           at: [-1.2, 1.12, -0.65], in: podsRoot)
            PodMount.mount(attachments.entity(for: "pod-capacitor"), name: "Capacitor",
                           at: [1.05, 1.72, -0.85], in: podsRoot)
            PodMount.mount(attachments.entity(for: "pod-magnetic"), name: "Magnetic field",
                           at: [1.2, 1.12, -0.65], in: podsRoot)
            PodMount.mount(attachments.entity(for: "pod-view"), name: "View",
                           at: [-0.62, 0.78, -0.75], drop: 0.13, in: podsRoot)
            PodMount.mount(attachments.entity(for: "pod-stats"), name: "Numbers",
                           at: [0.62, 0.78, -0.75], in: podsRoot)

            configureRouter(renderer: renderer)
            renderer.subscriptions = router.subscriptions(for: content)

            // Simulation clock: step the probe every rendered frame, then
            // move its entity in the same tick — buttery motion that never
            // waits for the observation round-trip.
            renderer.subscriptions.append(
                content.subscribe(to: SceneEvents.Update.self) { [weak renderer] event in
                    model.stepProbe(dt: event.deltaTime)
                    renderer?.syncProbeNow(model.probe, isPositive: model.probeIsPositive)
                    podsRoot.isEnabled = appModel.controlPodsVisible
                }
            )

            renderer.startObserving(model)
            self.renderer = renderer
        } attachments: {
            Attachment(id: "pod-charges") { ChargesPod() }
            Attachment(id: "pod-probe") { TestChargePod() }
            Attachment(id: "pod-capacitor") { CapacitorPod() }
            Attachment(id: "pod-magnetic") { MagneticPod() }
            Attachment(id: "pod-view") { FieldViewPod() }
            Attachment(id: "pod-stats") {
                ControlPod(title: "Numbers", icon: "number",
                           tint: .secondary, width: 330) {
                    PhysicsStatsView()
                }
            }
        }
    }

    private func configureRouter(renderer: FieldRenderer) {
        func plateIndex(_ name: String) -> Int? {
            name == "plate-0" ? 0 : name == "plate-1" ? 1 : nil
        }
        router.onBegin = { [weak renderer] name, position in
            if let index = plateIndex(name) {
                renderer?.manipulatingPlateIndex = index
                model.movePlate(index, toWorld: SIMD3<Double>(position))
            } else if name == FieldRenderer.probeEntityName {
                renderer?.isManipulatingProbe = true
                model.holdProbe(at: SIMD3<Double>(position))
            } else if let id = UUID(uuidString: name) {
                renderer?.manipulatingChargeID = id
                model.select(id: id)
            }
        }
        router.onMove = { name, position in
            if let index = plateIndex(name) {
                model.movePlate(index, toWorld: SIMD3<Double>(position))
            } else if name == FieldRenderer.probeEntityName {
                model.holdProbe(at: SIMD3<Double>(position))
            } else if let id = UUID(uuidString: name) {
                model.moveCharge(id: id, to: SIMD3<Double>(position))
            }
        }
        router.onEnd = { [weak renderer] name, position in
            if let index = plateIndex(name) {
                model.movePlate(index, toWorld: SIMD3<Double>(position))
                renderer?.manipulatingPlateIndex = nil
            } else if name == FieldRenderer.probeEntityName {
                renderer?.isManipulatingProbe = false
                model.holdProbe(at: SIMD3<Double>(position))
                model.releaseProbe()
            } else if let id = UUID(uuidString: name) {
                // Clear the in-flight flag first, then write the final
                // position: the observation-triggered re-render then snaps
                // the entity to the (floor-clamped) model position.
                renderer?.manipulatingChargeID = nil
                model.moveCharge(id: id, to: SIMD3<Double>(position))
            }
        }
    }
}
