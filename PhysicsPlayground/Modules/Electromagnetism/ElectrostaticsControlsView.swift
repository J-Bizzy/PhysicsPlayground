//
//  ElectrostaticsControlsView.swift
//  Physics Playground — Electromagnetism module
//
//  The electromagnetism window content. While the immersive space is
//  open, the floating pods around the field own the everyday controls —
//  repeating them here was pure dead weight, a second place to do the
//  same thing. The window keeps only what the pods can't offer: the
//  precise position sliders for the selected charge (also the
//  accessibility path for moving one without a hand-drag). When the
//  space is closed the pods don't exist, so the full control stack
//  returns as the fallback.
//

import SwiftUI

struct ElectrostaticsControlsView: View {
    @Environment(FieldModel.self) private var model

    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var model = model

        VStack(spacing: DesignTokens.Panel.sectionSpacing) {
            if appModel.isImmersiveSpaceOpen {
                PanelSection("Place a charge precisely") {
                    Text("Select a charge in the field, then set its position exactly — or just drag it by hand.")
                        .font(DesignTokens.TypeScale.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    positionSliders(model: $model)
                }
                Text("Everything else lives on the floating pods around the field.")
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
            } else {
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
    }

    // MARK: Sections

    private func displayToggles(model: Bindable<FieldModel>) -> some View {
        VStack(spacing: 8) {
            Toggle("Field lines", isOn: model.showLines)
                .accessibilityHint("Continuous lines with arrowheads riding them, showing the field's direction")
                .accessibilityHint("Curves that follow the field from positive to negative charges")
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
