//
//  OrbitalMechanicsDataCard.swift
//  The selected body's orbit and energy, floating above the body (via `selectedAnchor`, rig-compensated).
//  Five lines, two readings each, at label size: where it is and how fast, the orbit's size and
//  shape, its two apsides, its tilt and period, and its energy with the word that matters. The
//  orientation angles and the energy split stay in the notebook's capture, not on the body.
//  Values are quantised to the digits shown: the attachment rasterises to a texture, so it
//  rerenders only when a reading changes.
//

import PhysicsCore
import SwiftUI

struct OrbitalMechanicsDataCard: View {
    @Environment(OrbitalMechanicsModel.self) private var model

    var body: some View {
        if let selected = model.selectedBody, let readout = model.readout(for: selected) {
            let elements = model.orbitElements(for: selected.id)
            let au = CelestialBody.astronomicalUnit
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 5) {
                GridRow {
                    reading("r", PhysicsFormat.measurement(quantise(readout.distanceAU, 100), "AU", decimals: 2))
                    reading("v", PhysicsFormat.measurement(quantise(readout.speedKmPerS, 10), "km/s", decimals: 1))
                }
                if let elements {
                    GridRow {
                        reading("a", elements.semiMajorAxis.map {
                            PhysicsFormat.measurement($0 / au, "AU", decimals: 2)
                        } ?? "—")
                        reading("e", PhysicsFormat.fixed(elements.eccentricity, decimals: 3))
                    }
                    GridRow {
                        reading("q", PhysicsFormat.measurement(elements.periapsisRadius / au, "AU", decimals: 2))
                        // A hyperbola's far apsis is algebraically behind the focus — not a distance.
                        reading("Q", elements.hasApoapsis
                                ? PhysicsFormat.measurement(elements.apoapsisRadius / au, "AU", decimals: 2)
                                : "—")
                    }
                    GridRow {
                        reading("i", PhysicsFormat.angle(elements.inclination * 180 / .pi, decimals: 0))
                        reading("T", elements.period.map {
                            PhysicsFormat.measurement($0 / (365.25 * 86_400), "yr", decimals: 2)
                        } ?? "unbound")
                    }
                }
                GridRow {
                    reading("E", PhysicsFormat.scientific(readout.totalEnergy) + " J")
                        .gridCellColumns(1)
                    Text(readout.totalEnergy < 0 ? "bound" : "leaving")
                        .font(DesignTokens.TypeScale.label)
                        .foregroundStyle(.primary.opacity(readout.totalEnergy < 0 ? 0.7 : 1))
                }
            }
            .frame(maxWidth: 300, alignment: .leading)
            .readoutCard()
            .accessibilityElement(children: .combine)
        }
    }

    /// One symbol and one number, the symbol dim and the number bright.
    private func reading(_ symbol: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(symbol)
                .font(DesignTokens.TypeScale.label)
                .foregroundStyle(.primary.opacity(0.7))
                .frame(minWidth: 14, alignment: .trailing)
            Text(value)
                .font(DesignTokens.TypeScale.label.monospacedDigit())
        }
    }

    private func quantise(_ value: Double, _ steps: Double) -> Double {
        (value * steps).rounded() / steps
    }
}
