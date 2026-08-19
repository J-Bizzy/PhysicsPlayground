//
//  GravityLabDataCard.swift
//  The selected body's orbit and energy, floating above the body (via `selectedAnchor`, rig-compensated).
//  Values are formatted to fixed precision: the attachment rasterises to a texture, so it rerenders only when a reading changes.
//

import PhysicsCore
import SwiftUI

struct GravityLabDataCard: View {
    @Environment(GravityLabModel.self) private var model

    var body: some View {
        if let selected = model.selectedBody {
            VStack(alignment: .leading, spacing: 6) {
                Text(selected.body.name)
                    .font(DesignTokens.TypeScale.control.weight(.semibold))

                if let elements = model.orbitElements(for: selected.id) {
                    orbitRows(elements)
                }
                if let readout = model.readout(for: selected) {
                    Divider().opacity(0.4)
                    energyRows(readout)
                }
            }
            .frame(maxWidth: 280, alignment: .leading)
            .readoutCard()
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private func orbitRows(_ elements: OrbitalElements) -> some View {
        let au = CelestialBody.astronomicalUnit
        row("a", elements.semiMajorAxis.map { PhysicsFormat.measurement($0 / au, "AU", decimals: 3) }
            ?? "∞ (parabolic)")
        row("e", PhysicsFormat.fixed(elements.eccentricity, decimals: 4))
        row("r_p", PhysicsFormat.measurement(elements.periapsisRadius / au, "AU", decimals: 3))
        // A hyperbola's far apsis is algebraically behind the focus — correct, and not a distance to read out.
        row("r_a", elements.hasApoapsis
            ? PhysicsFormat.measurement(elements.apoapsisRadius / au, "AU", decimals: 3)
            : "—")
        row("i", degrees(elements.inclination))
        // Ω/ω are conventions, not measurements, for degenerate orbits — omit rather than show a meaningless number.
        if elements.degeneracy != .equatorial
            && elements.degeneracy != .circularEquatorial {
            row("Ω", degrees(elements.longitudeOfAscendingNode))
        }
        if elements.degeneracy != .circular
            && elements.degeneracy != .circularEquatorial {
            row("ω", degrees(elements.argumentOfPeriapsis))
        }
        row("ν", degrees(elements.trueAnomaly))
        row("T", elements.period.map {
            PhysicsFormat.measurement($0 / (365.25 * 86_400), "years", decimals: 2)
        } ?? "unbound")
        if elements.degeneracy != .none {
            Text(degeneracyNote(elements.degeneracy))
                .font(DesignTokens.TypeScale.footnote)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func energyRows(_ readout: GravityLabModel.Readout) -> some View {
        row("Kinetic", PhysicsFormat.scientific(readout.kineticEnergy) + " J")
        row("Potential", PhysicsFormat.scientific(readout.potentialEnergy) + " J")
        row("Total", PhysicsFormat.scientific(readout.totalEnergy) + " J")
        Text(readout.totalEnergy < 0
             ? "Negative: bound. It comes back."
             : "Positive: unbound. It is leaving.")
            .font(DesignTokens.TypeScale.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(DesignTokens.TypeScale.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(value)
                .font(DesignTokens.TypeScale.footnote.monospacedDigit())
        }
    }

    /// Tenths of a degree, not hundredths: finer precision re-rasterises the card every frame at high clock speeds.
    private func degrees(_ radians: Double) -> String {
        PhysicsFormat.angle(radians * 180 / .pi)
    }

    private func degeneracyNote(_ degeneracy: OrbitDegeneracy) -> String {
        switch degeneracy {
        case .none: ""
        case .circular:
            "Circular: no periapsis, so ω is a convention and ν is measured "
            + "from the ascending node."
        case .equatorial:
            "In the reference plane: no node, so Ω is a convention and ω is "
            + "measured from the +x axis."
        case .circularEquatorial:
            "Circular and in the reference plane: neither a periapsis nor a "
            + "node exists, so ν is measured from the +x axis."
        }
    }
}
