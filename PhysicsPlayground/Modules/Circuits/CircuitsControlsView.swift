//
//  CircuitsControlsView.swift
//  Physics Playground — Circuits module
//
//  The circuit lab control panel: the parts palette, the selected
//  component's editable value (V, Ω, or F — sliders are logarithmic
//  where the quantity spans decades), display options, and the live
//  electrical summary. The shell adds the hint, legend, and real-world
//  button around it.
//

import PhysicsCore
import SwiftUI

struct CircuitsControlsView: View {
    @Environment(CircuitsModel.self) private var model

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 8)]

    var body: some View {
        @Bindable var model = model

        VStack(spacing: DesignTokens.Panel.sectionSpacing) {
            PanelSection("Parts") {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(CircuitsModel.ComponentKind.allCases) { kind in
                        Button(kind.displayName) {
                            model.add(kind)
                        }
                        .buttonStyle(.podQuiet)
                        .disabled(model.components.count >= CircuitsModel.componentBudget)
                        .accessibilityLabel("Add a \(kind.displayName)")
                    }
                }

                Button(role: .destructive) {
                    model.removeSelected()
                } label: {
                    Label("Remove selected part", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.podQuiet)
                .disabled(model.selectedComponent == nil)

                Text("Grab parts to carry them anywhere. Pinch a copper terminal, then another, to wire them; pinch a wire to remove it.")
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
            }

            PanelSection {
                CircuitsStatsView()
            }
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

// MARK: - Lab summary

struct CircuitsStatsView: View {
    @Environment(CircuitsModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Panel.rowSpacing) {
            HStack {
                Text("The whole circuit")
                    .font(DesignTokens.TypeScale.sectionHeader)
                Spacer()
                Text("solved live")
                    .font(.caption.smallCaps())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: Capsule())
                    .foregroundStyle(.secondary)
            }

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    Text("Parts").font(DesignTokens.TypeScale.label).foregroundStyle(.secondary)
                    Text("\(model.components.count)")
                        .font(DesignTokens.TypeScale.control.monospacedDigit())
                        .gridColumnAlignment(.trailing)
                    Text("of \(CircuitsModel.componentBudget)")
                        .font(DesignTokens.TypeScale.label).foregroundStyle(.secondary)
                }
                GridRow {
                    Text("Wires").font(DesignTokens.TypeScale.label).foregroundStyle(.secondary)
                    Text("\(model.wires.count)")
                        .font(DesignTokens.TypeScale.control.monospacedDigit())
                        .gridColumnAlignment(.trailing)
                    Text("of \(CircuitsModel.wireBudget)")
                        .font(DesignTokens.TypeScale.label).foregroundStyle(.secondary)
                }
                GridRow {
                    Text("Source power").font(DesignTokens.TypeScale.label).foregroundStyle(.secondary)
                    Text(String(format: "%.2f", model.totalSourcePower))
                        .font(DesignTokens.TypeScale.control.monospacedDigit())
                        .gridColumnAlignment(.trailing)
                    Text("W").font(DesignTokens.TypeScale.label).foregroundStyle(.secondary)
                }
            }

            Text("Every number comes from one nodal solve of your whole build, every frame — Kirchhoff's laws hold by construction, and batteries carry a real 0.05 Ω inside (short one and watch the numbers say why that's a bad idea).")
                .font(DesignTokens.TypeScale.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .contain)
    }
}
