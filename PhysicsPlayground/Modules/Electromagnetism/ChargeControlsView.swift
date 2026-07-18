//
//  ChargeControlsView.swift
//  Physics Playground — Electromagnetism module
//
//  The charge editing controls, shared by the main window and the floating
//  in-space panel so the two can never drift apart. `compact` trims labels
//  for the in-space version.
//
//  The sliders always edit the *selected* charge — the one most recently
//  added or grabbed, marked with a white halo in the scene.
//

import PhysicsCore
import SwiftUI

struct ChargeControlsView: View {
    @Environment(FieldModel.self) private var model
    var compact = false

    var body: some View {
        @Bindable var model = model
        let hasSelection = model.selectedChargeID != nil

        VStack(alignment: .leading, spacing: compact ? 14 : 20) {
            HStack(spacing: 12) {
                Button {
                    model.addCharge(positive: true)
                } label: {
                    Label("Add +", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .tint(DesignTokens.Palette.positive)
                .accessibilityLabel("Add positive charge")

                Button {
                    model.addCharge(positive: false)
                } label: {
                    Label("Add −", systemImage: "minus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .tint(DesignTokens.Palette.negative)
                .accessibilityLabel("Add negative charge")
            }
            .buttonStyle(.borderedProminent)

            VStack(alignment: .leading, spacing: 6) {
                Text("Strength: \(model.selectedMagnitudeMicroCoulombs, specifier: "%.1f") µC")
                    .font(.body.monospacedDigit())
                Slider(value: $model.selectedMagnitudeMicroCoulombs, in: 0.1...5.0, step: 0.1)
                    .disabled(!hasSelection)
                    .accessibilityLabel("Charge strength")
                    .accessibilityValue("\(model.selectedMagnitudeMicroCoulombs, specifier: "%.1f") microcoulombs")
            }

            Picker("Polarity", selection: $model.selectedIsPositive) {
                Text("Positive +").tag(true)
                Text("Negative −").tag(false)
            }
            .pickerStyle(.segmented)
            .disabled(!hasSelection)
            .accessibilityLabel("Charge polarity")

            HStack(spacing: 12) {
                Button(role: .destructive) {
                    model.removeSelectedCharge()
                } label: {
                    Label("Remove", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .disabled(!hasSelection)
                .accessibilityLabel("Remove selected charge")

                Button(role: .destructive) {
                    model.removeAllCharges()
                } label: {
                    Label("Clear All", systemImage: "trash.slash")
                        .frame(maxWidth: .infinity)
                }
                .disabled(model.charges.isEmpty)
                .accessibilityLabel("Remove all charges")
            }
            .buttonStyle(.bordered)

            HStack(spacing: 12) {
                Button {
                    model.dropProbe()
                } label: {
                    Label(
                        model.probe == nil ? "Drop test charge" : "Reset test charge",
                        systemImage: "scope"
                    )
                    .frame(maxWidth: .infinity)
                }
                .tint(model.probeIsPositive ? DesignTokens.Palette.probePositive : DesignTokens.Palette.probeNegative)
                .disabled(model.charges.isEmpty && !model.capacitorOn && !model.magneticFieldOn)
                .accessibilityHint("A small charge that accelerates along the field")

                Picker("Test charge polarity", selection: $model.probeIsPositive) {
                    Text("+").tag(true)
                    Text("−").tag(false)
                }
                .pickerStyle(.segmented)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Charge: \(model.probeIsPositive ? "+" : "−")\(model.probeChargeMagnitude * 1e9, specifier: "%.0f") nC — F = qE scales with it")
                        .font(DesignTokens.TypeScale.control.monospacedDigit())
                    Slider(value: $model.probeChargeMagnitude, in: FieldModel.probeChargeRange)
                        .accessibilityLabel("Test charge magnitude")
                }
                .frame(width: 110)
                .accessibilityLabel("Test charge polarity")

                if model.probe != nil {
                    Button {
                        model.removeProbe()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Remove test charge")
                }
            }
            .buttonStyle(.bordered)

            if compact {
                HStack(spacing: 16) {
                    Toggle("Lines", isOn: $model.showLines)
                        .accessibilityLabel("Show field lines")
                    Toggle("Arrows", isOn: $model.showArrows)
                        .accessibilityLabel("Show arrow grid")
                    Toggle("Shells", isOn: $model.showEquipotentials)
                        .accessibilityLabel("Show equipotential shells")
                }

                if model.showEquipotentials {
                    Stepper("Casings per polarity: \(model.equipotentialShells)",
                            value: $model.equipotentialShells, in: 1...6)
                        .font(DesignTokens.TypeScale.control)
                }

                PanelSection("Parallel plates") {
                    Toggle("Capacitor field", isOn: $model.capacitorOn)
                        .font(DesignTokens.TypeScale.control)
                    if model.capacitorOn {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("ΔV: \(model.plateVoltage / 1000, specifier: "%.0f") kV   E = V/d = \(model.plateVoltage / model.plateSeparation / 1000, specifier: "%.1f") kV/m   d = \(model.plateSeparation * 100, specifier: "%.0f") cm")
                                .font(DesignTokens.TypeScale.control.monospacedDigit())
                            Slider(value: $model.plateVoltage, in: FieldModel.plateVoltageRange)
                                .accessibilityLabel("Plate voltage")
                        }
                        Text("Uniform field between the plates: red is +, blue is −. Drop the probe in the gap — a + probe drifts toward the blue plate with a = qE/m, and doubling ΔV doubles the push.")
                            .font(DesignTokens.TypeScale.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                PanelSection("Magnetic field") {
                    Toggle("Uniform B (pointing up)", isOn: $model.magneticFieldOn)
                        .font(DesignTokens.TypeScale.control)
                    Toggle("Electron mode", isOn: $model.electronMode)
                        .font(DesignTokens.TypeScale.control)
                        .accessibilityHint("The probe becomes a real electron; realistic fields curve it")
                    if model.magneticFieldOn {
                        if model.electronMode {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("B: \(model.electronFieldTesla * 1000, specifier: "%.2f") mT   r = mv/qB = \(model.cyclotronRadius * 100, specifier: "%.0f") cm")
                                    .font(DesignTokens.TypeScale.control.monospacedDigit())
                                Slider(value: $model.electronFieldTesla, in: FieldModel.electronFieldRange)
                                    .accessibilityLabel("Magnetic field strength")
                            }
                            Text("A real electron (q = e, m = mₑ) at 2×10⁶ m/s: a TENTH of a millitesla bends it into an 11 cm circle — the classic Helmholtz-coil e/m lab. Time runs 10⁷× slower on display (1 s shows 0.1 µs); the physics is SI-exact. Flip polarity for a positron.")
                                .font(DesignTokens.TypeScale.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("B: \(model.magneticFieldTesla / 1000, specifier: "%.0f") kT   r = mv/qB = \(model.cyclotronRadius * 100, specifier: "%.0f") cm")
                                    .font(DesignTokens.TypeScale.control.monospacedDigit())
                                Slider(value: $model.magneticFieldTesla, in: FieldModel.magneticFieldRange)
                                    .accessibilityLabel("Magnetic field strength")
                            }
                            Text("Drop the probe and it launches sideways, then curves on an exact cyclotron circle — F = qv×B, computed with the Boris integrator so the speed never drifts. The kilotesla numbers are what a 0.5 g ball needs — or flip on Electron mode for realistic fields. Turn the plates on too for cycloids.")
                                .font(DesignTokens.TypeScale.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .font(.callout)
            }

            if !compact {
                Text(statusLine)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statusLine: String {
        let count = model.charges.count
        guard count > 0 else { return "No charges — add one to see a field." }
        let selected = model.selectedCharge.map {
            "editing the \($0.isPositive ? "red" : "blue") one with the halo"
        }
        return "\(count) charge\(count == 1 ? "" : "s") in the field\(selected.map { " — \($0)" } ?? "")."
    }
}
