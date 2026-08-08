//
//  ExperimentsView.swift
//  Physics Playground — Shell
//
//  THE EXPERIMENTS GET A ROOM OF THEIR OWN.
//
//  They were a strip inside the Gallery's catalog — the app-wide tally,
//  the single next step, and a "3 of 5 experiments" line under every
//  module row — visible whether or not anyone had asked. Owner's call
//  2026-08-08: put them behind a button beside Settings and the Lab
//  Notebook, which is where the app already keeps the things you consult
//  rather than the things you look at.
//
//  That is also the first surface the full catalog has ever had.
//  `ExperimentCatalog.experiments(for:)` could list every experiment in
//  a module with its detail and its concrete step, and the only readers
//  were a per-module COUNT and the exhibits' progress rings. Twenty
//  authored steps, each written to be read, and the number was all
//  anybody saw. Hiding the strip and showing the list are the same
//  change: the tally moves out of the way and the writing it was
//  standing in front of finally appears.
//
//  ONE STEP IS STILL SINGLED OUT at the top, because a list of twenty is
//  a to-do list and `ExperimentCatalog.nextStep`'s own doc comment is an
//  argument against exactly that — "a tally that says '4 of 24 complete'
//  tells you where you are and nothing about where to go". The list
//  answers "what is there"; the line above it answers "what now".
//

import SwiftUI

struct ExperimentsView: View {
    static let windowID = "experiments"

    @Environment(AppModel.self) private var appModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    AppProgressLine()
                    ForEach(ModuleCatalog.all(appModel: appModel)) { module in
                        let entries = ExperimentCatalog.experiments(
                            for: module.id, appModel: appModel)
                        if !entries.isEmpty {
                            moduleSection(module, entries)
                        }
                    }
                }
                .padding(DesignTokens.Panel.outerPadding)
            }
            .navigationTitle("Experiments")
        }
        .frame(minWidth: 460, minHeight: 340)
    }

    // MARK: What now
    //
    // `AppProgressLine`, NOT A SECOND COPY OF IT. It was written for the
    // catalog and its reasoning — a tally is a score, a step is a
    // direction, and the second is what makes a surface somewhere you
    // return to — is exactly this window's reasoning. Rewriting those
    // twelve lines here is how the resistance rule ended up in two files
    // spelled two ways.

    // MARK: What is there

    @ViewBuilder
    private func moduleSection(
        _ module: ModuleDescriptor,
        _ entries: [(experiment: Experiment, isMet: () -> Bool)]
    ) -> some View {
        // COMPLETION IS THE RECORDED FACT, not the live one. `isMet`
        // asks whether the physics is in the goal state RIGHT NOW, which
        // is how the checker chimes; `completed` is whether it ever has
        // been. A list that unticked itself when you moved a magnet
        // would be a list nobody could trust.
        let completed = appModel.experiments.completed
        let done = entries.filter { completed.contains($0.experiment.id) }.count

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: module.icon)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(module.accent)
                Text(module.title)
                    .font(.callout.weight(.semibold))
                Spacer(minLength: 0)
                Text("\(done)/\(entries.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(done == entries.count
                                     ? DesignTokens.Palette.completionGold
                                     : Color.secondary)
            }

            ForEach(entries, id: \.experiment.id) { entry in
                row(entry.experiment,
                    isComplete: completed.contains(entry.experiment.id),
                    accent: module.accent)
            }
        }
    }

    @ViewBuilder
    private func row(_ experiment: Experiment, isComplete: Bool,
                     accent: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                .font(.footnote)
                .foregroundStyle(isComplete ? accent : Color.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(experiment.title)
                    .font(.footnote.weight(.medium))
                Text(experiment.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                // THE STEP, which had no reader anywhere in the app.
                // Shown only while the experiment is outstanding: an
                // instruction for something already done is noise, and
                // the completed rows are what make the list read as
                // progress rather than as homework.
                if !isComplete, !experiment.step.isEmpty {
                    Text(experiment.step)
                        .font(.caption2)
                        .foregroundStyle(accent)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.regularMaterial,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        // One control's worth of speech, not four fragments — the same
        // fix `HubCatalogRow` needed when a UI test could not address it.
        .accessibilityElement(children: .combine)
        .accessibilityValue(isComplete ? "done" : "not done")
    }
}
