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

    var body: some View {
        RealityView { content, attachments in
            let renderer = CircuitsRenderer()
            content.add(renderer.root)

            if let quick = attachments.entity(for: "quick") {
                quick.position = [-1.35, 1.2, -0.7]
                quick.orientation = simd_quatf(angle: 0.35, axis: [0, 1, 0])
                renderer.root.addChild(quick)
            }
            if let readout = attachments.entity(for: "info") {
                readout.position = [0, 0.02, 0]
                renderer.selectedAnchor.addChild(readout)
            }

            configureRouter(renderer: renderer)
            renderer.subscriptions = router.subscriptions(for: content)
            renderer.subscriptions.append(
                content.subscribe(to: SceneEvents.Update.self) { event in
                    model.step(dt: event.deltaTime)
                }
            )

            renderer.startObserving(model)
            self.renderer = renderer
        } attachments: {
            Attachment(id: "quick") {
                CircuitsQuickPanel()
                    .environment(model)
                    .padding(18)
                    .frame(width: 340)
                    .glassBackgroundEffect()
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
            // Keep whatever twist the hand gave the part.
            if let axis = renderer.liveAxis(of: id) {
                model.setAxis(id: id, axis: axis)
            }
            renderer.manipulatingComponentID = nil
        }
    }
}

/// The floating palette: spawn parts and steer the lab without looking
/// away from the build.
struct CircuitsQuickPanel: View {
    @Environment(CircuitsModel.self) private var model

    private let columns = [GridItem(.adaptive(minimum: 92), spacing: 8)]

    var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(CircuitsModel.ComponentKind.allCases) { kind in
                    Button(kind.displayName) {
                        model.add(kind)
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.components.count >= CircuitsModel.componentBudget)
                    .accessibilityLabel("Add a \(kind.displayName)")
                }
            }

            Toggle("Electron flow", isOn: $model.showElectronFlow)
                .font(DesignTokens.TypeScale.label)
                .accessibilityHint("Cyan dots drifting minus to plus along every live wire")

            if model.hasOverloadedBattery {
                Label("Short circuit! The battery's own internal resistance is all that's limiting the current — put a bulb or resistor in the loop.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.red)
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
