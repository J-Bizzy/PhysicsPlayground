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
    @State private var confirmingReset = false
    @State private var showingSensing = false
    /// Set when "Show in room" fails, so it can say so.
    @State private var showInRoomFailed = false

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                // Left: navigation.
                Button {
                    appModel.activeModuleID = nil
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
                // (The palette bead does NOT carry lab switching either,
                // despite being the obvious place to look: its four
                // petals are pause, capture, settings and reset, and a
                // fifth was refused on the record.)
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
                        .frame(width: 30, height: 30)
                        .background(module.accent.opacity(0.18),
                                    in: RoundedRectangle(cornerRadius: 9, style: .continuous))
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
                        showInRoomFailed = false
                        let result = await openImmersiveSpace(
                            id: PlaygroundSpaceView.spaceID)
                        if case .error = result { showInRoomFailed = true }
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
                }
            }

            // The one-time hint: a sentence from the module, shown
            // until the user closes it. Dismissal is the read receipt.
            if !appModel.settings.hasSeenHint(module.id) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "hand.point.up.left")
                        .font(.footnote)
                        .foregroundStyle(module.accent)
                    Text(module.firstRunHint)
                        .font(DesignTokens.TypeScale.footnote)
                        .foregroundStyle(.secondary)
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
                .padding(.horizontal, 8)
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
            in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    // The three cases get three sentences, and they are deliberately not
    // one sentence with a variable in it. The worst version of this
    // message is the one that tells a simulator user to open Settings and
    // grant a permission they were never asked for.

    private static func sensingHeadline(_ sensing: RoomModel.Sensing) -> String {
        switch sensing {
        case .fine: ""
        case .unsupported: "This device can't sense your room"
        case .denied: "Physics Playground can't see your room"
        case .failed: "Room sensing didn't start"
        }
    }

    private static func sensingDetail(_ sensing: RoomModel.Sensing) -> String {
        switch sensing {
        case .fine:
            ""
        case .unsupported:
            "Experiments run in open space instead. The physics is "
            + "identical — only the parts that use your real walls and "
            + "furniture are missing."
        case .denied:
            "Experiments won't bounce off your real walls or floor, and "
            + "apparatus won't be hidden behind your furniture. To turn "
            + "it back on, open Settings › Privacy & Security › World "
            + "Sensing and allow Physics Playground."
        case .failed:
            "Something went wrong starting it. Leaving this lab and "
            + "opening it again usually fixes it."
        }
    }
}
