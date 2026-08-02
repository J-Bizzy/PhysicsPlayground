//
//  ModuleHostView.swift
//  Physics Playground — Shell
//
//  The module's window is a TITLE BAR. Not "a title bar plus" — the bar,
//  and two things that appear only when they have something to say.
//
//  Left: back to the catalog, and a jump to any module. Middle: the
//  module's name. Right: notebook, place-the-lab, studio, the legend
//  key, and Reset. Beneath it, and only conditionally: "Show in room"
//  while the immersive space is closed, because the space is where the
//  module lives and there would otherwise be no way back into it; and
//  the module's one authored first-run sentence until it is dismissed.
//
//  EVERYTHING ELSE WENT (DECISIONS.md, 2026-08-01). `makeControls` is
//  deleted from the module contract, the six `*ControlsPanel.swift` are
//  gone, the legend moved into a popover on the bar, the placement strip
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
    @State private var showingLegend = false

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                // Left: navigation.
                Button {
                    appModel.activeModuleID = nil
                } label: {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel("All simulations")
                .accessibilityHint("Returns to the catalog")

                Menu {
                    ForEach(ModuleCatalog.all(appModel: appModel)) { entry in
                        Button {
                            appModel.activeModuleID = entry.id
                        } label: {
                            if entry.id == module.id {
                                Label(entry.title, systemImage: "checkmark")
                            } else {
                                Label(entry.title, systemImage: entry.icon)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "square.grid.3x3")
                }
                .accessibilityLabel("Switch simulation")

                Spacer(minLength: 12)

                // Center: the module's identity.
                HStack(spacing: 10) {
                    Image(systemName: module.icon)
                        .font(.system(size: 15, weight: .semibold))
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

                // The legend, as a POPOVER rather than a section
                // stacked under the bar.
                //
                // It could not simply be deleted with the rest: colour
                // is semantic in this app and owned by `VectorPalette`
                // (red = positive/N-pole, blue = negative, arrow length
                // = strength), so the legend is the key to the app's own
                // vocabulary — and Gravity Lab's carries the load-bearing
                // admission that Mercury's 43″/century needs GR, "which
                // this lab does not model". Dropping that would repeat
                // the disclosed-fiction failure the field module was
                // pulled up on.
                //
                // Anchored to the bar, so the window still shows only
                // the bar at rest, and still rendered by the SHELL from
                // `module.legend`, so no module can restyle or forget it.
                if !module.legend.isEmpty {
                    Button {
                        showingLegend.toggle()
                    } label: {
                        Image(systemName: "list.bullet.rectangle")
                    }
                    .accessibilityLabel("Key")
                    .accessibilityHint("What the colours and shapes in this simulation mean")
                    .popover(isPresented: $showingLegend,
                             attachmentAnchor: .point(.bottom)) {
                        LegendView(items: module.legend)
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
                .accessibilityHint("Returns this simulation to its starting state")
                .confirmationDialog("Reset \(module.title)?",
                                    isPresented: $confirmingReset,
                                    titleVisibility: .visible) {
                    Button("Reset", role: .destructive) { module.reset() }
                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text("Everything you have set up here goes back to how the module opened. Recorded notebook entries are kept.")
                }
            }
            .buttonBorderShape(.circle)

            if !appModel.isImmersiveSpaceOpen {
                Button {
                    Task {
                        _ = await openImmersiveSpace(id: PlaygroundSpaceView.spaceID)
                    }
                } label: {
                    Label("Show in room", systemImage: "sparkles")
                        .font(.body)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.podProminent(module.accent))
                .accessibilityHint("Places the simulation and its control pods in your room")
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
        // The legend's Key button makes SIX, so this went to 740. The
        // number is load-bearing and the arithmetic is why: shave it and
        // the module's own name is what breaks first.
        .frame(minWidth: 740)
        .glassBackgroundEffect(
            in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}
