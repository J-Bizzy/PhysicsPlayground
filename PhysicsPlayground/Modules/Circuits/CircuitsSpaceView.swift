//
//  CircuitsSpaceView.swift
//  Physics Playground — Circuits module
//
//  The circuit lab immersive scene. Component bodies route through
//  RenderKit's ManipulationRouter (grab to carry anywhere); terminals,
//  wires, and switch levers are tap targets — pinch a terminal, then
//  another, and they're wired; pinch a wire to remove it; pinch a
//  lever to flip it. The solver clock is SceneEvents.Update.
//

import PhysicsCore
import SwiftUI
import RealityKit
import RenderKit

struct CircuitsSpaceView: View {
    @Environment(CircuitsModel.self) private var model
    @State private var renderer: CircuitsRenderer?
    @State private var wireDragFrom: CircuitsModel.Terminal?
    @State private var partDrag: RelativeDrag?
    @State private var trayDragID: UUID?
    @State private var gripDrag: (grip: CircuitsModel.Terminal, pivot: SIMD3<Double>)?
    @Environment(AppModel.self) private var appModel

    var body: some View {
        RealityView { content, attachments in
            let renderer = CircuitsRenderer()
            content.add(renderer.root)

            // Control pods: build helpers on the left near the tray,
            // bench status on the right — the tray itself is the
            // spatial way to add parts.
            let podsRoot = PodMount.makeRoot(module: "circuits")
            renderer.root.addChild(podsRoot)
            PodMount.mount(attachments.entity(for: "pod-presets"), name: "Premade circuits",
                           at: [-1.1, 1.7, -0.9], in: podsRoot)
            PodMount.mount(attachments.entity(for: "pod-saved"), name: "Saved circuits",
                           at: [-1.25, 1.12, -0.72], in: podsRoot)
            PodMount.mount(attachments.entity(for: "pod-bench"), name: "Bench",
                           at: [1.12, 1.5, -0.85], in: podsRoot)
            if let readout = attachments.entity(for: "info") {
                readout.position = [0, 0.02, 0]
                renderer.selectedAnchor.addChild(readout)
            }

            renderer.subscriptions.append(
                content.subscribe(to: SceneEvents.Update.self) { [weak renderer] event in
                    podsRoot.isEnabled = appModel.controlPodsVisible
                    PodMount.persistIfMoved(podsRoot)
                    model.step(dt: event.deltaTime)
                    // Rendered here every frame (not via the observation
                    // loop): a steady DC circuit mutates nothing that
                    // observation reliably re-fires on, but its electrons
                    // must keep drifting.
                    renderer?.tick(dt: event.deltaTime, model: model)
                }
            )

            self.renderer = renderer
        } attachments: {
            Attachment(id: "pod-presets") {
                CircuitPresetsPod()
                    .environment(model)
            }
            Attachment(id: "pod-saved") {
                CircuitSavedPod()
                    .environment(model)
            }
            Attachment(id: "pod-bench") {
                CircuitBenchPod()
                    .environment(model)
            }
            Attachment(id: "info") {
                CircuitsSelectedReadout()
                    .environment(model)
                    .padding(12)
                    .glassBackgroundEffect()
            }
        }
        .gesture(
            TapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    handleTap(on: value.entity)
                }
        )
        // One drag gesture, four grabs — all relative, nothing lurches
        // toward the hand: a terminal pulls a live wire; an end grip
        // aims/stretches its part; a tray template spawns a copy that
        // follows the hand's displacement; a part body carries the
        // part. Tap-tap wiring still works too.
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .targetedToAnyEntity()
                .onChanged { value in
                    guard let renderer else { return }
                    let handF = SIMD3<Float>(value.convert(
                        value.location3D, from: .local, to: .scene))
                    let hand = SIMD3<Double>(handF)
                    if wireDragFrom == nil, partDrag == nil {
                        beginCircuitDrag(entity: value.entity, hand: hand, renderer: renderer)
                    }
                    if let source = wireDragFrom,
                       let sourceComponent = model.components.first(
                         where: { $0.id == source.componentID }) {
                        let target = nearestTerminal(to: handF, excluding: source)
                        renderer.rubberTargetTerminal = target?.terminal
                        renderer.showRubberBand(
                            from: SIMD3<Float>(sourceComponent.terminalPosition(source.end)),
                            to: target.map { SIMD3<Float>($0.position) } ?? handF)
                    } else if let partDrag {
                        applyCircuitDrag(partDrag, hand: hand)
                    }
                }
                .onEnded { value in
                    defer {
                        renderer?.hideRubberBand()
                        renderer?.previewComponentID = nil
                        wireDragFrom = nil
                        partDrag = nil
                        trayDragID = nil
                        gripDrag = nil
                    }
                    guard let renderer else { return }
                    let handF = SIMD3<Float>(value.convert(
                        value.location3D, from: .local, to: .scene))
                    let hand = SIMD3<Double>(handF)
                    if let source = wireDragFrom {
                        if let target = nearestTerminal(to: handF, excluding: source) {
                            model.connectTerminals(source, target.terminal)
                        }
                        return
                    }
                    guard let partDrag else { return }
                    applyCircuitDrag(partDrag, hand: hand)
                    if let gripDrag {
                        model.autoConnect(id: gripDrag.grip.componentID)
                    } else if let id = trayDragID ?? UUID(uuidString: partDrag.name) {
                        model.autoConnect(id: id)
                    }
                    if trayDragID != nil {
                        renderer.setTrayTemplateHidden(partDrag.name, false)
                    }
                }
        )
    }

    /// Resolves what the pinch landed on and opens the right session:
    /// wire (terminal), aim/stretch (grip), spawn (tray), carry (body).
    private func beginCircuitDrag(
        entity: Entity, hand: SIMD3<Double>, renderer: CircuitsRenderer
    ) {
        var current: Entity? = entity
        while let candidate = current {
            let name = candidate.name
            if name.hasPrefix("t0-") || name.hasPrefix("t1-") {
                wireDragFrom = terminal(on: candidate)
                return
            }
            if let grip = stretchTerminal(from: name),
               let component = model.components.first(
                where: { $0.id == grip.componentID }) {
                let sign = grip.end == 0 ? -1.0 : 1.0
                let gripWorld = component.position + sign
                    * (component.terminalHalfSpan + CircuitsModel.endGripOffset)
                    * component.axis
                gripDrag = (grip, component.terminalPosition(1 - grip.end))
                partDrag = RelativeDrag(name: name, target: gripWorld, hand: hand)
                renderer.previewComponentID = grip.componentID
                model.select(id: grip.componentID)
                return
            }
            if name.hasPrefix("tray-") {
                guard let kind = CircuitsModel.ComponentKind(
                        rawValue: String(name.dropFirst(5))) else { return }
                let templateWorld = SIMD3<Double>(candidate.position(relativeTo: nil))
                guard let id = model.add(kind, at: templateWorld) else { return }
                trayDragID = id
                partDrag = RelativeDrag(name: name, target: templateWorld, hand: hand)
                renderer.previewComponentID = id
                renderer.setTrayTemplateHidden(name, true)
                return
            }
            if let id = UUID(uuidString: name),
               let component = model.components.first(where: { $0.id == id }) {
                partDrag = RelativeDrag(name: name, target: component.position, hand: hand)
                renderer.previewComponentID = id
                model.select(id: id)
                return
            }
            current = candidate.parent
        }
    }

    private func applyCircuitDrag(_ drag: RelativeDrag, hand: SIMD3<Double>) {
        let position = drag.position(forHand: hand)
        if let gripDrag {
            model.dragEnd(id: gripDrag.grip.componentID,
                          grabbedEnd: gripDrag.grip.end,
                          pivot: gripDrag.pivot, hand: position)
        } else if let id = trayDragID ?? UUID(uuidString: drag.name) {
            model.move(id: id, to: position)
        }
    }

    /// The terminal an entity (or any ancestor) represents, if any.
    private func terminal(on entity: Entity) -> CircuitsModel.Terminal? {
        var current: Entity? = entity
        while let candidate = current {
            let name = candidate.name
            if name.hasPrefix("t0-") || name.hasPrefix("t1-"),
               let id = UUID(uuidString: String(name.dropFirst(3))) {
                return CircuitsModel.Terminal(
                    componentID: id, end: name.hasPrefix("t0-") ? 0 : 1)
            }
            current = candidate.parent
        }
        return nil
    }

    /// The closest connectable terminal within reach of the hand.
    private func nearestTerminal(
        to hand: SIMD3<Float>, excluding source: CircuitsModel.Terminal
    ) -> (terminal: CircuitsModel.Terminal, position: SIMD3<Double>)? {
        var best: (CircuitsModel.Terminal, SIMD3<Double>, Float)?
        for component in model.components {
            for end in 0...1 {
                let terminal = CircuitsModel.Terminal(componentID: component.id, end: end)
                guard terminal != source else { continue }
                let position = component.terminalPosition(end)
                let distance = simd_distance(SIMD3<Float>(position), hand)
                guard distance < 0.09 else { continue }
                if best == nil || distance < best!.2 {
                    best = (terminal, position, distance)
                }
            }
        }
        return best.map { ($0.0, $0.1) }
    }

    /// Terminals ("t0-"/"t1-"), wires ("w-"), and levers ("k-") are tap
    /// targets; walk up the hierarchy to find whichever was hit.
    private func handleTap(on entity: Entity) {
        var current: Entity? = entity
        while let candidate = current {
            let name = candidate.name
            if name.hasPrefix("t0-") || name.hasPrefix("t1-") {
                let end = name.hasPrefix("t0-") ? 0 : 1
                if let id = UUID(uuidString: String(name.dropFirst(3))) {
                    model.tapTerminal(CircuitsModel.Terminal(componentID: id, end: end))
                }
                return
            }
            if name.hasPrefix("w-"), let id = UUID(uuidString: String(name.dropFirst(2))) {
                model.deleteWire(id: id)
                return
            }
            if name.hasPrefix("k-"), let id = UUID(uuidString: String(name.dropFirst(2))) {
                model.toggleSwitch(id: id)
                return
            }
            current = candidate.parent
        }
    }

    /// The end-grip being pulled, parsed from "s0-"/"s1-" entity names.
    private func stretchTerminal(from name: String) -> CircuitsModel.Terminal? {
        guard name.hasPrefix("s0-") || name.hasPrefix("s1-"),
              let id = UUID(uuidString: String(name.dropFirst(3))) else { return nil }
        return CircuitsModel.Terminal(componentID: id, end: name.hasPrefix("s0-") ? 0 : 1)
    }

    /// Component bodies (named by UUID, marked by the white center knob)
    /// are carried directly. Tray templates ("tray-<kind>") spawn a copy
    /// on grab-begin; the copy follows the hand while the hidden template
    /// glides back to its slot on release. End grips ("s0-"/"s1-") swing
    /// the part around its opposite end — pinned where it was when the
    /// pull began — and set a wire's length from the hand's reach.
}

/// Premade circuits, floating by the parts tray: series, parallel,
/// divider, RC — each built from ordinary parts, ready to rewire.
struct CircuitPresetsPod: View {
    @Environment(CircuitsModel.self) private var model

    var body: some View {
        ControlPod(title: "Premade circuits", icon: "square.grid.2x2",
                   tint: DesignTokens.Palette.circuitsAccent) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
                ForEach(CircuitsModel.Preset.allCases) { preset in
                    Button(preset.displayName) {
                        model.loadPreset(preset)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Build the \(preset.displayName) circuit")
                }
            }
            Text("Each one is ordinary parts — rewire, re-value, pull apart.")
                .font(DesignTokens.TypeScale.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

/// The save slots, on their own card below the presets.
struct CircuitSavedPod: View {
    @Environment(CircuitsModel.self) private var model
    @State private var slotName = ""

    var body: some View {
        @Bindable var model = model

        ControlPod(title: "Saved circuits", icon: "tray.full",
                   tint: DesignTokens.Palette.circuitsAccent) {
            HStack(spacing: 6) {
                TextField("Name this build", text: $slotName)
                    .textFieldStyle(.roundedBorder)
                    .font(DesignTokens.TypeScale.footnote)
                Button {
                    if model.saveSlot(named: slotName) {
                        slotName = ""
                    }
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)
                .disabled(slotName.trimmingCharacters(in: .whitespaces).isEmpty
                          || model.components.isEmpty)
                .accessibilityLabel("Save the current circuit")
            }
            if model.slotNames.isEmpty {
                Text("Nothing saved yet — name the bench and tap save.")
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.slotNames, id: \.self) { name in
                    HStack(spacing: 6) {
                        Button(name) {
                            model.loadSlot(named: name)
                        }
                        .buttonStyle(.bordered)
                        .font(DesignTokens.TypeScale.footnote)
                        .accessibilityLabel("Load \(name)")
                        Spacer(minLength: 0)
                        Button(role: .destructive) {
                            model.deleteSlot(named: name)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.mini)
                        .accessibilityLabel("Delete \(name)")
                    }
                }
            }
        }
    }
}

/// Bench status and housekeeping: electron flow, clear, the live
/// insight line, and the wiring hint — the read side of the lab.
struct CircuitBenchPod: View {
    @Environment(CircuitsModel.self) private var model

    var body: some View {
        @Bindable var model = model

        ControlPod(title: "Bench", icon: "list.clipboard",
                   tint: DesignTokens.Palette.circuitsAccent) {
            Toggle("Electron flow", isOn: $model.showElectronFlow)
                .font(DesignTokens.TypeScale.control)
                .accessibilityHint("Cyan dots drifting minus to plus along every live wire")
            Button {
                model.clearBench()
            } label: {
                Label("Clear bench", systemImage: "eraser")
            }
            .buttonStyle(.bordered)
            .disabled(model.components.isEmpty)
            .accessibilityHint("Removes every part and wire; Reset brings the starter loop back")

            if model.hasOverloadedBattery {
                Label("Short circuit! Only the battery's internal resistance limits the current — put a bulb or resistor in the loop.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.red)
            }
            if !model.insightText.isEmpty {
                Text(model.insightText)
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.pendingTerminal != nil {
                Text("Terminal armed — pinch another terminal to wire them (or the same one to cancel).")
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(DesignTokens.Palette.circuitsAccent)
            } else {
                Text("Drag from a copper terminal to pull a wire — let go on another to connect. Carried parts show green ghost wires where they'll snap.")
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// The live card floating above the selected component — readings plus
/// the in-space way to throw a part away.
struct CircuitsSelectedReadout: View {
    @Environment(CircuitsModel.self) private var model

    var body: some View {
        if let component = model.selectedComponent {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(component.kind.displayName)
                        .font(DesignTokens.TypeScale.sectionHeader)
                    if let readout = model.readouts[component.id] {
                        Text("\(abs(readout.volts), specifier: "%.2f") V   \(abs(readout.amps) * 1000, specifier: "%.1f") mA")
                            .font(DesignTokens.TypeScale.footnote.monospacedDigit())
                        Text("\(abs(readout.watts), specifier: "%.2f") W")
                            .font(DesignTokens.TypeScale.footnote.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    if component.kind == .capacitor {
                        Text("charged to \(component.capacitorVoltage, specifier: "%.2f") V")
                            .font(DesignTokens.TypeScale.footnote.monospacedDigit())
                            .foregroundStyle(DesignTokens.Palette.circuitsAccent)
                    }
                    if component.kind == .battery,
                       abs(model.readouts[component.id]?.amps ?? 0) > CircuitsModel.overloadAmps {
                        Label("short circuit", systemImage: "exclamationmark.triangle.fill")
                            .font(DesignTokens.TypeScale.footnote)
                            .foregroundStyle(.red)
                    }
                }
                .accessibilityElement(children: .combine)

                Button(role: .destructive) {
                    model.removeSelected()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .controlSize(.mini)
                .accessibilityLabel("Remove this \(component.kind.displayName), and any wires connected to it")
            }
        }
    }
}
