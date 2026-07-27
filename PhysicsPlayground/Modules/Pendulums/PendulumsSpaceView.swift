//
//  PendulumsSpaceView.swift
//  Physics Playground — Pendulums module
//
//  The pendulum lab immersive scene. Bobs route through the
//  ManipulationRouter: grabbing freezes that pendulum, the bob rides
//  the hand (cable staying taut), and release rethrows it with the
//  hand's velocity estimated from the last tenth of a second of
//  motion — a hard sideways throw whips it, a gentle release barely
//  stirs it.
//

import PhysicsCore
import SwiftUI
import RealityKit
import RenderKit
import simd

struct PendulumsSpaceView: View {
    @Environment(PendulumsModel.self) private var model
    @State private var renderer: PendulumsRenderer?
    @State private var drag: RelativeDrag?
    @State private var handSamples: [(time: Double, position: SIMD3<Double>)] = []
    @Environment(AppModel.self) private var appModel

    var body: some View {
        RealityView { content, attachments in
            let renderer = PendulumsRenderer()
            content.add(renderer.root)

            let podsRoot = PodMount.makeRoot(module: "pendulums")
            renderer.root.addChild(podsRoot)
            PodMount.mount(attachments.entity(for: "pod-bench"), name: "Bench",
                           at: [-1.1, 1.75, -0.9], in: podsRoot)
            PodMount.mount(attachments.entity(for: "pod-time"), name: "Time",
                           at: [-1.2, 1.15, -0.85], in: podsRoot)
            PodMount.mount(attachments.entity(for: "pod-view"), name: "View",
                           at: [1.1, 1.7, -0.9], in: podsRoot)
            PodMount.mount(attachments.entity(for: "pod-gravity"), name: "Gravity",
                           at: [1.2, 1.1, -0.85], in: podsRoot)
            if let info = attachments.entity(for: "info") {
                info.position = [0, 0.02, 0]
                renderer.infoAnchor.addChild(info)
            }

            renderer.subscriptions.append(
                content.subscribe(to: SceneEvents.Update.self) { [weak renderer] event in
                    renderer?.tick(dt: event.deltaTime, model: model)
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
            self.renderer = renderer
        } attachments: {
            Attachment(id: "pod-bench") {
                PendulumsBenchPod()
                    .environment(model)
            }
            Attachment(id: "pod-time") {
                PendulumsTimePod()
                    .environment(model)
            }
            Attachment(id: "pod-view") {
                PendulumsViewPod()
                    .environment(model)
            }
            Attachment(id: "pod-gravity") {
                PendulumsGravityPod()
                    .environment(model)
            }
            Attachment(id: "info") {
                PendulumInfoCard()
                    .environment(model)
                    .padding(12)
                    .glassBackgroundEffect()
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .targetedToAnyEntity()
                .onChanged { value in
                    let hand = SIMD3<Double>(SIMD3<Float>(value.convert(
                        value.location3D, from: .local, to: .scene)))
                    if drag == nil {
                        var current: Entity? = value.entity
                        while let candidate = current {
                            if let id = UUID(uuidString: candidate.name),
                               let pendulum = model.pendulums.first(where: { $0.id == id }) {
                                renderer?.grabbedID = id
                                renderer?.clearTrail()
                                model.beginGrab(id: id)
                                drag = RelativeDrag(
                                    name: candidate.name,
                                    target: pendulum.bobWorld, hand: hand)
                                handSamples = [(Date.timeIntervalSinceReferenceDate,
                                                pendulum.bobWorld)]
                                break
                            }
                            current = candidate.parent
                        }
                    }
                    guard let drag, let id = UUID(uuidString: drag.name) else { return }
                    let world = drag.position(forHand: hand)
                    model.moveGrabbed(id: id, toWorld: world)
                    let now = Date.timeIntervalSinceReferenceDate
                    handSamples.append((now, world))
                    handSamples.removeAll { now - $0.time > 0.14 }
                }
                .onEnded { value in
                    defer {
                        renderer?.grabbedID = nil
                        drag = nil
                        handSamples = []
                    }
                    guard let drag, let id = UUID(uuidString: drag.name) else { return }
                    let hand = SIMD3<Double>(SIMD3<Float>(value.convert(
                        value.location3D, from: .local, to: .scene)))
                    let world = drag.position(forHand: hand)
                    model.moveGrabbed(id: id, toWorld: world)
                    var velocity = SIMD3<Double>.zero
                    let now = Date.timeIntervalSinceReferenceDate
                    if let oldest = handSamples.first, now - oldest.time > 0.02 {
                        velocity = (world - oldest.position) / (now - oldest.time)
                    }
                    model.release(id: id, handVelocity: velocity)
                }
        )
        .gesture(
            TapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    var current: Entity? = value.entity
                    while let candidate = current {
                        if let id = UUID(uuidString: candidate.name) {
                            model.select(id: id)
                            return
                        }
                        current = candidate.parent
                    }
                }
        )
    }

}

/// The bench: add pendulums, load the resonance demo.
struct PendulumsBenchPod: View {
    @Environment(PendulumsModel.self) private var model

    var body: some View {
        ControlPod(title: "Bench", icon: "metronome", tint: DesignTokens.Palette.pendulumsAccent) {
            HStack(spacing: 8) {
                Button {
                    model.addPendulum()
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(DesignTokens.TypeScale.footnote)
                }
                .buttonStyle(.podQuiet)
                .disabled(model.pendulums.count >= PendulumsModel.pendulumBudget)

                Button {
                    model.loadResonancePreset()
                } label: {
                    Label("Resonance ×5", systemImage: "waveform.path")
                        .font(DesignTokens.TypeScale.footnote)
                }
                .buttonStyle(.podQuiet)
            }
        }
    }
}

/// Pause and the swing clock's gears.
struct PendulumsTimePod: View {
    @Environment(PendulumsModel.self) private var model

    private let timeScales: [(String, Double)] = [
        ("¼×", 0.25), ("½×", 0.5), ("1×", 1), ("2×", 2), ("5×", 5), ("20×", 20),
    ]

    var body: some View {
        @Bindable var model = model

        ControlPod(title: "Time", icon: "clock", tint: DesignTokens.Palette.pendulumsAccent, width: 330) {
            HStack(spacing: 5) {
                Button {
                    model.isPaused.toggle()
                } label: {
                    Image(systemName: model.isPaused ? "play.fill" : "pause.fill")
                }
                .buttonStyle(.podQuiet)
                .accessibilityLabel(model.isPaused ? "Resume" : "Pause")

                ForEach(timeScales, id: \.1) { label, scale in
                    Button(label) {
                        model.timeScale = scale
                        model.isPaused = false
                    }
                    .buttonStyle(.podQuiet)
                    .tint(model.timeScale == scale && !model.isPaused ? DesignTokens.Palette.pendulumsAccent : nil)
                    .font(DesignTokens.TypeScale.footnote.monospacedDigit())
                }
            }
        }
    }
}

/// Trails and overlay vectors.
struct PendulumsViewPod: View {
    @Environment(PendulumsModel.self) private var model

    var body: some View {
        @Bindable var model = model

        ControlPod(title: "View", icon: "eye", tint: DesignTokens.Palette.pendulumsAccent, width: 310) {
            Picker("Trail", selection: $model.trailMode) {
                Text("Off").tag(PendulumsModel.TrailMode.off)
                Text("Short").tag(PendulumsModel.TrailMode.short)
                Text("Long").tag(PendulumsModel.TrailMode.long)
                Text("∞").tag(PendulumsModel.TrailMode.infinite)
            }
            .pickerStyle(.segmented)

            HStack(spacing: 10) {
                Toggle("v", isOn: $model.showVelocity)
                Toggle("a", isOn: $model.showAcceleration)
                Toggle("F", isOn: $model.showForces)
                Toggle("E", isOn: $model.showEnergyBars)
            }
            .toggleStyle(.button)
            .font(DesignTokens.TypeScale.footnote)
        }
    }
}

/// The planet knob, plus the live insight line.
struct PendulumsGravityPod: View {
    @Environment(PendulumsModel.self) private var model

    var body: some View {
        @Bindable var model = model

        ControlPod(title: "Gravity", icon: "arrow.down.circle", tint: DesignTokens.Palette.pendulumsAccent) {
            VStack(alignment: .leading, spacing: 4) {
                Text("g = \(model.gravity, specifier: "%.2f") m/s²")
                    .font(DesignTokens.TypeScale.control.monospacedDigit())
                Slider(value: $model.gravity, in: PendulumsModel.gravityRange)
                    .accessibilityLabel("Gravity")
            }
            Toggle("Friction", isOn: $model.frictionOn)
                .font(DesignTokens.TypeScale.control)
                .accessibilityHint("Off: ideal pendulums that swing forever")
            if !model.insightText.isEmpty {
                Text(model.insightText)
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}


/// The card floating above the selected bob: the numbers behind the swing.
struct PendulumInfoCard: View {
    @Environment(PendulumsModel.self) private var model

    var body: some View {
        if let pendulum = model.selected {
            let speed = simd_length(pendulum.state.velocity)
            let angle = pendulum.state.angle(length: pendulum.length)
            let energies = pendulum.state.energies(
                length: pendulum.length, gravity: model.gravity, mass: pendulum.mass)
            VStack(alignment: .leading, spacing: 3) {
                Text("L \(pendulum.length, specifier: "%.2f") m   T \(pendulum.period(gravity: model.gravity), specifier: "%.2f") s")
                    .font(DesignTokens.TypeScale.footnote.monospacedDigit())
                Text("θ \(angle * 180 / .pi, specifier: "%.0f")°   v \(speed, specifier: "%.2f") m/s")
                    .font(DesignTokens.TypeScale.footnote.monospacedDigit())
                Text("KE \(energies.kinetic, specifier: "%.2f") J   PE \(energies.potential, specifier: "%.2f") J")
                    .font(DesignTokens.TypeScale.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
    }
}
