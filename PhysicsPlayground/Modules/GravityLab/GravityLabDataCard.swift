//
//  GravityLabDataCard.swift
//  Physics Playground — Gravity Lab module
//
//  The selected body's orbit and energy, floating above the body itself.
//
//  This is the module's physics made legible, and it used to live two
//  taps deep in the window panel behind "This orbit" and "Energy" — nine
//  orbital elements and four energies, in a dropdown, beside an orrery
//  you were supposed to be looking at. It hangs on the body now.
//
//  `GravityLabRenderer.selectedAnchor` was built for exactly this and
//  says so in its own doc comment ("the space view attaches the SwiftUI
//  attachment here"). It has been billboarded, parented and repositioned
//  above the selected body every frame, carrying nothing, since the
//  renderer was written.
//
//  THE ANCHOR LIVES UNDER `systemRoot`, WHICH IS SCALED 0.4×–9×. Anything
//  parented there inherits the rig, so a card attached naively would be
//  a postage stamp at 0.4× and a billboard at 9×. `compensateForRig`
//  is the module's own answer — the same call the creation well makes,
//  for the same reason, recorded there as "the module's one creation
//  affordance, out of reach exactly when you are inside the system and
//  most want to add something to it."
//
//  On quantisation: these numbers are derived from positions that change
//  every frame, and an attachment is rasterised into a texture. What
//  costs is how often the rendered output changes, so every value is
//  formatted to a fixed precision — the strings only differ when the
//  reading does. See `PendulumInfoCard`, where this rule was settled.
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
        // A hyperbola's far apsis is algebraically behind the focus,
        // which is correct and is not a distance anyone wants read out.
        row("r_a", elements.hasApoapsis
            ? PhysicsFormat.measurement(elements.apoapsisRadius / au, "AU", decimals: 3)
            : "—")
        row("i", degrees(elements.inclination))
        // A circular orbit has no periapsis and an equatorial one has no
        // node, so the angles measured from them are conventions rather
        // than measurements. The panel said which, and so does this: a
        // number that means nothing is worse than an absent one.
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
        // The sentence the numbers are for. Kept verbatim from the panel:
        // it is the one line that says what the sign MEANS, and the
        // energies are only worth reading because of it.
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

    /// An angle, at a TENTH of a degree rather than a hundredth.
    ///
    /// The header above says every value is quantised so the card only
    /// re-rasterises when a reading actually changes. At `%.2f` that was
    /// true of Ω and ω, which barely move, and false of ν: a planet's
    /// true anomaly crosses 0.01° in well under a frame at 20× and 100×
    /// clock, so the string changed every single frame and the card was
    /// rebuilt every single frame at exactly the moment the module is
    /// working hardest.
    ///
    /// A hundredth of a degree is 36 milliarcseconds. Nothing on this
    /// card is read to that precision, and `PendulumInfoCard` already
    /// makes the same trade deliberately — the rule is to choose the
    /// precision a reader needs, not the precision the type can hold.
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
