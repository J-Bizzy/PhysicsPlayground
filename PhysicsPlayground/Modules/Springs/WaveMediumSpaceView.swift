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

            let podsRoot = PodMount.makeRoot(module: "elasticfield")
            content.add(podsRoot)
            PodMount.mount(attachments.entity(for: "pod-drive"), name: "Shaker",
                           at: [0.92, 1.42, -0.7], in: podsRoot)
            PodMount.mount(attachments.entity(for: "pod-medium"), name: "Medium",
                           at: [-0.92, 1.28, -0.7], in: podsRoot)

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
            Attachment(id: "pod-drive") {
                WaveDrivePod()
                    .environment(model)
            }
            Attachment(id: "pod-medium") {
                WaveMediumPod()
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

/// The star control: the shaker. Sweep the drive frequency and hunt for
/// the drumhead's resonances — the meter swells and the sheet blooms as
/// you close in, and you can jump straight onto any mode.
struct WaveDrivePod: View {
    @Environment(WaveMediumModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let near = model.nearestResonance()
        ControlPod(title: "Shaker", icon: "waveform.path.ecg", tint: DesignTokens.Palette.springsAccent) {
            Toggle("Drive the drumhead", isOn: $model.driveOn)
                .font(DesignTokens.TypeScale.control)

            VStack(alignment: .leading, spacing: 4) {
                Text("Drive: \(model.driveFrequency, specifier: "%.2f") Hz")
                    .font(DesignTokens.TypeScale.control.monospacedDigit())
                Slider(value: $model.driveFrequency, in: WaveMediumModel.driveFrequencyRange)
                    .accessibilityLabel("Drive frequency")
                    .disabled(!model.driveOn)
            }

            ResonanceMeter(resonance: model.resonance)

            Text("Nearest mode (\(near.mode.m),\(near.mode.p)) rings at \(near.frequency, specifier: "%.2f") Hz")
                .font(DesignTokens.TypeScale.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Jump onto a resonance")
                .font(DesignTokens.TypeScale.footnote)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(WaveMediumModel.drivableModes) { mode in
                    // The mode the drive is parked on wears the accent, so
                    // the row shows where in the spectrum you are.
                    ModeSeekButton(
                        mode: mode,
                        isCurrent: mode == near.mode && abs(near.detune) < 0.02
                    ) { model.seekMode(mode) }
                }
            }
        }
    }
}

/// One resonance in the jump-to row. The mode the drive is parked on
/// fills with the accent; the rest stay quiet glass.
struct ModeSeekButton: View {
    let mode: WaveMediumModel.Mode
    let isCurrent: Bool
    let action: () -> Void

    var body: some View {
        Group {
            if isCurrent {
                Button(mode.label, action: action).buttonStyle(.podProminent)
            } else {
                Button(mode.label, action: action).buttonStyle(.podQuiet)
            }
        }
        .font(DesignTokens.TypeScale.footnote.monospacedDigit())
        .accessibilityLabel("Drive mode \(mode.m), \(mode.p)")
        .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
    }
}

/// A horizontal bar that swells and warms as the sheet rings — the
/// resonance peak made visible.
struct ResonanceMeter: View {
    let resonance: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Resonance")
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(resonance * 100))%")
                    .font(DesignTokens.TypeScale.footnote.monospacedDigit())
                    .foregroundStyle(resonance > 0.6 ? .orange : .secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.secondary.opacity(0.22))
                    Capsule()
                        .fill(LinearGradient(
                            colors: [.teal, .yellow, .red],
                            startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(3, geo.size.width * resonance))
                }
            }
            .frame(height: 9)
            .accessibilityLabel("Resonance \(Int(resonance * 100)) percent")
        }
    }
}

/// The medium's character: how fast waves travel (so where the modes
/// land), how sharply it rings, and what the rim does — plus a one-off
/// strike or a hush.
struct WaveMediumPod: View {
    @Environment(WaveMediumModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ControlPod(title: "Medium", icon: "dial.medium", tint: DesignTokens.Palette.springsAccent) {
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
                    .accessibilityHint("Lower damping makes the resonances sharper and ring longer.")
            }
            Toggle("Clamped rim", isOn: $model.boundaryFixed)
                .font(DesignTokens.TypeScale.control)
                .accessibilityHint("On: a drumhead with fixed edges. Off: free edges the whole sheet can heave over.")

            HStack(spacing: 8) {
                Button {
                    model.centerPluck()
                } label: {
                    Label("Strike", systemImage: "hand.tap.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.podQuiet)
                Button(role: .destructive) {
                    model.flatten()
                } label: {
                    Label("Hush", systemImage: "square")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.podQuiet)
            }
        }
    }
}
