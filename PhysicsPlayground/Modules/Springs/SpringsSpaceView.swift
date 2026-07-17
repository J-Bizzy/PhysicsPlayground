//
//  SpringsSpaceView.swift
//  Physics Playground — Springs module
//
//  The spring lab immersive scene. Blocks route through the
//  ManipulationRouter constrained to the rail axis: pulling stretches
//  the helix live, release launches with the hand's along-rail
//  velocity. The panel switches single/coupled mode, graph channel,
//  and time scale.
//

import PhysicsCore
import SwiftUI
import RealityKit
import RenderKit
import simd

struct SpringsSpaceView: View {
    @Environment(SpringsModel.self) private var model
    @State private var renderer: SpringsRenderer?
    @State private var router = ManipulationRouter()
    @State private var handSamples: [(time: Double, position: SIMD3<Double>)] = []

    var body: some View {
        RealityView { content, attachments in
            let renderer = SpringsRenderer()
            content.add(renderer.root)

            if let quick = attachments.entity(for: "quick") {
                quick.position = [-1.35, 1.35, -0.75]
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
                SpringsQuickPanel()
                    .environment(model)
                    .padding(18)
                    .frame(width: 340)
                    .glassBackgroundEffect()
            }
            Attachment(id: "info") {
                SpringInfoCard()
                    .environment(model)
                    .padding(12)
                    .glassBackgroundEffect()
            }
        }
    }

    private func blockIndex(from name: String) -> Int? {
        guard name.hasPrefix("s-block-") else { return nil }
        return Int(name.dropFirst(8))
    }

    private func configureRouter(renderer: SpringsRenderer) {
        router.onBegin = { [weak renderer] name, position in
            guard let index = blockIndex(from: name) else { return }
            renderer?.grabbedBlock = index
            model.beginGrab(block: index)
            handSamples = [(Date.timeIntervalSinceReferenceDate, SIMD3<Double>(position))]
        }
        router.onMove = { name, position in
            guard blockIndex(from: name) != nil else { return }
            model.moveGrabbed(toWorld: SIMD3<Double>(position))
            let now = Date.timeIntervalSinceReferenceDate
            handSamples.append((now, SIMD3<Double>(position)))
            handSamples.removeAll { now - $0.time > 0.14 }
        }
        router.onEnd = { [weak renderer] name, position in
            guard blockIndex(from: name) != nil else { return }
            let world = SIMD3<Double>(position)
            model.moveGrabbed(toWorld: world)
            // Release speed along the motion axis only.
            var velocity = 0.0
            let now = Date.timeIntervalSinceReferenceDate
            if let oldest = handSamples.first, now - oldest.time > 0.02 {
                let handVelocity = (world - oldest.position) / (now - oldest.time)
                velocity = simd_dot(handVelocity, model.axisDirection)
            }
            model.release(handVelocityX: velocity)
            renderer?.grabbedBlock = nil
            handSamples = []
        }
    }
}

/// Floating panel: mode, graph channel, time, parameters.
struct SpringsQuickPanel: View {
    @Environment(SpringsModel.self) private var model

    private let timeScales: [(String, Double)] = [
        ("¼×", 0.25), ("½×", 0.5), ("1×", 1), ("2×", 2), ("5×", 5),
    ]

    var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Button("Single spring") { model.setMode(.single) }
                    .buttonStyle(.bordered)
                    .tint(model.mode == .single ? .teal : nil)
                Button("Coupled ×2") { model.setMode(.coupled) }
                    .buttonStyle(.bordered)
                    .tint(model.mode == .coupled ? .teal : nil)
            }
            .font(DesignTokens.TypeScale.footnote)

            HStack(spacing: 8) {
                Button {
                    model.setOrientation(.horizontal)
                } label: {
                    Label("Rail", systemImage: "arrow.left.and.right")
                }
                .buttonStyle(.bordered)
                .tint(model.orientation == .horizontal ? .teal : nil)
                Button {
                    model.setOrientation(.vertical)
                } label: {
                    Label("Hanging", systemImage: "arrow.down")
                }
                .buttonStyle(.bordered)
                .tint(model.orientation == .vertical ? .teal : nil)
                .disabled(model.mode == .coupled)
            }
            .font(DesignTokens.TypeScale.footnote)

            HStack(spacing: 5) {
                Button {
                    model.isPaused.toggle()
                } label: {
                    Image(systemName: model.isPaused ? "play.fill" : "pause.fill")
                }
                .buttonStyle(.bordered)
                ForEach(timeScales, id: \.1) { label, scale in
                    Button(label) {
                        model.timeScale = scale
                        model.isPaused = false
                    }
                    .buttonStyle(.bordered)
                    .tint(model.timeScale == scale && !model.isPaused ? .teal : nil)
                    .font(DesignTokens.TypeScale.footnote.monospacedDigit())
                }
            }

            Picker("Graph", selection: $model.graphMode) {
                Text("x·t").tag(SpringsModel.GraphMode.position)
                Text("v·t").tag(SpringsModel.GraphMode.velocity)
                Text("a·t").tag(SpringsModel.GraphMode.acceleration)
                Text("E·t").tag(SpringsModel.GraphMode.energy)
            }
            .pickerStyle(.segmented)

            HStack(spacing: 10) {
                Toggle("v", isOn: $model.showVelocity)
                Toggle("a", isOn: $model.showAcceleration)
                Toggle("F", isOn: $model.showForce)
                Toggle("E", isOn: $model.showEnergyBars)
            }
            .toggleStyle(.button)
            .font(DesignTokens.TypeScale.footnote)

            slider("Stiffness k", $model.stiffness,
                   SpringsModel.stiffnessRange, "%.0f N/m")
            slider("Mass", $model.mass, SpringsModel.massRange, "%.1f kg")
            slider("Damping", $model.damping, SpringsModel.dampingRange, "%.2f N·s/m")
            if model.orientation == .horizontal {
                Toggle("Gravity along the rail", isOn: $model.gravityOn)
                    .font(DesignTokens.TypeScale.footnote)
            } else {
                Text("Hanging: equilibrium sags mg/k = \(String(format: "%.1f", model.equilibriumSag * 100)) cm")
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
            }

            if !model.insightText.isEmpty {
                Text(model.insightText)
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func slider(_ label: String, _ value: Binding<Double>,
                        _ range: ClosedRange<Double>, _ format: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(label): \(String(format: format, value.wrappedValue))")
                .font(DesignTokens.TypeScale.control.monospacedDigit())
            Slider(value: value, in: range)
                .accessibilityLabel(label)
        }
    }
}

/// The card floating above the block.
struct SpringInfoCard: View {
    @Environment(SpringsModel.self) private var model

    var body: some View {
        let displacement = model.mode == .single
            ? model.state.displacement : model.coupled.displacements.x
        let velocity = model.mode == .single
            ? model.state.velocity : model.coupled.velocities.x
        let energies = model.energies()
        VStack(alignment: .leading, spacing: 3) {
            Text("x \(displacement * 100, specifier: "%+.1f") cm   v \(velocity, specifier: "%+.2f") m/s")
                .font(DesignTokens.TypeScale.footnote.monospacedDigit())
            Text("F \(model.springForce, specifier: "%+.1f") N   T \(model.period, specifier: "%.2f") s   f \(model.frequency, specifier: "%.2f") Hz")
                .font(DesignTokens.TypeScale.footnote.monospacedDigit())
            if model.mode == .single {
                Text("KE \(energies.kinetic, specifier: "%.2f") J   PE \(energies.potential, specifier: "%.2f") J")
                    .font(DesignTokens.TypeScale.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
