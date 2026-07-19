//
//  GravityLabSpaceView.swift
//  Physics Playground — Gravity Lab module
//
//  The orbital mechanics immersive scene. Every celestial body is
//  grabbable: holding one freezes it (it keeps attracting the others)
//  and shows the orbit it would get if released now; releasing applies
//  the hand's velocity. The floating data panel follows the selected
//  body; the time panel floats by the platform.
//

import PhysicsCore
import SwiftUI
import RealityKit
import RenderKit

struct GravityLabSpaceView: View {
    @Environment(GravityLabModel.self) private var model
    @State private var renderer: GravityLabRenderer?
    @State private var drag: RelativeDrag?
    @Environment(AppModel.self) private var appModel

    var body: some View {
        RealityView { content, attachments in
            let renderer = GravityLabRenderer()
            content.add(renderer.root)

            let podsRoot = PodMount.makeRoot(module: "gravitylab")
            renderer.root.addChild(podsRoot)
            PodMount.mount(attachments.entity(for: "pod-time"), name: "Time",
                           at: [0, 1.14, -1.05], in: podsRoot)
            PodMount.mount(attachments.entity(for: "pod-bodies"), name: "Bodies",
                           at: [-1.1, 1.62, -0.9], in: podsRoot)
            PodMount.mount(attachments.entity(for: "pod-view"), name: "View",
                           at: [1.1, 1.6, -0.9], in: podsRoot)
            if let data = attachments.entity(for: "data") {
                data.position = [0, 0.05, 0]
                renderer.selectedAnchor.addChild(data)
            }

            renderer.subscriptions.append(
                content.subscribe(to: SceneEvents.Update.self) { [weak renderer] event in
                    model.step(dt: event.deltaTime)
                    renderer?.tick(model)
                    // Separate from the tick so the field keeps flowing
                    // even while the simulation is paused.
                    renderer?.tickFieldParticles(dt: event.deltaTime, model: model)
                    podsRoot.isEnabled = appModel.controlPodsVisible
                    PodMount.persistIfMoved(podsRoot)
                }
            )

            renderer.tick(model)
            self.renderer = renderer
        } attachments: {
            Attachment(id: "pod-time") {
                ControlPod(title: "Time", icon: "clock",
                           tint: DesignTokens.Palette.gravityAccent, width: 460) {
                    GravityLabTimePanel()
                        .environment(model)
                }
            }
            Attachment(id: "pod-bodies") {
                GravityBodiesPod()
                    .environment(model)
            }
            Attachment(id: "pod-view") {
                GravityViewPod()
                    .environment(model)
            }
            Attachment(id: "data") {
                GravityLabDataPanel(compact: true)
                    .environment(model)
                    .padding(16)
                    .frame(width: 300)
                    .glassBackgroundEffect()
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .targetedToAnyEntity()
                .onChanged { value in
                    guard let renderer else { return }
                    let hand = renderer.displayPoint(fromWorld: SIMD3<Float>(value.convert(
                        value.location3D, from: .local, to: .scene)))
                    if drag == nil {
                        var current: Entity? = value.entity
                        while let candidate = current {
                            if let id = UUID(uuidString: candidate.name),
                               let body = model.bodies.first(where: { $0.id == id }) {
                                let target = body.body.position * model.simToDisplay
                                drag = RelativeDrag(
                                    name: candidate.name, target: target, hand: hand)
                                model.grab(id: id, at: target)
                                break
                            }
                            current = candidate.parent
                        }
                    }
                    guard let drag, let id = UUID(uuidString: drag.name) else { return }
                    model.hold(id: id, at: drag.position(forHand: hand))
                }
                .onEnded { value in
                    defer { drag = nil }
                    guard let renderer, let drag,
                          let id = UUID(uuidString: drag.name) else { return }
                    let hand = renderer.displayPoint(fromWorld: SIMD3<Float>(value.convert(
                        value.location3D, from: .local, to: .scene)))
                    model.hold(id: id, at: drag.position(forHand: hand))
                    model.release(id: id)
                }
        )
    }

}

/// Pause / play and the 1–100× time scale, plus the simulation clock.
struct GravityLabTimePanel: View {
    @Environment(GravityLabModel.self) private var model

    var body: some View {
        @Bindable var model = model

        HStack(spacing: 14) {
            Button {
                model.isPaused.toggle()
            } label: {
                Image(systemName: model.isPaused ? "play.fill" : "pause.fill")
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(model.isPaused ? "Resume time" : "Pause time")

            Picker("Speed", selection: $model.timeScale) {
                ForEach(GravityLabModel.timeScales, id: \.self) { scale in
                    Text("\(Int(scale))×").tag(scale)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 240)
            .accessibilityLabel("Time scale")

            Text(clockText)
                .font(DesignTokens.TypeScale.label.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .trailing)
                .accessibilityLabel("Simulated time: \(clockText)")
        }
    }

    private var clockText: String {
        let days = model.simulatedDays
        return days < 400
            ? String(format: "%.0f days", days)
            : String(format: "%.2f years", days / 365.25)
    }
}

/// Spawn planets onto their real orbits without leaving the system.
struct GravityBodiesPod: View {
    @Environment(GravityLabModel.self) private var model

    var body: some View {
        ControlPod(title: "Bodies", icon: "plus.circle",
                   tint: DesignTokens.Palette.gravityAccent, width: 316) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 6)], spacing: 6) {
                ForEach(GravityLabModel.Preset.allCases) { preset in
                    Button(preset.displayName) {
                        model.spawn(preset)
                    }
                    .buttonStyle(.bordered)
                    .font(DesignTokens.TypeScale.footnote)
                    .disabled(model.bodies.count >= GravityLabModel.bodyBudget
                              || model.mode == .lagrange)
                    .accessibilityLabel("Spawn \(preset.displayName) on its real orbit")
                }
            }
            HStack(spacing: 8) {
                Button(role: .destructive) {
                    model.removeSelected()
                } label: {
                    Image(systemName: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(model.selectedBody == nil
                          || model.selectedBody?.id == model.primaryBody?.id)
                .accessibilityLabel("Remove selected body")

                if model.mode == .solarSystem, model.hasSingleSun {
                    Button {
                        model.makeBinary()
                    } label: {
                        Label("Twin suns", systemImage: "circle.grid.2x1.fill")
                            .font(DesignTokens.TypeScale.footnote)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DesignTokens.Palette.gravityAccent)
                    .disabled(model.bodies.count >= GravityLabModel.bodyBudget)
                    .accessibilityHint("Splits the Sun into a binary pair — mass and momentum conserved")
                }
            }
            Text("\(model.bodies.count) of \(GravityLabModel.bodyBudget) bodies — grab any of them.")
                .font(DesignTokens.TypeScale.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

/// Trails, vectors, and the two field pictures.
struct GravityViewPod: View {
    @Environment(GravityLabModel.self) private var model

    var body: some View {
        @Bindable var model = model

        ControlPod(title: "View", icon: "eye",
                   tint: DesignTokens.Palette.gravityAccent, width: 280) {
            Picker("Trails", selection: $model.trailLength) {
                ForEach(GravityLabModel.TrailLength.allCases) { length in
                    Text(length.rawValue.capitalized).tag(length)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Trail length")

            HStack(spacing: 10) {
                Toggle("v", isOn: $model.showVelocityVector)
                Toggle("a", isOn: $model.showAccelerationVector)
                Toggle("F", isOn: $model.showForceVector)
            }
            .toggleStyle(.button)
            .font(DesignTokens.TypeScale.footnote)

            Toggle("Field particles", isOn: $model.showFieldParticles)
                .font(DesignTokens.TypeScale.control)
                .accessibilityHint("Particles drifting along the true local field")
            Toggle("Spacetime grid", isOn: $model.showSpacetimeGrid)
                .font(DesignTokens.TypeScale.control)
                .accessibilityHint("The rubber-sheet picture — an analogy, not the simulation")
        }
    }
}
