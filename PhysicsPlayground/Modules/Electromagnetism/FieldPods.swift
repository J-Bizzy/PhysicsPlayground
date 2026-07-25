//
//  FieldPods.swift
//  Physics Playground — Electromagnetism module
//
//  The EM module's control pods — four single-purpose cards spread
//  around the field region: charges upper left, the test charge below
//  them, the two imposed uniform fields (plates + magnet) upper right,
//  and the numbers card (with the view toggles) lower right. See
//  ControlPod.swift for the system's rules.
//

import PhysicsCore
import SwiftUI

struct ChargesPod: View {
    @Environment(FieldModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let hasSelection = model.selectedChargeID != nil

        ControlPod(title: "Charges", icon: "bolt.fill",
                   tint: DesignTokens.Palette.positive) {
            HStack(spacing: 8) {
                Button {
                    model.addCharge(positive: true)
                } label: {
                    Label("Add +", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.podProminent(DesignTokens.Palette.positive))
                .accessibilityLabel("Add positive charge")
                Button {
                    model.addCharge(positive: false)
                } label: {
                    Label("Add −", systemImage: "minus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.podProminent(DesignTokens.Palette.negative))
                .accessibilityLabel("Add negative charge")
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Strength: \(model.selectedMagnitudeMicroCoulombs, specifier: "%.1f") µC")
                    .font(DesignTokens.TypeScale.control.monospacedDigit())
                Slider(value: $model.selectedMagnitudeMicroCoulombs, in: 0.1...5.0, step: 0.1)
                    .disabled(!hasSelection)
                    .accessibilityLabel("Charge strength")
            }
            Picker("Polarity", selection: $model.selectedIsPositive) {
                Text("+").tag(true)
                Text("−").tag(false)
            }
            .pickerStyle(.segmented)
            .disabled(!hasSelection)
            .accessibilityLabel("Charge polarity")

            HStack(spacing: 8) {
                Button(role: .destructive) {
                    model.removeSelectedCharge()
                } label: {
                    Image(systemName: "trash")
                        .frame(maxWidth: .infinity)
                }
                .disabled(!hasSelection)
                .accessibilityLabel("Remove selected charge")
                Button(role: .destructive) {
                    model.removeAllCharges()
                } label: {
                    Image(systemName: "trash.slash")
                        .frame(maxWidth: .infinity)
                }
                .disabled(model.charges.isEmpty)
                .accessibilityLabel("Remove all charges")
            }
            .buttonStyle(.podQuiet)
        }
    }
}

struct TestChargePod: View {
    @Environment(FieldModel.self) private var model

    var body: some View {
        @Bindable var model = model

        ControlPod(title: "Test charge", icon: "scope",
                   tint: model.probeIsPositive
                       ? DesignTokens.Palette.probePositive
                       : DesignTokens.Palette.probeNegative) {
            HStack(spacing: 8) {
                Button {
                    model.dropProbe()
                } label: {
                    Label(model.probe == nil ? "Drop" : "Reset", systemImage: "scope")
                        .frame(maxWidth: .infinity)
                }
                .tint(model.probeIsPositive
                      ? DesignTokens.Palette.probePositive
                      : DesignTokens.Palette.probeNegative)
                .disabled(model.charges.isEmpty && !model.capacitorOn && !model.magneticFieldOn)
                .accessibilityLabel("Drop the test charge")
                .accessibilityHint("A small charge that accelerates along the field")

                Picker("Test charge polarity", selection: $model.probeIsPositive) {
                    Text("+").tag(true)
                    Text("−").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(width: 84)
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
            .buttonStyle(.podQuiet)

            VStack(alignment: .leading, spacing: 4) {
                Text("q = \(model.probeIsPositive ? "+" : "−")\(model.probeChargeMagnitude * 1e9, specifier: "%.0f") nC — F = qE scales with it")
                    .font(DesignTokens.TypeScale.control.monospacedDigit())
                Slider(value: $model.probeChargeMagnitude, in: FieldModel.probeChargeRange)
                    .accessibilityLabel("Test charge magnitude")
            }
        }
    }
}

struct UniformFieldsPod: View {
    @Environment(FieldModel.self) private var model

    var body: some View {
        @Bindable var model = model

        ControlPod(title: "Uniform fields", icon: "plus.forwardslash.minus",
                   tint: DesignTokens.Palette.forceVector) {
            Toggle("Parallel plates", isOn: $model.capacitorOn)
                .font(DesignTokens.TypeScale.control)
            if model.capacitorOn {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ΔV \(model.plateVoltage / 1000, specifier: "%.0f") kV   E = V/d = \(model.plateVoltage / model.plateSeparation / 1000, specifier: "%.1f") kV/m   d = \(model.plateSeparation * 100, specifier: "%.0f") cm")
                        .font(DesignTokens.TypeScale.footnote.monospacedDigit())
                    Slider(value: $model.plateVoltage, in: FieldModel.plateVoltageRange)
                        .accessibilityLabel("Plate voltage")
                }
                Text("Uniform field in the gap — drop the probe there and it drifts with a = qE/m. Grab a plate to change d.")
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
            }

            Toggle("Uniform B (up)", isOn: $model.magneticFieldOn)
                .font(DesignTokens.TypeScale.control)
            if model.magneticFieldOn {
                Toggle("Electron mode", isOn: $model.electronMode)
                    .font(DesignTokens.TypeScale.control)
                    .accessibilityHint("The probe becomes a real electron; realistic fields curve it")
                if model.electronMode {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("B \(model.electronFieldTesla * 1000, specifier: "%.2f") mT   r = mv/qB = \(model.cyclotronRadius * 100, specifier: "%.0f") cm")
                            .font(DesignTokens.TypeScale.footnote.monospacedDigit())
                        Slider(value: $model.electronFieldTesla, in: FieldModel.electronFieldRange)
                            .accessibilityLabel("Magnetic field strength")
                    }
                    Text("A real electron at 2×10⁶ m/s: a tenth of a millitesla bends an 11 cm circle. Display time runs 10⁷× slow; the physics is SI-exact.")
                        .font(DesignTokens.TypeScale.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("B \(model.magneticFieldTesla / 1000, specifier: "%.0f") kT   r = mv/qB = \(model.cyclotronRadius * 100, specifier: "%.0f") cm")
                            .font(DesignTokens.TypeScale.footnote.monospacedDigit())
                        Slider(value: $model.magneticFieldTesla, in: FieldModel.magneticFieldRange)
                            .accessibilityLabel("Magnetic field strength")
                    }
                    Text("F = qv×B curves the probe on an exact cyclotron circle — or flip on Electron mode for realistic fields.")
                        .font(DesignTokens.TypeScale.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// The display toggles, now living at the top of the Numbers pod — a
/// glance-and-set row rather than a whole card of their own.
struct FieldViewToggles: View {
    @Environment(FieldModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Toggle("Field lines", isOn: $model.showLines)
            .accessibilityLabel("Show field lines with direction arrows")
        Toggle("Equipotential shells", isOn: $model.showEquipotentials)
            .accessibilityLabel("Show equipotential shells")
        if model.showEquipotentials {
            Stepper("Casings: \(model.equipotentialShells)",
                    value: $model.equipotentialShells, in: 1...6)
        }
    }
}
