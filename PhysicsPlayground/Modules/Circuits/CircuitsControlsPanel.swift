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
                // The meter is an object on the bench now — tap it to arm
                // it, and the answer appears ON IT rather than here,
                // which is where you were already looking and where a
                // real bench meter puts it.
                Text(self.model.multimeterArmed
                     ? "Armed — tap two terminals and the meter reads the "
                       + "voltage between them instead of wiring them."
                     : "The meter stands to the left of the bench. Tap it "
                       + "to arm it, then tap two terminals.")
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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

            CircuitLinkSection()
        }
    }
}

/// The one wired pair in the app: switch the coil on and the magnetic
/// field materialises beside the bench, cabled to the inductor.
///
/// This section lives on Circuit Workshop's panel — not Magnetism's —
/// because the CIRCUIT is what powers it: the coil's moment is
/// m = N·I·A with I read off this bench, and opening the switch here
/// is what kills the magnet over there. Magnetism alone has no cable
/// and no coil; the demonstration cannot exist with one bench, which
/// is exactly why this experience brings the second one (DECISIONS.md,
/// 2026-07-30: co-presence survives where it is WIRING, never layout).
private struct CircuitLinkSection: View {
    @Environment(CircuitsModel.self) private var circuits
    @Environment(MagnetismModel.self) private var magnetism

    var body: some View {
        @Bindable var magnetism = magnetism

        PanelSection("The link") {
            // The switch stands ON the cable run now, between the bench
            // and where the coil appears — throw it and you watch the
            // cable it belongs to wake up, which is the whole reason this
            // pair is co-present at all.
            Text(magnetism.electromagnetOn
                 ? "The coil is standing beside the bench, cabled to your inductor."
                 : "The coil's switch is on the run to its right — flick it "
                   + "and the magnetic field stands up beside the bench.")
                .font(DesignTokens.TypeScale.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if magnetism.electromagnetOn {
                if hasInductor {
                    Text("Feed current \(circuits.inductorCurrent, specifier: "%.3f") A")
                        .font(DesignTokens.TypeScale.control.monospacedDigit())
                        .foregroundStyle(DesignTokens.Palette.circuitsAccent)
                    Text("moment \(magnetism.electromagnetMoment, specifier: "%.2f") A·m²  (m = N·I·A, 400 turns)")
                        .font(DesignTokens.TypeScale.footnote.monospacedDigit())
                        .foregroundStyle(DesignTokens.Palette.magnetismAccent)
                    Text("Open the switch and this falls to zero — the cable's electrons stop and the coil stops being a magnet.")
                        .font(DesignTokens.TypeScale.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    // The coil is on but nothing feeds it. Say why,
                    // rather than showing a confident 0.000 A.
                    Label("No inductor on the bench", systemImage: "cable.connector")
                        .font(DesignTokens.TypeScale.control)
                        .foregroundStyle(.secondary)
                    Text("The coil is standing in its field but nothing is driving it. Add an inductor and wire it into a live loop — the cable wakes up.")
                        .font(DesignTokens.TypeScale.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("Switch the coil on and the magnetic field appears beside the bench, cabled to your inductor — build a loop and your current becomes a magnet.")
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
