//
//  KinematicsSpaceView.swift
//  Physics Playground — Kinematics module
//
//  The room-scale immersive scene. Manipulation events route by entity
//  name: the launcher body (move it), the aim bead (point it), any ball
//  (grab and THROW — release velocity comes from the hand's motion), and
//  any hoop (place it). The flight clock is SceneEvents.Update.
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
                panel.position = [-0.45, 1.0, -0.8]
                panel.orientation = simd_quatf(angle: -0.2, axis: [1, 0, 0])
                renderer.root.addChild(panel)
            }
            if let stats = attachments.entity(for: "stats") {
                stats.position = [0.5, 1.0, -0.8]
                stats.orientation = simd_quatf(angle: -0.2, axis: [1, 0, 0])
                renderer.root.addChild(stats)
            }

            configureRouter(renderer: renderer)
            renderer.subscriptions = router.subscriptions(for: content)

            // Flight clock: step every rendered frame (simulated time —
            // the model applies the slow-motion scale and pause).
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
                    .frame(width: 360)
                    .glassBackgroundEffect()
            }
            Attachment(id: "stats") {
                KinematicsStatsView()
                    .environment(model)
                    .padding(20)
                    .frame(width: 360)
                    .glassBackgroundEffect()
            }
        }
    }

    private func configureRouter(renderer: KinematicsRenderer) {
        router.onBegin = { [weak renderer] name, position in
            guard let renderer else { return }
            switch name {
            case KinematicsRenderer.launcherName:
                renderer.isManipulatingLauncher = true
                model.moveLauncher(to: SIMD3<Double>(position))
            case KinematicsRenderer.aimBeadName:
                renderer.isManipulatingBead = true
                model.aim(toward: SIMD3<Double>(position))
            default:
                guard let id = UUID(uuidString: name) else { return }
                if model.rings.contains(where: { $0.id == id }) {
                    renderer.manipulatingRingID = id
                    model.moveRing(id: id, to: SIMD3<Double>(position))
                } else {
                    renderer.manipulatingBallID = id
                    model.grabBall(id: id)
                    model.holdBall(id: id, at: SIMD3<Double>(position))
                }
            }
        }
        router.onMove = { name, position in
            switch name {
            case KinematicsRenderer.launcherName:
                model.moveLauncher(to: SIMD3<Double>(position))
            case KinematicsRenderer.aimBeadName:
                model.aim(toward: SIMD3<Double>(position))
            default:
                guard let id = UUID(uuidString: name) else { return }
                if model.rings.contains(where: { $0.id == id }) {
                    model.moveRing(id: id, to: SIMD3<Double>(position))
                } else {
                    model.holdBall(id: id, at: SIMD3<Double>(position))
                }
            }
        }
        router.onEnd = { [weak renderer] name, position in
            guard let renderer else { return }
            switch name {
            case KinematicsRenderer.launcherName:
                model.moveLauncher(to: SIMD3<Double>(position))
                renderer.isManipulatingLauncher = false
            case KinematicsRenderer.aimBeadName:
                // The render loop snaps the bead back onto the aim line.
                renderer.isManipulatingBead = false
            default:
                guard let id = UUID(uuidString: name) else { return }
                if model.rings.contains(where: { $0.id == id }) {
                    model.moveRing(id: id, to: SIMD3<Double>(position))
                    renderer.manipulatingRingID = nil
                } else {
                    model.holdBall(id: id, at: SIMD3<Double>(position))
                    model.releaseBall(id: id)
                    renderer.manipulatingBallID = nil
                }
            }
        }
    }
}

/// The floating in-space panel: everything you need mid-play without
/// looking away — fire, spawn a throwable ball, slow time.
struct KinematicsQuickPanel: View {
    @Environment(KinematicsModel.self) private var model

    var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: DesignTokens.Panel.rowSpacing) {
                Button {
                    model.fire()
                } label: {
                    Label("Fire", systemImage: "paperplane.fill")
                        .font(.title3)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignTokens.Palette.kinematicsAccent)
                .accessibilityHint("Launches a ball from the launcher")

                Button {
                    model.spawnBall()
                } label: {
                    Label("Ball", systemImage: "circle.fill")
                        .font(.title3)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("New ball to throw")
                .accessibilityHint("A ball appears in front of you — grab and throw it")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Speed: \(model.launchSpeed, specifier: "%.1f") m/s")
                    .font(DesignTokens.TypeScale.label.monospacedDigit())
                Slider(value: $model.launchSpeed, in: KinematicsModel.speedRange)
                    .accessibilityLabel("Launch speed")
            }

            HStack(spacing: DesignTokens.Panel.rowSpacing) {
                Button {
                    model.isPaused.toggle()
                } label: {
                    Image(systemName: model.isPaused ? "play.fill" : "pause.fill")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(model.isPaused ? "Resume time" : "Pause time")

                VStack(alignment: .leading, spacing: 2) {
                    Text("Time ×\(model.timeScale, specifier: "%.1f")")
                        .font(DesignTokens.TypeScale.footnote.monospacedDigit())
                    Slider(value: $model.timeScale, in: KinematicsModel.timeScaleRange)
                        .accessibilityLabel("Time scale")
                        .accessibilityValue("\(model.timeScale, specifier: "%.1f") times")
                }
            }

            Toggle("Air resistance", isOn: $model.airResistance)
                .font(DesignTokens.TypeScale.label)
        }
    }
}
