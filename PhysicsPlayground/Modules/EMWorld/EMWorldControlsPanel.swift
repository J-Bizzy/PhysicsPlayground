//
//  EMWorldControlsPanel.swift
//  Physics Playground — Electricity & Magnetism
//
//  The window panel for the merged world: the circuit bench's controls,
//  then the link, then the magnetic bench's.
//
//  This is NOT a bench picker. The last two mergers in this app died of
//  exactly that — a segmented control in the window that chose which
//  half of the module existed, back when the controls had already moved
//  into spatial pods and nobody found it. Both benches are always in
//  the room and always live; this panel is the flat, labelled,
//  simulator-and-accessibility path to the same controls, and it shows
//  both sets at once because both sets are always in play.
//
//  The Link section is the only genuinely new control surface here, and
//  it earns its place: the electromagnet switch is what makes the cable
//  appear, and it is the one thing in the world that belongs to neither
//  bench.
//

import SwiftUI

struct EMWorldControlsPanel: View {
    @Environment(CircuitsModel.self) private var circuits
    @Environment(MagnetismModel.self) private var magnetism

    var body: some View {
        VStack(spacing: DesignTokens.Panel.sectionSpacing) {
            CircuitsControlsPanel()
            EMLinkSection()
            MagnetismControlsPanel()
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
