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
            content.add(podsRoot)   // outside renderer.root: pods must not
                                    // scale with the Electron View bench
            PodMount.mount(attachments.entity(for: "pod-presets"), name: "Premade circuits",
                           at: [-1.1, 1.7, -0.9], in: podsRoot)
            PodMount.mount(attachments.entity(for: "pod-saved"), name: "Saved circuits",
                           at: [-1.25, 1.12, -0.72], in: podsRoot)
            PodMount.mount(attachments.entity(for: "pod-bench"), name: "Bench",
                           at: [1.12, 1.5, -0.85], in: podsRoot)
            PodMount.mount(attachments.entity(for: "pod-scope"), name: "Oscilloscope",
                           at: [1.18, 0.92, -0.8], in: podsRoot)
            PodMount.mount(attachments.entity(for: "pod-meter"), name: "Multimeter",
                           at: [0.55, 1.9, -1.1], in: podsRoot)
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
            Attachment(id: "pod-scope") {
                CircuitScopePod()
                    .environment(model)
            }
            Attachment(id: "pod-meter") {
                CircuitMultimeterPod()
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
                        model.endCarry()
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
                model.beginCarry(id: grip.componentID)
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
                model.beginCarry(id: id)
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
            model.breakOverstretchedWires(id: gripDrag.grip.componentID)
        } else if let id = trayDragID ?? UUID(uuidString: drag.name) {
            model.move(id: id, to: position)
            model.breakOverstretchedWires(id: id)
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
                    let terminal = CircuitsModel.Terminal(componentID: id, end: end)
                    if model.multimeterArmed {
                        model.probeTap(terminal)
                    } else {
                        model.tapTerminal(terminal)
                    }
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
            Toggle("Electron View", isOn: $model.electronView)
                .font(DesignTokens.TypeScale.control)
                .accessibilityHint("The bench swells around you until wires are tunnels — walk inside your circuit")
            if model.electronView {
                Text("Wires are tunnels now. Electrons drift slowly — millimeters per second — but the field pushes all of them at once, everywhere.")
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
            }
            Toggle("Voltage heights", isOn: $model.showVoltageHeights)
                .font(DesignTokens.TypeScale.control)
                .accessibilityHint("Raises a glowing tower over every node to a height equal to its voltage — potential as terrain")
            if model.showVoltageHeights {
                Text("Each node's voltage becomes a height. The battery towers up, ground sits at the datum, every component steps the height down — walk the loop and the drops sum to zero. That's Kirchhoff's voltage law you can see.")
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
            }
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

/// The oscilloscope: a scrolling five-second window of the selected
/// part's voltage and current — watch an RC charge curve, an AC
/// cycle, or an inductor's rise as it happens.
struct CircuitScopePod: View {
    @Environment(CircuitsModel.self) private var model

    var body: some View {
        ControlPod(title: "Oscilloscope", icon: "waveform.path.ecg",
                   tint: DesignTokens.Palette.circuitsAccent, width: 300) {
            if let selected = model.selectedComponent {
                TimelineView(.animation) { _ in
                    Canvas { context, size in
                        let samples = model.scopeSamples
                        guard samples.count > 2 else { return }
                        // Grid.
                        var grid = Path()
                        for step in 1..<5 {
                            let x = size.width * CGFloat(step) / 5
                            grid.move(to: CGPoint(x: x, y: 0))
                            grid.addLine(to: CGPoint(x: x, y: size.height))
                        }
                        grid.move(to: CGPoint(x: 0, y: size.height / 2))
                        grid.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                        context.stroke(grid, with: .color(.white.opacity(0.12)), lineWidth: 1)

                        let vMax = max(samples.map { abs($0.volts) }.max() ?? 0, 0.1)
                        let iMax = max(samples.map { abs($0.amps) }.max() ?? 0, 1e-4)
                        let t0 = samples.first!.time
                        let span = max(samples.last!.time - t0, 0.5)
                        func path(_ value: @escaping ((time: Double, volts: Double, amps: Double)) -> Double,
                                  scale: Double) -> Path {
                            var path = Path()
                            for (index, sample) in samples.enumerated() {
                                let x = size.width * CGFloat((sample.time - t0) / span)
                                let y = size.height * CGFloat(0.5 - 0.42 * value(sample) / scale)
                                if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
                                else { path.addLine(to: CGPoint(x: x, y: y)) }
                            }
                            return path
                        }
                        context.stroke(path({ $0.volts }, scale: vMax),
                                       with: .color(.orange), lineWidth: 2)
                        context.stroke(path({ $0.amps }, scale: iMax),
                                       with: .color(.cyan), lineWidth: 2)
                    }
                    .frame(height: 120)
                }
                let vMax = max(model.scopeSamples.map { abs($0.volts) }.max() ?? 0, 0.1)
                let iMax = max(model.scopeSamples.map { abs($0.amps) }.max() ?? 0, 1e-4)
                HStack(spacing: 12) {
                    Label(String(format: "±%.1f V", vMax), systemImage: "circle.fill")
                        .foregroundStyle(.orange)
                    Label(String(format: "±%.0f mA", iMax * 1000), systemImage: "circle.fill")
                        .foregroundStyle(.cyan)
                    Spacer()
                    Text(selected.kind.displayName)
                        .foregroundStyle(.secondary)
                }
                .font(DesignTokens.TypeScale.footnote)
                Text("Pause freezes the trace.")
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("Select a part — its voltage (orange) and current (cyan) trace here, live.")
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// The multimeter: arm it, tap any two copper terminals, read the
/// live voltage difference — continuity and inline current included,
/// exactly like the real thing.
struct CircuitMultimeterPod: View {
    @Environment(CircuitsModel.self) private var model

    var body: some View {
        @Bindable var model = model

        ControlPod(title: "Multimeter", icon: "gauge.with.needle",
                   tint: DesignTokens.Palette.circuitsAccent, width: 270) {
            Toggle("Probes armed", isOn: $model.multimeterArmed)
                .font(DesignTokens.TypeScale.control)
                .accessibilityHint("While armed, tapping terminals lands the probes instead of wiring")
            if model.multimeterArmed {
                if let reading = model.multimeterReading {
                    Text(String(format: "ΔV  %+.3f V", reading.deltaVolts))
                        .font(DesignTokens.TypeScale.sectionHeader.monospacedDigit())
                        .foregroundStyle(DesignTokens.Palette.circuitsAccent)
                    if reading.continuity {
                        Label("Continuity", systemImage: "dot.radiowaves.left.and.right")
                            .font(DesignTokens.TypeScale.footnote)
                            .foregroundStyle(.green)
                    }
                    if let amps = reading.inlineAmps {
                        Text(String(format: "%.1f mA through this part", abs(amps) * 1000))
                            .font(DesignTokens.TypeScale.footnote.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Text("Tap another terminal to move the red probe.")
                        .font(DesignTokens.TypeScale.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text(model.probeA == nil
                         ? "Tap any copper terminal — that's the red probe."
                         : "Now tap a second terminal for the black probe.")
                        .font(DesignTokens.TypeScale.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Arm the probes, then touch any two points in the circuit to read the voltage between them.")
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

                VStack(spacing: 6) {
                    if component.failed {
                        Button {
                            model.replaceFailed(id: component.id)
                        } label: {
                            Label("Replace", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .tint(.orange)
                        .accessibilityLabel("Replace the failed \(component.kind.displayName)")
                    }
                    if model.selectedIsWired {
                        Button {
                            model.detachComponent(id: component.id)
                        } label: {
                            Label("Detach", systemImage: "scissors")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .accessibilityLabel("Detach this \(component.kind.displayName) — drop its wires but keep the part")
                    }
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
}
