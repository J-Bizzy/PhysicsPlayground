//
//  HubView.swift
//  Physics Playground — Hub
//
//  The hub's window. Two states, and until 2026-08-07 the first of them
//  was BLANK.
//
//  · Gallery not in the room — the full front door: the app's name, one
//    button that raises the Gallery, and a domain-grouped catalog with
//    live progress.
//  · Gallery in the room — a compact version of the same catalog and the
//    same progress line. The space is the menu and the wordmark hangs in
//    the room, so the ceremony comes off; the CONTENT does not.
//
//  WHY THE SECOND STATE EXISTS. Everything here used to sit inside
//  `if !appModel.isImmersiveSpaceOpen`, and `task` opens the Gallery
//  half a second after launch — so within a second of a cold start the
//  window collapsed to an empty 560×720 frame and stayed that way for
//  the whole session. Two things went with it, and both are load-bearing:
//
//  1. THE FLAT CATALOG IS THE ACCESSIBILITY PATH. The standing rule is
//     that nothing may be reachable only in space, and the catalog is
//     how this app satisfies it. Hidden for the entire time the app is
//     in its normal state, that guarantee was unmet in normal use — and
//     it was also the safety net under the only-way-into-a-lab problem.
//  2. IT WAS THE APP'S ONLY VIEW OF PROGRESS. `AppProgressLine` carries
//     the tally, the streak and the single next step, and it was
//     invisible whenever the hub was actually up.
//
//     NO LONGER TRUE OF THIS FILE, 2026-08-08: the progress line moved
//     to `ExperimentsView`, behind the Gallery bar's flask button, on
//     the owner's call that the experiments should be something you ask
//     for rather than something you look at. Point 1 above is untouched
//     and is still why this window must not blank itself — the catalog
//     is the accessibility path whatever else it carries.
//

import SwiftUI

struct HubView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
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

                RoomSensingNote()
                HubCatalogList()
            } else {
                // THE COMPACT STATE. Same catalog, same progress line,
                // no ceremony: the wordmark and the "Enter the Gallery"
                // button would both be lying, since the Gallery is
                // already in the room and has its own sign over the
                // door. What stays is everything that answers a
                // question — where am I, what next, and what are the
                // six labs — plus a way into each of them that needs no
                // aim and no carry.
                RoomSensingNote()
                HubCatalogList(isCompact: true)

                // THE WAY OUT. `dismissImmersiveSpace` appeared ZERO
                // times in the app target, so a user who simply wanted
                // their room back mid-session had to know about the
                // Digital Crown. The palette bead's `home` petal leaves
                // a LAB; this leaves the room entirely, and the two are
                // different requests.
                Button {
                    Task {
                        appModel.activeModuleID = nil
                        await dismissImmersiveSpace()
                    }
                } label: {
                    Label("Put the Gallery away", systemImage: "xmark.circle")
                        .font(DesignTokens.TypeScale.footnote)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityHint("Closes the room and returns to this window")
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
            // `-uiTesting 1` holds it back, so the FULL front door
            // stays up: XCUITest can only see the window, and the
            // wordmark and the "Enter the Gallery" button exist only in
            // that state. (Before 2026-08-07 the argument was
            // load-bearing for a harder reason — the window went
            // completely blank once the Gallery opened, so without it
            // there was nothing at all to test. The compact catalog
            // means that is no longer true, and the argument now buys
            // coverage of the front door rather than coverage of
            // anything.) The catalog it leaves up is not a test fixture:
            // it is the app's real accessibility path, the one the
            // standing rule demands — nothing may be reachable only in
            // space — so testing against it tests something that has to
            // work anyway.
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

/// What the app is about to ask for, or what it lost when the ask was
/// refused.
///
/// PRE-EXPLAINED, because the ask is not where the user is looking.
/// `room.retain()` starts the `ARKitSession` about a second after
/// launch, from the GALLERY, before any lab — and the only sentence in
/// the app explaining why lived in a module's `firstRunHint`, which the
/// user has not reached and may never render. So the system sheet was
/// the first anyone heard of it, and a decline produced a warning
/// triangle in a title bar they may never look at.
///
/// One line before, the real consequence after, both in the window the
/// user is actually facing at that moment. The sentences are
/// `RoomModel.Sensing`'s, shared with the module title bar.
struct RoomSensingNote: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        let sensing = appModel.room.sensing
        Group {
            if sensing == .fine {
                Label(RoomModel.Sensing.preExplanation, systemImage: "arkit")
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.tertiary)
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    Label(sensing.headline, systemImage: "exclamationmark.triangle.fill")
                        .font(DesignTokens.TypeScale.footnote.weight(.semibold))
                        .foregroundStyle(.orange)
                    Text(sensing.detail)
                        .font(DesignTokens.TypeScale.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: 500, alignment: .leading)
        .multilineTextAlignment(.leading)
        .accessibilityElement(children: .combine)
    }
}

/// The flat catalog: the modules grouped under their domains, each with
/// its live progress, mirroring the terraces the space shows as objects.
///
/// Shown in BOTH window states since 2026-08-07 — compactly while the
/// Gallery is in the room. See this file's header for why hiding it was
/// a defect rather than a simplification.
struct HubCatalogList: View {
    /// Shown beside a Gallery that is already in the room: the domain
    /// headers stay (they are how this app names its two halves) but the
    /// vertical rhythm tightens, because this is now a reference surface
    /// rather than the front door.
    var isCompact = false

    @Environment(AppModel.self) private var appModel

    var body: some View {
        let byID = Dictionary(uniqueKeysWithValues:
            ModuleCatalog.all(appModel: appModel).map { ($0.id, $0) })

        VStack(alignment: .leading, spacing: isCompact ? 10 : 14) {
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
            // GRAVE, 2026-08-08: `AppProgressLine` stood here — the
            // app-wide tally and the single next step, in the catalog,
            // whether or not anyone had asked for it. Owner's call: the
            // experiments go behind a button beside Settings and the Lab
            // Notebook. Both halves now live in `ExperimentsView`, which
            // also became the first surface to show the twenty authored
            // STEPS rather than counting them.
            //
            // The view itself is kept — it is still the right shape, and
            // the reasoning above it about tally-versus-direction is the
            // reasoning `ExperimentsView` follows.
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
                    .font(.footnote.weight(.semibold))
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
                                             ? DesignTokens.Palette.completionGold
                                             : Color.secondary)
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
