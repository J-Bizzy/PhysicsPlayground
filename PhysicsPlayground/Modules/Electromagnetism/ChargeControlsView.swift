//
//  ChargeControlsView.swift
//  Physics Playground — Electromagnetism module
//
//  The charge editing controls for the main window's flat panel (the
//  in-space UI is the pod constellation in FieldPods.swift).
//
//  The sliders always edit the *selected* charge — the one most recently
//  added or grabbed, marked with a white halo in the scene.
//

import PhysicsCore
import SwiftUI

struct ChargeControlsView: View {
    @Environment(FieldModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let hasSelection = model.selectedChargeID != nil

        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
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
            .buttonStyle(.podQuiet)

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
            .buttonStyle(.podQuiet)

            Text(statusLine)
                .font(.footnote)
                .foregroundStyle(.secondary)
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
