//
//  WindTunnelControlsPanel.swift
//  Physics Playground — Wind Tunnel module
//
//  The module's one-glance panel — and, at last, the wind gauge the
//  scene's header comment promised. The always-open card is the wind
//  itself; the body (shape and the spin that makes Magnus lift), the
//  display layers, and the probe's numbers wait behind collapsed
//  sections. The test body's own ring carries size and next-shape.
//

import PhysicsCore
import SwiftUI

struct WindTunnelControlsPanel: View {
    @Environment(WindTunnelModel.self) private var model

    var body: some View {
        @Bindable var model = model

        VStack(spacing: DesignTokens.Panel.sectionSpacing) {
            PanelSection("Wind") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Wind: \(self.model.windSpeed, specifier: "%.2f") m/s")
                        .font(DesignTokens.TypeScale.control.monospacedDigit())
                    Slider(value: $model.windSpeed, in: WindTunnelModel.windSpeedRange)
                        .accessibilityLabel("Wind speed")
                }
                Text("The fan spins with it; every streamline, particle, and force follows. Put your hands in the smoke — it bends around them.")
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            CollapsedSection("Test body") {
                Picker("Body", selection: $model.testBody) {
                    ForEach(DragBody.allCases) { body in
                        Text(body.displayName).tag(body)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityLabel("Test body")

                if self.model.testBody == .cylinder {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Spin: \(self.model.spinRPM, specifier: "%.0f") RPM   lift \(self.model.liftPerSpan, specifier: "%.2f") N/m")
                            .font(DesignTokens.TypeScale.control.monospacedDigit())
                        Slider(value: $model.circulation,
                               in: WindTunnelModel.circulationRange)
                            .accessibilityLabel("Cylinder spin")
                    }
                    Text("Kutta–Joukowski: spin bends the flow, and the bent flow pushes back — the Magnus lift a curveball rides.")
                        .font(DesignTokens.TypeScale.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Drag: \(self.model.dragForce, specifier: "%.3f") N at this wind")
                        .font(DesignTokens.TypeScale.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            CollapsedSection("Display") {
                Toggle("Pressure skin", isOn: $model.showPressureSkin)
                    .font(DesignTokens.TypeScale.control)
                Toggle("Streamlines", isOn: $model.showStreamlines)
                    .font(DesignTokens.TypeScale.control)
                Toggle("Smoke particles", isOn: $model.showParticles)
                    .font(DesignTokens.TypeScale.control)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Time: \(self.model.timeScale, specifier: "%.1f")×")
                        .font(DesignTokens.TypeScale.control.monospacedDigit())
                    Slider(value: $model.timeScale, in: WindTunnelModel.timeScaleRange)
                        .accessibilityLabel("Time scale")
                }
            }

            CollapsedSection("Numbers") {
                WindTunnelProbeReadout()
                Text("The probe's reading — drag the white bead through the flow.")
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
