//
//  KinematicsSpaceView.swift
//  Physics Playground — Kinematics module
//
//  The room-scale immersive scene. Manipulation events route by entity
//  name: the launcher body (move it), the aim bead (point it), any ball
//  (grab and THROW — release velocity comes from the hand's motion), and
//  any hoop (place it). The flight clock is SceneEvents.Update.
//

import PhysicsCore
import SwiftUI
import RealityKit
import RenderKit

struct KinematicsSpaceView: View {
    @Environment(KinematicsModel.self) private var model
    @State private var renderer: KinematicsRenderer?
    @State private var drag: RelativeDrag?
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

            renderer.subscriptions = []

            // Flight clock: step every rendered frame (simulated time —
            // the model applies the slow-motion scale and pause).
            renderer.subscriptions.append(
                content.subscribe(to: SceneEvents.Update.self) { [weak renderer] event in
                    // On device, detected walls flow into the physics.
                    // The walls come from the SHARED room session — this
                    // module used to run a second plane-detection session
                    // of its own, for the same planes the shell was
                    // already tracking.
                    if appModel.room.hasScannedRoom {
                        model.roomWalls = appModel.room.walls
                    }
                    model.step(dt: event.deltaTime)
                    // A ball that reaches an open hand is caught: the
                    // one moment in the module where the simulation
                    // reaches back to you. Device-only — the simulator
                    // reports no fingertips, so this is simply inert
                    // there.
                    model.catchBalls(atFingertips: appModel.room.fingertips)
                    renderer?.tick(model)
                    podsRoot.isEnabled = appModel.controlPodsVisible
                    PodMount.persistIfMoved(podsRoot)
                    // The lab's placement in the user's room — a pure
                    // display offset, safe because every grab in this app
                    // moves a body by hand DISPLACEMENT, which a constant
                    // translation leaves untouched.
                    renderer?.root.position = appModel.labPlacement.offset
                    // …but the control pods do NOT go with it: the user
                    // parked them where they wanted them, and moving the
                    // apparatus is not a request to move the controls.
                    podsRoot.position = -appModel.labPlacement.offset
                }
            )

            renderer.tick(model)
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
        }
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
                    defer { drag = nil }
                    guard let drag else { return }
                    let hand = SIMD3<Double>(SIMD3<Float>(value.convert(
                        value.location3D, from: .local, to: .scene)))
                    apply(drag: drag, hand: hand)
                    if let id = UUID(uuidString: drag.name),
                       model.flights.contains(where: { $0.id == id }) {
                        model.releaseBall(id: id)
                    }
                }
        )
    }

    /// Resolves a pinch: launcher body, aim bead, a flying/resting
    /// ball, or a hoop.
    private func beginDrag(entity: Entity, hand: SIMD3<Double>) -> RelativeDrag? {
        var current: Entity? = entity
        while let candidate = current {
            switch candidate.name {
            case KinematicsRenderer.launcherName:
                return RelativeDrag(name: candidate.name,
                                    target: model.launcherPosition, hand: hand)
            case KinematicsRenderer.aimBeadName:
                let target = model.launcherPosition
                    + Double(KinematicsRenderer.beadDistance) * model.aimDirection
                return RelativeDrag(name: candidate.name, target: target, hand: hand)
            default:
                if let id = UUID(uuidString: candidate.name) {
                    if let ring = model.rings.first(where: { $0.id == id }) {
                        return RelativeDrag(name: candidate.name,
                                            target: ring.position, hand: hand)
                    }
                    if let flight = model.flights.first(where: { $0.id == id }) {
                        model.grabBall(id: id)
                        return RelativeDrag(name: candidate.name,
                                            target: flight.state.position, hand: hand)
                    }
                }
                current = candidate.parent
            }
        }
        return nil
    }

    private func apply(drag: RelativeDrag, hand: SIMD3<Double>) {
        let position = drag.position(forHand: hand)
        switch drag.name {
        case KinematicsRenderer.launcherName:
            model.moveLauncher(to: position)
        case KinematicsRenderer.aimBeadName:
            model.aim(toward: position)
        default:
            guard let id = UUID(uuidString: drag.name) else { return }
            if model.rings.contains(where: { $0.id == id }) {
                model.moveRing(id: id, to: position)
            } else {
                model.holdBall(id: id, at: position)
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
                .buttonStyle(.podProminent)
                .tint(DesignTokens.Palette.kinematicsAccent)
                .accessibilityHint("Launches a ball from the launcher")

                Button {
                    model.spawnBall()
                } label: {
                    Label("Ball", systemImage: "circle.fill")
                        .font(.title3)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.podQuiet)
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
                .buttonStyle(.podQuiet)
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
                 ? "Walls come from your room, on device — the prediction bounces too."
                 : "Balls phase through walls to hold their trajectory.")
                .font(DesignTokens.TypeScale.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
