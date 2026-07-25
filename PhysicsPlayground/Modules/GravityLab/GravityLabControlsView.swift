//
//  GravityLabControlsView.swift
//  Physics Playground — Gravity Lab module
//
//  The Gravity Lab control panel content: spawn real planets, build a
//  custom one, bend the rules (Sun mass, G), tune trails and vectors,
//  and read the live orbital data. The shell adds the hint, legend, and
//  real-world button around it.
//

import PhysicsCore
import SwiftUI

struct GravityLabControlsView: View {
    @Environment(GravityLabModel.self) private var model

    private let presetColumns = [GridItem(.adaptive(minimum: 92), spacing: 8)]

    var body: some View {
        @Bindable var model = model

        VStack(spacing: DesignTokens.Panel.sectionSpacing) {
            PanelSection("Custom planet") {
                labeledSlider(
                    "Distance", value: $model.customDistanceAU,
                    range: 0.3...4.5, format: "%.2f AU"
                )
                labeledSlider(
                    "Mass", value: $model.customMassExponent,
                    range: 22...28, format: "10^%.1f kg"
                )
                labeledSlider(
                    "Speed", value: $model.customSpeedFactor,
                    range: 0.4...1.6, format: "×%.2f circular"
                )
                if model.customSpeedFactor >= 1.414 {
                    Text("×1.41 (√2) of circular speed is escape velocity — this one leaves.")
                        .font(DesignTokens.TypeScale.footnote)
                        .foregroundStyle(.secondary)
                }
                Button {
                    model.spawnCustom()
                } label: {
                    Label("Spawn", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.podProminent)
                .tint(DesignTokens.Palette.gravityAccent)
                .disabled(model.bodies.count >= GravityLabModel.bodyBudget
                          || model.mode == .lagrange)
            }

            PanelSection("Lagrange points") {
                if model.mode == .solarSystem {
                    Text("Five places where a satellite can ride along with the Moon's orbit — two of them for free, forever.")
                        .font(DesignTokens.TypeScale.label)
                        .foregroundStyle(.secondary)
                    Button {
                        model.enterLagrangeMode()
                    } label: {
                        Label("Enter Lagrange mode", systemImage: "circle.hexagongrid")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.podProminent)
                    .tint(DesignTokens.Palette.gravityAccent)
                    .accessibilityHint("Replaces the scene with Earth, the Moon, and a satellite you can park at the five points")
                } else {
                    Text("Drop the satellite near a marker — its velocity is matched to the rotating frame, then real gravity decides. L4 and L5 hold; L1, L2, and L3 shed it within days.")
                        .font(DesignTokens.TypeScale.label)
                        .foregroundStyle(.secondary)
                    if let captured = model.capturedPointName,
                       let explanation = GravityLabModel.lagrangeExplanations[captured] {
                        Divider()
                        Text("Parked at \(captured)")
                            .font(DesignTokens.TypeScale.sectionHeader)
                            .foregroundStyle(DesignTokens.Palette.target)
                        Text(explanation)
                            .font(DesignTokens.TypeScale.label)
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        model.exitLagrangeMode()
                    } label: {
                        Label("Back to the solar system", systemImage: "sun.max")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.podQuiet)
                }
            }

            PanelSection("Physics") {
                if model.mode == .solarSystem, model.hasSingleSun {
                    labeledSlider(
                        "Sun mass", value: $model.sunMassMultiplier,
                        range: 0.1...5, format: "×%.1f"
                    )
                }
                labeledSlider(
                    "Gravity (G)", value: $model.gMultiplier,
                    range: 0.1...5, format: "×%.1f"
                )
            }
            .font(DesignTokens.TypeScale.control)

            PanelSection {
                GravityLabDataPanel(compact: false)
            }
        }
    }

    private func labeledSlider(
        _ label: String, value: Binding<Double>,
        range: ClosedRange<Double>, format: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(label): \(String(format: format, value.wrappedValue))")
                .font(DesignTokens.TypeScale.control.monospacedDigit())
            Slider(value: value, in: range)
                .accessibilityLabel(label)
                .accessibilityValue(String(format: format, value.wrappedValue))
        }
    }
}

// MARK: - Live orbital data + the equation, for the selected body

struct GravityLabDataPanel: View {
    @Environment(GravityLabModel.self) private var model
    /// Compact = the in-space floating panel; full = the window section.
    var compact: Bool

    var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: DesignTokens.Panel.rowSpacing) {
            if compact {
                Text(model.selectedBody?.body.name ?? "—")
                    .font(DesignTokens.TypeScale.sectionHeader)
            } else {
                HStack {
                    Text("Orbital data")
                        .font(DesignTokens.TypeScale.sectionHeader)
                    Spacer()
                    Picker("Body", selection: Binding(
                        get: { model.selectedBody?.id },
                        set: { if let id = $0 { model.select(id: id) } }
                    )) {
                        ForEach(model.bodies) { orbiting in
                            Text(orbiting.body.name).tag(Optional(orbiting.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityLabel("Selected body")
                }
            }

            if let selected = model.selectedBody,
               let readout = model.readout(for: selected) {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 7) {
                    row("Distance", PhysicsFormat.fixed(readout.distanceAU), "AU")
                    row("Speed", PhysicsFormat.fixed(readout.speedKmPerS), "km/s")
                    row("Escape speed", PhysicsFormat.fixed(readout.escapeSpeedKmPerS), "km/s")
                    if let period = readout.periodDays {
                        row("Period",
                            period < 1000 ? PhysicsFormat.fixed(period) : PhysicsFormat.fixed(period / 365.25),
                            period < 1000 ? "days" : "years")
                    }
                    if !compact {
                        row("Mass", PhysicsFormat.scientific(readout.massKg), "kg")
                        row("Acceleration", PhysicsFormat.scientific(readout.accelerationMS2), "m/s²")
                        row("Kinetic E", PhysicsFormat.scientific(readout.kineticEnergy), "J")
                        row("Potential E", PhysicsFormat.scientific(readout.potentialEnergy), "J")
                        row("Total E", PhysicsFormat.scientific(readout.totalEnergy), "J")
                    }
                }

                boundBadge(readout)
                equation(readout, name: selected.body.name)
            } else if model.selectedBody?.id == model.primaryBody?.id {
                Text("The Sun anchors the system — grab it and drag to see every orbit follow. Select a planet for orbital data.")
                    .font(DesignTokens.TypeScale.label)
                    .foregroundStyle(.secondary)
            } else {
                Text("Grab a body to select it.")
                    .font(DesignTokens.TypeScale.label)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func boundBadge(_ readout: GravityLabModel.Readout) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(readout.isBound ? Color.green : Color.red)
                .frame(width: 10, height: 10)
            Text(readout.isBound
                 ? "Bound orbit — total energy is negative"
                 : "Escaping! Faster than escape velocity — total energy is positive")
                .font(DesignTokens.TypeScale.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    /// F = G·M·m/r², color-coded, every value live.
    private func equation(_ readout: GravityLabModel.Readout, name: String) -> some View {
        let f = AttributedString("F")
        var fMutable = f
        fMutable.foregroundColor = DesignTokens.Palette.forceVector
        fMutable.font = .system(size: UIFont.labelFontSize, weight: .bold)

        let eq = AttributedString(" = G · ")

        let mSun = AttributedString("M")
        var mSunMutable = mSun
        mSunMutable.foregroundColor = DesignTokens.Palette.sunColor
        mSunMutable.font = .system(size: UIFont.labelFontSize, weight: .bold)

        let dot = AttributedString(" · ")

        let m = AttributedString("m")
        var mMutable = m
        mMutable.foregroundColor = DesignTokens.Palette.gravityAccent
        mMutable.font = .system(size: UIFont.labelFontSize, weight: .bold)

        let div = AttributedString(" / ")

        let r = AttributedString("r")
        var rMutable = r
        rMutable.foregroundColor = DesignTokens.Palette.fieldLine
        rMutable.font = .system(size: UIFont.labelFontSize, weight: .bold)

        let squared = AttributedString("²")

        let forceString = AttributedString(PhysicsFormat.scientific(readout.forceNewtons) + " N")
        var forceStringMutable = forceString
        forceStringMutable.foregroundColor = DesignTokens.Palette.forceVector

        let middleDot1 = AttributedString("  ·  ")

        let rString = AttributedString("r = " + PhysicsFormat.fixed(readout.distanceAU) + " AU")
        var rStringMutable = rString
        rStringMutable.foregroundColor = DesignTokens.Palette.fieldLine

        let middleDot2 = AttributedString("  ·  ")

        let mString = AttributedString("m = " + PhysicsFormat.scientific(readout.massKg) + " kg")
        var mStringMutable = mString
        mStringMutable.foregroundColor = DesignTokens.Palette.gravityAccent

        return VStack(alignment: .leading, spacing: 4) {
            Text(fMutable + eq + mSunMutable + dot + mMutable + div + rMutable + squared)
                .font(DesignTokens.TypeScale.control)

            Text(forceStringMutable + middleDot1 + rStringMutable + middleDot2 + mStringMutable)
                .font(DesignTokens.TypeScale.footnote)
        }
        .accessibilityLabel(
            "Newton's law of gravitation. Force \(PhysicsFormat.scientific(readout.forceNewtons)) newtons at \(PhysicsFormat.fixed(readout.distanceAU)) astronomical units."
        )
    }

    private func row(_ label: String, _ value: String, _ unit: String) -> some View {
        GridRow {
            Text(label)
                .font(DesignTokens.TypeScale.label)
                .foregroundStyle(.secondary)
            Text(value)
                .font(DesignTokens.TypeScale.control.monospacedDigit())
                .gridColumnAlignment(.trailing)
            Text(unit)
                .font(DesignTokens.TypeScale.label)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value) \(unit)")
    }
}

