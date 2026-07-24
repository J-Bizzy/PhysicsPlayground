//
//  OpticsSpaceView.swift
//  Physics Playground — Optics Studio
//
//  One room, three stations, separated by DIRECTION so nothing ever
//  stacks in view: the thin-lens bench dead ahead, the dispersion
//  station on the left wall, the refraction corner on the right —
//  where a hand-held laser always aims at the glass block, so
//  carrying it around IS the incidence-angle control. One unified
//  drag gesture routes by entity name; bench elements stay
//  axis-projected, the laser and block move freely in 3D.
//

import PhysicsCore
import SwiftUI
import RealityKit
import RenderKit
import simd

struct OpticsSpaceView: View {
    @Environment(OpticsModel.self) private var model
    @State private var renderer: OpticsRenderer?
    @State private var drag: RelativeDrag?
    @State private var dialDrag: DialDrag?
    @Environment(AppModel.self) private var appModel

    var body: some View {
        RealityView { content, attachments in
            let renderer = OpticsRenderer()
            content.add(renderer.root)

            let podsRoot = PodMount.makeRoot(module: "optics")
            content.add(podsRoot)
            // Every pod hangs ABOVE its own station, never in front of
            // one: bench pods flank the beam, the prism pod tops the
            // left wall, the glass pod tops the right corner.
            PodMount.mount(attachments.entity(for: "pod-bench"), name: "Bench",
                           at: [-0.55, 1.85, -1.0], in: podsRoot)
            PodMount.mount(attachments.entity(for: "pod-selected"), name: "Selected element",
                           at: [0.55, 1.85, -1.0], in: podsRoot)
            if let info = attachments.entity(for: "info") {
                info.position = [0, 0.02, 0]
                renderer.infoAnchor.addChild(info)
            }

            renderer.subscriptions.append(
                content.subscribe(to: SceneEvents.Update.self) { [weak renderer] _ in
                    renderer?.tick(model: model)
                    podsRoot.isEnabled = appModel.controlPodsVisible
                    PodMount.persistIfMoved(podsRoot)
                }
            )
            self.renderer = renderer
        } attachments: {
            Attachment(id: "pod-bench") {
                OpticsBenchPod()
                    .environment(model)
            }
            Attachment(id: "pod-selected") {
                OpticsSelectedPod()
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
                    if drag == nil, dialDrag == nil {
                        beginDrag(value.entity, hand: hand)
                    }
                    // A dial twist wins if one is engaged.
                    if var dial = dialDrag, let renderer,
                       let spatial = renderer.dials.first(where: { $0.name == dial.name }) {
                        let newValue = dial.advance(toAngle: spatial.handAngle(hand))
                        dialDrag = dial
                        applyDial(name: dial.name, value: newValue)
                        return
                    }
                    guard let drag else { return }
                    let position = drag.position(forHand: hand)
                    applyDrag(name: drag.name, position: position)
                }
                .onEnded { _ in
                    drag = nil
                    dialDrag = nil
                }
        )
        .gesture(
            TapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    var current: Entity? = value.entity
                    while let candidate = current {
                        if let id = UUID(uuidString: candidate.name),
                           model.elements.contains(where: { $0.id == id }) {
                            model.select(id: id)
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
            if let renderer, let dial = renderer.dials.first(where: { $0.name == candidate.name }) {
                dialDrag = DialDrag(
                    name: dial.name, startValue: dialStartValue(dial.name),
                    startAngle: dial.handAngle(hand), range: dialRange(dial.name))
                return
            }
            if let id = UUID(uuidString: candidate.name),
               let element = model.elements.first(where: { $0.id == id }) {
                model.select(id: id)
                drag = RelativeDrag(
                    name: candidate.name,
                    target: OpticsModel.center + SIMD3(element.x, 0, 0),
                    hand: hand)
                return
            }
            if candidate.name == OpticsRenderer.laserName {
                drag = RelativeDrag(name: candidate.name,
                                    target: model.laserPosition, hand: hand)
                return
            }
            if candidate.name == OpticsRenderer.blockName {
                drag = RelativeDrag(name: candidate.name,
                                    target: model.blockCenter, hand: hand)
                return
            }
            current = candidate.parent
        }
    }

    private func applyDrag(name: String, position: SIMD3<Double>) {
        if let id = UUID(uuidString: name) {
            model.moveElement(id: id, toX: position.x - OpticsModel.center.x)
        } else if name == OpticsRenderer.laserName {
            model.moveLaser(toWorld: position)
        } else if name == OpticsRenderer.blockName {
            model.moveBlock(toWorld: position)
        }
    }

    private func dialRange(_ name: String) -> ClosedRange<Double> {
        switch name {
        case "dial-prism": OpticsModel.prismRotationRange
        case "dial-index": OpticsModel.blockIndexRange
        default: OpticsModel.focalRange
        }
    }

    private func dialStartValue(_ name: String) -> Double {
        switch name {
        case "dial-prism": model.prismRotationDegrees
        case "dial-index": model.blockIndex
        default: model.selected?.focal ?? 0.25
        }
    }

    private func applyDial(name: String, value: Double) {
        switch name {
        case "dial-prism": model.prismRotationDegrees = value
        case "dial-index": model.blockIndex = value
        default:
            if let lens = model.selected { model.setFocal(id: lens.id, value) }
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
                    .buttonStyle(.podQuiet)
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
                    Text("Twist the blue focal dial above the lens to change f.")
                        .font(DesignTokens.TypeScale.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button(role: .destructive) {
                    model.removeSelected()
                } label: {
                    Label("Remove", systemImage: "trash")
                }
                .buttonStyle(.podQuiet)
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
