//
//  ModuleHostView.swift
//  Physics Playground — Shell
//
//  The module's window is a TITLE BAR. Not "a title bar plus" — the bar,
//  and two things that appear only when they have something to say.
//
//  Left: back to the catalog. Middle: the module's name. Right:
//  notebook, place-the-lab, studio, and Reset — four, since the
//  module-switch menu and the legend key came off on 2026-08-02 (the key
//  moved to the Lab Notebook, which already knows which module is open). Beneath it, and only conditionally: "Show in room"
//  while the immersive space is closed, because the space is where the
//  module lives and there would otherwise be no way back into it; and
//  the module's one authored first-run sentence until it is dismissed.
//
//  EVERYTHING ELSE WENT (DECISIONS.md, 2026-08-01). `makeControls` is
//  deleted from the module contract, the six `*ControlsPanel.swift` are
//  gone, the legend moved to the notebook, the placement strip
//  became a tap on the cross-hair it describes, and the experiment's
//  current step moved to the hub — where you read it before you come in,
//  rather than off a card floating in front of the apparatus it is
//  telling you to touch.
//
//  What the panels held at the end was 71 readout `Text`s, 13 buttons —
//  six of them duplicating a control already standing in the room — and
//  four collapsed cards whose entire content was prose explaining where
//  a control had gone. A surface whose content is directions to
//  elsewhere is not a surface.
//

import SwiftUI

struct ModuleHostView: View {
    let module: ModuleDescriptor

    @Environment(AppModel.self) private var appModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.openWindow) private var openWindow
    /// The icon tile scales with the type it frames.
    @ScaledMetric(relativeTo: .headline) private var iconTile = 30.0
    @State private var confirmingReset = false
    @State private var showingSensing = false
    /// Set when "Show in room" fails, so it can say so.
    @State private var showInRoomFailed = false

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                // Left: navigation.
                Button {
                    appModel.go(to: nil)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel("All labs")
                .accessibilityHint("Returns to the catalog")

// NO MODULE-SWITCH MENU, and no legend button. The bar carries
                // navigation, identity, and the things you reach for
                // WHILE working; switching labs is neither. The
                // chevron-left goes back to the catalog, which is where
                // choosing belongs — the front door, which is the rule
                // this project has now arrived at three separate times.
                //
                // (The palette bead DOES carry lab switching — its ring
                // slots are the six labs as live vignettes, and
                // `Palette.onSelect` goes through `AppModel.go(to:)` —
                // and it has six petals: home, pause, capture, dim,
                // settings, reset. This comment said "four petals, no
                // switching" from 2026-07-29 until 2026-09-01, three
                // weeks after both stopped being true; the bar still
                // carries no switch because the bead already does.)
                                Spacer(minLength: 12)

                // Center: the module's identity.
                HStack(spacing: 10) {
                    Image(systemName: module.icon)
                        // A semantic style, not a point size: this is
                        // real text in the largest row of the window, and
                        // `.system(size: 15)` did not scale with Dynamic
                        // Type at all.
                        .font(.headline)
                        .foregroundStyle(module.accent)
                        // The tile scales WITH the glyph — a fixed
                        // 30-point frame around a semantic font let an
                        // accessibility text size overflow its own tile.
                        .frame(width: iconTile, height: iconTile)
                        .background(module.accent.opacity(0.18),
                                    in: RoundedRectangle(cornerRadius: DesignTokens.Panel.chipRadius, style: .continuous))
                        .accessibilityHidden(true)
                    Text(module.title)
                        .font(.title2.bold())
                        .lineLimit(1)
                }

                Spacer(minLength: 12)

                // Right: modes.
                Button {
                    openWindow(id: NotebookView.windowID)
                } label: {
                    Image(systemName: "book.closed")
                }
                .accessibilityLabel("Lab Notebook")
                .accessibilityHint("Your recorded observations — capture, read, export")

                Button {
                    appModel.labPlacement.isPlacing.toggle()
                } label: {
                    Image(systemName: appModel.labPlacement.isPlacing
                          ? "scope" : "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left")
                }
                .accessibilityLabel("Place the lab")
                .accessibilityHint("Shows an anchor you can drag to move the whole experiment to where you have room")

                Button {
                    appModel.studioMode.toggle()
                } label: {
                    Image(systemName: appModel.studioMode ? "moon.stars.fill" : "moon.stars")
                }
                .accessibilityLabel("Studio Mode")
                .accessibilityHint("Replaces your room with a dark studio")

                // THE ROOM, when the app cannot see it.
                //
                // Shown only when there is something to say, so in the
                // ordinary case the bar is unchanged. Every failure path
                // in `RoomModel.retain()` used to be a silent `return`:
                // deny the permission and Projectiles simply stopped
                // bouncing off your walls, occlusion never appeared, and
                // nothing anywhere in the app said why. A capability the
                // user switched off is the one kind of missing feature
                // they can actually fix, and it was the one the app was
                // quietest about.
                //
                // It is a popover on the bar rather than a banner under
                // it for the same reason the legend is: the module window
                // is a title bar, and a persistent row would be the
                // beginning of a panel growing back.
                if appModel.room.sensing != .fine {
                    Button {
                        showingSensing.toggle()
                    } label: {
                        Image(systemName: "exclamationmark.triangle")
                    }
                    .accessibilityLabel("Room sensing unavailable")
                    .accessibilityHint(Self.sensingHeadline(appModel.room.sensing))
                    .popover(isPresented: $showingSensing,
                             attachmentAnchor: .point(.bottom)) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(Self.sensingHeadline(appModel.room.sensing))
                                .font(DesignTokens.TypeScale.sectionHeader)
                            Text(Self.sensingDetail(appModel.room.sensing))
                                .font(DesignTokens.TypeScale.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(20)
                        .frame(maxWidth: 340)
                    }
                }

                // Reset ASKS FIRST.
                //
                // It used to live on the in-space rail, where a stray
                // gaze-pinch could fire it, so it carried a two-pinch
                // arming dance to be safe. Moving it to the window
                // removed the stray-pinch risk but also removed the
                // guard — and in Circuit Workshop a reset wipes a bench
                // that persists across launches. A confirmation is the
                // platform's own answer and a clearer one than arming.
                Button {
                    confirmingReset = true
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .accessibilityLabel("Reset")
                .accessibilityHint("Returns this lab to its starting state")
                .confirmationDialog("Reset \(module.title)?",
                                    isPresented: $confirmingReset,
                                    titleVisibility: .visible) {
                    Button("Reset", role: .destructive) {
                        appModel.resetActiveModule(module)
                    }
                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text("Everything you have set up here goes back to how the module opened. Recorded notebook entries are kept.")
                }
            }
            .buttonBorderShape(.circle)

            if !appModel.isImmersiveSpaceOpen {
                Button {
                    Task {
                        withAnimation(.easeOut(duration: 0.2)) {
                            showInRoomFailed = false
                        }
                        // Same order as the gallery door: assets warm
                        // off-main before the space opens.
                        await PropCache.warmUp()
                        let result = await openImmersiveSpace(
                            id: PlaygroundSpaceView.spaceID)
                        if case .error = result {
                            withAnimation(.easeOut(duration: 0.2)) {
                                showInRoomFailed = true
                            }
                        }
                    }
                } label: {
                    Label("Show in room", systemImage: "sparkles")
                        .font(.body)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.podProminent(module.accent))
                // "and its control pods" until 2026-08-03. There are no
                // pods — the instruments stand on the apparatus — and the
                // dead flag behind that phrase, `controlPodsVisible`, was
                // deleted in the same pass.
                .accessibilityHint("Places this lab in your room")

                // IT USED TO SWALLOW THE FAILURE. The result was
                // discarded, so a space that refused to open left this
                // window sitting there with a button that had visibly
                // done nothing. `HubView` fixed exactly this for the
                // gallery — banner, manual retry, never a loop — and its
                // own comment says the auto-open "used to swallow its
                // failure". The module window's copy still did.
                if showInRoomFailed {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Couldn't open the room.")
                            .font(DesignTokens.TypeScale.footnote)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule())
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            // The one-time hint, room open or shut (2026-09-01).
            //
            // Its history is three moves. The teach moved into the room
            // on 2026-08-08 (`RoomTeach`, deleted the next day) because
            // the apparatus stood through it HERE — RealityKit content
            // renders in front of a window behind it, and the first
            // photograph of a lab in a room showed five bobs and four
            // vector arrows crossing the sentence. When the room card was
            // cut, the hint stayed here gated on the space being CLOSED,
            // which was reasonable while the window was the launch scene.
            // On 2026-08-22 the space became the launch scene, and from
            // that day the condition had zero readers: nobody reaches a
            // lab's window with the room shut, so no lab ever showed its
            // one sentence. Found on 2026-09-01 while scripting the demo.
            //
            // What changed to make showing it here safe again is the
            // 2026-08-30 lift: the bar is top-aligned in a taller frame
            // and rides ~0.35 m above the apparatus band in all six
            // modules (photo-verified per module), so the sentence under
            // it clears the physics it describes. That claim is judged
            // by screenshot (`-resetHints 1 -openModule <id>`, each lab)
            // and on device — a SwiftUI body cannot be rendered in a
            // test, and the gate below collapses to `hasSeenHint`, which
            // `AppSettingsTests` already covers.
            if !appModel.settings.hasSeenHint(module.id) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "hand.point.up.left")
                        .font(.footnote)
                        .foregroundStyle(module.accent)
                    // PRIMARY, not secondary. It was styled as a caption
                    // — the app's lowest-contrast text — for the first
                    // sentence a new wearer reads in a lab, while the
                    // failure banner ten lines up, one short line you can
                    // ignore, is plain. The ranking was backwards.
                    Text(module.firstRunHint)
                        .font(DesignTokens.TypeScale.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 6)
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            appModel.settings.markHintSeen(module.id)
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss hint")
                }
                // Glass, like the failure banner above — this was the
                // last bare element in the title bar, a naked HStack
                // pretending it wasn't chrome — but thicker, because four
                // lines you must read is a different job from one line
                // you may ignore.
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.thickMaterial,
                            in: RoundedRectangle(cornerRadius: DesignTokens.Panel.cardRadius,
                                                 style: .continuous))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        // Wide enough for the LONGEST module name.
        //
        // At 560 the bar ran out of room and truncated: "Circuit
        // Workshop" arrived as "Circuit Works…", which is the module's
        // own name, misspelled by the layout, in the largest type on
        // screen. Five circular buttons took about 280 points before the
        // title got any, and "Wave Interference" needs about 200 more.
        //
        // Back down to 620 now that the module-switch menu and the Key
        // button are gone (2026-08-02): four circular buttons take about
        // 230 points, and the longest name — "Circuit Workshop" — needs
        // roughly 200 more. The number is load-bearing either way, and
        // the arithmetic is why: shave it and the module's own name is
        // what breaks first, which is how it broke at 560.
        .frame(minWidth: 620)
        .glassBackgroundEffect(
            in: RoundedRectangle(cornerRadius: DesignTokens.Panel.windowRadius, style: .continuous))
        // THE BAR RIDES THE TOP OF ITS WINDOW (2026-08-29). visionOS owns
        // where the window stands — there is no API to park it high — and
        // the system's default drop is dead ahead at apparatus height,
        // which put this bar inside the scene of every module (in Electric
        // Fields it opened BEHIND a capacitor plate). What the app does
        // own is where the bar sits within its invisible plain window:
        // top-aligned in the tall frame the window already claims, it
        // rides ~0.3 m higher and clears the apparatus band. The wearer
        // can still grab the window and park it anywhere; this only moves
        // the default.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // The three cases get three sentences, and they are deliberately not
    // one sentence with a variable in it. The worst version of this
    // message is the one that tells a simulator user to open Settings and
    // grant a permission they were never asked for.

    // The sentences moved onto `RoomModel.Sensing` on 2026-08-07, so the
    // hub can say the same things at the moment they actually matter —
    // the permission is asked for on the gallery, long before anybody
    // reaches a module title bar. See `Sensing.headline`.
    private static func sensingHeadline(_ sensing: RoomModel.Sensing) -> String {
        sensing.headline
    }

    private static func sensingDetail(_ sensing: RoomModel.Sensing) -> String {
        sensing.detail
    }
}
