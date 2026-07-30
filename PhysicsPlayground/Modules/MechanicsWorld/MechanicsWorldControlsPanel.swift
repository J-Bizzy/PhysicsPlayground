//
//  MechanicsWorldControlsPanel.swift
//  Physics Playground — Mechanics & Energy
//
//  One section per bench, expanded for the one being attended to and
//  folded to a live number for the other.
//
//  Same contract as the E&M world's panel, and the same reason: a
//  collapsed section is still in the accessibility tree and still one
//  tap from open, and that tap also brings its bench forward in the
//  room — so the panel is the second, always-reachable path to focus
//  for a simulator or a user who never raises their hands. See
//  `StationFocus` for the four properties this keeps.
//

import SwiftUI

struct MechanicsWorldControlsPanel: View {
    @Environment(KinematicsModel.self) private var kinematics
    @Environment(PendulumsModel.self) private var pendulums
    @Environment(AppModel.self) private var appModel

    var body: some View {
        VStack(spacing: DesignTokens.Panel.sectionSpacing) {
            StationSection(
                MechanicsStation.projectile.title,
                readout: String(format: "%.1f m/s", kinematics.launchSpeed),
                accent: DesignTokens.Palette.kinematicsAccent,
                isFocused: appModel.mechanicsFocus.focused == .projectile,
                focus: { appModel.mechanicsFocus.focus(.projectile) }
            ) {
                KinematicsControlsPanel()
            }

            StationSection(
                MechanicsStation.pendulum.title,
                readout: pendulumReadout,
                accent: DesignTokens.Palette.pendulumsAccent,
                isFocused: appModel.mechanicsFocus.focused == .pendulum,
                focus: { appModel.mechanicsFocus.focus(.pendulum) }
            ) {
                PendulumsControlsPanel()
            }
        }
    }

    /// The selected bob's period if there is one — the number this
    /// bench exists to make you feel — and otherwise the count.
    private var pendulumReadout: String {
        guard let selected = pendulums.selected else {
            return "\(pendulums.pendulums.count) hanging"
        }
        return String(format: "T %.2f s", selected.period(gravity: pendulums.gravity))
    }
}
