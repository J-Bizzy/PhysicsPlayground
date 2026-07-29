//
//  FieldControlsPanel.swift
//  Physics Playground — Electromagnetism module
//
//  The module's flat control panel, back in the window. The rebuild
//  moved every control into spatial affordances — wells you pull new
//  charges from, a bloom that unfurls on the charge you look at — and
//  they are lovely in a headset, but they are revealed by gaze: in the
//  simulator they barely exist, and nothing about them can be
//  discovered by reading. This panel is the discoverable, labelled,
//  accessibility-friendly path to the same model. The spatial
//  affordances remain; the two paths edit the one FieldModel.
//
//  The sliders always edit the *selected* charge — the one most
//  recently added, tapped, or grabbed, marked with a white halo.
//
//  Largely restored from the pre-rebuild ChargeControlsView / FieldPods
//  (774a621), rewired against the current model surface.
//

import PhysicsCore
import SwiftUI

struct FieldControlsPanel: View {
    @Environment(FieldModel.self) private var model

    var body: some View {
        @Bindable var model = model

        VStack(spacing: DesignTokens.Panel.sectionSpacing) {
            PanelSection("Charges") {
                chargeControls(model: $model)
            }
            PanelSection("Test charge") {
                probeControls(model: $model)
            }
            PanelSection("Uniform fields") {
                uniformFieldControls(model: $model)
            }
            PanelSection("Display") {
                displayToggles(model: $model)
                GaussSurfaceControls()
            }
            PanelSection {
                PhysicsStatsView()
            }
        }
    }

    // MARK: Charges

    @ViewBuilder
    private func chargeControls(model: Bindable<FieldModel>) -> some View {
        let hasSelection = self.model.selectedChargeID != nil

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
        }

        // Sign and magnitude together, because they are one quantity:
        // the charge is q, and "+ 1.0 µC" is a single reading.
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text("Strength: \(self.model.selectedMagnitudeMicroCoulombs, specifier: "%.1f") µC")
                    .font(DesignTokens.TypeScale.control.monospacedDigit())
                    .lineLimit(1)
                Spacer(minLength: 4)
                Picker("Polarity", selection: model.selectedIsPositive) {
                    Text("+").tag(true)
                    Text("−").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(width: 96)
                .disabled(!hasSelection)
                .accessibilityLabel("Charge polarity")
            }
            Slider(value: model.selectedMagnitudeMicroCoulombs,
                   in: FieldModel.magnitudeRange, step: 0.1)
                .disabled(!hasSelection)
                .accessibilityLabel("Charge strength")
                .accessibilityValue("\(self.model.selectedMagnitudeMicroCoulombs, specifier: "%.1f") microcoulombs")
        }

        Toggle("Charges respond to forces", isOn: model.chargesRespond)
            .font(DesignTokens.TypeScale.control)
            .accessibilityHint("Free the charges: opposites drift together, likes push apart. Off, they stay exactly where you put them.")

        HStack(spacing: 12) {
            Button(role: .destructive) {
                self.model.removeSelectedCharge()
            } label: {
                // Named, not just a glyph. "trash" and "trash.slash"
                // side by side are indistinguishable at arm's length,
                // and one of them clears the whole room.
                Label("Remove", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .disabled(!hasSelection)
            .accessibilityLabel("Remove selected charge")

            Button(role: .destructive) {
                self.model.removeAllCharges()
            } label: {
                Label("Clear all", systemImage: "trash.slash")
                    .frame(maxWidth: .infinity)
            }
            .disabled(self.model.charges.isEmpty)
            .accessibilityLabel("Remove all charges")
        }
        .buttonStyle(.podQuiet)

        positionSliders(model: model)

        Text(statusLine)
            .font(DesignTokens.TypeScale.footnote)
            .foregroundStyle(.secondary)
    }

    private var statusLine: String {
        let count = model.charges.count
        guard count > 0 else { return "No charges — add one to see a field." }
        let selected = model.selectedCharge.map {
            "editing the \($0.isPositive ? "red" : "blue") one with the halo"
        }
        return "\(count) charge\(count == 1 ? "" : "s") in the field\(selected.map { " — \($0)" } ?? "")."
    }

    /// The precise path — also the accessibility path for moving a
    /// charge without a hand-drag.
    private func positionSliders(model: Bindable<FieldModel>) -> some View {
        let half = FieldModel.regionExtent / 2
        return DisclosureGroup("Position (or just drag the charge)") {
            VStack(spacing: DesignTokens.Panel.rowSpacing) {
                labeledSlider("Left / Right", value: model.selectedOffset.x, range: -half...half)
                labeledSlider("Down / Up", value: model.selectedOffset.y, range: -half...half)
                labeledSlider("Far / Near", value: model.selectedOffset.z, range: -half...half)
            }
            .padding(.top, 8)
            .disabled(self.model.selectedChargeID == nil)
        }
        .font(DesignTokens.TypeScale.control)
    }

    private func labeledSlider(_ label: String, value: Binding<Double>,
                               range: ClosedRange<Double>) -> some View {
        HStack {
            Text(label)
                .frame(width: 110, alignment: .leading)
                .font(DesignTokens.TypeScale.label)
            Slider(value: value, in: range)
                .accessibilityLabel(label)
        }
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
        Toggle("Equipotential shells", isOn: model.showEquipotentials)
            .accessibilityHint("Translucent surfaces of constant potential, always perpendicular to the field lines")
        if self.model.showEquipotentials {
            Stepper("Casings: \(self.model.equipotentialShells)",
                    value: model.equipotentialShells, in: 1...6)
        }
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
