//
//  FieldSpaceView.swift
//  Physics Playground — Electrostatics module
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

struct FieldSpaceView: View {
    @Environment(FieldModel.self) private var model
    @State private var renderer: FieldRenderer?
    @State private var router = ManipulationRouter()

    var body: some View {
        RealityView { content, attachments in
            let renderer = FieldRenderer()
            content.add(renderer.root)

            if let panel = attachments.entity(for: "controls") {
                // Below the field region, tilted up toward the user's face.
                panel.position = [-0.25, 0.72, -0.75]
                panel.orientation = simd_quatf(angle: -0.35, axis: [1, 0, 0])
                renderer.root.addChild(panel)
            }
            if let stats = attachments.entity(for: "stats") {
                stats.position = [0.42, 0.72, -0.75]
                stats.orientation = simd_quatf(angle: -0.35, axis: [1, 0, 0])
                renderer.root.addChild(stats)
            }

            configureRouter(renderer: renderer)
            renderer.subscriptions = router.subscriptions(for: content)

            // Simulation clock: step the probe every rendered frame, then
            // move its entity in the same tick — buttery motion that never
            // waits for the observation round-trip.
            renderer.subscriptions.append(
                content.subscribe(to: SceneEvents.Update.self) { [weak renderer] event in
                    model.stepProbe(dt: event.deltaTime)
                    renderer?.syncProbeNow(model.probe, isPositive: model.probeIsPositive)
                }
            )

            renderer.startObserving(model)
            self.renderer = renderer
        } attachments: {
            Attachment(id: "controls") {
                ChargeControlsView(compact: true)
                    .padding(20)
                    .frame(width: 360)
                    .glassBackgroundEffect()
            }
            Attachment(id: "stats") {
                PhysicsStatsView()
                    .padding(20)
                    .frame(width: 340)
                    .glassBackgroundEffect()
            }
        }
    }

    private func configureRouter(renderer: FieldRenderer) {
        router.onBegin = { [weak renderer] name, position in
            if name == FieldRenderer.probeEntityName {
                renderer?.isManipulatingProbe = true
                model.holdProbe(at: SIMD3<Double>(position))
            } else if let id = UUID(uuidString: name) {
                renderer?.manipulatingChargeID = id
                model.select(id: id)
            }
        }
        router.onMove = { name, position in
            if name == FieldRenderer.probeEntityName {
                model.holdProbe(at: SIMD3<Double>(position))
            } else if let id = UUID(uuidString: name) {
                model.moveCharge(id: id, to: SIMD3<Double>(position))
            }
        }
        router.onEnd = { [weak renderer] name, position in
            if name == FieldRenderer.probeEntityName {
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
