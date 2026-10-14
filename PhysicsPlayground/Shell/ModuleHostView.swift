//
//  ModuleHostView.swift
//  Physics Playground — Shell
//
//  The module's window is a title bar: back to the catalog, the module's
//  name, and the Physics box, place-the-lab, studio and Reset. Beneath it, only
//  while the immersive space is closed, "Show in room". Nothing else —
//  no panel and no hint; the apparatus explains itself.
//

import RenderKit
import SwiftUI

struct ModuleHostView: View {
    let module: ModuleDescriptor

    @Environment(AppModel.self) private var appModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
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
                ControlButton("Home", systemImage: "chevron.left", iconOnly: true) {
                    appModel.go(to: nil)
                }
                .accessibilityHint("Leaves this lab for the gallery of labs")

                Spacer(minLength: 12)

                // Center: the module's identity.
                HStack(spacing: 10) {
                    Image(systemName: module.icon)
                        // A semantic style, so it scales with Dynamic Type.
                        .font(.headline)
                        .foregroundStyle(module.accent)
                        // The tile scales with the glyph, so accessibility sizes do not
                        // overflow it.
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
                // The Physics box: the lab's live numbers on a card in the
                // room, with a rail for each quantity you can set.
                ControlToggle("Physics", systemImage: "function", iconOnly: true,
                              isOn: Bindable(appModel).physicsBoardOpen)
                    .accessibilityHint("Shows this lab's live physics values in the room, with rails for the ones you can set")

                ControlToggle("Place the lab", systemImage: "move.3d", iconOnly: true,
                              isOn: Bindable(appModel.labPlacement).isPlacing)
                    .accessibilityHint("Shows an anchor you can drag to move the whole lab to where you have room")

                ControlToggle("Studio Mode", systemImage: "moon.stars", iconOnly: true,
                              isOn: Bindable(appModel).studioMode)
                    .accessibilityHint("Replaces your room with a dark studio")

                // Shown only when the app cannot see the room, so the bar is unchanged
                // in the ordinary case; a popover rather than a row, so no panel grows
                // back.
                if appModel.room.sensing != .fine {
                    ControlButton("Room sensing unavailable",
                                  systemImage: "exclamationmark.triangle",
                                  iconOnly: true) {
                        showingSensing.toggle()
                    }
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

                // Reset asks first: in Circuit Workshop it wipes a bench that persists
                // across launches.
                ControlButton("Reset", systemImage: "arrow.counterclockwise",
                              iconOnly: true) {
                    confirmingReset = true
                }
                .accessibilityHint("Returns this lab to its starting state")
                .confirmationDialog("Reset \(module.title)?",
                                    isPresented: $confirmingReset,
                                    titleVisibility: .visible) {
                    Button("Reset", role: .destructive) {
                        appModel.resetActiveModule(module)
                    }
                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text("Everything you have set up here goes back to how the lab opened.")
                }
            }

            if !appModel.isImmersiveSpaceOpen {
                ControlButton("Show in room", systemImage: "sparkles",
                              emphasis: .prominent(module.accent),
                              fillsWidth: true) {
                    Task {
                        withAnimation(.easeOut(duration: 0.2)) {
                            showInRoomFailed = false
                        }
                        // Assets warm off-main before the space opens, as at the gallery door.
                        await PropCache.warmUp()
                        let result = await openImmersiveSpace(
                            id: PlaygroundSpaceView.spaceID)
                        if case .error = result {
                            withAnimation(.easeOut(duration: 0.2)) {
                                showInRoomFailed = true
                            }
                        }
                    }
                }
                .accessibilityHint("Places this lab in your room")

                // Says so when the space refused to open, with a manual retry and never
                // a loop.
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

        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        // Wide enough for the longest module names beside the circular
        // buttons: "Orbital Mechanics" and "Projectile Motion" (17 characters).
        // At 620 "Orbital Mecha…" truncated in the simulator (2026-09-06).
        .frame(minWidth: 690)
        .glassBackgroundEffect(
            in: RoundedRectangle(cornerRadius: DesignTokens.Panel.windowRadius, style: .continuous))
        // Top-aligned in the tall frame the window claims, so the bar rides
        // above the apparatus band instead of inside it. The wearer can still
        // park the window anywhere.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // The sentences live on `RoomModel.Sensing`, so the hub says the same
    // things where the permission is asked for.
    private static func sensingHeadline(_ sensing: RoomModel.Sensing) -> String {
        sensing.headline
    }

    private static func sensingDetail(_ sensing: RoomModel.Sensing) -> String {
        sensing.detail
    }
}
