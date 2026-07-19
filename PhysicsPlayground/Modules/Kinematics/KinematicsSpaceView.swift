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
    @State private var sensing = KinematicsSensing()
    @Environment(AppModel.self) private var appModel

    var body: some View {
        RealityView { content, attachments in
            let renderer = KinematicsRenderer()
            content.add(renderer.root)

            let podsRoot = PodMount.makeRoot(module: "kinematics")
            renderer.root.addChild(podsRoot)
            PodMount.mount(attachments.entity(for: "pod-launcher"), name: "Launcher",
                           at: [-0.9, 1.6, -0.95], in: podsRoot)
            PodMount.mount(attachments.entity(for: "pod-time"), name: "Time",
                           at: [-0.7, 0.95, -0.75], in: podsRoot)
            PodMount.mount(attachments.entity(for: "pod-stats"), name: "Numbers",
                           at: [0.9, 1.5, -0.95], in: podsRoot)

            configureRouter(renderer: renderer)
            renderer.subscriptions = router.subscriptions(for: content)

            // Flight clock: step every rendered frame (simulated time —
            // the model applies the slow-motion scale and pause).
            renderer.subscriptions.append(
                content.subscribe(to: SceneEvents.Update.self) { event in
                    // On device, detected walls flow into the physics.
                    if sensing.isRunning {
                        model.roomWalls = sensing.walls
                    }
                    model.step(dt: event.deltaTime)
                    podsRoot.isEnabled = appModel.controlPodsVisible
                    PodMount.persistIfMoved(podsRoot)
                }
            )

            renderer.startObserving(model)
            self.renderer = renderer
        } attachments: {
            Attachment(id: "pod-launcher") {
                LauncherPod()
                    .environment(model)
            }
            Attachment(id: "pod-time") {
                KinematicsTimePod()
                    .environment(model)
            }
            Attachment(id: "pod-stats") {
                ControlPod(title: "Numbers", icon: "number",
                           tint: .secondary, width: 340) {
                    KinematicsStatsView()
                        .environment(model)
                }
            }
        }
        .task {
            // Plane detection: device-only, quietly absent in the sim.
            await sensing.start()
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

/// The launcher's pod: fire, spawn a throwable ball, set the speed.
struct LauncherPod: View {
    @Environment(KinematicsModel.self) private var model

    var body: some View {
        @Bindable var model = model

        ControlPod(title: "Launcher", icon: "paperplane.fill",
                   tint: DesignTokens.Palette.kinematicsAccent) {
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
        }
    }
}

/// Time and air: the flight's environment.
struct KinematicsTimePod: View {
    @Environment(KinematicsModel.self) private var model

    var body: some View {
        @Bindable var model = model

        ControlPod(title: "Time", icon: "clock",
                   tint: DesignTokens.Palette.kinematicsAccent) {
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
            Toggle("Bounce off room walls", isOn: $model.respectRoomWalls)
                .font(DesignTokens.TypeScale.label)
                .accessibilityHint("Your real walls, detected on device — off, balls sail straight through")
            Text(model.respectRoomWalls
                 ? "Walls come from your room, on device. The dotted prediction shows the wall-free path."
                 : "Balls phase through walls to hold their trajectory.")
                .font(DesignTokens.TypeScale.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
