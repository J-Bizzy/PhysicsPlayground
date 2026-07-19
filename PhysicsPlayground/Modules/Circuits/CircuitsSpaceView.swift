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
    @State private var router = ManipulationRouter()
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

            configureRouter(renderer: renderer)
            renderer.subscriptions = router.subscriptions(for: content)
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
    private func configureRouter(renderer: CircuitsRenderer) {
        router.onBegin = { [weak renderer] name, position in
            guard let renderer else { return }
            if name.hasPrefix("tray-") {
                guard let kind = CircuitsModel.ComponentKind(rawValue: String(name.dropFirst(5))),
                      let id = model.add(kind, at: SIMD3<Double>(position))
                else { return }
                renderer.trayDragIDs[name] = id
                renderer.setTrayTemplateHidden(name, true)
                return
            }
            if let grip = stretchTerminal(from: name) {
                renderer.stretchingHandle = grip
                renderer.swingPivot = model.components
                    .first { $0.id == grip.componentID }?
                    .terminalPosition(1 - grip.end)
                model.select(id: grip.componentID)
                return
            }
            guard let id = UUID(uuidString: name) else { return }
            renderer.manipulatingComponentID = id
            model.select(id: id)
            model.move(id: id, to: SIMD3<Double>(position))
        }
        router.onMove = { [weak renderer] name, position in
            if name.hasPrefix("tray-") {
                guard let id = renderer?.trayDragIDs[name] else { return }
                model.move(id: id, to: SIMD3<Double>(position))
                return
            }
            if let grip = stretchTerminal(from: name) {
                guard let pivot = renderer?.swingPivot else { return }
                model.dragEnd(id: grip.componentID, grabbedEnd: grip.end,
                              pivot: pivot, hand: SIMD3<Double>(position))
                return
            }
            guard let id = UUID(uuidString: name) else { return }
            model.move(id: id, to: SIMD3<Double>(position))
        }
        router.onEnd = { [weak renderer] name, position in
            guard let renderer else { return }
            if name.hasPrefix("tray-") {
                if let id = renderer.trayDragIDs[name] {
                    model.move(id: id, to: SIMD3<Double>(position))
                    model.autoConnect(id: id)
                    renderer.trayDragIDs[name] = nil
                }
                renderer.setTrayTemplateHidden(name, false)
                return
            }
            if let grip = stretchTerminal(from: name) {
                if let pivot = renderer.swingPivot {
                    model.dragEnd(id: grip.componentID, grabbedEnd: grip.end,
                                  pivot: pivot, hand: SIMD3<Double>(position))
                }
                renderer.stretchingHandle = nil
                renderer.swingPivot = nil
                return
            }
            guard let id = UUID(uuidString: name) else { return }
            model.move(id: id, to: SIMD3<Double>(position))
            // Keep whatever twist the hand gave the part, then let any
            // nearly-touching terminals connect themselves.
            if let axis = renderer.liveAxis(of: id) {
                model.setAxis(id: id, axis: axis)
            }
            model.autoConnect(id: id)
            // Don't reclaim the holder immediately: the manipulation
            // system settles the entity for a beat after release, and
            // writing transforms under it makes the part shudder. Hand
            // it back once the settle is over (positions already agree).
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(450))
                if renderer.manipulatingComponentID == id {
                    renderer.manipulatingComponentID = nil
                }
            }
        }
    }
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
                Text("Pinch a copper terminal, then another, to run a wire.")
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
