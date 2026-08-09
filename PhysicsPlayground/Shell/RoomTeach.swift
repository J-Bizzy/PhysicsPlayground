//
//  RoomTeach.swift
//  PhysicsPlayground
//
//  THE FIRST SENTENCE OF A LAB, IN THE LAB.
//
//  Every module authors one `firstRunHint` — the sentence that tells you
//  what the apparatus in front of you is and what your hands can do to
//  it. Until 2026-08-08 the shell drew it in the flat module window, and
//  the first photograph ever taken of a lab in a room showed why that
//  was wrong: five steel bobs and four vector arrows standing THROUGH
//  the sentence, whole phrases unreadable, because RealityKit content
//  renders in front of a window that happens to be behind it.
//
//  Raising the text's contrast (it was styled `.secondary`, the app's
//  quietest, for the most important sentence in the lab) was a real fix
//  for a different problem and did almost nothing for this one. You
//  cannot win a depth argument with a colour.
//
//  So the teach moves into the room, which is where the goal document
//  said to put it and where everything else in this app already lives.
//  Three things follow from that, and they are the whole design:
//
//  1. IT STANDS NEARER THAN THE APPARATUS. Every occlusion bug in this
//     codebase has the same shape — the wordmark behind the catalog
//     window, the L4 paragraph inside the star, this — and the same fix:
//     put the words in front. `standoff` is closer than any lab's
//     physics, which is a promise the shell can keep because it is the
//     shell that places both.
//  2. IT DOES NOT RECEDE. `Recession` dims an instrument until a hand is
//     near, and it is right for instruments. A sentence you have not
//     read yet, dimmed because your hands are in your lap, is a sentence
//     you will dismiss unread.
//  3. IT IS DISMISSED BY TOUCHING IT, not by a close box in a corner.
//     Dismissal is the read receipt (`AppSettings.markHintSeen`), so the
//     target is the card, and the plate under it just says so.
//

import Foundation
import RealityKit
import SwiftUI
import RenderKit

@MainActor
final class RoomTeachCard {

    let root = Entity()

    /// SIZED FOR THE ANGLE IT SUBTENDS, not for how it looks written
    /// down. The first build used 0.026 m glyphs on a 0.66 m card at
    /// 0.70 m, which is half the field of view — the photograph is a wall
    /// of text with the room behind it. A card this close has to be
    /// physically small; 0.46 m at 0.72 m is about 35 degrees, which is
    /// a paragraph you take in rather than scan.
    static let wrapWidth: CGFloat = 0.46
    static let textSize: CGFloat = 0.018

    /// Nearer than any lab's apparatus — Pendulums hangs its rig around
    /// z = −0.95, Gravity Lab centres its system near −1.0, Circuits puts
    /// its bench at −0.9 — and just below the eye line, which is the
    /// other half of the placement.
    ///
    /// The first build sat at y = 1.12, and the photograph showed the
    /// bottom two lines cut off by the bottom of the field of view: 0.38
    /// m below a standing wearer's eyes at 0.70 m is nearly 30 degrees
    /// down, which is a glance, not a reading position. At 1.30 the card
    /// spans roughly 10 to 20 degrees below the horizon, where a book
    /// would be.
    static let standoff = SIMD3<Float>(0, 1.30, -0.72)

    /// Called when the card is touched. The shell turns this into
    /// `markHintSeen`, so it is the read receipt.
    var onDismiss: (() -> Void)?

    private var label: ModelEntity?
    private var backing: ModelEntity?
    private let target = Entity()
    private var lastText = ""
    private var reveal: Float = 0
    private var dismissing = false

    var isShowing: Bool { root.isEnabled && !dismissing }

    init() {
        root.components.set(OpacityComponent(opacity: 0))
        root.isEnabled = false
        root.addChild(target)
    }

    func setText(_ text: String) {
        guard text != lastText else { return }
        lastText = text
        rebuild(text)
    }

    /// Starts the fade-out and fires the receipt exactly once. Idempotent
    /// on purpose: a card mid-fade is still tappable for a few frames,
    /// and two receipts for one read is a wrong count in Settings.
    func dismiss() {
        guard !dismissing else { return }
        dismissing = true
        onDismiss?()
    }

    /// The whole card is the target, so a tap anywhere on it counts.
    func handleTap(_ entity: Entity) -> Bool {
        guard isShowing else { return false }
        var node: Entity? = entity
        while let current = node {
            if current === target { dismiss(); return true }
            node = current.parent
        }
        return false
    }

    func update(viewer: SIMD3<Float>?, dt: Double) {
        let wanted: Float = (dismissing || lastText.isEmpty) ? 0 : 1
        reveal = Motion.ease(reveal, toward: wanted, dt: dt, rate: 6)
        root.components.set(OpacityComponent(opacity: reveal))
        root.isEnabled = reveal > 0.001

        // FACES THE READER, because a paragraph read at a slant is a
        // paragraph read slowly. Yaw only — a card that tips to meet a
        // tall or short wearer reads as furniture that is falling over.
        if let viewer {
            let toViewer = viewer - root.position(relativeTo: nil)
            let flat = SIMD3<Float>(toViewer.x, 0, toViewer.z)
            if length(flat) > 1e-4 {
                root.orientation = simd_quatf(from: [0, 0, 1],
                                              to: normalize(flat))
            }
        }
    }

    private func rebuild(_ text: String) {
        label?.removeFromParent()
        backing?.removeFromParent()
        target.children.forEach { $0.removeFromParent() }
        guard !text.isEmpty else {
            label = nil
            backing = nil
            return
        }

        let mesh = Callout.textMesh(text, size: Self.textSize,
                                    wrapWidth: Self.wrapWidth)
        let bounds = mesh.bounds

        // "Tap anywhere…", because a card that is secretly a button is a
        // card nobody dismisses.
        let hintMesh = Callout.textMesh("Tap anywhere on this card to dismiss",
                                        size: PlateStyle.labelSize,
                                        wrapWidth: 0)
        let hintBounds = hintMesh.bounds

        // ONE PLATE UNDER BOTH. Sized from the union, because the footer
        // hung off the bottom of its own backing when the plate was built
        // from the paragraph alone — a caption floating on the room,
        // which is the very thing the plate exists to prevent.
        let textSpan = SIMD2<Float>(bounds.max.x - bounds.min.x,
                                    bounds.max.y - bounds.min.y)
        let hintSpan = SIMD2<Float>(hintBounds.max.x - hintBounds.min.x,
                                    hintBounds.max.y - hintBounds.min.y)
        let gap = PlateStyle.labelGap
        let blockWidth = max(textSpan.x, hintSpan.x)
        let blockHeight = textSpan.y + gap + hintSpan.y
        let union = BoundingBox(
            min: [-blockWidth / 2, -blockHeight / 2, 0],
            max: [blockWidth / 2, blockHeight / 2, 0])
        let plate = BackedLabel.backing(behind: union, size: Self.textSize)
        root.addChild(plate)
        backing = plate

        var material = UnlitMaterial(color: UIColor(white: 0.97, alpha: 1))
        material.blending = .opaque
        let model = ModelEntity(mesh: mesh, materials: [material])
        // Top-aligned inside the block: the paragraph occupies the upper
        // `textSpan.y`, the footer the lower `hintSpan.y`.
        model.position = [
            -(bounds.min.x + bounds.max.x) / 2,
            blockHeight / 2 - textSpan.y / 2 - (bounds.min.y + bounds.max.y) / 2,
            0.001,
        ]
        root.addChild(model)
        label = model

        var hintMaterial = UnlitMaterial(color: UIColor(white: 0.72, alpha: 1))
        hintMaterial.blending = .opaque
        let footer = ModelEntity(mesh: hintMesh, materials: [hintMaterial])
        footer.position = [
            -(hintBounds.min.x + hintBounds.max.x) / 2,
            -blockHeight / 2 + hintSpan.y / 2
                - (hintBounds.min.y + hintBounds.max.y) / 2,
            0.001,
        ]
        root.addChild(footer)

        // The touch target is the plate's footprint, not the glyph run:
        // the gaps between words are part of the card, and so is the
        // footer that tells you to touch it.
        let extents = plate.model?.mesh.bounds.extents
            ?? SIMD3<Float>(blockWidth, blockHeight, 0)
        target.components.set(CollisionComponent(shapes: [
            .generateBox(width: extents.x, height: extents.y, depth: 0.02),
        ]))
        target.components.set(InputTargetComponent())
        target.components.set(HoverEffectComponent())

        // THE LABEL IS THE SENTENCE. `SpatialActions.attach` writes the
        // accessibility label itself, so setting one beforehand and then
        // attaching leaves whatever `attach` was given — the first draft
        // here said "First-run hint", which is a VoiceOver user being
        // told a hint exists and never being read it. The card's whole
        // content is text; there is nothing else for the label to be.
        SpatialActions.attach(
            to: target,
            label: text,
            value: "Tap to dismiss",
            activate: { [weak self] in
                guard let self else { return }
                _ = self.handleTap(self.target)
            })
    }
}

/// Mounts the teach for whichever module is active, and turns a touch
/// into the read receipt.
struct RoomTeachView: View {
    let module: ModuleDescriptor
    @Environment(AppModel.self) private var appModel

    @State private var card: RoomTeachCard?
    @State private var subscription: EventSubscription?

    var body: some View {
        RealityView { content in
            let made = RoomTeachCard()
            made.root.position = RoomTeachCard.standoff
            made.onDismiss = { appModel.settings.markHintSeen(module.id) }
            if !appModel.settings.hasSeenHint(module.id) {
                made.setText(module.firstRunHint)
            }
            content.add(made.root)
            card = made
            subscription = content.subscribe(to: SceneEvents.Update.self) {
                [weak made] event in
                made?.update(
                    viewer: appModel.room.headPosition.map { SIMD3<Float>($0) },
                    dt: event.deltaTime)
            }
        }
        .onDisappear {
            subscription?.cancel()
            subscription = nil
        }
        .simultaneousGesture(
            TapGesture()
                .targetedToAnyEntity()
                .onEnded { value in _ = card?.handleTap(value.entity) }
        )
    }
}
