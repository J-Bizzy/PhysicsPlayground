//
//  WindTunnelControlsView.swift
//  Physics Playground — Wind Tunnel module
//
//  The wind tunnel control panel content: wind and cylinder, the Magnus
//  spin, display toggles, and the live aerodynamic numbers. The shell
//  adds the hint, legend, and real-world button around it.
//

import PhysicsCore
import SwiftUI

struct WindTunnelControlsView: View {
    @Environment(WindTunnelModel.self) private var model

    var body: some View {
        @Bindable var model = model

        VStack(spacing: DesignTokens.Panel.sectionSpacing) {
            PanelSection("Wind tunnel") {
                labeledSlider(
                    "Wind speed", value: $model.windSpeed,
                    range: WindTunnelModel.windSpeedRange, format: "%.2f m/s"
                )
                labeledSlider(
                    "Cylinder radius", value: $model.cylinderRadius,
                    range: WindTunnelModel.radiusRange, format: "%.0f cm",
                    scale: 100
                )
                Toggle("Streamlines", isOn: $model.showStreamlines)
                    .accessibilityHint("Lines the air actually follows")
                Toggle("Air particles", isOn: $model.showParticles)
                    .accessibilityHint("A sheet of particles carried by the flow at true speed")
            }
            .font(DesignTokens.TypeScale.control)

            PanelSection("Spin — the Magnus effect") {
                labeledSlider(
                    "Spin", value: $model.circulation,
                    range: WindTunnelModel.circulationRange, format: "%.2f m²/s"
                )
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    row("Spin rate", String(format: "%.0f", model.spinRPM), "rpm")
                    row("Lift (ρUΓ)", String(format: "%.2f", abs(model.liftPerSpan)),
                        model.liftPerSpan == 0 ? "N/m"
                        : "N/m \(model.liftPerSpan > 0 ? "→ near side" : "→ far side")")
                }
                Text(model.stagnationPoints.isEmpty
                     ? "Spin is past the critical value — the stagnation point has lifted off the surface entirely."
                     : "The red dots are stagnation points: air comes to rest there. Watch them slide around as you add spin.")
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
            }
            .font(DesignTokens.TypeScale.control)

            PanelSection {
                WindTunnelStatsView()
            }
        }
    }

    private func labeledSlider(
        _ label: String, value: Binding<Double>,
        range: ClosedRange<Double>, format: String, scale: Double = 1
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(label): \(String(format: format, value.wrappedValue * scale))")
                .font(DesignTokens.TypeScale.control.monospacedDigit())
            Slider(value: value, in: range)
                .accessibilityLabel(label)
                .accessibilityValue(String(format: format, value.wrappedValue * scale))
        }
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

// MARK: - Live aerodynamic numbers

struct WindTunnelStatsView: View {
    @Environment(WindTunnelModel.self) private var model

    var body: some View {
        let readout = model.probeReadout
        let shoulders = model.shoulderSpeeds

        VStack(alignment: .leading, spacing: DesignTokens.Panel.rowSpacing) {
            HStack {
                Text("Aerodynamics")
                    .font(DesignTokens.TypeScale.sectionHeader)
                Spacer()
                Text("exact solution")
                    .font(.caption.smallCaps())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: Capsule())
                    .foregroundStyle(.secondary)
            }

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                row("Near-side shoulder", String(format: "%.2f", shoulders.top), "m/s")
                row("Far-side shoulder", String(format: "%.2f", shoulders.bottom), "m/s")
                row("Probe speed", String(format: "%.2f", readout.speed), "m/s")
                row("Probe Cp", String(format: "%.2f", readout.pressureCoefficient), "")
            }

            Text("Cp = 1 − (v/U)²: +1 where the air rests (high pressure), negative where it rushes (low pressure). Faster shoulder + slower shoulder = the pressure imbalance that IS lift.")
                .font(DesignTokens.TypeScale.footnote)
                .foregroundStyle(.secondary)

            Divider()

            Text("Drag here is exactly zero — d'Alembert's paradox. Ideal air has no friction; real drag comes from viscosity and the wake, which is why streamlining matters (see the real-world panel).")
                .font(DesignTokens.TypeScale.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .contain)
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
