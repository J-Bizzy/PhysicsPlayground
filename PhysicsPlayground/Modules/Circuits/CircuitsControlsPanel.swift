//
//  CircuitsControlsPanel.swift
//  Physics Playground — Circuits module
//
//  The module's one-glance panel. The always-open card stocks the
//  bench (mirroring the 3D tray, so every part is also reachable by
//  button); electron flow, the multimeter, and the selected part's
//  readings wait behind collapsed sections. Per-PART editing lives on
//  the part: tap it and its ring unfolds — value bead, switch/replace/
//  detach petals, delete.
//

import SwiftUI

struct CircuitsControlsPanel: View {
    @Environment(CircuitsModel.self) private var model
    @State private var confirmingClear = false

    var body: some View {
        @Bindable var model = model

        VStack(spacing: DesignTokens.Panel.sectionSpacing) {
            PanelSection("Bench") {
                HStack(spacing: 12) {
                    Menu {
                        ForEach(CircuitsModel.ComponentKind.allCases) { kind in
                            Button(kind.displayName) {
                                _ = self.model.add(kind)
                            }
                        }
                    } label: {
                        Label("Add part", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.podProminent)
                    .accessibilityLabel("Add a circuit part")

                    Button(role: .destructive) {
                        confirmingClear = true
                    } label: {
                        Label("Clear", systemImage: "trash.slash")
                    }
                    .buttonStyle(.podQuiet)
                    .disabled(self.model.components.isEmpty)
                    .confirmationDialog("Clear the bench?",
                                        isPresented: $confirmingClear,
                                        titleVisibility: .visible) {
                        Button("Clear everything", role: .destructive) {
                            self.model.clearBench()
                        }
                        Button("Keep my circuit", role: .cancel) {}
                    } message: {
                        Text("Every part and wire goes — the bench persists across launches, so this is the only way back to empty.")
                    }
                }

                Text("Drag parts off the tray, drop copper ends near each other to connect, tap two terminals to wire across a distance. Tap a part for its ring — value bead, switch, replace, detach, delete.")
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            CollapsedSection("Flow") {
                // These are switches on the layers bank beside the bench
                // now (DECISIONS.md, 2026-07-29) — a lit plate is on. The
                // bank also carries ELECTRON VIEW, which had no control at
                // all until today: it swells the bench to 4x so the
                // drifting electrons become things you stand among, and it
                // was reachable only by accidentally pinching past 4x.
                Text("Electron flow, True speed, Voltage skyline and Electron view are plates on the bank beside the bench.")
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if self.model.electronView {
                    Text("Electron view: each electron drifts under a millimetre per second, but the field pushes all of them at once — which is why the bulb lights instantly.")
                        .font(DesignTokens.TypeScale.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            CollapsedSection("Multimeter") {
                Toggle("Multimeter", isOn: $model.multimeterArmed)
                    .font(DesignTokens.TypeScale.control)
                    .accessibilityHint("Armed, tapping two terminals reads the voltage between them instead of wiring them")
                if let reading = self.model.multimeterReading {
                    Text("ΔV \(reading.deltaVolts, specifier: "%.2f") V\(reading.inlineAmps.map { String(format: "   I %.1f mA", abs($0) * 1000) } ?? "")")
                        .font(DesignTokens.TypeScale.footnote.monospacedDigit())
                        .foregroundStyle(DesignTokens.Palette.circuitsAccent)
                }
            }

            CollapsedSection("Selected part") {
                if self.model.selectedComponent != nil {
                    CircuitsSelectedReadout()
                } else {
                    Text("Tap a part on the bench to read it here.")
                        .font(DesignTokens.TypeScale.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
