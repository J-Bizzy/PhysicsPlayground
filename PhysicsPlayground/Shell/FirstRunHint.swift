//
//  FirstRunHint.swift
//  Physics Playground — Shell
//
//  The one-time teach, IN THE ROOM.
//
//  `ModuleDescriptor.firstRunHint` is a hand-written paragraph per lab —
//  what to tap, what to pull, what the two-hand gesture does — and until
//  2026-08-07 it had exactly one render site: a strip inside the module's
//  flat window. That window is a `.plain` panel the user placed at some
//  point in their room, and entering a lab does not move it or turn them
//  toward it. So the app's only onboarding was routinely BEHIND the
//  reader, describing gestures for apparatus they were looking at over
//  their shoulder.
//
//  This is the same sentence, mounted where the apparatus is. It is a
//  SwiftUI attachment rather than a `Callout` because a callout is the
//  app's form for a NUMBER anchored to a place — one short line, no
//  wrapping — and these are paragraphs. What makes it in-room is that it
//  hangs in the room; the text layout is just text layout.
//
//  BOTH SURFACES STAY, and they are not a duplication. They read and
//  write the same `AppSettings.seenHints`, so dismissing either dismisses
//  the other, and the flat one is the app's standing guarantee that
//  nothing is reachable only in space. Two doors to one thing is the
//  pattern this project asks for everywhere else.
//

import RealityKit
import SwiftUI

struct FirstRunHintView: View {
    let module: ModuleDescriptor

    @Environment(AppModel.self) private var appModel
    @State private var anchor = Entity()

    /// Above the apparatus and slightly left, at about the height a lab's
    /// own instruments sit — the same reasoning the palette bead's
    /// placement comment gives, in the mirror position. Every module
    /// centres its physics, so one shell position works for all six, and
    /// a teach that appears in the same place every time is a teach the
    /// reader learns to look for.
    private static let home = SIMD3<Float>(-0.58, 1.66, -1.02)

    var body: some View {
        RealityView { content, attachments in
            guard let card = attachments.entity(for: "firstRunHint") else { return }
            anchor.position = Self.home
            anchor.components.set(BillboardComponent())
            anchor.addChild(card)
            content.add(anchor)
        } update: { _, _ in
            // The card retires the moment the hint is marked seen — by a
            // pinch here, or by the close button on the flat one.
            anchor.isEnabled = !appModel.settings.hasSeenHint(module.id)
        } attachments: {
            Attachment(id: "firstRunHint") {
                VStack(alignment: .leading, spacing: 8) {
                    Label(module.title, systemImage: "hand.point.up.left")
                        .font(DesignTokens.TypeScale.footnote.weight(.semibold))
                        .foregroundStyle(module.accent)
                    Text(module.firstRunHint)
                        .font(DesignTokens.TypeScale.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Pinch this to dismiss")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: 320, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .glassBackgroundEffect(in: RoundedRectangle(cornerRadius: 16,
                                                            style: .continuous))
                // A PINCH DISMISSES IT, which is why this one keeps its
                // hit testing where the podium hint deliberately drops
                // its own: that card sits in the path of the carry it
                // describes and must never take a pinch, and this one IS
                // the target. It hangs clear of every module's apparatus
                // rather than over it.
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.2)) {
                        appModel.settings.markHintSeen(module.id)
                    }
                    SoundPalette.play(.releaseTick, on: anchor, volume: 0.25)
                }
                .accessibilityHint("Dismisses this hint")
            }
        }
        .opacity(appModel.settings.hasSeenHint(module.id) ? 0 : 1)
    }
}
