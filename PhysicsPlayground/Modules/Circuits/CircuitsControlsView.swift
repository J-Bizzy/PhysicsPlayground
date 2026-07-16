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
                        .buttonStyle(.bordered)
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
                .buttonStyle(.bordered)
                .disabled(model.selectedComponent == nil)

                Text("Grab parts to carry them anywhere. Pinch a copper terminal, then another, to wire them; pinch a wire to remove it.")
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
            }

            PanelSection("Selected part") {
                if let component = model.selectedComponent {
                    selectedControls(for: component, model: $model)
                } else {
                    Text("Grab a part to select it.")
                        .font(DesignTokens.TypeScale.label)
                        .foregroundStyle(.secondary)
                }
            }

            PanelSection("Display") {
                Toggle("Electron flow", isOn: $model.showElectronFlow)
                    .font(DesignTokens.TypeScale.control)
                    .accessibilityHint("Cyan dots drifting along every live wire")
                Text("The dots are electrons: they drift from − to +, opposite the conventional current arrow — a 280-year-old sign convention we're stuck with.")
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
            }

            PanelSection {
                CircuitsStatsView()
            }
        }
    }

    @ViewBuilder
    private func selectedControls(
        for component: CircuitsModel.Component,
        model: Bindable<CircuitsModel>
    ) -> some View {
        let readout = self.model.readouts[component.id]

        switch component.kind {
        case .battery:
            valueSlider("Voltage", model: model, range: 1.5...24,
                        format: { String(format: "%.1f V", $0) })
        case .resistor:
            logSlider("Resistance", model: model, range: 1...10_000,
                      format: { $0 >= 1000 ? String(format: "%.1f kΩ", $0 / 1000)
                                           : String(format: "%.0f Ω", $0) })
            Text("The color bands are the real code — read them like an engineer.")
                .font(DesignTokens.TypeScale.footnote)
                .foregroundStyle(.secondary)
        case .bulb:
            logSlider("Filament resistance", model: model, range: 5...500,
                      format: { String(format: "%.0f Ω", $0) })
        case .capacitor:
            logSlider("Capacitance", model: model, range: 1e-5...1e-2,
                      format: { $0 >= 1e-3 ? String(format: "%.1f mF", $0 * 1000)
                                           : String(format: "%.0f µF", $0 * 1e6) })
        case .switcher:
            Toggle("Closed", isOn: model.selectedIsClosed)
                .font(DesignTokens.TypeScale.control)
        }

        if let readout {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                row("Voltage across", String(format: "%.2f", abs(readout.volts)), "V")
                row("Current through", String(format: "%.1f", abs(readout.amps) * 1000), "mA")
                row("Power", String(format: "%.2f", abs(readout.watts)), "W")
                if component.kind == .capacitor {
                    row("Charged to", String(format: "%.2f", component.capacitorVoltage), "V")
                }
            }
        }
    }

    private func valueSlider(
        _ label: String, model: Bindable<CircuitsModel>,
        range: ClosedRange<Double>, format: @escaping (Double) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(label): \(format(self.model.selectedValue))")
                .font(DesignTokens.TypeScale.control.monospacedDigit())
            Slider(value: model.selectedValue, in: range)
                .accessibilityLabel(label)
        }
    }

    private func logSlider(
        _ label: String, model: Bindable<CircuitsModel>,
        range: ClosedRange<Double>, format: @escaping (Double) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(label): \(format(self.model.selectedValue))")
                .font(DesignTokens.TypeScale.control.monospacedDigit())
            Slider(
                value: Binding(
                    get: { log10(max(self.model.selectedValue, range.lowerBound)) },
                    set: { self.model.selectedValue = pow(10, $0) }
                ),
                in: log10(range.lowerBound)...log10(range.upperBound)
            )
            .accessibilityLabel(label)
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
