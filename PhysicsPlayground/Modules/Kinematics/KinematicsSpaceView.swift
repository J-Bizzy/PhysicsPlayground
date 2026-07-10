//
//  KinematicsSpaceView.swift
//  Physics Playground — Kinematics module
//
//  The kinematics immersive scene, hosted by PlaygroundSpaceView. The
//  aim bead's manipulation events route through RenderKit's
//  ManipulationRouter into KinematicsModel.aim(toward:); the flight clock
//  is RealityKit's per-frame SceneEvents.Update, same pattern as the
//  electromagnetism probe.
//

import SwiftUI
import RealityKit
import RenderKit

struct KinematicsSpaceView: View {
    @Environment(KinematicsModel.self) private var model
    @State private var renderer: KinematicsRenderer?
    @State private var router = ManipulationRouter()

    var body: some View {
        RealityView { content, attachments in
            let renderer = KinematicsRenderer()
            content.add(renderer.root)

            if let panel = attachments.entity(for: "quick") {
                panel.position = [-0.35, 0.6, -0.72]
                panel.orientation = simd_quatf(angle: -0.35, axis: [1, 0, 0])
                renderer.root.addChild(panel)
            }
            if let stats = attachments.entity(for: "stats") {
                stats.position = [0.42, 0.6, -0.72]
                stats.orientation = simd_quatf(angle: -0.35, axis: [1, 0, 0])
                renderer.root.addChild(stats)
            }

            configureRouter(renderer: renderer)
            renderer.subscriptions = router.subscriptions(for: content)

            // Flight clock: step every rendered frame.
            renderer.subscriptions.append(
                content.subscribe(to: SceneEvents.Update.self) { event in
                    model.step(dt: event.deltaTime)
                }
            )

            renderer.startObserving(model)
            self.renderer = renderer
        } attachments: {
            Attachment(id: "quick") {
                KinematicsQuickPanel()
                    .environment(model)
                    .padding(20)
                    .frame(width: 340)
                    .glassBackgroundEffect()
            }
            Attachment(id: "stats") {
                KinematicsStatsView()
                    .environment(model)
                    .padding(20)
                    .frame(width: 340)
                    .glassBackgroundEffect()
            }
        }
    }

    private func configureRouter(renderer: KinematicsRenderer) {
        router.onBegin = { [weak renderer] name, position in
            guard name == KinematicsRenderer.aimBeadName, let renderer else { return }
            renderer.isManipulatingBead = true
            model.aim(toward: renderer.physicsPoint(fromWorld: position))
        }
        router.onMove = { [weak renderer] name, position in
            guard name == KinematicsRenderer.aimBeadName, let renderer else { return }
            model.aim(toward: renderer.physicsPoint(fromWorld: position))
        }
        router.onEnd = { [weak renderer] name, _ in
            guard name == KinematicsRenderer.aimBeadName else { return }
            // The render loop snaps the bead back onto the aim line.
            renderer?.isManipulatingBead = false
        }
    }
}

/// The floating in-space panel: just enough to aim and fire without
/// looking away from the diorama.
struct KinematicsQuickPanel: View {
    @Environment(KinematicsModel.self) private var model

    var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: 14) {
            Button {
                model.fire()
            } label: {
                Label("Fire", systemImage: "paperplane.fill")
                    .font(.title3)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignTokens.Palette.kinematicsAccent)
            .accessibilityHint("Launches a projectile with the current aim and speed")

            VStack(alignment: .leading, spacing: 6) {
                Text("Speed: \(model.launchSpeed, specifier: "%.1f") m/s")
                    .font(DesignTokens.TypeScale.label.monospacedDigit())
                Slider(value: $model.launchSpeed, in: KinematicsModel.speedRange)
                    .accessibilityLabel("Launch speed")
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Angle: \(model.elevationDegrees, specifier: "%.0f")°")
                    .font(DesignTokens.TypeScale.label.monospacedDigit())
                Slider(value: $model.elevationDegrees, in: KinematicsModel.elevationRangeDegrees)
                    .accessibilityLabel("Launch angle")
            }

            Toggle("Air resistance", isOn: $model.airResistance)
                .font(DesignTokens.TypeScale.label)
        }
    }
}
