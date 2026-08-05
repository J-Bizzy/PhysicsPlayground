//
//  HubView.swift
//  Physics Playground — Hub
//
//  The hub's window. While the Gallery is in the room this window is
//  deliberately empty — the space IS the menu, and the wordmark hangs
//  in the room itself. Before the space opens (or if opening fails),
//  the window is the real front door: the app's name, one button that
//  raises the Gallery, and a domain-grouped catalog with live progress,
//  so nothing about the app is unreachable from a plain window.
//

import SwiftUI

struct HubView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @State private var openFailed = false

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 12)

            if !appModel.isImmersiveSpaceOpen {
                VStack(spacing: 5) {
                    Text("Physics Playground")
                        .font(DesignTokens.TypeScale.wordmark())
                    Text("Room-scale physics labs, in your actual room.")
                        .font(DesignTokens.TypeScale.label)
                        .foregroundStyle(.secondary)
                }

                if openFailed {
                    // The auto-open used to swallow its failure — the
                    // window just sat there with no explanation. Say
                    // what happened; retry only by hand, never a loop.
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("The Gallery couldn't open.")
                            .font(DesignTokens.TypeScale.footnote)
                        Button("Try Again") { Task { await openGallery() } }
                            .font(DesignTokens.TypeScale.footnote.weight(.semibold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Button {
                    Task { await openGallery() }
                } label: {
                    Label("Enter the Gallery", systemImage: "sparkles")
                        .font(.title3)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.podProminent)
                .accessibilityHint("Places the Gallery — the exhibit terraces — in your room")

                HubCatalogList()
            }

            Spacer(minLength: 12)
        }
        .padding(DesignTokens.Panel.outerPadding)
        .frame(minWidth: 440, maxWidth: .infinity, minHeight: 200, maxHeight: .infinity)
        // Bare type over passthrough needs its own separation from the room.
        .shadow(color: .black.opacity(0.45), radius: 8, y: 2)
        .task {
            SoundPalette.warmUp()
            SoundPalette.masterVolume = appModel.settings.masterVolume
            // The Gallery is the menu — bring it up on arrival.
            //
            // `-uiTesting 1` holds it back, because this window is
            // deliberately EMPTY while the Gallery is in the room, and
            // XCUITest can only see the window: nothing in an immersive
            // space is addressable to it. The flat catalog it leaves up
            // is not a test fixture, though — it is the app's real
            // accessibility path, the one the standing rule demands
            // (nothing may be reachable only in space), so testing
            // against it tests something that has to work anyway.
            if !appModel.isImmersiveSpaceOpen, !Self.isUITesting {
                await openGallery()
            }
        }
    }

    /// Whether a UI test is driving the app. Not `#if DEBUG`-gated: the
    /// UI test target builds and runs the shipping configuration too,
    /// and a hook that vanishes in Release is a hook that cannot test
    /// what ships.
    ///
    /// SIGNED OFF FOR RELEASE, consciously, as part of the 2026-08-01
    /// submission pass. It is the only launch-argument read in the app
    /// that is live outside `#if DEBUG`, so it deserves a decision rather
    /// than an oversight, and the decision is that it stays. What it does
    /// in a shipped build: suppresses the automatic opening of the
    /// Gallery, leaving the flat catalog up. That is it — no data is
    /// exposed, nothing is unlocked, and no state is written.
    ///
    /// And it is not reachable by a user. Launch arguments come from the
    /// debugger or from `simctl`; a shipped visionOS app launched from
    /// the Home View is handed none, and this key is never written to
    /// `UserDefaults` by any code path in the app. Removing the hook
    /// would cost the only automated coverage that proves the catalog is
    /// reachable at all.
    static var isUITesting: Bool {
        UserDefaults.standard.bool(forKey: "uiTesting")
    }

    private func openGallery() async {
        withAnimation(.easeOut(duration: 0.2)) { openFailed = false }
        let result = await openImmersiveSpace(id: PlaygroundSpaceView.spaceID)
        if case .error = result {
            withAnimation(.easeOut(duration: 0.2)) { openFailed = true }
        }
    }
}

/// The flat catalog, shown only when the Gallery is not in the room:
/// the modules grouped under their domains, each with its live
/// progress, mirroring the terraces the space shows as objects.
struct HubCatalogList: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        let byID = Dictionary(uniqueKeysWithValues:
            ModuleCatalog.all(appModel: appModel).map { ($0.id, $0) })

        VStack(alignment: .leading, spacing: 14) {
            // WHERE YOU ARE, AND WHERE TO GO — the app-wide pair, wired
            // on 2026-08-03.
            //
            // `ExperimentCatalog` has four public entry points and THREE
            // OF THEM HAD NO CALLERS: `total`, `completedCount` and
            // `nextStep`. The last one carries a doc comment arguing at
            // length that "a tally that says '4 of 24 complete' tells you
            // where you are and nothing about where to go — so the hub
            // could only ever be a launcher. One concrete next step …
            // turns it into somewhere you come back TO." The argument was
            // written, the function was written, and the surface never
            // was — the same "authored but dark" defect as the coach
            // marks and `Lagrange.swift`.
            //
            // It goes HERE rather than into the room. The gallery's focus
            // panel already names the next step for the module you are
            // looking at, which is the better place for a per-module
            // instruction. What was missing is the answer to "what next,
            // anywhere" — and that is a question you ask of a catalog,
            // not of one exhibit.
            AppProgressLine()
            ForEach(HubDomain.allCases) { domain in
                let modules = domain.moduleIDs.compactMap { byID[$0] }
                if !modules.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 7) {
                            Circle()
                                .fill(domain.color)
                                .frame(width: 7, height: 7)
                            Text(domain.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.leading, 4)

                        ForEach(modules) { module in
                            HubCatalogRow(module: module)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: 500)
    }
}

/// The app-wide tally and the single next thing to do.
///
/// Deliberately ONE line of each. A tally is a score and a step is a
/// direction, and the argument in `ExperimentCatalog.nextStep` is that
/// the second is what makes a hub somewhere you return to. Listing every
/// outstanding experiment would be a to-do list, which is the shape this
/// project rejected when the experiments were "a checklist in a side pod
/// … achievements to stumble into rather than a path through the module".
struct AppProgressLine: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        let done = ExperimentCatalog.completedCount(appModel: appModel)
        let total = ExperimentCatalog.total(appModel: appModel)

        if total > 0 {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("\(done) of \(total) experiments")
                        .font(DesignTokens.TypeScale.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if appModel.experiments.streak > 1 {
                        Text("· \(appModel.experiments.streak)-day streak")
                            .font(DesignTokens.TypeScale.footnote)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 0)
                }

                if let next = ExperimentCatalog.nextStep(appModel: appModel) {
                    // The module's own accent, because the line is a
                    // pointer INTO a room and the colour is how this app
                    // says which one.
                    Label {
                        Text("\(next.experiment.title) — \(next.module.title)")
                            .font(DesignTokens.TypeScale.footnote)
                    } icon: {
                        Image(systemName: "flask")
                            .foregroundStyle(next.module.accent)
                    }
                    if !next.experiment.step.isEmpty {
                        Text(next.experiment.step)
                            .font(DesignTokens.TypeScale.footnote)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text("Every experiment done.")
                        .font(DesignTokens.TypeScale.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 2)
            .accessibilityElement(children: .combine)
        }
    }
}

private struct HubCatalogRow: View {
    let module: ModuleDescriptor
    @Environment(AppModel.self) private var appModel

    var body: some View {
        let entries = ExperimentCatalog.experiments(for: module.id,
                                                    appModel: appModel)
        let done = entries.filter {
            appModel.experiments.completed.contains($0.experiment.id)
        }.count

        Button {
            appModel.activeModuleID = module.id
        } label: {
            HStack(spacing: 10) {
                Image(systemName: module.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(module.accent)
                    .frame(width: 28, height: 28)
                    .background(module.accent.opacity(0.18),
                                in: RoundedRectangle(cornerRadius: 8,
                                                     style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(module.title)
                        .font(.callout)
                        .lineLimit(1)
                    if !entries.isEmpty {
                        Text("\(done) of \(entries.count) experiments")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(done == entries.count
                                             ? Color.yellow : Color.secondary)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.forward")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .hoverEffect()
        // Named as ONE control. Without this the row exposes only its
        // composed children — an icon, a title, a progress line, a
        // chevron — so VoiceOver reads it as four things and a UI test
        // cannot address it by name at all. Found by the first UI test
        // that tried to press it (`HomeChromeUITests`), which is
        // precisely the class of defect a screenshot cannot show.
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("lab.\(module.id)")
        .accessibilityLabel(module.title)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens \(module.title)")
    }
}
