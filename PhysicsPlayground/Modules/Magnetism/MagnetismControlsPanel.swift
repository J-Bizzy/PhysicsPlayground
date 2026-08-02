//
//  MagnetismControlsPanel.swift
//  Physics Playground — Magnetism module
//
//  The module's one-glance panel — and it holds no slider, no picker and
//  no toggle. It makes magnets, and otherwise it READS.
//
//  All four switches stand beside the field now, as one bank: whether
//  the magnets are free to move, and the three things that can be drawn.
//  Freezing them was the odd one out and gets the top plate, because a
//  bank of "draw this" plates with one "run the simulation" plate hidden
//  among them would be lying by arrangement.
//
//  Per-MAGNET editing (strength bead, flip poles, delete) lives on the
//  magnet: tap it and its ring unfolds.
//

import SwiftUI

struct MagnetismControlsPanel: View {
    @Environment(MagnetismModel.self) private var model

    var body: some View {
        @Bindable var model = model

        VStack(spacing: DesignTokens.Panel.sectionSpacing) {
            PanelSection("Magnets") {
                HStack(spacing: 12) {
                    Button {
                        self.model.addMagnet()
                    } label: {
                        Label("Add magnet", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.podProminent)
                    .disabled(self.model.magnets.count >= MagnetismModel.magnetBudget)

                    Text("\(self.model.magnets.count) of \(MagnetismModel.magnetBudget)")
                        .font(DesignTokens.TypeScale.label.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Text(self.model.dynamicsOn
                     ? "Free: they glide together head-to-tail and swing to align."
                     : "Frozen: they hold exactly where you put them.")
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Tap a magnet for its own controls — pull the bead for strength, petals flip its poles or delete it.")
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // The electromagnet's switch and readouts are NOT here any
            // more. The coil is the join between this bench and the
            // circuit bench, so it belongs to neither — it lives in the
            // merged panel's own "The link" section, between the two.

            CollapsedSection("The room") {
                Text("The bank beside the field carries all four switches: "
                     + "whether the magnets move, and whether you see the "
                     + "field lines, the compass grid and the hand compass.")
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Field lines are closed LOOPS — a magnetic line has no "
                     + "endpoint to start or stop at, which is the one way "
                     + "they differ from the electric ones next door.")
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            CollapsedSection("Numbers") {
                Text("Compass reads \(self.model.compassMicroTesla, specifier: "%.1f") µT")
                    .font(DesignTokens.TypeScale.control.monospacedDigit())
                Text(self.model.compassIsReadingEarth
                     ? "Reading EARTH — you have carried it clear of the magnets. The needle points north and 65° DOWN, which is where the field actually goes."
                     : "Reading the BENCH — the magnets here are stronger than Earth. Carry it about 30 cm clear and the needle hands over to the planet.")
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Earth: 50 µT, 65° below horizontal — real values. WHICH WAY north lies in your room is a convention: visionOS gives no true heading, so north is straight ahead as you entered.")
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
                // Induced EMF reads out in "The link" section above,
                // beside the coil switch that makes it meaningful.
            }
        }
    }
}
