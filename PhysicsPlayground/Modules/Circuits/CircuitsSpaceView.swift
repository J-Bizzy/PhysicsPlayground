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
    /// Two-handed zoom on the bench. Electron View is now a FLOOR under
    /// this same number rather than a competing 1x/4x flip, so "get in
    /// among the electrons" and "pull the bench open with both hands"
    /// are one continuous control.
    @State private var scaleRig = SpatialScaleRig(
        pivot: CircuitsRenderer.benchPivot, range: 0.6...8.0, allowsTurn: false)

    var body: some View {
        RealityView { content in
            let renderer = CircuitsRenderer()
            content.add(renderer.root)

            renderer.subscriptions.append(
                content.subscribe(to: SceneEvents.Update.self) { [weak renderer] event in
                    // The lab's placement in the user's room — a pure
                    // display offset, safe because every grab in this app
                    // moves a body by hand DISPLACEMENT, which a constant
                    // translation leaves untouched.
                    renderer?.root.position = appModel.labPlacement.offset
                    // (No counter-translation here: this module's pods
                    // hang off the scene content rather than the renderer
                    // root, so they never inherited the offset.)
                    model.step(dt: event.deltaTime)
                    // Rendered here every frame (not via the observation
                    // loop): a steady DC circuit mutates nothing that
                    // observation reliably re-fires on, but its electrons
                    // must keep drifting.
                    renderer?.handZoom = scaleRig.liveScale
                    renderer?.tick(dt: event.deltaTime, model: model)
                }
            )
            #if DEBUG
            if UserDefaults.standard.double(forKey: "trueSpeed") > 0 {
                model.trueSpeedMode = true
            }
            let forcedScale = UserDefaults.standard.double(forKey: "viewScale")
            if forcedScale > 0 {
                scaleRig.updateMagnification(Float(forcedScale))
                scaleRig.endGesture()
            }
            #endif

            self.renderer = renderer
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
                    // Into the BENCH's own frame, not the room's. The
                    // bench can be zoomed (Electron View, two hands) and
                    // moved (lab placement); converting through viewRoot
                    // inverts both exactly, so a part follows the hand
                    // 1:1 on screen at any zoom instead of flying four
                    // times as far.
                    let handF = renderer.viewRoot.convert(
                        position: SIMD3<Float>(value.convert(
                            value.location3D, from: .local, to: .scene)),
                        from: nil)
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
                    // Into the BENCH's own frame, not the room's. The
                    // bench can be zoomed (Electron View, two hands) and
                    // moved (lab placement); converting through viewRoot
                    // inverts both exactly, so a part follows the hand
                    // 1:1 on screen at any zoom instead of flying four
                    // times as far.
                    let handF = renderer.viewRoot.convert(
                        position: SIMD3<Float>(value.convert(
                            value.location3D, from: .local, to: .scene)),
                        from: nil)
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
        .spatialScale(scaleRig)
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
                let templateWorld = SIMD3<Double>(candidate.position(relativeTo: renderer.viewRoot))
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
                        .buttonStyle(.podQuiet)
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
                        .buttonStyle(.podQuiet)
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
