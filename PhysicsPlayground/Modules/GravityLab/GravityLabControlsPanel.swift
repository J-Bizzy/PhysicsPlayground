//
//  GravityLabControlsPanel.swift
//  Physics Playground — Gravity Lab module
//
//  The module's one-glance panel — and as of 2026-07-31 it holds no
//  slider, no picker and no toggle. It makes worlds, it runs the clock,
//  it arms a prediction, and otherwise it READS.
//
//  What left, and where each thing went:
//  · Five display toggles → the switch bank standing to the left of the
//    system, joined by a SIXTH the panel never had: the acceleration
//    vector, which the renderer has read and defaulted to false since it
//    was written, with no control anywhere in the app.
//  · Sun mass → the star's own bead. Mass has physical extent; the star
//    inflates as its cube root while you pull.
//  · G → the rail under the bank. It is the one quantity here with no
//    extent of its own, which is exactly why it gets the app's decided
//    form for a continuous quantity rather than an invented one.
//
//  What arrived: the ORBIT of the selected body, in the classical
//  elements, and its ENERGY. Four of the eleven numbers this model
//  computes every frame — mass, kinetic, potential and total energy —
//  were shown to nobody at all, and the total is the one that makes
//  "bound" a fact rather than a label: negative and it comes back,
//  positive and it never does.
//

import PhysicsCore
import SwiftUI

struct GravityLabControlsPanel: View {
    @Environment(GravityLabModel.self) private var model

    var body: some View {
        @Bindable var model = model

        VStack(spacing: DesignTokens.Panel.sectionSpacing) {
            PanelSection("Worlds") {
                HStack(spacing: 12) {
                    Menu {
                        ForEach(GravityLabModel.Preset.allCases) { preset in
                            Button(preset.displayName) {
                                self.model.spawn(preset)
                            }
                        }
                    } label: {
                        Label("Add world", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.podProminent)
                    .accessibilityLabel("Add a preset world")

                    Button("Twin suns") {
                        self.model.makeBinary()
                    }
                    .buttonStyle(.podQuiet)
                    .accessibilityHint("Splits the star into a binary pair — every orbit reshapes")
                }

                Text(clockText)
                    .font(DesignTokens.TypeScale.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)

                Text("Pull a new world from the well and let it fall — or tap a planet for its own controls: pull the bead for mass, the petal deletes it.")
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            CollapsedSection("Time") {
                HStack(spacing: 14) {
                    Button {
                        self.model.isPaused.toggle()
                    } label: {
                        Image(systemName: self.model.isPaused ? "play.fill" : "pause.fill")
                    }
                    .buttonStyle(.podQuiet)
                    .accessibilityLabel(self.model.isPaused ? "Resume time" : "Pause time")

                    // The speed picker is a standing bank of labelled discs
                    // beside the system now — tap one (DECISIONS.md,
                    // 2026-07-29). It stays visible rather than folding,
                    // because which speed you are running is itself a thing
                    // worth reading: at 1× an Earth year takes two minutes.
                    Text("Clock: \(Int(self.model.timeScale))× — tap a disc on the bank beside the system.")
                        .font(DesignTokens.TypeScale.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("1× is three simulated days per second.")
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
            }

            CollapsedSection("Prediction") {
                Button {
                    self.model.armPrediction()
                } label: {
                    Label("Predict an orbit", systemImage: "scope")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.podQuiet)
                .disabled(self.model.selectedBody == nil
                          || self.model.selectedBody?.id == self.model.primaryBody?.id)
                Text("Arms a ghost at the selected planet: drag the ghost, and the white line shows the orbit that release would create — then time answers.")
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            CollapsedSection("This orbit") {
                if let selected = model.selectedBody,
                   let elements = model.orbitElements(for: selected.id) {
                    orbitRows(selected.body.name, elements)
                } else {
                    Text("Tap a planet: its orbit appears as a ring you can "
                         + "take hold of, and its numbers appear here.")
                        .font(DesignTokens.TypeScale.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            CollapsedSection("Energy") {
                if let selected = model.selectedBody,
                   let readout = model.readout(for: selected) {
                    energyRows(readout)
                } else {
                    Text("Total energy is what decides whether an orbit comes "
                         + "back: negative is bound, positive is gone.")
                        .font(DesignTokens.TypeScale.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Readouts

    @ViewBuilder
    private func orbitRows(_ name: String, _ elements: OrbitalElements) -> some View {
        let au = CelestialBody.astronomicalUnit
        VStack(alignment: .leading, spacing: 3) {
            Text(name)
                .font(DesignTokens.TypeScale.control.weight(.semibold))
            row("Semi-major axis a",
                elements.semiMajorAxis.map { String(format: "%.3f AU", $0 / au) }
                    ?? "∞ (parabolic)")
            row("Eccentricity e", String(format: "%.4f", elements.eccentricity))
            row("Periapsis r_p", String(format: "%.3f AU", elements.periapsisRadius / au))
            // A hyperbola's far apsis is algebraically behind the focus,
            // which is correct and is not a distance anyone wants read out.
            row("Apoapsis r_a", elements.hasApoapsis
                ? String(format: "%.3f AU", elements.apoapsisRadius / au)
                : "—")
            row("Inclination i", degrees(elements.inclination))
            if elements.degeneracy != .equatorial
                && elements.degeneracy != .circularEquatorial {
                row("Ascending node Ω", degrees(elements.longitudeOfAscendingNode))
            }
            if elements.degeneracy != .circular
                && elements.degeneracy != .circularEquatorial {
                row("Arg. of periapsis ω", degrees(elements.argumentOfPeriapsis))
            }
            row("True anomaly ν", degrees(elements.trueAnomaly))
            row("Period T", elements.period.map {
                String(format: "%.2f years", $0 / (365.25 * 86_400))
            } ?? "unbound")
            // A circular orbit has no periapsis and an equatorial one has
            // no node, so the angles measured from them are conventions
            // rather than measurements. Saying which is cheaper than
            // showing a number that means nothing.
            if elements.degeneracy != .none {
                Text(degeneracyNote(elements.degeneracy))
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func energyRows(_ readout: GravityLabModel.Readout) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            row("Mass", PhysicsFormat.scientific(readout.massKg) + " kg")
            row("Kinetic", PhysicsFormat.scientific(readout.kineticEnergy) + " J")
            row("Potential", PhysicsFormat.scientific(readout.potentialEnergy) + " J")
            row("Total", PhysicsFormat.scientific(readout.totalEnergy) + " J")
            Text(readout.totalEnergy < 0
                 ? "Negative: bound. It comes back."
                 : "Positive: unbound. It is leaving.")
                .font(DesignTokens.TypeScale.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(DesignTokens.TypeScale.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(DesignTokens.TypeScale.footnote.monospacedDigit())
        }
    }

    private func degrees(_ radians: Double) -> String {
        String(format: "%.2f°", radians * 180 / .pi)
    }

    private func degeneracyNote(_ degeneracy: OrbitDegeneracy) -> String {
        switch degeneracy {
        case .none: ""
        case .circular:
            "Circular: there is no periapsis, so ω is a convention and ν is "
            + "measured from the ascending node."
        case .equatorial:
            "In the reference plane: there is no node, so Ω is a convention "
            + "and ω is measured from the +x axis."
        case .circularEquatorial:
            "Circular and in the reference plane: neither a periapsis nor a "
            + "node exists, so ν is measured from the +x axis."
        }
    }

    private var clockText: String {
        let days = model.simulatedDays
        let clock = days < 400
            ? String(format: "%.0f simulated days", days)
            : String(format: "%.2f simulated years", days / 365.25)
        return "\(model.bodies.count) bodies · \(clock)"
    }
}
