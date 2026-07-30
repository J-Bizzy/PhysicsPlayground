//
//  KinematicsControlsPanel.swift
//  Physics Playground — Kinematics module
//
//  The module's one-glance panel, pared to what a person reaches for:
//  fire, clear, and the world. Every ball is born at the launcher's
//  muzzle — the staged mid-air basketballs, the hoops and scoring, the
//  throw boost, the custom ball, the wall toggle, and the time slider
//  are all gone from this surface (2026-07-29): they read as clutter
//  that had to be explained, not controls that asked to be used. Walls
//  always bounce; the hoop machinery sleeps in the model.
//

import PhysicsCore
import SwiftUI

struct KinematicsControlsPanel: View {
    @Environment(KinematicsModel.self) private var model

    var body: some View {
        @Bindable var model = model

        VStack(spacing: DesignTokens.Panel.sectionSpacing) {
            PanelSection("Launch") {
                HStack(spacing: 12) {
                    Button {
                        self.model.fire()
                    } label: {
                        Label("Fire", systemImage: "paperplane.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.podProminent)

                    Button {
                        self.model.clearFlights()
                    } label: {
                        Label("Clear", systemImage: "trash.slash")
                    }
                    .buttonStyle(.podQuiet)
                    .disabled(self.model.flights.isEmpty)
                    .accessibilityLabel("Clear every ball")
                }

                Text("Every ball leaves the launcher's muzzle — pinch the orange bead to aim, grab a landed ball and throw it again. Balls bounce off your floor, walls, and ceiling.")
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            CollapsedSection("World") {
                HStack(spacing: 8) {
                    ForEach(KinematicsModel.gravityPresets) { preset in
                        Button(preset.name) {
                            self.model.gravity = preset.gravity
                        }
                        .buttonStyle(.podQuiet)
                        .accessibilityLabel("Gravity of \(preset.name)")
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("g = \(self.model.gravity, specifier: "%.2f") m/s²")
                        .font(DesignTokens.TypeScale.control.monospacedDigit())
                    Slider(value: $model.gravity, in: KinematicsModel.gravityRange)
                        .accessibilityLabel("Gravity")
                }
                Toggle("Bounce off walls", isOn: $model.respectRoomWalls)
                    .font(DesignTokens.TypeScale.control)
                    .accessibilityHint("Off, balls sail through the walls and ceiling")
                Toggle("Air resistance", isOn: $model.airResistance)
                    .font(DesignTokens.TypeScale.control)
                if self.model.airResistance {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Wind: \(self.model.windSpeed, specifier: "%.1f") m/s")
                            .font(DesignTokens.TypeScale.control.monospacedDigit())
                        Slider(value: $model.windSpeed, in: KinematicsModel.windSpeedRange)
                            .accessibilityLabel("Wind speed")
                    }
                }
                // The ball menu is gone — it is a labelled fan on the
                // launcher's Balls petal now (DECISIONS.md, 2026-07-29:
                // a discrete choice gets an object in the room).
                //
                // It also fixes a real bug in passing. This picker was
                // nested INSIDE `if airResistance`, so you could only
                // choose your ball while drag was switched on — and mass
                // and restitution decide the arc and the bounce whether
                // there is air or not. A golf ball and a table-tennis
                // ball are 17× apart in mass; that choice was hidden
                // behind an unrelated toggle.
                Text("Throwing: \(self.model.kind.displayName) — pinch the launcher's Balls petal to swap it.")
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
