//
//  ModuleHostView.swift
//  Physics Playground — Shell
//
//  A lab's window is a title bar: Home and More on the left, the lab's
//  name, Pause on the right. More opens one glass panel beside the window
//  holding everything secondary — the lab's own layers, modes and verbs,
//  the quantities it has no object for, its live numbers, the room, and
//  Reset. The room holds the apparatus and nothing else. Beneath the bar,
//  only while the immersive space is closed, "Show in Room".
//

import RenderKit
import SwiftUI

struct ModuleHostView: View {
    let module: ModuleDescriptor

    @Environment(AppModel.self) private var appModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    /// The icon tile scales with the type it frames.
    @ScaledMetric(relativeTo: .headline) private var iconTile = 30.0
    @State private var showingSensing = false
    /// Set when "Show in Room" fails, so it can say so.
    @State private var showInRoomFailed = false

    var body: some View {
        @Bindable var appModel = appModel
        VStack(spacing: 14) {
            HStack(spacing: ControlMetrics.spacing) {
                // Left: navigation, and the one way to everything secondary.
                ControlButton("Home", systemImage: "chevron.left", iconOnly: true) {
                    appModel.go(to: nil)
                }
                .accessibilityHint("Leaves this lab for the home and its portals")
                MoreButton(isExpanded: $appModel.moreOpen)

                Spacer(minLength: 12)

                // Center: the lab's identity.
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
                        // "Orbital Me…" at the largest sizes otherwise; the bar
                        // has no room to grow beside the window.
                        .minimumScaleFactor(0.6)
                        .accessibilityAddTraits(.isHeader)
                }

                Spacer(minLength: 12)

                // Shown only when the app cannot see the room, so the bar is unchanged
                // in the ordinary case; a popover rather than a row, so no panel grows
                // back.
                if appModel.room.sensing != .fine {
                    ControlButton("Room sensing unavailable",
                                  systemImage: "exclamationmark.triangle",
                                  iconOnly: true) {
                        showingSensing.toggle()
                    }
                    .accessibilityHint(appModel.room.sensing.headline)
                    .popover(isPresented: $showingSensing,
                             attachmentAnchor: .point(.bottom)) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(appModel.room.sensing.headline)
                                .font(DesignTokens.TypeScale.sectionHeader)
                            Text(appModel.room.sensing.detail)
                                .font(DesignTokens.TypeScale.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(20)
                        .frame(maxWidth: 340)
                    }
                }

                // Right: time — the one control every lab shares.
                let paused = module.isPaused()
                ControlButton(paused ? "Resume" : "Pause",
                              systemImage: paused ? "play.fill" : "pause.fill",
                              iconOnly: true) {
                    module.togglePause()
                }
                .accessibilityHint(Self.pauseHint(
                    paused: paused, recording: appModel.settings.timeCapsule))
            }

            if !appModel.isImmersiveSpaceOpen {
                // The home window's words, in its case: one button, one name.
                ControlButton("Show in Room", systemImage: "sparkles",
                              emphasis: .prominent,
                              fillsWidth: true) {
                    Task {
                        withAnimation(.easeOut(duration: 0.2)) {
                            showInRoomFailed = false
                        }
                        // Assets warm off-main before the space opens, as at the home's door.
                        await PropCache.warmUp()
                        let result = await openImmersiveSpace(
                            id: PlaygroundSpaceView.spaceID)
                        if case .error = result {
                            withAnimation(.easeOut(duration: 0.2)) {
                                showInRoomFailed = true
                            }
                            AccessibilityNotification.Announcement("The room couldn't open.").post()
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
                        Text("The room couldn't open.")
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
        .frame(minWidth: 620)
        .glassBackgroundEffect(
            in: RoundedRectangle(cornerRadius: DesignTokens.Panel.windowRadius, style: .continuous))
        // More opens beside the window, on the left, where every control in
        // the house stands — never over the apparatus in front of you.
        .ornament(visibility: appModel.moreOpen ? .visible : .hidden,
                  attachmentAnchor: .scene(.topLeading),
                  contentAlignment: .topTrailing) {
            // Mounted only while open: a hidden ornament keeps its content
            // live, and behind a closed More the Values timeline re-derived
            // every reading eight times a second.
            if appModel.moreOpen {
                LabMorePanel(module: module)
                    .padding(.trailing, ControlMetrics.spacing)
            }
        }
        // Top-aligned in the tall frame the window claims, so the bar rides
        // above the apparatus band instead of inside it. The wearer can still
        // park the window anywhere.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// What Pause says it does. The reel is promised only while the Time
    /// Capsule records: switched off in Settings, a pause is just a pause.
    static func pauseHint(paused: Bool, recording: Bool) -> String {
        if paused { return "Runs the lab again, from the moment on screen" }
        return recording ? "Freezes the lab; a reel appears to rewind it"
                         : "Freezes the lab"
    }
}
