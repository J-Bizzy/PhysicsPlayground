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
//  2. IT WAS THE APP'S ONLY VIEW OF PROGRESS. `AppProgressLine` carried
//     the tally, the streak and the single next step, and it was
//     invisible whenever the hub was actually up.
//
//     REASON 2 IS GONE, and so is everything it referred to: the
//     progress line moved to `ExperimentsView` on 2026-08-08, and on
//     2026-08-09 the owner cut the experiments system entirely. Reason 1
//     is untouched and is the whole reason this window must not blank
//     itself — the catalog is the accessibility path whatever else it
//     carries, and it now carries nothing else.
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

                // THIS IS THE WAY BACK, NOT THE WAY IN (2026-08-22).
                //
                // The app launches into the gallery now, so nobody
                // arrives here: this branch is reached by deliberately
                // pressing "Put the Gallery away" below, or by the
                // Digital Crown. Deleting the button along with the
                // front door was the tempting half of that change and
                // would have stranded exactly the user who had just
                // asked for their room back, with the catalog in front
                // of them and no way to reopen what it lists.
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
                //
                // WHEN IS THIS BRANCH EVEN SEEN, since 2026-08-10? The
                // shell dismisses this window while the gallery owns the
                // home screen (`PlaygroundSpaceView.syncMainWindow`), so
                // the compact state is no longer what you find parked
                // behind the terraces. It is what you get when you ASK
                // for the window back — reopening the app from the Home
                // View while the gallery is up — plus a frame or two
                // during the dismissal itself.
                //
                // That is the whole reason this branch survived the
                // change rather than going with the window. The button
                // below is still the only `dismissImmersiveSpace` in the
                // app; it is now one deliberate step away instead of
                // standing in front of the thing it closes.
                Button {
                    Task {
                        appModel.closeForDismissal()
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
            // Cheap and idempotent, and this view can appear without the
            // space ever having opened (the `-uiTesting` retreat), so it
            // cannot rely on the space having warmed the sound set.
            SoundPalette.warmUp()
            SoundPalette.masterVolume = appModel.settings.masterVolume
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
    ///
    /// WHAT IT DOES CHANGED ON 2026-08-22, though not what it is for.
    /// It used to suppress this view's automatic opening of the gallery.
    /// There is no such call any more — the ImmersiveSpace is the launch
    /// scene, chosen by a static Info.plist key no argument can reach —
    /// so the flag is now read by `PlaygroundSpaceView.retreatForUITesting`,
    /// which turns round on the way in and hands the window back. Same
    /// contract for the tests: with `-uiTesting 1`, the app is a window
    /// app showing the flat catalog.
    static var isUITesting: Bool {
        UserDefaults.standard.bool(forKey: "uiTesting")
    }

    private func openGallery() async {
        withAnimation(.easeOut(duration: 0.2)) { openFailed = false }
        // Assets first, THEN the door. The gallery's build parses every
        // prop it can't find in the cache synchronously on the main
        // thread — warming here means the parsing happens while only
        // this task is waiting, instead of as a multi-second Thread-1
        // hang inside the space's first frames. The window is already
        // up, so the wait reads as the room opening, not the app
        // freezing.
        await PropCache.warmUp()
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
            // A GRAVE, TWO DAYS DEEP. `AppProgressLine` stood here — the
            // app-wide tally, the streak and the one concrete next step
            // — on an argument worth keeping even though the feature is
            // not: a tally tells you where you are and nothing about
            // where to go, so a hub carrying only a score can only ever
            // be a launcher. It moved to `ExperimentsView` on 2026-08-08
            // (the owner's call that experiments should be something you
            // ask for rather than something you look at), and on
            // 2026-08-09 the whole system came out.
            //
            // What is left is the catalog itself, which was always the
            // load-bearing half: six labs, grouped by domain, each a
            // button that opens its lab without needing a room.
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

private struct HubCatalogRow: View {
    let module: ModuleDescriptor
    @Environment(AppModel.self) private var appModel

    var body: some View {
        Button {
            appModel.go(to: module.id)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: module.icon)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(module.accent)
                    .frame(width: 28, height: 28)
                    .background(module.accent.opacity(0.18),
                                in: RoundedRectangle(cornerRadius: DesignTokens.Panel.chipRadius,
                                                     style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(module.title)
                        .font(.callout)
                        .lineLimit(1)
                    // WHAT THE ROW'S SECOND LINE SAYS NOW. It read
                    // "2 of 5 experiments" until 2026-08-09, and the
                    // honest minimum after deleting that was to drop to
                    // one line — but the row is built around two, and
                    // `HubDomain.promise` is the sentence the gallery
                    // already shows under the exhibit you are facing.
                    // The flat catalog is the accessibility path, so the
                    // one thing it should not be is the version that
                    // tells you less about a lab than the room does.
                    Text(HubDomain.promise(for: module.id))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
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
            in: RoundedRectangle(cornerRadius: DesignTokens.Panel.cardRadius, style: .continuous))
        .hoverEffect()
        // Named as ONE control. Without this the row exposes only its
        // composed children — an icon, a title, a promise line, a
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
