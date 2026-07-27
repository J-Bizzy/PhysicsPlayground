//
//  HubSpaceView.swift
//  Physics Playground — Hub
//
//  The spatial menu: a clock face of exhibits. The large, shell-free
//  3D miniatures form a vertical ring facing the user, encircling the
//  title window at its center — one glance takes in every exhibit,
//  names beneath each in their module accents. Look at one (the system
//  hover effect lights it up) and pinch to enter.
//
//  The only motion is idle life: exhibits bob out of phase and their
//  miniatures slowly turn. A handful of entities; per-frame work is a
//  few transform writes.
//
//  Vignettes are keyed by module id with a generic fallback, so a new
//  module joins the carousel for free and gets a bespoke miniature
//  with one case.
//

import SwiftUI
import RealityKit
import RenderKit

struct HubSpaceView: View {
    @Environment(AppModel.self) private var appModel
    @State private var scene = HubScene()

    var body: some View {
        RealityView { content, attachments in
            let modules = ModuleCatalog.all(appModel: appModel)
            var progress: [String: (done: Int, total: Int)] = [:]
            for module in modules {
                let entries = ExperimentCatalog.experiments(for: module.id,
                                                            appModel: appModel)
                progress[module.id] = (
                    entries.filter {
                        appModel.experiments.completed.contains($0.experiment.id)
                    }.count,
                    entries.count)
            }
            scene.build(modules: modules, progress: progress)
            content.add(scene.root)

            if let card = attachments.entity(for: "detail") {
                // The reading shelf: a fixed spot under the gallery,
                // billboarded so it always faces the reader.
                card.position = HubScene.detailCardPosition
                card.components.set(BillboardComponent())
                card.isEnabled = false
                scene.root.addChild(card)
                scene.detailCard = card
            }

            // `[weak scene]` matters here, and every module already knew
            // it. The subscription is stored ON the scene, so a strong
            // capture makes scene → subscription → closure → scene: a
            // cycle that no amount of leaving the hub can break. Each
            // return to the hub built another one, and every one of them
            // went on animating its own orphaned copy of the gallery,
            // forever, while you were somewhere else entirely.
            scene.subscription = content.subscribe(to: SceneEvents.Update.self) { [weak scene] event in
                scene?.animate(dt: event.deltaTime, lookRay: appModel.room.lookRay)
            }
        } attachments: {
            Attachment(id: "detail") {
                if let module = ModuleCatalog.all(appModel: appModel)
                    .first(where: { $0.id == scene.focusedModuleID }) {
                    HubDetailCard(module: module)
                }
            }
        }
        // Entering a module replaces this view, and an EventSubscription
        // is not tied to the view that made it — left alone it keeps
        // calling `animate` on a hub that is no longer on screen, for
        // the whole time you are inside a module, holding the entire
        // exhibit graph alive behind it.
        .onDisappear {
            scene.subscription?.cancel()
            scene.subscription = nil
        }
        .gesture(
            TapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    guard let id = scene.moduleID(for: value.entity) else { return }
                    scene.pulseExhibit(id: id)
                    Task {
                        // Let the pulse land before the scene switches.
                        try? await Task.sleep(for: .milliseconds(160))
                        appModel.activeModuleID = id
                    }
                }
        )
    }
}

/// The hub's entity graph and idle animation state.
@MainActor
@Observable
final class HubScene {
    let root = Entity()
    var subscription: EventSubscription?

    private struct Exhibit {
        let moduleID: String
        let anchor: Entity      // ring position (bobbed every frame)
        let pulser: Entity      // scale pulse on selection
        let vignette: Entity    // slowly rotating miniature
        let namePivot: Entity   // billboarded name plate
        let halo: Entity        // accent glow, focused only
        let basePosition: SIMD3<Float>
        /// The animation the miniature was built with — captured
        /// alongside its own geometry, so a model and its motion cannot
        /// drift apart. They did: the old table matched children by
        /// NAME, and those names only existed in the procedural
        /// fallbacks, so every module that loaded an asset instead
        /// silently never animated at all.
        let animate: (Double) -> Void
        /// 0 = resting in the ring, 1 = the one you are facing. Eased.
        var focus: Float = 0
    }

    /// Which exhibit the user is facing, published only when it CHANGES
    /// so the detail card can re-render without SwiftUI seeing sixty
    /// updates a second.
    private(set) var focusedModuleID: String?
    /// Where the focused exhibit is, for the detail card to hang under.
    private(set) var focusedAnchor: Entity?
    /// The SwiftUI reading shelf, shown while something has focus.
    var detailCard: Entity?
    /// Under the lower arc, clear of the hub window above it.
    static let detailCardPosition = SIMD3<Float>(0, 0.94, -1.42)
    private var exhibits: [Exhibit] = []
    private var time = 0.0
    /// The 3-D bubble title the exhibits ring, bobbing at the centre.
    private let titleAnchor = Entity()

    /// The ring encircles the title: a vertical circle in the frontal
    /// plane, a step beyond it in depth.
    // MARK: Layout — two staggered arcs, not a ring
    //
    // The ring was a clock face of nine miniatures, and it had two
    // problems that no amount of polish fixed. It was effectively
    // PAINTED ON THE FAR WALL — every exhibit at one depth, so the whole
    // menu read as a poster rather than as objects in a room. And a ring
    // wide enough to space nine things put its left and right extremes
    // past 50 degrees of azimuth, out at the edge of vision where you
    // cannot see them without turning your whole head.
    //
    // Two shallow arcs wrapped around the user fix both. Everything sits
    // on a cylinder at arm's-length-and-a-bit, so each exhibit genuinely
    // faces you and the ones to the side are nearer than the ones ahead
    // — real parallax as you move. Five above, four below, staggered so
    // no exhibit hides another and so a gap falls dead ahead at the
    // bottom, where the hub window lives.

    /// Distance from the user to every exhibit.
    private static let arcRadius: Float = 2.35
    /// The two rows, as (height, azimuths in degrees). The bottom row is
    /// offset half a step so the two rows interleave rather than
    /// stacking into columns.
    private static let arcRows: [(y: Float, azimuths: [Float])] = [
        (1.86, [-30, -15, 0, 15, 30]),
        (1.16, [-22.5, -7.5, 7.5, 22.5]),
    ]

    /// Where an exhibit sits, by its index in the catalog.
    private static func arcPosition(_ index: Int) -> SIMD3<Float> {
        var remaining = index
        for row in arcRows {
            if remaining < row.azimuths.count {
                let azimuth = row.azimuths[remaining] * .pi / 180
                return SIMD3(arcRadius * sin(azimuth), row.y,
                             -arcRadius * cos(azimuth))
            }
            remaining -= row.azimuths.count
        }
        // More modules than slots: tuck extras behind the middle.
        return SIMD3(0, arcRows[0].y, -arcRadius - 0.6)
    }

    /// The miniatures, unbottled and enlarged. They were trinkets.
    /// How large every miniature reads, whatever it is made of. Each is
    /// measured after it is built and normalised to this, so the gallery
    /// has one rhythm however the nine models happen to be drawn.
    private static let exhibitSize: Float = 0.27

    // MARK: Focus
    //
    // Nine exhibits shouting equally is a wall of clutter with no way in.
    // A menu in a headset can do what a menu on a screen cannot: notice
    // which one you have TURNED TOWARD, and answer. The one you face
    // grows, brightens, lights an accent halo and names itself in full,
    // with a card underneath telling you what it is and how far through
    // it you are; the other eight recede and their names drop to a
    // whisper. Nothing moves on its own — the motion is yours.
    //
    // Head direction, not eye gaze: visionOS never hands an app the
    // eyes. Turning your head at something is the honest signal, and it
    // is the same look ray the field probes use.

    /// How far off your look direction an exhibit can be and still take
    /// focus, radians.
    private static let focusCone: Float = 26 * .pi / 180
    /// The focused exhibit has to be this much closer to your look
    /// direction than the current one before focus jumps — hysteresis,
    /// so a scanning glance doesn't strobe the ring.
    private static let focusStickiness: Float = 0.72
    /// Resting scale of an unfocused exhibit once ANY exhibit is
    /// focused, and how much the focused one grows.
    private static let unfocusedScale: Float = 0.90
    private static let focusedScale: Float = 1.34
    /// How far the focused exhibit steps toward the user.
    private static let focusedApproach: Float = 0.16

    // MARK: Build

    func build(modules: [ModuleDescriptor],
               progress: [String: (done: Int, total: Int)] = [:]) {
        // The name crowns the gallery; the exhibits fill two arcs below
        // it, reading left to right, top row then bottom.
        buildBubbleTitle()
        for (index, module) in modules.enumerated() {
            buildExhibit(for: module, at: Self.arcPosition(index),
                         progress: progress[module.id] ?? (0, 0))
        }
    }

    // MARK: The 3-D bubble title

    /// The title crowns the arcs rather than being ringed by them —
    /// there is no longer a middle for it to sit in.
    private static let titlePosition = SIMD3<Float>(0, 2.32, -2.05)

    /// Warm ivory, opaque, self-lit enough to hold its own against
    /// daylight. (It was a frosted grey at 80% opacity, which over a
    /// cream wall is a smudge.)
    private static let titleColor = UIColor(red: 0.99, green: 0.98, blue: 0.95, alpha: 1)
    /// The warm edge-light behind the letters — the thing that turns
    /// flat white type into something that looks lit. Champagne rather
    /// than gold: at full saturation it read as a toy.
    private static let titleRimColor = UIColor(red: 1.0, green: 0.88, blue: 0.70, alpha: 1)
    /// The lockup's overall width, metres. Both lines are scaled to
    /// exactly this, which is what makes it read as a designed mark.
    private static let titleWidth: Float = 0.72
    /// Gap between the two lines, as a fraction of a line's cap height.
    private static let titleLeading: Float = 0.30

    /// "Physics / Playground" as a two-line LOCKUP, not two words that
    /// happen to be near each other.
    ///
    /// Three things were wrong. It was not actually centred: `bubbleText`
    /// only ever centred on X, so every line hung with its baseline on
    /// the anchor and the whole block floated high. The two lines were
    /// spaced by a hard-coded ±12 cm unrelated to how tall the glyphs
    /// actually are. And "Physics" is seven characters against
    /// "Playground"'s ten, so at one point size the lines were wildly
    /// different widths and the pair read as an accident.
    ///
    /// Now both lines are measured and scaled to a common width, stacked
    /// with leading derived from their real cap height, and the whole
    /// block is centred on its anchor — the flush-both-sides two-line
    /// lockup that every good wordmark uses.
    private func buildBubbleTitle() {
        titleAnchor.position = Self.titlePosition

        let lines = ["Physics", "Playground"]
        // Build at a reference size, then scale each to the common width.
        let reference: CGFloat = 0.17
        let built = lines.map { text -> (entity: Entity, extents: SIMD3<Float>) in
            (Self.titleLine(text, size: reference), Self.textExtents(text, size: reference))
        }
        let scales = built.map { Self.titleWidth / max($0.extents.x, 1e-4) }
        // Cap heights AFTER scaling — a wider scale makes taller letters.
        let heights = zip(built, scales).map { $0.0.extents.y * $0.1 }
        let gap = heights.reduce(0, +) / Float(heights.count) * Self.titleLeading
        let blockHeight = heights.reduce(0, +) + gap * Float(heights.count - 1)

        // Walk down from the top of the block, so the whole lockup ends
        // up centred on the anchor whatever the words are.
        var cursor = blockHeight / 2
        for (index, item) in built.enumerated() {
            let scale = scales[index]
            let height = heights[index]
            item.entity.scale = SIMD3(repeating: scale)
            item.entity.position.y = cursor - height / 2
            titleAnchor.addChild(item.entity)
            cursor -= height + gap
        }

        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = "Physics Playground"
        titleAnchor.components.set(accessibility)
        root.addChild(titleAnchor)
    }

    /// One line of the title, as three stacked passes.
    ///
    /// The old treatment was a near-black copy shoved down and back,
    /// which is a drop shadow — and a hard offset drop shadow is exactly
    /// what makes 3-D type look like clip art. These layers sit
    /// CONCENTRICALLY instead: a soft dark plate that gives the letters
    /// something to be light against whatever wall is behind them, a
    /// warm rim just proud of the glyph edge that reads as light
    /// catching them, and the ivory letters themselves on top.
    private static func titleLine(_ text: String, size: CGFloat) -> Entity {
        let line = Entity()

        let backing = bubbleText(text, size: size,
                                 color: UIColor(white: 0.03, alpha: 1),
                                 opacity: 0.45, emissive: 0)
        // Pulled in tight behind the glyphs. The layers were far enough
        // back that parallax revealed them off to one side, which is the
        // hard offset drop shadow this was meant to replace; keeping
        // them close makes the separation come from SCALE, which reads
        // as a rim from any angle.
        backing.scale = SIMD3(repeating: 1.10)
        backing.position.z = -0.022
        line.addChild(backing)

        let rim = bubbleText(text, size: size, color: titleRimColor,
                             opacity: 0.55, emissive: 0.75)
        rim.scale = SIMD3(repeating: 1.042)
        rim.position.z = -0.009
        line.addChild(rim)

        let letters = bubbleText(text, size: size, color: titleColor,
                                 opacity: 1, emissive: 0.32)
        line.addChild(letters)
        return line
    }

    /// The measured size of a run of the title face, for the lockup.
    private static func textExtents(_ text: String, size: CGFloat) -> SIMD3<Float> {
        MeshResource.generateText(
            text, extrusionDepth: Float(size) * 0.45,
            font: roundedFont(size: size), alignment: .center
        ).bounds.extents
    }

    /// The app's signature 3-D "bubble" type, in one reusable builder:
    /// fat rounded heavy glyphs extruded into a glossy clear-coated
    /// solid, centred on its own origin and returned as a group. The hub
    /// title and every exhibit name plate share this one treatment.
    ///
    /// "Centred" now means centred on BOTH axes. It only ever centred on
    /// X, so every run of this type hung with its baseline on the anchor
    /// and its visible mass floating above — which is why the hub title
    /// sat high in its ring and every exhibit name sat high under its
    /// miniature. One line, two words of a fix.
    ///
    /// `opacity` < 1 turns the letters to smoky glass; `emissive` sets
    /// how much they glow against the room.
    static func bubbleText(_ text: String, size: CGFloat, color: UIColor,
                           opacity: Float = 1, emissive: Float = 0.28) -> Entity {
        let group = Entity()
        let font = roundedFont(size: size)
        let mesh = MeshResource.generateText(
            text, extrusionDepth: Float(size) * 0.45,
            font: font, alignment: .center)
        let bounds = mesh.bounds
        let centerX = -(bounds.min.x + bounds.max.x) / 2
        let centerY = -(bounds.min.y + bounds.max.y) / 2

        var glossy = PhysicallyBasedMaterial()
        glossy.baseColor = .init(tint: color)
        glossy.roughness = 0.16
        glossy.metallic = 0.0
        glossy.clearcoat = .init(floatLiteral: 1.0)
        glossy.clearcoatRoughness = .init(floatLiteral: 0.12)
        glossy.emissiveColor = .init(color: color)
        glossy.emissiveIntensity = emissive
        if opacity < 1 {
            glossy.blending = .transparent(opacity: .init(floatLiteral: opacity))
        }
        let letters = ModelEntity(mesh: mesh, materials: [glossy])
        letters.position = [centerX, centerY, 0]
        group.addChild(letters)
        return group
    }

    /// SF Rounded at a heavy weight — the fat, round glyphs that make
    /// the extruded text read as bubbles.
    private static func roundedFont(size: CGFloat) -> MeshResource.Font {
        let base = UIFont.systemFont(ofSize: size, weight: .heavy)
        if let descriptor = base.fontDescriptor.withDesign(.rounded) {
            return UIFont(descriptor: descriptor, size: size)
        }
        return base
    }

    private func buildExhibit(for module: ModuleDescriptor,
                              at basePosition: SIMD3<Float>,
                              progress: (done: Int, total: Int)) {
        let anchor = Entity()
        anchor.name = module.id
        anchor.position = basePosition
        // Invisible gaze/pinch target wrapping the whole miniature; the
        // hover highlight lights the miniature itself — no shell.
        anchor.components.set(InputTargetComponent())
        anchor.components.set(CollisionComponent(
            shapes: [.generateSphere(radius: 0.19)]))
        anchor.components.set(HoverEffectComponent())
        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = LocalizedStringResource(
            stringLiteral: "Enter \(module.title). \(module.blurb)")
        anchor.components.set(accessibility)
        root.addChild(anchor)

        let pulser = Entity()
        anchor.addChild(pulser)

        // The pool of light that marks the one you are facing.
        let glow = Self.focusGlow(accent: UIColor(module.accent))
        glow.components.set(OpacityComponent(opacity: 0))
        pulser.addChild(glow)

        // The living miniature, and the motion it was authored with.
        let built = HubVignettes.make(for: module.id)
        let vignette = built.entity
        // MEASURED, then fitted to a common apparent size. Authoring
        // nine models to a nominal size is not the same as nine models
        // being the same size, and a gallery whose exhibits are wildly
        // different scales reads as an accident. Normalising from the
        // real bounds means a future model cannot break the rhythm
        // however it happens to be drawn.
        let bounds = vignette.visualBounds(relativeTo: nil).extents
        let largest = max(bounds.x, max(bounds.y, 1e-4))
        vignette.scale = SIMD3(repeating: Self.exhibitSize / largest)
        vignette.position = .zero
        pulser.addChild(vignette)

        // The floating name beneath, always facing the user — the same
        // 3-D bubble type as the title, tinted in the module's accent.
        let name = Self.namePlate(module.title, accent: UIColor(module.accent))
        let namePivot = Entity()
        namePivot.position = [0, -0.145, 0]
        namePivot.components.set(BillboardComponent())
        namePivot.addChild(name)
        pulser.addChild(namePivot)

        exhibits.append(Exhibit(
            moduleID: module.id, anchor: anchor, pulser: pulser,
            vignette: vignette, namePivot: namePivot, halo: glow,
            basePosition: basePosition, animate: built.animate))
    }

    /// An exhibit's name, built to survive the room behind it.
    ///
    /// Saturated accent glyphs alone were legible while each exhibit sat
    /// on a dark card. With the cards gone the wall shows through, and a
    /// bright room under a mid-tone accent is the worst case for reading
    /// type: cyan on white, red on white, green on white.
    ///
    /// The title's trick — a slightly larger dark copy of the same text
    /// behind the glyphs — does not survive being shrunk to name size.
    /// Scaling a whole string moves every glyph outward from the centre,
    /// so at 36 mm the casing letters land between their own neighbours
    /// and the name reads as if it were printed twice, badly. What works
    /// at this size is an actual backing: one small dark plate, sized to
    /// the words it carries. Crisp accent type, guaranteed contrast, and
    /// nothing around the MODEL — which is the part that has to stay
    /// unframed.
    private static func namePlate(_ text: String, accent: UIColor) -> Entity {
        let plate = Entity()
        let size: CGFloat = 0.036

        let extents = textExtents(text, size: size)
        let padX: Float = 0.026
        let padY: Float = 0.016
        let width = extents.x + padX * 2
        let height = extents.y + padY * 2

        var backing = UnlitMaterial(color: UIColor(white: 0.02, alpha: 1))
        backing.blending = .transparent(opacity: 0.58)
        let card = ModelEntity(
            mesh: .generatePlane(width: width, height: height,
                                 cornerRadius: height / 2),
            materials: [backing])
        card.position.z = -0.006
        plate.addChild(card)

        plate.addChild(bubbleText(text, size: size, color: accent, emissive: 0.6))
        return plate
    }

    /// The focus glow: a soft pool of the module's own colour behind the
    /// miniature, lit only for the exhibit you are facing.
    ///
    /// The exhibits wore CARDS for a while — a gradient face, a frame, a
    /// rule, a shadow. It made a tidy gallery and it buried the physics:
    /// nine little machines, each behind a pane. The models are the
    /// point, and they read better with nothing around them. So the
    /// furniture is gone and focus is expressed the only way that does
    /// not add any: the thing you are facing gets bigger, comes toward
    /// you, and sits in a pool of its own light.
    private static func focusGlow(accent: UIColor) -> Entity {
        let glow = Entity()
        for (radius, opacity) in [(Float(0.085), Float(0.30)),
                                  (Float(0.135), Float(0.15)),
                                  (Float(0.200), Float(0.06))] {
            var material = UnlitMaterial(color: accent)
            material.blending = .transparent(opacity: .init(floatLiteral: opacity))
            let disc = ModelEntity(
                mesh: .generateCylinder(height: 0.001, radius: radius),
                materials: [material])
            disc.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
            disc.position.z = -0.13
            glow.addChild(disc)
        }
        glow.components.set(BillboardComponent())
        return glow
    }


    // MARK: Idle animation & interaction

    /// The exhibits hold their places on the ring; the life in them is
    /// their own physics running, plus a gentle bob — and the ANSWER to
    /// where you are looking.
    func animate(dt: Double, lookRay: (origin: SIMD3<Double>, direction: SIMD3<Double>)?) {
        time += dt
        updateFocus(lookRay: lookRay, dt: dt)

        for (index, exhibit) in exhibits.enumerated() {
            let bob = 0.012 * Float(sin(time * 0.8 + Double(index) * 2.1))
            let focus = exhibit.focus
            // The focused exhibit steps toward the user as it grows —
            // the parallax is what sells it as an object rather than a
            // picture that got bigger.
            let approach = Self.focusedApproach * focus
            exhibit.anchor.position = exhibit.basePosition
                + SIMD3(0, bob, approach)

            let resting = hasLookRay ? Self.unfocusedScale : 1
            let scale = resting + (Self.focusedScale - resting) * focus
            exhibit.pulser.scale = SIMD3(repeating: scale)

            exhibit.halo.components.set(OpacityComponent(opacity: focus))
            // Unfocused names drop to a whisper so the ring stops being
            // nine labels competing over the furniture.
            let nameOpacity = hasLookRay ? (0.58 + 0.42 * focus) : 1
            exhibit.namePivot.components.set(OpacityComponent(opacity: nameOpacity))

            // A gentle SWAY rather than a full turn. Spinning a
            // miniature all the way round shows it is a 3-D object, and
            // also swings the flat ones — the drumhead, the lens —
            // edge-on for half of every rotation, where they vanish.
            // Swaying through about fifty degrees shows the same depth
            // and never hides anything. It eases to a stop on the
            // exhibit being read, so a focused one holds still.
            let sway = 0.44 * Float(sin(time * 0.4 + Double(index) * 1.3))
            exhibit.vignette.orientation = simd_quatf(
                angle: sway * (1 - focus * 0.75), axis: [0, 1, 0])
            // …and whatever this particular exhibit does for a living.
            exhibit.animate(time)
        }
        // The title floats and breathes, like a balloon on a string.
        let bob = 0.02 * Float(sin(time * 0.6))
        titleAnchor.position = Self.titlePosition + SIMD3(0, bob, 0)
        let breathe = 1 + 0.015 * Float(sin(time * 0.9))
        titleAnchor.scale = SIMD3(repeating: breathe)
    }

    private var hasLookRay = false

    /// Picks the exhibit nearest the user's look direction and eases
    /// every exhibit's focus value toward its target.
    private func updateFocus(lookRay: (origin: SIMD3<Double>,
                                       direction: SIMD3<Double>)?, dt: Double) {
        var winner: String?
        #if DEBUG
        // `-hubFocus <module id>` pins the focus so the focused state can
        // be screenshot-checked from the CLI: the simulator has no world
        // tracking, so there is no look ray to aim with.
        if let forced = UserDefaults.standard.string(forKey: "hubFocus"),
           exhibits.contains(where: { $0.moduleID == forced }) {
            hasLookRay = true
            applyFocus(winner: forced, dt: dt)
            return
        }
        #endif
        if let lookRay {
            hasLookRay = true
            let origin = SIMD3<Float>(lookRay.origin)
            let forward = simd_normalize(SIMD3<Float>(lookRay.direction))
            var best = Self.focusCone
            for exhibit in exhibits {
                let toExhibit = exhibit.basePosition - origin
                let distance = simd_length(toExhibit)
                guard distance > 1e-4 else { continue }
                let cosine = simd_dot(toExhibit / distance, forward)
                let angle = acos(min(max(cosine, -1), 1))
                // Hysteresis: the exhibit already in focus keeps it
                // unless another is clearly closer to where you look.
                let bias: Float = exhibit.moduleID == focusedModuleID
                    ? Self.focusStickiness : 1
                if angle * bias < best {
                    best = angle * bias
                    winner = exhibit.moduleID
                }
            }
        } else {
            hasLookRay = false
        }

        applyFocus(winner: winner, dt: dt)
    }

    private func applyFocus(winner: String?, dt: Double) {
        // Publish only on change — SwiftUI must not see this per frame.
        if winner != focusedModuleID {
            focusedModuleID = winner
            let anchor = exhibits.first { $0.moduleID == winner }?.anchor
            focusedAnchor = anchor
            // Move the card to the new exhibit rather than building one
            // per exhibit: only ever one is readable at a time.
            // The card does NOT chase the focused exhibit. A panel that
            // jumps between nine positions is something you have to hunt
            // for every time; a fixed reading shelf under the gallery is
            // somewhere your eyes learn once. It fades in and out
            // instead, and the accent rim says which exhibit it is for.
            detailCard?.isEnabled = anchor != nil
        }

        let rate = Float(min(dt * 7, 1))
        for index in exhibits.indices {
            let target: Float = exhibits[index].moduleID == winner ? 1 : 0
            exhibits[index].focus += (target - exhibits[index].focus) * rate
        }
    }

    /// Maps a tapped entity (target or any child) back to its module.
    func moduleID(for entity: Entity) -> String? {
        var current: Entity? = entity
        while let candidate = current {
            if exhibits.contains(where: { $0.moduleID == candidate.name }) {
                return candidate.name
            }
            current = candidate.parent
        }
        return nil
    }

    /// A quick swell as the chosen exhibit accepts the pinch.
    func pulseExhibit(id: String) {
        guard let exhibit = exhibits.first(where: { $0.moduleID == id }) else { return }
        SoundPalette.play(.pop, on: exhibit.anchor, volume: 0.7)
        exhibit.pulser.move(
            to: Transform(scale: SIMD3(repeating: 1.15)),
            relativeTo: exhibit.anchor,
            duration: 0.14,
            timingFunction: .easeOut
        )
    }
}

/// The card that appears under whichever exhibit you turn toward.
///
/// A menu of nine physics simulations cannot say what any of them ARE
/// while all nine are on screen — there is no room, and nine blurbs at
/// once is a wall of text nobody reads. Focus buys the room: one card,
/// for the one you are looking at, with its name, what it is, and how
/// far through its experiments you are, so choosing is informed instead
/// of a guess from a small floating object and a coloured word.
struct HubDetailCard: View {
    let module: ModuleDescriptor
    @Environment(AppModel.self) private var appModel

    var body: some View {
        let entries = ExperimentCatalog.experiments(for: module.id, appModel: appModel)
        let done = entries.filter {
            appModel.experiments.completed.contains($0.experiment.id)
        }.count

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                Image(systemName: module.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(module.accent)
                    .frame(width: 30, height: 30)
                    .background(module.accent.opacity(0.18),
                                in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                Text(module.title)
                    .font(.title3.bold())
                Spacer(minLength: 0)
            }

            Text(module.blurb)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(4)

            HStack(spacing: 8) {
                if !entries.isEmpty {
                    ProgressView(value: Double(done), total: Double(entries.count))
                        .tint(done == entries.count ? .green : module.accent)
                        .frame(width: 96)
                    Text("\(done)/\(entries.count) experiments")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Label("Pinch to enter", systemImage: "hand.pinch")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(module.accent)
            }
        }
        .padding(16)
        .frame(width: 380, alignment: .leading)
        .glassBackgroundEffect(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .transition(.opacity)
    }
}
