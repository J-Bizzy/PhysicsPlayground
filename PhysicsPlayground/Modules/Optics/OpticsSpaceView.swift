//
//  OpticsSpaceView.swift
//  Physics Playground — Waves & Optics Studio
//
//  The studio's immersive scene: two areas sharing one room. The
//  OPTICS BENCH (rail elements slide axis-projected, the ray fan
//  re-traces instantly, white light disperses through the prism
//  station) and the WAVE LAB (grabbable emitters with Doppler-true
//  crest shells, a walkable interference lattice, the room-scale
//  double slit). One unified drag gesture routes by entity name.
//

import PhysicsCore
import SwiftUI
import RealityKit
import RenderKit
import simd

struct OpticsSpaceView: View {
    @Environment(OpticsModel.self) private var model
    @State private var renderer: OpticsRenderer?
    @State private var waveLab: WaveLabRenderer?
    @State private var drag: RelativeDrag?
    @Environment(AppModel.self) private var appModel

    var body: some View {
        RealityView { content, attachments in
            let renderer = OpticsRenderer()
            content.add(renderer.root)
            let waveLab = WaveLabRenderer()
            waveLab.root.isEnabled = false
            content.add(waveLab.root)

            let podsRoot = PodMount.makeRoot(module: "optics")
            content.add(podsRoot)
            let studioPod = PodMount.mount(
                attachments.entity(for: "pod-studio"), name: "Studio",
                at: [0, 1.98, -0.85], in: podsRoot)
            let benchPod = PodMount.mount(
                attachments.entity(for: "pod-bench"), name: "Bench",
                at: [-1.1, 1.65, -0.8], in: podsRoot)
            let selectedPod = PodMount.mount(
                attachments.entity(for: "pod-selected"), name: "Selected element",
                at: [1.1, 1.55, -0.8], in: podsRoot)
            let prismPod = PodMount.mount(
                attachments.entity(for: "pod-prism"), name: "Prism",
                at: [-1.15, 1.9, -0.85], in: podsRoot)
            let wavePod = PodMount.mount(
                attachments.entity(for: "pod-wave"), name: "Wave lab",
                at: [-1.1, 1.45, -0.75], in: podsRoot)
            let slitPod = PodMount.mount(
                attachments.entity(for: "pod-slit"), name: "Double slit",
                at: [1.1, 1.45, -0.75], in: podsRoot)
            if let info = attachments.entity(for: "info") {
                info.position = [0, 0.02, 0]
                renderer.infoAnchor.addChild(info)
            }

            renderer.subscriptions.append(
                content.subscribe(to: SceneEvents.Update.self) { [weak renderer, weak waveLab] event in
                    model.stepLab(dt: event.deltaTime)
                    let inLab = model.area == .waveLab
                    renderer?.root.isEnabled = !inLab
                    waveLab?.root.isEnabled = inLab
                    if inLab {
                        waveLab?.tick(model)
                    } else {
                        renderer?.tick(model: model)
                    }
                    podsRoot.isEnabled = appModel.controlPodsVisible
                    studioPod?.isEnabled = true
                    benchPod?.isEnabled = !inLab
                    selectedPod?.isEnabled = !inLab
                    prismPod?.isEnabled = !inLab
                    wavePod?.isEnabled = inLab
                    slitPod?.isEnabled = inLab
                    PodMount.persistIfMoved(podsRoot)
                }
            )
            self.renderer = renderer
            self.waveLab = waveLab
        } attachments: {
            Attachment(id: "pod-studio") {
                StudioAreaPod()
                    .environment(model)
            }
            Attachment(id: "pod-bench") {
                OpticsBenchPod()
                    .environment(model)
            }
            Attachment(id: "pod-selected") {
                OpticsSelectedPod()
                    .environment(model)
            }
            Attachment(id: "pod-prism") {
                PrismPod()
                    .environment(model)
            }
            Attachment(id: "pod-wave") {
                WaveLabPod()
                    .environment(model)
            }
            Attachment(id: "pod-slit") {
                DoubleSlitPod()
                    .environment(model)
            }
            Attachment(id: "info") {
                OpticsInfoCard()
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
                        beginDrag(value.entity, hand: hand)
                    }
                    guard let drag else { return }
                    let position = drag.position(forHand: hand)
                    applyDrag(name: drag.name, position: position)
                }
                .onEnded { _ in
                    drag = nil
                    waveLab?.manipulatingEmitterID = nil
                }
        )
        .gesture(
            TapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    var current: Entity? = value.entity
                    while let candidate = current {
                        if let id = UUID(uuidString: candidate.name) {
                            if model.elements.contains(where: { $0.id == id }) {
                                model.select(id: id)
                            } else {
                                model.selectEmitter(id: id)
                            }
                            return
                        }
                        current = candidate.parent
                    }
                }
        )
    }

    private func beginDrag(_ entity: Entity, hand: SIMD3<Double>) {
        var current: Entity? = entity
        while let candidate = current {
            if let id = UUID(uuidString: candidate.name),
               let element = model.elements.first(where: { $0.id == id }) {
                model.select(id: id)
                drag = RelativeDrag(
                    name: candidate.name,
                    target: OpticsModel.center + SIMD3(element.x, 0, 0),
                    hand: hand)
                return
            }
            if let id = UUID(uuidString: candidate.name),
               let emitter = model.emitters.first(where: { $0.id == id }) {
                model.selectEmitter(id: id)
                waveLab?.manipulatingEmitterID = id
                drag = RelativeDrag(name: candidate.name,
                                    target: emitter.position, hand: hand)
                return
            }
            if candidate.name == WaveLabRenderer.barrierName {
                drag = RelativeDrag(
                    name: candidate.name,
                    target: OpticsModel.labCenter + SIMD3(model.rigBarrierX, 0, 0),
                    hand: hand)
                return
            }
            if candidate.name == WaveLabRenderer.screenName {
                drag = RelativeDrag(
                    name: candidate.name,
                    target: OpticsModel.labCenter + SIMD3(model.rigScreenX, 0, 0),
                    hand: hand)
                return
            }
            current = candidate.parent
        }
    }

    private func applyDrag(name: String, position: SIMD3<Double>) {
        if let id = UUID(uuidString: name) {
            if model.elements.contains(where: { $0.id == id }) {
                model.moveElement(id: id, toX: position.x - OpticsModel.center.x)
            } else {
                model.moveEmitter(id: id, toWorld: position)
            }
        } else if name == WaveLabRenderer.barrierName {
            model.moveBarrier(toWorldX: position.x)
        } else if name == WaveLabRenderer.screenName {
            model.moveScreen(toWorldX: position.x)
        }
    }
}

/// The area switch: one studio, two rooms of physics.
struct StudioAreaPod: View {
    @Environment(OpticsModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ControlPod(title: "Studio", icon: "circle.grid.cross",
                   tint: DesignTokens.Palette.opticsAccent, width: 320) {
            Picker("Area", selection: $model.area) {
                Text("Optics bench").tag(OpticsModel.StudioArea.optics)
                Text("Wave lab").tag(OpticsModel.StudioArea.waveLab)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Studio area")
        }
    }
}

/// The dispersion station's one control — and its one revelation.
struct PrismPod: View {
    @Environment(OpticsModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ControlPod(title: "Prism", icon: "triangle",
                   tint: DesignTokens.Palette.opticsAccent) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Rotation: \(model.prismRotationDegrees, specifier: "%.0f")°")
                    .font(DesignTokens.TypeScale.control.monospacedDigit())
                Slider(value: $model.prismRotationDegrees,
                       in: OpticsModel.prismRotationRange)
                    .accessibilityLabel("Prism rotation")
            }
            Text(model.prismShowsTIR
                 ? "The exit face has gone past the critical angle — it's a MIRROR now. That's total internal reflection, the trick inside every optical fiber."
                 : "Blue sees more glass than red (n falls with wavelength), so blue bends more — white light fans into a spectrum. Rotate toward +15° and watch the exit face lock shut.")
                .font(DesignTokens.TypeScale.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The wave lab's controls: the wave, the clock, and the emitters.
struct WaveLabPod: View {
    @Environment(OpticsModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ControlPod(title: "Wave lab", icon: "wave.3.forward",
                   tint: DesignTokens.Palette.waveSource) {
            VStack(alignment: .leading, spacing: 4) {
                Text("f = \(model.labFrequency, specifier: "%.1f") Hz    λ = c/f = \(model.labWavelength * 100, specifier: "%.0f") cm")
                    .font(DesignTokens.TypeScale.control.monospacedDigit())
                Slider(value: $model.labFrequency, in: OpticsModel.labFrequencyRange)
                    .accessibilityLabel("Frequency")
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Wave speed: \(model.labWaveSpeed, specifier: "%.2f") m/s")
                    .font(DesignTokens.TypeScale.control.monospacedDigit())
                Slider(value: $model.labWaveSpeed, in: OpticsModel.labSpeedRange)
                    .accessibilityLabel("Wave speed")
            }
            HStack(spacing: 8) {
                Toggle(isOn: $model.labPaused) {
                    Image(systemName: model.labPaused ? "play.fill" : "pause.fill")
                }
                .toggleStyle(.button)
                .accessibilityLabel(model.labPaused ? "Resume" : "Freeze the room")
                Toggle(isOn: $model.labSlowMotion) {
                    Image(systemName: "tortoise.fill")
                }
                .toggleStyle(.button)
                .accessibilityLabel("Slow motion")
                Button {
                    model.stepLabOneFrame()
                } label: {
                    Image(systemName: "forward.frame.fill")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Step one frame")
                .accessibilityHint("Freezes time and advances one ninetieth of a second")
            }
            if !model.slitRigOn {
                HStack(spacing: 8) {
                    Button {
                        model.addEmitter()
                    } label: {
                        Label("Add", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DesignTokens.Palette.waveSource)
                    .disabled(model.emitters.count >= OpticsModel.emitterBudget)
                    Button {
                        model.duplicateSelectedEmitter()
                    } label: {
                        Image(systemName: "plus.square.on.square")
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.selectedEmitter == nil
                              || model.emitters.count >= OpticsModel.emitterBudget)
                    .accessibilityLabel("Duplicate emitter")
                    Button(role: .destructive) {
                        model.removeSelectedEmitter()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.emitters.count <= 1)
                    .accessibilityLabel("Remove emitter")
                }
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

/// The double slit: the wave lab's marquee experiment.
struct DoubleSlitPod: View {
    @Environment(OpticsModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ControlPod(title: "Double slit", icon: "line.3.horizontal",
                   tint: DesignTokens.Palette.waveSource) {
            Toggle("Slit experiment", isOn: $model.slitRigOn)
                .font(DesignTokens.TypeScale.control)
            if model.slitRigOn {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Slit separation d: \(model.slitSeparation * 100, specifier: "%.0f") cm")
                        .font(DesignTokens.TypeScale.control.monospacedDigit())
                    Slider(value: $model.slitSeparation, in: OpticsModel.slitSeparationRange)
                        .accessibilityLabel("Slit separation")
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Slit width w: \(model.slitWidth * 1000, specifier: "%.0f") mm")
                        .font(DesignTokens.TypeScale.control.monospacedDigit())
                    Slider(value: $model.slitWidth, in: OpticsModel.slitWidthRange)
                        .accessibilityLabel("Slit width")
                }
                Toggle("Ray picture", isOn: $model.showFringeRays)
                    .font(DesignTokens.TypeScale.control)
                    .accessibilityHint("Overlays straight lines from each slit to the bright fringes — geometry and waves agreeing")
                Text("Δy = \(model.fringeSpacing * 100, specifier: "%.1f") cm between bright fringes. Grab the barrier or the screen and slide them; walk between the fringes.")
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The optical bench: add elements, choose the source, read insight.
struct OpticsBenchPod: View {
    @Environment(OpticsModel.self) private var model

    var body: some View {
        @Bindable var model = model

        ControlPod(title: "Bench", icon: "camera.aperture", tint: DesignTokens.Palette.opticsAccent) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 6)], spacing: 6) {
                ForEach(OpticsModel.ElementKind.allCases, id: \.rawValue) { kind in
                    Button(kind.displayName) {
                        model.addElement(kind)
                    }
                    .buttonStyle(.bordered)
                    .font(DesignTokens.TypeScale.footnote)
                    .disabled(model.elements.count >= OpticsModel.elementBudget)
                }
            }
            Picker("Source", selection: $model.sourceMode) {
                Text("Parallel beam").tag(OpticsModel.SourceMode.parallel)
                Text("Point source").tag(OpticsModel.SourceMode.point)
            }
            .pickerStyle(.segmented)
            if !model.insightText.isEmpty {
                Text(model.insightText)
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The selected element's own controls — or a nudge to pick one.
struct OpticsSelectedPod: View {
    @Environment(OpticsModel.self) private var model

    var body: some View {
        ControlPod(title: "Selected", icon: "viewfinder", tint: DesignTokens.Palette.opticsAccent) {
            if let selected = model.selected {
                if selected.kind == .convergingLens || selected.kind == .divergingLens {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Focal length: \(selected.focal * 100, specifier: "%.0f") cm")
                            .font(DesignTokens.TypeScale.control.monospacedDigit())
                        Slider(value: Binding(
                            get: { selected.focal },
                            set: { model.setFocal(id: selected.id, $0) }
                        ), in: OpticsModel.focalRange)
                        .accessibilityLabel("Focal length")
                    }
                }
                Button(role: .destructive) {
                    model.removeSelected()
                } label: {
                    Label("Remove", systemImage: "trash")
                }
                .buttonStyle(.bordered)
            } else {
                Text("Pinch an element on the bench to select it.")
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// The card above the selected element: thin-lens numbers, live.
struct OpticsInfoCard: View {
    @Environment(OpticsModel.self) private var model

    var body: some View {
        if let element = model.selected {
            VStack(alignment: .leading, spacing: 3) {
                Text(element.kind.displayName)
                    .font(DesignTokens.TypeScale.sectionHeader)
                if let prediction = model.imagePrediction,
                   element.kind == .convergingLens || element.kind == .divergingLens {
                    Text("dₒ \(prediction.objectDistance * 100, specifier: "%.0f") cm   dᵢ \(prediction.imageDistance * 100, specifier: "%+.0f") cm")
                        .font(DesignTokens.TypeScale.footnote.monospacedDigit())
                    Text("m \(prediction.magnification, specifier: "%+.2f")\(prediction.imageDistance < 0 ? "   (virtual image)" : "")")
                        .font(DesignTokens.TypeScale.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else if element.kind == .mirror {
                    Text("Folds the bench — equal angles in and out")
                        .font(DesignTokens.TypeScale.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}
