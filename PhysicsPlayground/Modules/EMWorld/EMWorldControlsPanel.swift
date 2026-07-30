//
//  EMWorldControlsPanel.swift
//  Physics Playground — Electricity & Magnetism
//
//  The window panel for the merged world: one section per bench, plus
//  the link that belongs to neither.
//
//  This is NOT a bench picker, and the distinction is load-bearing. The
//  last two mergers in this app died of exactly that — a segmented
//  control in the window that chose which half of the module EXISTED,
//  back when the controls had already moved into spatial pods, so the
//  other half became unreachable. Both benches here are always in the
//  room, always live, always solving.
//
//  What the sections do is follow FOCUS. The attended bench's controls
//  are open; the other's fold down to their single most important live
//  number, still in the panel, still in the accessibility tree, still
//  one tap from open. And that tap is not merely a disclosure — it
//  attends to that bench in the room too, which makes this panel the
//  second, always-reachable path to focus for a simulator or a user
//  who never raises their hands. See StationFocus for the full
//  contract; this file keeps property 3 of it.
//
//  Stacking both benches at full height was the alternative, and it was
//  what shipped first. Two worked. Three — Electric Fields is coming to
//  the same window — is a wall.
//
//  The Link section never folds: the electromagnet switch is what makes
//  the cable appear, and it is the one thing in the world that belongs
//  to neither bench, so it has no station to fold into.
//

import SwiftUI

struct EMWorldControlsPanel: View {
    @Environment(CircuitsModel.self) private var circuits
    @Environment(MagnetismModel.self) private var magnetism
    @Environment(FieldModel.self) private var fields
    @Environment(AppModel.self) private var appModel

    var body: some View {
        VStack(spacing: DesignTokens.Panel.sectionSpacing) {
            StationSection(
                EMStation.charges.title,
                readout: "\(fields.charges.count) charges",
                accent: DesignTokens.Palette.electromagnetismAccent,
                isFocused: appModel.emFocus.focused == .charges,
                focus: { appModel.emFocus.focus(.charges) }
            ) {
                FieldControlsPanel()
            }

            StationSection(
                EMStation.bench.title,
                readout: String(format: "%.3f W", circuits.totalSourcePower),
                accent: DesignTokens.Palette.circuitsAccent,
                isFocused: appModel.emFocus.focused == .bench,
                focus: { appModel.emFocus.focus(.bench) }
            ) {
                CircuitsControlsPanel()
            }

            EMLinkSection()

            StationSection(
                EMStation.field.title,
                readout: String(format: "%.3f mT", magnetism.centerFieldMilliTesla),
                accent: DesignTokens.Palette.magnetismAccent,
                isFocused: appModel.emFocus.focused == .field,
                focus: { appModel.emFocus.focus(.field) }
            ) {
                MagnetismControlsPanel()
            }
        }
    }
}

/// The cable between the benches, as a control and a readout.
private struct EMLinkSection: View {
    @Environment(CircuitsModel.self) private var circuits
    @Environment(MagnetismModel.self) private var magnetism

    var body: some View {
        @Bindable var magnetism = magnetism

        PanelSection("The link") {
            Toggle("Electromagnet coil", isOn: $magnetism.electromagnetOn)
                .font(DesignTokens.TypeScale.control)
                .accessibilityHint("Stands a coil in the magnetic field and runs a cable to it from the circuit bench's inductor")

            if magnetism.electromagnetOn {
                if hasInductor {
                    Text("Feed current \(circuits.inductorCurrent, specifier: "%.3f") A")
                        .font(DesignTokens.TypeScale.control.monospacedDigit())
                        .foregroundStyle(DesignTokens.Palette.circuitsAccent)
                    Text("moment \(magnetism.electromagnetMoment, specifier: "%.2f") A·m²  (m = N·I·A, 400 turns)")
                        .font(DesignTokens.TypeScale.footnote.monospacedDigit())
                        .foregroundStyle(DesignTokens.Palette.magnetismAccent)
                    Text("Open the switch on the circuit bench and this falls to zero — the cable's electrons stop and the coil stops being a magnet.")
                        .font(DesignTokens.TypeScale.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    // The coil is on but nothing feeds it. Say why,
                    // rather than showing a confident 0.000 A.
                    Label("No inductor on the bench", systemImage: "cable.connector")
                        .font(DesignTokens.TypeScale.control)
                        .foregroundStyle(.secondary)
                    Text("The coil is standing in the field but nothing is driving it. Add an inductor to the circuit and wire it into a live loop — the cable appears and the coil wakes up.")
                        .font(DesignTokens.TypeScale.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Faraday's law runs the link BACKWARDS: move a bar
                // magnet through the coil and the coil answers. It is
                // the one law here you cannot infer from a still image,
                // so it needs a number that MOVES.
                Text("Coil EMF \(magnetism.inducedEMF * 1000, specifier: "%.2f") mV")
                    .font(DesignTokens.TypeScale.control.monospacedDigit())
                    .foregroundStyle(DesignTokens.Palette.magnetismAccent)
                Text("ε = −N dΦ/dt. Carry a bar magnet through the coil and this jumps; hold it still inside and it falls to zero — only *change* induces.")
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Switch the coil on to run a cable from the circuit bench's inductor to a coil standing in the magnetic field.")
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var hasInductor: Bool {
        circuits.components.contains { $0.kind == .inductor }
    }
}
