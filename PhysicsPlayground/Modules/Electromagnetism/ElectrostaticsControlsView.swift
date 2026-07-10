//
//  ElectrostaticsControlsView.swift
//  Physics Playground — Electromagnetism module
//
//  The electromagnetism control panel content. The shell wraps it with the
//  shared chrome (first-run hint above, legend and real-world button below),
//  so this view supplies only the module-specific sections: charge editing,
//  display toggles, fallback position sliders, and the live stats readout.
//

import SwiftUI

struct ElectrostaticsControlsView: View {
    @Environment(FieldModel.self) private var model

    var body: some View {
        @Bindable var model = model

        VStack(spacing: DesignTokens.Panel.sectionSpacing) {
            PanelSection("Charges") {
                ChargeControlsView()
                displayToggles(model: $model)
                positionSliders(model: $model)
            }

            PanelSection {
                PhysicsStatsView()
            }
        }
    }

    // MARK: Sections

    private func displayToggles(model: Bindable<FieldModel>) -> some View {
        VStack(spacing: 8) {
            Toggle("Field lines", isOn: model.showLines)
                .accessibilityHint("Curves that follow the field from positive to negative charges")
            Toggle("Arrow grid", isOn: model.showArrows)
                .accessibilityHint("Arrows showing field direction and strength at fixed points")
            Toggle("Equipotential shells", isOn: model.showEquipotentials)
                .accessibilityHint("Translucent surfaces of constant potential, always perpendicular to the field lines")
        }
        .font(DesignTokens.TypeScale.control)
    }

    private func positionSliders(model: Bindable<FieldModel>) -> some View {
        let half = FieldModel.regionExtent / 2
        return DisclosureGroup("Position (or just drag the charge)") {
            VStack(spacing: DesignTokens.Panel.rowSpacing) {
                labeledSlider("Left / Right", value: model.selectedOffset.x, range: -half...half)
                labeledSlider("Down / Up", value: model.selectedOffset.y, range: -half...half)
                labeledSlider("Far / Near", value: model.selectedOffset.z, range: -half...half)
            }
            .padding(.top, 8)
            .disabled(model.wrappedValue.selectedChargeID == nil)
        }
        .font(DesignTokens.TypeScale.control)
    }

    private func labeledSlider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(label)
                .frame(width: 110, alignment: .leading)
                .font(DesignTokens.TypeScale.label)
            Slider(value: value, in: range)
                .accessibilityLabel(label)
        }
    }
}
