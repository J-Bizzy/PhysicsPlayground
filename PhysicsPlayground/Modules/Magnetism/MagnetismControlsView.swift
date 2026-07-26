//
//  MagnetismControlsView.swift
//  Physics Playground — Magnetism module
//
//  The window controls and the in-space pods: add/remove/flip magnets and
//  set their strength, toggle the field lines and compass grid, and read
//  the live field. The 2D window mirrors the pods as the flat fallback.
//

import SwiftUI

// MARK: - Window (flat fallback)

struct MagnetismControlsView: View {
    @Environment(MagnetismModel.self) private var model

    var body: some View {
        VStack(spacing: DesignTokens.Panel.sectionSpacing) {
            PanelSection("Magnets") { MagnetEditControls() }
            PanelSection("View") { MagnetViewControls() }
            PanelSection { MagnetismStatsView() }
        }
    }
}

// MARK: - Shared control bodies

private struct MagnetEditControls: View {
    @Environment(MagnetismModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: DesignTokens.Panel.rowSpacing) {
            HStack(spacing: DesignTokens.Panel.rowSpacing) {
                Button {
                    model.addMagnet()
                } label: {
                    Label("Add magnet", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.podProminent)
                .disabled(model.magnets.count >= MagnetismModel.magnetBudget)

                Button(role: .destructive) {
                    model.removeSelected()
                } label: {
                    Label("Remove", systemImage: "trash").frame(maxWidth: .infinity)
                }
                .buttonStyle(.podQuiet)
                .disabled(model.magnets.count <= 1)
            }

            Button {
                model.flipSelected()
            } label: {
                Label("Flip poles (N \u{2194} S)", systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.podQuiet)
            .disabled(model.selectedMagnet == nil)

            Toggle("Magnets respond to forces", isOn: $model.dynamicsOn)
                .font(DesignTokens.TypeScale.control)
                .accessibilityHint("Off, magnets hold exactly where you park them — study a frozen arrangement's field. On, they attract, repel, and swing to align.")
            .accessibilityHint("Reverses the selected magnet — turns attraction into repulsion")

            VStack(alignment: .leading, spacing: 6) {
                Text("Strength: \(model.selectedStrength, specifier: "%.1f") A\u{00B7}m\u{00B2}")
                    .font(DesignTokens.TypeScale.control.monospacedDigit())
                Slider(value: $model.selectedStrength, in: MagnetismModel.strengthRange)
                    .disabled(model.selectedMagnet == nil)
                    .accessibilityLabel("Selected magnet strength")
            }

            Text("\(model.magnets.count) of \(MagnetismModel.magnetBudget) magnets — carry one near another and watch them attract, repel, and swing to align.")
                .font(DesignTokens.TypeScale.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

private struct MagnetViewControls: View {
    @Environment(MagnetismModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: DesignTokens.Panel.rowSpacing) {
            Toggle("Field lines", isOn: $model.showFieldLines)
                .font(DesignTokens.TypeScale.control)
                .accessibilityHint("The looping magnetic field lines that thread from N to S")
            Toggle("Compass needles", isOn: $model.showCompasses)
                .font(DesignTokens.TypeScale.control)
                .accessibilityHint("A grid of needles filling the room, each pointing along the local field")
            Toggle("Hand compass", isOn: $model.compassOn)
                .font(DesignTokens.TypeScale.control)
                .accessibilityHint("A brass compass you carry; the needle swings to the field wherever you take it")
            if model.compassOn {
                Text("Carry it around a magnet — \(model.compassMicroTesla, specifier: "%.1f") µT where it is now.")
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
            }

            Button {
                model.isPaused.toggle()
            } label: {
                Label(model.isPaused ? "Resume" : "Freeze",
                      systemImage: model.isPaused ? "play.fill" : "pause.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.podQuiet)
        }
    }
}

struct MagnetismStatsView: View {
    @Environment(MagnetismModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Panel.rowSpacing) {
            Text("Field")
                .font(DesignTokens.TypeScale.sectionHeader)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    Text("|B| at centre").font(DesignTokens.TypeScale.label)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.3f", model.centerFieldMilliTesla))
                        .font(DesignTokens.TypeScale.control.monospacedDigit())
                        .gridColumnAlignment(.trailing)
                    Text("mT").font(DesignTokens.TypeScale.label).foregroundStyle(.secondary)
                }
                GridRow {
                    Text("Magnets").font(DesignTokens.TypeScale.label)
                        .foregroundStyle(.secondary)
                    Text("\(model.magnets.count)")
                        .font(DesignTokens.TypeScale.control.monospacedDigit())
                        .gridColumnAlignment(.trailing)
                    Text("").font(DesignTokens.TypeScale.label)
                }
            }
            Text("Ideal dipoles: B = (\u{03BC}\u{2080}/4\u{03C0})[3(m\u{00B7}r\u{0302})r\u{0302} \u{2212} m]/r\u{00B3}. Every field vector and force here is the exact value.")
                .font(DesignTokens.TypeScale.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Pods (spatial primary)

struct MagnetsPod: View {
    @Environment(MagnetismModel.self) private var model

    var body: some View {
        ControlPod(title: "Magnets", icon: "cylinder.fill",
                   tint: DesignTokens.Palette.magnetismAccent) {
            MagnetEditControls()
        }
    }
}

struct MagnetViewPod: View {
    @Environment(MagnetismModel.self) private var model

    var body: some View {
        ControlPod(title: "View", icon: "eye.fill",
                   tint: DesignTokens.Palette.magnetismAccent) {
            MagnetViewControls()
        }
    }
}
