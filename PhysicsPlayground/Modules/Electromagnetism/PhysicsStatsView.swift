//
//  PhysicsStatsView.swift
//  Physics Playground — Electromagnetism module
//
//  Live physics readout anchored to the test charge: the field, potential,
//  force, acceleration, and speed at its current position, updating every
//  simulation frame. Shared by the in-space stats panel and the window.
//

import SwiftUI

struct PhysicsStatsView: View {
    @Environment(FieldModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Physics")
                    .font(.headline)
                Spacer()
                statusBadge
            }

            if let readout = model.probeReadout {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    statRow("E field", PhysicsFormat.scientific(readout.fieldMagnitude), "N/C")
                    statRow("Potential", PhysicsFormat.scientific(readout.potential), "V")
                    statRow("Force", PhysicsFormat.scientific(readout.forceMagnitude), "N")
                    statRow("Acceleration", PhysicsFormat.fixed(readout.acceleration), "m/s²")
                    statRow("Speed", PhysicsFormat.fixed(readout.speed), "m/s")
                }

                Text("Test charge: q = \(model.probeIsPositive ? "+" : "−")\(model.probeChargeMagnitude * 1e9, specifier: "%.0f") nC, m = 0.5 g.  F = qE, a = F/m.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("Drop a test charge to see the field value, force, and motion at its location.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var statusBadge: some View {
        let (text, color): (String, Color) = switch model.probeStatus {
        case .none: ("no probe", .secondary)
        case .running: ("running", .green)
        case .held: ("held", .orange)
        case .captured: ("captured", .red)
        case .escaped: ("escaped", .secondary)
        }
        return Text(text)
            .font(.caption.smallCaps())
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.quaternary, in: Capsule())
            .foregroundStyle(color)
            .accessibilityLabel("Test charge status: \(text)")
    }

    private func statRow(_ label: String, _ value: String, _ unit: String) -> some View {
        GridRow {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body.monospacedDigit())
                .gridColumnAlignment(.trailing)
            Text(unit)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value) \(unit)")
    }
}
