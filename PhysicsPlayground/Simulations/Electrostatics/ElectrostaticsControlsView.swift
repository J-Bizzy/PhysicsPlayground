//
//  ElectrostaticsControlsView.swift
//  Physics Playground — Electrostatics module
//
//  The electrostatics control panel shown in the main window (the shell
//  provides navigation chrome around it). Deliberately few, large controls:
//  edit charges, display toggles, live stats, and a legend that makes the
//  color conventions self-explanatory. Position sliders are a fallback —
//  the primary interaction is grabbing charges in the space.
//

import SwiftUI

struct ElectrostaticsControlsView: View {
    @Environment(FieldModel.self) private var model
    @AppStorage("hasSeenPlacementHint") private var hasSeenHint = false

    var body: some View {
        @Bindable var model = model

        VStack(spacing: 24) {
            if !hasSeenHint {
                placementHint
            }

            VStack(alignment: .leading, spacing: 20) {
                Text("Charges")
                    .font(.headline)
                ChargeControlsView()
                displayToggles(model: $model)
                positionSliders(model: $model)
            }
            .padding(20)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))

            PhysicsStatsView()
                .padding(20)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))

            legend
        }
    }

    // MARK: Sections

    private var placementHint: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "hand.pinch")
                .font(.title2)
                .foregroundStyle(.tint)
            Text("Look at a charge and pinch to grab it, then drag it anywhere — the field follows. The charge with the white halo is the one the sliders edit.")
                .font(.callout)
            Button {
                hasSeenHint = true
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss hint")
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func displayToggles(model: Bindable<FieldModel>) -> some View {
        VStack(spacing: 8) {
            Toggle("Field lines", isOn: model.showLines)
                .accessibilityHint("Curves that follow the field from positive to negative charges")
            Toggle("Arrow grid", isOn: model.showArrows)
                .accessibilityHint("Arrows showing field direction and strength at fixed points")
            Toggle("Equipotential shells", isOn: model.showEquipotentials)
                .accessibilityHint("Translucent surfaces of constant potential, always perpendicular to the field lines")
        }
        .font(.body)
    }

    private func positionSliders(model: Bindable<FieldModel>) -> some View {
        let half = FieldModel.regionExtent / 2
        return DisclosureGroup("Position (or just drag the charge)") {
            VStack(spacing: 12) {
                labeledSlider("Left / Right", value: model.selectedOffset.x, range: -half...half)
                labeledSlider("Down / Up", value: model.selectedOffset.y, range: -half...half)
                labeledSlider("Far / Near", value: model.selectedOffset.z, range: -half...half)
            }
            .padding(.top, 8)
            .disabled(model.wrappedValue.selectedChargeID == nil)
        }
        .font(.body)
    }

    private func labeledSlider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(label)
                .frame(width: 110, alignment: .leading)
                .font(.callout)
            Slider(value: value, in: range)
                .accessibilityLabel(label)
        }
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Legend")
                .font(.headline)
            legendRow(color: .red, text: "Positive charge")
            legendRow(color: .blue, text: "Negative charge")
            legendRow(color: .green, text: "Positive test charge (accelerates via F = qE)")
            legendRow(color: .purple, text: "Negative test charge")
            HStack(spacing: 12) {
                Circle()
                    .fill(.orange.opacity(0.35))
                    .frame(width: 18, height: 18)
                Text("Translucent shells: equal potential (orange +, indigo −), always at right angles to field lines")
                    .font(.callout)
            }
            HStack(spacing: 12) {
                Circle()
                    .stroke(.white, lineWidth: 2)
                    .frame(width: 18, height: 18)
                Text("Halo marks the selected charge")
                    .font(.callout)
            }
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(.cyan)
                    .frame(width: 18, height: 3)
                Text("Field lines run from positive to negative")
                    .font(.callout)
            }
            HStack(spacing: 12) {
                Image(systemName: "arrow.up.right")
                    .foregroundStyle(.yellow)
                    .frame(width: 22)
                Text("Arrows show field direction; longer and brighter means stronger")
                    .font(.callout)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }

    private func legendRow(color: Color, text: String) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(color)
                .frame(width: 18, height: 18)
            Text(text)
                .font(.callout)
        }
    }
}
