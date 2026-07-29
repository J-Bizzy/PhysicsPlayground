//
//  FieldControlsPanel.swift
//  Physics Playground — Electromagnetism module
//
//  The module's flat control panel, kept ONE GLANCE TALL: the always-
//  visible card carries only the global actions (add, free, clear),
//  and everything deeper — test charge, imposed fields, Gauss, the
//  numbers — waits behind collapsed sections. Editing ONE charge never
//  happens here at all: tap the charge in the field and its own ring
//  of controls unfolds around it (strength bead, delete). The window
//  states the rule once and points at the object. A charge's polarity
//  is fixed at birth — add the sign you want.
//

import PhysicsCore
import SwiftUI

struct FieldControlsPanel: View {
    @Environment(FieldModel.self) private var model

    var body: some View {
        @Bindable var model = model

        VStack(spacing: DesignTokens.Panel.sectionSpacing) {
            // The only always-open card: make things, free things.
            // Everything about ONE charge — strength, polarity, delete —
            // lives on the charge itself: tap it and its ring unfolds.
            PanelSection("Charges") {
                chargeControls(model: $model)
            }
            CollapsedSection("Test charge") {
                probeControls(model: $model)
            }
            CollapsedSection("Uniform fields") {
                uniformFieldControls(model: $model)
            }
            CollapsedSection("Display & Gauss's law") {
                displayToggles(model: $model)
                GaussSurfaceControls()
            }
            CollapsedSection("Numbers") {
                PhysicsStatsView()
            }
        }
    }

    // MARK: Charges

    @ViewBuilder
    private func chargeControls(model: Bindable<FieldModel>) -> some View {
        HStack(spacing: 12) {
            Button {
                self.model.addCharge(positive: true)
            } label: {
                Label("Add +", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.podProminent(DesignTokens.Palette.positive))
            .accessibilityLabel("Add positive charge")

            Button {
                self.model.addCharge(positive: false)
            } label: {
                Label("Add −", systemImage: "minus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.podProminent(DesignTokens.Palette.negative))
            .accessibilityLabel("Add negative charge")

            Button(role: .destructive) {
                self.model.removeAllCharges()
            } label: {
                Label("Clear", systemImage: "trash.slash")
            }
            .buttonStyle(.podQuiet)
            .disabled(self.model.charges.isEmpty)
            .accessibilityLabel("Remove all charges")
        }

        Toggle("Charges respond to forces", isOn: model.chargesRespond)
            .font(DesignTokens.TypeScale.control)
            .accessibilityHint("Free the charges: opposites drift together, likes push apart. Off, they stay exactly where you put them.")

        Text("Tap a charge in the field for its own controls — pull the bead to change strength, or the petal to delete it.")
            .font(DesignTokens.TypeScale.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

        Text(statusLine)
            .font(DesignTokens.TypeScale.footnote)
            .foregroundStyle(.secondary)
    }

    private var statusLine: String {
        let count = model.charges.count
        guard count > 0 else { return "No charges — add one to see a field." }
        let selected = model.selectedCharge.map {
            "the halo marks the \($0.isPositive ? "red" : "blue") one you tapped"
        }
        return "\(count) charge\(count == 1 ? "" : "s") in the field\(selected.map { " — \($0)" } ?? "")."
    }

    // MARK: Test charge

    @ViewBuilder
    private func probeControls(model: Bindable<FieldModel>) -> some View {
        HStack(spacing: 8) {
            Button {
                self.model.dropProbe()
            } label: {
                Label(self.model.probe == nil ? "Drop" : "Reset", systemImage: "scope")
                    .frame(maxWidth: .infinity)
            }
            .tint(self.model.probeIsPositive
                  ? DesignTokens.Palette.probePositive
                  : DesignTokens.Palette.probeNegative)
            .disabled(self.model.charges.isEmpty
                      && !self.model.capacitorOn && !self.model.magneticFieldOn)
            .accessibilityLabel("Drop the test charge")
            .accessibilityHint("A small charge that accelerates along the field")

            Picker("Test charge polarity", selection: model.probeIsPositive) {
                Text("+").tag(true)
                Text("−").tag(false)
            }
            .pickerStyle(.segmented)
            .frame(width: 84)
            .accessibilityLabel("Test charge polarity")

            if self.model.probe != nil {
                Button {
                    self.model.removeProbe()
                } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel("Remove test charge")
            }
        }
        .buttonStyle(.podQuiet)

        VStack(alignment: .leading, spacing: 4) {
            Text("q = \(self.model.probeIsPositive ? "+" : "−")\(self.model.probeChargeMagnitude * 1e9, specifier: "%.0f") nC — F = qE scales with it")
                .font(DesignTokens.TypeScale.control.monospacedDigit())
            Slider(value: model.probeChargeMagnitude, in: FieldModel.probeChargeRange)
                .accessibilityLabel("Test charge magnitude")
        }
    }

    // MARK: Uniform fields

    @ViewBuilder
    private func uniformFieldControls(model: Bindable<FieldModel>) -> some View {
        Toggle("Parallel plates", isOn: model.capacitorOn)
            .font(DesignTokens.TypeScale.control)
        if self.model.capacitorOn {
            VStack(alignment: .leading, spacing: 4) {
                Text("ΔV \(self.model.plateVoltage / 1000, specifier: "%.0f") kV   E = V/d = \(self.model.plateVoltage / self.model.plateSeparation / 1000, specifier: "%.1f") kV/m   d = \(self.model.plateSeparation * 100, specifier: "%.0f") cm")
                    .font(DesignTokens.TypeScale.footnote.monospacedDigit())
                Slider(value: model.plateVoltage, in: FieldModel.plateVoltageRange)
                    .accessibilityLabel("Plate voltage")
            }
            Text("Uniform field in the gap — drop the probe there and it drifts with a = qE/m. Grab a plate to change d.")
                .font(DesignTokens.TypeScale.footnote)
                .foregroundStyle(.secondary)
        }

        Toggle("Uniform B (up)", isOn: model.magneticFieldOn)
            .font(DesignTokens.TypeScale.control)
        if self.model.magneticFieldOn {
            Toggle("Electron mode", isOn: model.electronMode)
                .font(DesignTokens.TypeScale.control)
                .accessibilityHint("The probe becomes a real electron; realistic fields curve it")
            if self.model.electronMode {
                VStack(alignment: .leading, spacing: 4) {
                    Text("B \(self.model.electronFieldTesla * 1000, specifier: "%.2f") mT   r = mv/qB = \(self.model.cyclotronRadius * 100, specifier: "%.0f") cm")
                        .font(DesignTokens.TypeScale.footnote.monospacedDigit())
                    Slider(value: model.electronFieldTesla, in: FieldModel.electronFieldRange)
                        .accessibilityLabel("Magnetic field strength")
                }
                Text("A real electron at 2×10⁶ m/s: a tenth of a millitesla bends an 11 cm circle. Display time runs 10⁷× slow; the physics is SI-exact.")
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("B \(self.model.magneticFieldTesla / 1000, specifier: "%.0f") kT   r = mv/qB = \(self.model.cyclotronRadius * 100, specifier: "%.0f") cm")
                        .font(DesignTokens.TypeScale.footnote.monospacedDigit())
                    Slider(value: model.magneticFieldTesla, in: FieldModel.magneticFieldRange)
                        .accessibilityLabel("Magnetic field strength")
                }
                Text("F = qv×B curves the probe on an exact cyclotron circle — or flip on Electron mode for realistic fields.")
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Display

    @ViewBuilder
    private func displayToggles(model: Bindable<FieldModel>) -> some View {
        Toggle("Field lines", isOn: model.showLines)
            .accessibilityHint("Continuous lines with arrowheads riding them, showing the field's direction")
    }
}

/// Gauss's law, as a thing you carry through the field.
///
/// A page can state ∮E·dA = Q/ε₀; it cannot let you move the surface.
/// The closed bubble is the demonstration: put a charge inside and the
/// flux jumps to exactly Q/ε₀, take it out and it drops to zero, and
/// nothing you do to the shape's position changes that.
struct GaussSurfaceControls: View {
    @Environment(FieldModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Divider().opacity(0.4)
        Toggle("Gauss surface", isOn: $model.gaussSurfaceOn)
            .accessibilityHint("A flux meter you carry through the field")
        if model.gaussSurfaceOn {
            Picker("Shape", selection: $model.gaussSurfaceKind) {
                ForEach(FieldModel.GaussSurfaceKind.allCases) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Toggle("Move it where I look", isOn: $model.lookToPlace)
                .accessibilityHint("The surface follows the direction your head is facing")
            if model.lookToPlace {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Reach: \(model.lookReach, specifier: "%.2f") m")
                        .font(DesignTokens.TypeScale.control.monospacedDigit())
                    Slider(value: $model.lookReach, in: FieldModel.lookReachRange)
                        .accessibilityLabel("How far along your look direction the surface sits")
                    Text("Head direction, not eye tracking — visionOS never gives an app your gaze.")
                        .font(DesignTokens.TypeScale.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Radius: \(model.gaussSurfaceRadius * 100, specifier: "%.0f") cm")
                    .font(DesignTokens.TypeScale.control)
                Slider(value: $model.gaussSurfaceRadius,
                       in: FieldModel.gaussRadiusRange)
                    .accessibilityLabel("Gauss surface radius")
            }

            if let enclosed = model.gaussEnclosedCharge,
               let predicted = model.gaussPredictedFlux {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Φ measured  \(PhysicsFormat.scientific(model.gaussFlux)) N·m²/C")
                    Text("Q enclosed  \(PhysicsFormat.scientific(enclosed)) C")
                    Text("Q/ε₀        \(PhysicsFormat.scientific(predicted)) N·m²/C")
                }
                .font(DesignTokens.TypeScale.footnote.monospaced())
                Text("Closed surface: the flux is the enclosed charge over ε₀ and nothing else. Carry the bubble anywhere — outside charges contribute exactly zero.")
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("Φ  \(PhysicsFormat.scientific(model.gaussFlux)) N·m²/C")
                    .font(DesignTokens.TypeScale.footnote.monospaced())
                Text("Open surface: tilt it edge-on to the field and the flux falls to zero. Switch to the bubble for Gauss's law.")
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
