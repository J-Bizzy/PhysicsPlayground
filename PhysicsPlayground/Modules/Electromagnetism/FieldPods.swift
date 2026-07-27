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

        // Wider than the default so "Charges respond to forces" fits on
        // ONE line. At 252 it wrapped to two, which pushed the row of
        // destructive buttons past the bottom of the pod — they were
        // sliced in half by the glass they were sitting on.
        ControlPod(title: "Charges", icon: "bolt.fill",
                   tint: DesignTokens.Palette.positive, width: 330) {
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

            // Sign and magnitude on ONE row, because they are one
            // quantity: the charge is q, and "+ 1.0 µC" is a single
            // reading. Splitting them cost a whole extra row, and this
            // pod had run out of room — the attachment caps its height,
            // so the buttons at the bottom were being drawn below the
            // glass they belong to, outside the pod entirely.
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Text("Strength: \(model.selectedMagnitudeMicroCoulombs, specifier: "%.1f") µC")
                        .font(DesignTokens.TypeScale.control.monospacedDigit())
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Picker("Polarity", selection: $model.selectedIsPositive) {
                        Text("+").tag(true)
                        Text("−").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 96)
                    .disabled(!hasSelection)
                    .accessibilityLabel("Charge polarity")
                }
                Slider(value: $model.selectedMagnitudeMicroCoulombs, in: 0.1...5.0, step: 0.1)
                    .disabled(!hasSelection)
                    .accessibilityLabel("Charge strength")
            }

            // Short label, sentence in the hint: a control's label is not
            // the place to explain the physics.
            Toggle("Free to move", isOn: $model.chargesRespond)
                .font(DesignTokens.TypeScale.control)
                .lineLimit(1)
                .accessibilityHint("Free the charges: opposites drift together, likes push apart. Off, they stay exactly where you put them.")

            HStack(spacing: 8) {
                Button(role: .destructive) {
                    model.removeSelectedCharge()
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
                    model.removeAllCharges()
                } label: {
                    Label("Clear all", systemImage: "trash.slash")
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
        GaussSurfaceControls()
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
