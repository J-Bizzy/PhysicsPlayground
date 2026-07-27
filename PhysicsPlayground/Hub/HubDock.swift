//
//  HubDock.swift
//  Physics Playground — Hub
//
//  The persistent system bar the home screen never had: notebook,
//  progress, daily challenge, search, studio mode, settings — six
//  things that used to be scattered across the window, a toast over
//  the TV, and nowhere at all. It rides the main window as a bottom
//  ornament, so it is always in the same place and never overlaps the
//  exhibits.
//

import SwiftUI

/// Which dock sheet is open, if any. One at a time, by design.
enum DockSheet: String, Identifiable {
    case notebook, progress, challenge, search
    var id: String { rawValue }
}

struct HubDock: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openWindow) private var openWindow
    @State private var sheet: DockSheet?

    var body: some View {
        let total = ExperimentCatalog.total(appModel: appModel)
        let done = ExperimentCatalog.completedCount(appModel: appModel)

        HStack(spacing: 6) {
            dockButton("book.closed", "Notebook") {
                sheet = .notebook
                // Opening the notebook completes the last coach mark.
                appModel.settings.advanceCoach(past: 2)
            }

            // The global ring lives ON the icon, at all times — the
            // one-glance answer to "how far along am I".
            Button {
                sheet = .progress
            } label: {
                VStack(spacing: 3) {
                    ZStack {
                        Circle()
                            .stroke(.tertiary, lineWidth: 2.5)
                        Circle()
                            .trim(from: 0, to: total > 0 ? CGFloat(done) / CGFloat(total) : 0)
                            .stroke(done == total && total > 0 ? .green : Color.accentColor,
                                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text("\(done)")
                            .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    }
                    .frame(width: 24, height: 24)
                    Text("Progress")
                        .font(.caption2)
                }
                .frame(width: 68, height: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Progress: \(done) of \(total) experiments complete")

            dockButton("target", "Challenge",
                       badge: appModel.experiments.streak > 1
                           ? "\(appModel.experiments.streak)" : nil) {
                sheet = .challenge
            }

            dockButton("magnifyingglass", "Search") { sheet = .search }

            dockButton(appModel.studioMode ? "moon.stars.fill" : "moon.stars",
                       "Studio") {
                appModel.studioMode.toggle()
            }

            dockButton("gearshape", "Settings") {
                openWindow(id: SettingsView.windowID)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassBackgroundEffect()
        .sheet(item: $sheet) { which in
            switch which {
            case .notebook: HubNotebookView().environment(appModel)
            case .progress: ProgressSheet().environment(appModel)
            case .challenge: ChallengeSheet().environment(appModel)
            case .search: SearchSheet().environment(appModel)
            }
        }
    }

    private func dockButton(_ icon: String, _ label: String,
                            badge: String? = nil,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .medium))
                    .frame(height: 24)
                    .overlay(alignment: .topTrailing) {
                        if let badge {
                            Text(badge)
                                .font(.system(size: 9, weight: .bold).monospacedDigit())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1.5)
                                .background(.orange, in: Capsule())
                                .offset(x: 10, y: -6)
                        }
                    }
                Text(label)
                    .font(.caption2)
            }
            .frame(width: 68, height: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - Progress

/// The full picture: overall ring, per-module breakdown, gilded rows
/// for finished modules. This answers "where should I go next" with a
/// list rather than a guess.
struct ProgressSheet: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let modules = ModuleCatalog.all(appModel: appModel)
        let total = ExperimentCatalog.total(appModel: appModel)
        let done = ExperimentCatalog.completedCount(appModel: appModel)

        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Progress", systemImage: "chart.pie")
                    .font(.title2.bold())
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.podProminent)
            }

            HStack(spacing: 14) {
                ZStack {
                    Circle().stroke(.tertiary, lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: total > 0 ? CGFloat(done) / CGFloat(total) : 0)
                        .stroke(done == total && total > 0 ? .green : Color.accentColor,
                                style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(done)/\(total)")
                        .font(.headline.monospacedDigit())
                }
                .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(done) of \(total) experiments")
                        .font(.headline)
                    if appModel.experiments.streak > 1 {
                        Text("\(appModel.experiments.streak)-day streak")
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                    }
                }
                Spacer()
            }

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(modules) { module in
                        let entries = ExperimentCatalog.experiments(
                            for: module.id, appModel: appModel)
                        let moduleDone = entries.filter {
                            appModel.experiments.completed.contains($0.experiment.id)
                        }.count
                        let complete = !entries.isEmpty && moduleDone == entries.count

                        Button {
                            appModel.activeModuleID = module.id
                            dismiss()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: module.icon)
                                    .foregroundStyle(module.accent)
                                    .frame(width: 26)
                                Text(module.title)
                                    .font(.callout)
                                Spacer()
                                if complete {
                                    Image(systemName: "medal.fill")
                                        .foregroundStyle(.yellow)
                                        .accessibilityLabel("Complete")
                                }
                                Text("\(moduleDone)/\(entries.count)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                ProgressView(value: Double(moduleDone),
                                             total: Double(max(entries.count, 1)))
                                    .tint(complete ? .yellow : module.accent)
                                    .frame(width: 70)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(.regularMaterial,
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .hoverEffect()
                        .accessibilityLabel(
                            "\(module.title): \(moduleDone) of \(entries.count) complete")
                    }
                }
            }
        }
        .padding(22)
        .frame(minWidth: 480, minHeight: 440)
    }
}

// MARK: - Daily challenge

/// The next unfinished experiment, framed as today's challenge — with
/// the streak it feeds. This used to be a toast floating over the TV;
/// now it has a place, and never overlaps anything.
struct ChallengeSheet: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Daily challenge", systemImage: "target")
                    .font(.title2.bold())
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.podProminent)
            }

            if appModel.experiments.streak > 0 {
                Label(appModel.experiments.completedToday
                      ? "\(appModel.experiments.streak)-day streak — today is banked"
                      : "\(appModel.experiments.streak)-day streak — keep it alive today",
                      systemImage: "flame.fill")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            }

            if let next = ExperimentCatalog.nextStep(appModel: appModel) {
                Button {
                    appModel.activeModuleID = next.module.id
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Image(systemName: next.module.icon)
                                .foregroundStyle(next.module.accent)
                            Text(next.experiment.title)
                                .font(.headline)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.tertiary)
                        }
                        Text(next.experiment.step.isEmpty
                             ? next.experiment.detail : next.experiment.step)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    .padding(14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(.regularMaterial,
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .hoverEffect()
            } else {
                Text("Every experiment is complete. The playground is yours.")
                    .font(.headline)
                    .padding(.vertical, 12)
            }
        }
        .padding(22)
        .frame(minWidth: 440)
    }
}

// MARK: - Search

/// Type (or dictate — the system keyboard provides it) to jump to any
/// experiment in any module.
struct SearchSheet: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        let modules = ModuleCatalog.all(appModel: appModel)
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        let hits: [(module: ModuleDescriptor, title: String, detail: String)] =
            modules.flatMap { module in
                ExperimentCatalog.experiments(for: module.id, appModel: appModel)
                    .map { (module, $0.experiment.title, $0.experiment.detail) }
            }
            .filter {
                needle.isEmpty
                    || $0.title.lowercased().contains(needle)
                    || $0.detail.lowercased().contains(needle)
                    || $0.module.title.lowercased().contains(needle)
            }

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Search", systemImage: "magnifyingglass")
                    .font(.title2.bold())
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.podProminent)
            }

            TextField("Experiment, topic, or module", text: $query)
                .textFieldStyle(.roundedBorder)

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(Array(hits.enumerated()), id: \.offset) { _, hit in
                        Button {
                            appModel.activeModuleID = hit.module.id
                            dismiss()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: hit.module.icon)
                                    .foregroundStyle(hit.module.accent)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(hit.title).font(.callout)
                                    Text(hit.module.title)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(.regularMaterial,
                                    in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .hoverEffect()
                    }
                    if hits.isEmpty {
                        Text("Nothing matches \u{201C}\(query)\u{201D}.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 20)
                    }
                }
            }
        }
        .padding(22)
        .frame(minWidth: 460, minHeight: 400)
    }
}
