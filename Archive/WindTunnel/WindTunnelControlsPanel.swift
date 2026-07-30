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
                // The wind slider is a gauge now — a dial mounted on the
                // tunnel's near side, upstream by the fan, which you reach
                // out and turn (DECISIONS.md, 2026-07-29). The number stays
                // here to be read; setting it is a physical act.
                Text("Wind: \(self.model.windSpeed, specifier: "%.2f") m/s")
                    .font(DesignTokens.TypeScale.control.monospacedDigit())
                Text("Turn the wind gauge on the tunnel's near side to change it. The fan spins with it; every streamline, particle, and force follows. Put your hands in the smoke — it bends around them.")
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            CollapsedSection("Test body") {
                // The body menu is gone. Shape was reachable two ways —
                // this menu and the labelled fan on the body's own ring —
                // and the interaction law says the choice belongs in the
                // room (DECISIONS.md, 2026-07-29). The fan wins: it shows
                // all nine bodies at once with their names and glyphs,
                // where the menu showed one and hid eight.
                Text("Body: \(self.model.testBody.displayName) — pinch the body's Shapes petal to swap it.")
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if self.model.testBody == .cylinder {
                    // Spin is the second gauge, which appears only while a
                    // cylinder is in the stream — there is no circulation
                    // to set on a teardrop.
                    Text("Spin: \(self.model.spinRPM, specifier: "%.0f") RPM   lift \(self.model.liftPerSpan, specifier: "%.2f") N/m")
                        .font(DesignTokens.TypeScale.control.monospacedDigit())
                    Text("Turn the spin gauge beside the wind one on the tunnel's near side. Kutta–Joukowski: spin bends the flow, and the bent flow pushes back — the Magnus lift a curveball rides.")
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
