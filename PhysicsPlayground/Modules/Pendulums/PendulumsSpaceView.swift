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
    @State private var router = ManipulationRouter()
    @State private var handSamples: [(time: Double, position: SIMD3<Double>)] = []

    var body: some View {
        RealityView { content, attachments in
            let renderer = PendulumsRenderer()
            content.add(renderer.root)

            if let quick = attachments.entity(for: "quick") {
                quick.position = [-1.35, 1.35, -0.85]
                quick.orientation = simd_quatf(angle: 0.3, axis: [0, 1, 0])
                renderer.root.addChild(quick)
            }
            if let info = attachments.entity(for: "info") {
                info.position = [0, 0.02, 0]
                renderer.infoAnchor.addChild(info)
            }

            configureRouter(renderer: renderer)
            renderer.subscriptions = router.subscriptions(for: content)
            renderer.subscriptions.append(
                content.subscribe(to: SceneEvents.Update.self) { [weak renderer] event in
                    renderer?.tick(dt: event.deltaTime, model: model)
                }
            )
            self.renderer = renderer
        } attachments: {
            Attachment(id: "quick") {
                PendulumsQuickPanel()
                    .environment(model)
                    .padding(18)
                    .frame(width: 340)
                    .glassBackgroundEffect()
            }
            Attachment(id: "info") {
                PendulumInfoCard()
                    .environment(model)
                    .padding(12)
                    .glassBackgroundEffect()
            }
        }
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

    private func configureRouter(renderer: PendulumsRenderer) {
        router.onBegin = { [weak renderer] name, position in
            guard let id = UUID(uuidString: name) else { return }
            renderer?.grabbedID = id
            model.beginGrab(id: id)
            handSamples = [(Date.timeIntervalSinceReferenceDate, SIMD3<Double>(position))]
        }
        router.onMove = { name, position in
            guard let id = UUID(uuidString: name) else { return }
            let world = SIMD3<Double>(position)
            model.moveGrabbed(id: id, toWorld: world)
            let now = Date.timeIntervalSinceReferenceDate
            handSamples.append((now, world))
            handSamples.removeAll { now - $0.time > 0.14 }
        }
        router.onEnd = { [weak renderer] name, position in
            guard let id = UUID(uuidString: name) else { return }
            let world = SIMD3<Double>(position)
            model.moveGrabbed(id: id, toWorld: world)
            // Release velocity: displacement over the sample window.
            var velocity = SIMD3<Double>.zero
            let now = Date.timeIntervalSinceReferenceDate
            if let oldest = handSamples.first, now - oldest.time > 0.02 {
                velocity = (world - oldest.position) / (now - oldest.time)
            }
            model.release(id: id, handVelocity: velocity)
            renderer?.grabbedID = nil
            handSamples = []
        }
    }
}

/// The floating panel: time, trails, vectors, and the pendulum bench.
struct PendulumsQuickPanel: View {
    @Environment(PendulumsModel.self) private var model

    private let timeScales: [(String, Double)] = [
        ("¼×", 0.25), ("½×", 0.5), ("1×", 1), ("2×", 2), ("5×", 5), ("20×", 20),
    ]

    var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Button {
                    model.addPendulum()
                } label: {
                    Label("Add pendulum", systemImage: "plus")
                        .font(DesignTokens.TypeScale.footnote)
                }
                .buttonStyle(.bordered)
                .disabled(model.pendulums.count >= PendulumsModel.pendulumBudget)

                Button {
                    model.loadResonancePreset()
                } label: {
                    Label("Resonance ×5", systemImage: "waveform.path")
                        .font(DesignTokens.TypeScale.footnote)
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 5) {
                Button {
                    model.isPaused.toggle()
                } label: {
                    Image(systemName: model.isPaused ? "play.fill" : "pause.fill")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(model.isPaused ? "Resume" : "Pause")

                ForEach(timeScales, id: \.1) { label, scale in
                    Button(label) {
                        model.timeScale = scale
                        model.isPaused = false
                    }
                    .buttonStyle(.bordered)
                    .tint(model.timeScale == scale && !model.isPaused ? .indigo : nil)
                    .font(DesignTokens.TypeScale.footnote.monospacedDigit())
                }
            }

            Picker("Trail", selection: $model.trailMode) {
                Text("No trail").tag(PendulumsModel.TrailMode.off)
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

            VStack(alignment: .leading, spacing: 6) {
                Text("Gravity: \(model.gravity, specifier: "%.2f") m/s²")
                    .font(DesignTokens.TypeScale.label.monospacedDigit())
                Slider(value: $model.gravity, in: PendulumsModel.gravityRange)
                    .accessibilityLabel("Gravity")
            }

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
