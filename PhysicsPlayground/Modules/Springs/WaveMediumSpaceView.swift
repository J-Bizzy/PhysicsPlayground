//
//  WaveMediumSpaceView.swift
//  Physics Playground — Elastic Field (Springs module)
//
//  The membrane immersive scene. The star is direct manipulation:
//  reach into the sheet, pinch, and pull any point — the medium
//  follows your hand and, on release, the disturbance ripples out
//  live. Small pods off to the sides tune the medium (wave speed,
//  damping, boundary) and offer instant setups (pluck, ring a mode),
//  never getting between you and the sheet.
//

import PhysicsCore
import SwiftUI
import RealityKit
import RenderKit
import simd

struct WaveMediumSpaceView: View {
    @Environment(WaveMediumModel.self) private var model
    @State private var renderer: WaveMediumRenderer?
    @State private var grabbing = false
    @Environment(AppModel.self) private var appModel

    var body: some View {
        RealityView { content, attachments in
            let renderer = WaveMediumRenderer()
            content.add(renderer.root)

            let podsRoot = PodMount.makeRoot(module: "springs")
            content.add(podsRoot)
            PodMount.mount(attachments.entity(for: "pod-medium"), name: "Medium",
                           at: [-1.05, 1.3, -0.5], in: podsRoot)
            PodMount.mount(attachments.entity(for: "pod-modes"), name: "Setups",
                           at: [1.05, 1.3, -0.5], in: podsRoot)

            renderer.subscriptions.append(
                content.subscribe(to: SceneEvents.Update.self) { [weak renderer] event in
                    renderer?.tick(dt: event.deltaTime, model: model)
                    podsRoot.isEnabled = appModel.controlPodsVisible
                    PodMount.persistIfMoved(podsRoot)
                }
            )
            self.renderer = renderer
        } attachments: {
            Attachment(id: "pod-medium") {
                WaveMediumPod()
                    .environment(model)
            }
            Attachment(id: "pod-modes") {
                WaveMediumSetupPod()
                    .environment(model)
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .targetedToAnyEntity()
                .onChanged { value in
                    let hand = SIMD3<Double>(SIMD3<Float>(value.convert(
                        value.location3D, from: .local, to: .scene)))
                    if !grabbing {
                        // Only the sheet is grabbable.
                        var current: Entity? = value.entity
                        while let candidate = current {
                            if candidate.name == WaveMediumRenderer.surfaceName {
                                model.grab(atWorld: hand)
                                grabbing = true
                                break
                            }
                            current = candidate.parent
                        }
                    } else {
                        model.moveHeld(toWorld: hand)
                    }
                }
                .onEnded { _ in
                    if grabbing { model.release() }
                    grabbing = false
                }
        )
    }
}

/// The medium's character: how fast waves travel, how fast they fade,
/// and what the rim does.
struct WaveMediumPod: View {
    @Environment(WaveMediumModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ControlPod(title: "Medium", icon: "waveform.path", tint: DesignTokens.Palette.springsAccent) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Wave speed c = \(model.waveSpeed, specifier: "%.1f") m/s")
                    .font(DesignTokens.TypeScale.control.monospacedDigit())
                Slider(value: $model.waveSpeed, in: WaveMediumModel.waveSpeedRange)
                    .accessibilityLabel("Wave speed")
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Damping: \(model.damping, specifier: "%.2f")")
                    .font(DesignTokens.TypeScale.control.monospacedDigit())
                Slider(value: $model.damping, in: WaveMediumModel.dampingRange)
                    .accessibilityLabel("Damping")
            }
            Toggle("Clamped rim", isOn: $model.boundaryFixed)
                .font(DesignTokens.TypeScale.control)
                .accessibilityHint("On: a drumhead with fixed edges. Off: free edges the whole sheet can heave over.")
            if !model.insightText.isEmpty {
                Text(model.insightText)
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Instant setups: strike it, or ring a pure mode.
struct WaveMediumSetupPod: View {
    @Environment(WaveMediumModel.self) private var model

    var body: some View {
        ControlPod(title: "Setups", icon: "circle.grid.2x2", tint: DesignTokens.Palette.springsAccent) {
            Button {
                model.centerPluck()
            } label: {
                Label("Strike the center", systemImage: "hand.point.up.left.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignTokens.Palette.springsAccent)

            Text("Ring a standing mode")
                .font(DesignTokens.TypeScale.footnote)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach([(1, 1), (2, 1), (2, 2), (3, 2)], id: \.0) { mode in
                    Button("\(mode.0),\(mode.1)") {
                        model.ringMode(m: mode.0, p: mode.1)
                    }
                    .buttonStyle(.bordered)
                    .font(DesignTokens.TypeScale.footnote.monospacedDigit())
                }
            }

            Button(role: .destructive) {
                model.flatten()
            } label: {
                Label("Still", systemImage: "square")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }
}
