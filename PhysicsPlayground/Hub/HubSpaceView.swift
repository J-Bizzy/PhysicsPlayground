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
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
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
            scene.build(modules: modules, progress: progress,
                        distance: Float(appModel.settings.arcDistance),
                        height: Float(appModel.settings.arcHeight),
                        yaw: appModel.settings.hubYaw)
            scene.stillness = appModel.settings.reduceMotion || systemReduceMotion
            content.add(scene.root)

            if let card = attachments.entity(for: "detail") {
                // The focus panel: it rides BEHIND whichever exhibit you
                // face — the diorama in front, its story behind it —
                // repositioned by applyFocus whenever focus moves.
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
        } update: { _, _ in
            scene.stillness = appModel.settings.reduceMotion || systemReduceMotion
        } attachments: {
            Attachment(id: "detail") {
                if let module = ModuleCatalog.all(appModel: appModel)
                    .first(where: { $0.id == scene.focusedModuleID }) {
                    HubFocusPanel(module: module) { enter(module.id) }
                }
            }
        }
        // The arc's geometry (distance, height, recenter yaw) lives in
        // settings; bumping layoutVersion gives this view a new identity,
        // which tears the old scene down and builds the arc fresh.
        .id(appModel.settings.layoutVersion)
        // Entering a module replaces this view, and an EventSubscription
        // is not tied to the view that made it — left alone it keeps
        // calling `animate` on a hub that is no longer on screen, for
        // the whole time you are inside a module, holding the entire
        // exhibit graph alive behind it.
        .onDisappear {
            scene.subscription?.cancel()
            scene.subscription = nil
        }
        .onChange(of: scene.focusedModuleID) {
            // First focus completes the "look at a module" coaching.
            if scene.focusedModuleID != nil {
                appModel.settings.advanceCoach(past: 0)
            }
        }
        .gesture(
            TapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    guard let id = scene.moduleID(for: value.entity) else { return }
                    enter(id)
                }
        )
    }

    /// One enter path for both the pinch and the panel's button: the
    /// chosen exhibit swells toward you while the rest of the hub holds,
    /// and the module takes over as the swell peaks — an arrival, not a
    /// hard cut.
    private func enter(_ id: String) {
        scene.beginEnterTransition(id: id)
        Task {
            try? await Task.sleep(for: .milliseconds(420))
            appModel.activeModuleID = id
        }
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
        /// This exhibit's own animation clock. Runs a little fast while
        /// focused — the "come alive" answer to being looked at — and
        /// pauses entirely while the exhibit is outside the field of
        /// view, where animating it is work nobody can see.
        var animTime: Double = 0
        /// Set by updateFocus: whether the exhibit is near enough to the
        /// look direction to be worth animating.
        var inView: Bool = true
    }

    /// True stills all idle motion — the bob, the sway, the running
    /// miniatures. Set from Reduce Motion (system or in-app setting).
    var stillness = false

    /// Which exhibit the user is facing, published only when it CHANGES
    /// so the detail card can re-render without SwiftUI seeing sixty
    /// updates a second.
    private(set) var focusedModuleID: String?
    /// Where the focused exhibit is, for the detail card to hang under.
    private(set) var focusedAnchor: Entity?
    /// The SwiftUI reading shelf, shown while something has focus.
    var detailCard: Entity?
    private var exhibits: [Exhibit] = []
    private var time = 0.0
    /// The 3-D bubble title the exhibits ring, bobbing at the centre.
    private let titleAnchor = Entity()

    // MARK: Layout — one arc, grouped by domain
    //
    // Two staggered rows spaced nine modules comfortably, but the rows
    // were ORDERED BY THE CATALOG, which is to say not ordered at all:
    // Circuits floated over the armchair, Waves over the window, and
    // nothing about where a thing sat said what kind of physics it was.
    // One arc, read left to right like a shelf, grouped into the four
    // domains a course would group them into — Mechanics, Waves &
    // Optics, Electricity & Magnetism, Fluids & Gravity — with a small
    // header floating over each group. Position now MEANS something.
    //
    // Geometry comes from settings (distance and height sliders,
    // recenter yaw), with the defaults at 2.0 m and 1.4 m — close
    // enough to read, low enough to feel on your shelf rather than on
    // the ceiling.

    private var arcRadius: Float = 2.0
    private var arcHeight: Float = 1.4

    // MARK: Layout — a constellation, not an arc
    //
    // The arc put every lab at ONE radius and ONE height, which is a
    // poster with a curve in it: your eyes sweep left to right and the
    // room contributes nothing. A headset's whole advantage is that
    // things can be at different DISTANCES — near ones large and
    // detailed, far ones small and quiet, everything moving against
    // everything else as you lean. So the labs hang at genuinely
    // different depths and heights, and the exhibits keep a constant
    // WORLD size rather than a constant apparent one, so distance is
    // something you read instead of something you are told.
    //
    // Positions are authored, not generated: a scatter that reads as
    // designed needs someone to have decided where things go.
    private static let constellation: [(azimuth: Float, height: Float, depth: Float)] = [
        (-38, 1.46, 1.95),
        ( -14, 1.08, 1.62),
        (  12, 1.72, 2.30),
        (  40, 1.22, 1.88),
        ( -30, 1.94, 2.70),
        (  30, 0.96, 2.35),
        (  -3, 1.32, 3.05),
    ]

    /// Every miniature is normalised to this WORLD size, so a lab
    /// further away genuinely looks further away. Constant apparent
    /// size would have thrown the depth away again.
    private static let exhibitSize: Float = 0.27

    /// Where the nth lab hangs. Distance and height settings scale the
    /// whole constellation rather than flattening it.
    private func constellationPoint(_ index: Int) -> SIMD3<Float> {
        let slot = Self.constellation[index % Self.constellation.count]
        let azimuth = slot.azimuth * .pi / 180
        let depth = slot.depth * (arcRadius / 2.0)
        let height = slot.height * (arcHeight / 1.4)
        return SIMD3(depth * sin(azimuth), height, -depth * cos(azimuth))
    }

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
               progress: [String: (done: Int, total: Int)] = [:],
               distance: Float = 2.0, height: Float = 1.4, yaw: Float = 0) {
        arcRadius = distance
        arcHeight = height
        // Recenter: the whole constellation swings about the user.
        root.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])

        titlePosition = SIMD3(0, arcHeight + 0.86, -(arcRadius + 0.15))
        buildBubbleTitle()

        // Domain order still decides WHICH slot a lab gets, so related
        // labs stay near each other — but the floating domain headers
        // are gone. Three text labels hanging in a room to explain a
        // grouping the colours already carry is exactly the kind of
        // caption this remaster exists to delete.
        let byID = Dictionary(uniqueKeysWithValues: modules.map { ($0.id, $0) })
        var ordered: [(ModuleDescriptor, HubDomain)] = []
        for domain in HubDomain.allCases {
            for id in domain.moduleIDs {
                if let module = byID[id] { ordered.append((module, domain)) }
            }
        }
        for module in modules where !HubDomain.arcOrder.contains(module.id) {
            ordered.append((module, HubDomain.domain(for: module.id)))
        }

        for (index, entry) in ordered.enumerated() {
            buildExhibit(for: entry.0,
                         at: constellationPoint(index),
                         domain: entry.1,
                         progress: progress[entry.0.id] ?? (0, 0))
        }
    }

    // MARK: The 3-D bubble title

    /// Just above the arc's centre — part of the gallery, not painted on
    /// the ceiling. Set from the arc geometry in build().
    private var titlePosition = SIMD3<Float>(0, 1.98, -2.05)

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
    private static let titleWidth: Float = 0.44
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
        // Once. An app that reintroduces itself every time you come
        // home is an app that thinks you might have forgotten what you
        // opened. After the first launch the constellation speaks for
        // itself and the wordmark stays out of the room.
        let key = "hasSeenWordmark"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)

        titleAnchor.position = titlePosition

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
                              domain: HubDomain,
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

        // The module's own progress, worn as a ring around the exhibit:
        // a faint track, the domain-coloured arc of what is done, and a
        // gold band once everything is — the reward lives on the home
        // screen itself.
        if progress.total > 0 {
            let ring = Self.progressRing(
                done: progress.done, total: progress.total,
                accent: UIColor(domain.color))
            ring.components.set(BillboardComponent())
            pulser.addChild(ring)
        }

        exhibits.append(Exhibit(
            moduleID: module.id, anchor: anchor, pulser: pulser,
            vignette: vignette, namePivot: namePivot, halo: glow,
            basePosition: basePosition, animate: built.animate))
    }

    /// A thin circular track with the completed fraction drawn over it.
    /// Billboarded behind the miniature, so it reads as a dial without
    /// ever framing the model.
    private static func progressRing(done: Int, total: Int,
                                     accent: UIColor) -> Entity {
        let ring = Entity()
        let radius: Float = 0.165
        let z: Float = -0.115
        let gold = UIColor(red: 1.0, green: 0.84, blue: 0.25, alpha: 1)
        let complete = done == total

        func circlePoints(fraction: Float, z: Float) -> [SIMD3<Float>] {
            let segments = max(Int(48 * fraction), 2)
            // Start at 12 o'clock, sweep clockwise as seen by the user.
            return (0...segments).map { step in
                let angle = .pi / 2 - 2 * .pi * fraction * Float(step) / Float(segments)
                return SIMD3(radius * cos(angle), radius * sin(angle), z)
            }
        }

        if let track = TubeMesh.tube(lines: [circlePoints(fraction: 1, z: z)],
                                     radius: 0.0016, sides: 4) {
            var faint = UnlitMaterial(color: UIColor(white: 0.9, alpha: 1))
            faint.blending = .transparent(opacity: 0.16)
            ring.addChild(ModelEntity(mesh: track, materials: [faint]))
        }
        let fraction = Float(done) / Float(total)
        if fraction > 0.01,
           let arc = TubeMesh.tube(lines: [circlePoints(fraction: fraction,
                                                        z: z + 0.002)],
                                   radius: 0.0024, sides: 4) {
            var lit = UnlitMaterial(color: complete ? gold : accent)
            lit.blending = .transparent(opacity: complete ? 0.6 : 0.5)
            ring.addChild(ModelEntity(mesh: arc, materials: [lit]))
        }
        return ring
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
    private static func namePlate(_ text: String, accent: UIColor,
                                  size: CGFloat = 0.036) -> Entity {
        let plate = Entity()

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

        for index in exhibits.indices {
            let focus = exhibits[index].focus
            // Reduce Motion: the gallery holds still. Focus scaling
            // stays — it answers the user's own head, which is exactly
            // the motion Reduce Motion is not about.
            let bob = stillness ? 0
                : 0.012 * Float(sin(time * 0.8 + Double(index) * 2.1))
            // The focused exhibit steps toward the user as it grows —
            // the parallax is what sells it as an object rather than a
            // picture that got bigger.
            let approach = Self.focusedApproach * focus
            let exhibit = exhibits[index]
            exhibit.anchor.position = exhibit.basePosition
                + SIMD3(0, bob, approach)

            let resting = hasLookRay ? Self.unfocusedScale : 1
            let scale = resting + (Self.focusedScale - resting) * focus
            exhibit.pulser.scale = SIMD3(repeating: scale)

            exhibit.halo.components.set(OpacityComponent(opacity: focus))
            // Names appear only for the lab you are FACING. Seven
            // permanent captions floating in a room is a menu; one that
            // materialises where you look is the same doctrine the labs
            // themselves now follow. Without a look ray (the simulator)
            // they all stay legible so nothing is unreachable.
            let nameOpacity = hasLookRay ? (focus * focus) : 1
            exhibit.namePivot.components.set(OpacityComponent(opacity: nameOpacity))

            if stillness { continue }

            // A gentle SWAY rather than a full turn. Spinning a
            // miniature all the way round shows it is a 3-D object, and
            // also swings the flat ones — the drumhead, the lens —
            // edge-on for half of every rotation, where they vanish.
            // It eases to a stop on the exhibit being read.
            let sway = 0.44 * Float(sin(time * 0.4 + Double(index) * 1.3))
            exhibit.vignette.orientation = simd_quatf(
                angle: sway * (1 - focus * 0.75), axis: [0, 1, 0])

            // Each exhibit runs on its own clock: paused outside the
            // field of view (work nobody can see), and a touch fast
            // while focused, so the one you turn to visibly comes alive.
            if exhibit.inView || focus > 0.01 || !hasLookRay {
                exhibits[index].animTime += dt * Double(1 + 0.6 * focus)
                exhibit.animate(exhibits[index].animTime)
            }
        }
        // The title floats and breathes, like a balloon on a string.
        let bob = stillness ? 0 : 0.02 * Float(sin(time * 0.6))
        titleAnchor.position = titlePosition + SIMD3(0, bob, 0)
        let breathe = stillness ? 1 : 1 + 0.015 * Float(sin(time * 0.9))
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
            // The whole scene may be yawed by Recenter; bring the ray
            // into the scene's own frame so the base positions the math
            // uses stay honest.
            let inverse = root.orientation.inverse
            let origin = inverse.act(SIMD3<Float>(lookRay.origin))
            let forward = simd_normalize(inverse.act(SIMD3<Float>(lookRay.direction)))
            var best = Self.focusCone
            for index in exhibits.indices {
                let exhibit = exhibits[index]
                let toExhibit = exhibit.basePosition - origin
                let distance = simd_length(toExhibit)
                guard distance > 1e-4 else { continue }
                let cosine = simd_dot(toExhibit / distance, forward)
                let angle = acos(min(max(cosine, -1), 1))
                // Anything within ~60° is worth animating; the rest is
                // outside the headset's view and pauses.
                exhibits[index].inView = angle < 1.05
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
            let exhibit = exhibits.first { $0.moduleID == winner }
            focusedAnchor = exhibit?.anchor
            // The panel floats ABOVE the focused exhibit, a step behind
            // it. Straight behind was the first attempt — the diorama is
            // angularly larger than the panel from where the user
            // stands, so "behind" meant "hidden". Below was the second —
            // and the app's own window and dock live dead ahead below
            // the arc, so the centre modules' panels drowned in UI.
            // Above is the one direction that is always clear: the
            // diorama keeps the stage, its story hangs over it like a
            // gallery caption. One panel, moved, not nine built.
            if let base = exhibit?.basePosition {
                let outward = simd_normalize(SIMD3<Float>(base.x, 0, base.z))
                detailCard?.position = base + outward * 0.24 + SIMD3(0, 0.38, 0)
            }
            detailCard?.isEnabled = exhibit != nil
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

    /// The chosen exhibit swells toward the user over the ~0.4 s before
    /// the module takes the stage — entering reads as an arrival rather
    /// than a hard cut. (A true cross-dissolve into the module scene
    /// would need both scenes alive at once; the swell carries the
    /// continuity on its own.)
    func beginEnterTransition(id: String) {
        guard let exhibit = exhibits.first(where: { $0.moduleID == id }) else { return }
        SoundPalette.play(.pop, on: exhibit.anchor, volume: 0.7)
        detailCard?.isEnabled = false
        exhibit.pulser.move(
            to: Transform(scale: SIMD3(repeating: 1.6),
                          translation: SIMD3(0, 0, 0.22)),
            relativeTo: exhibit.anchor,
            duration: 0.42,
            timingFunction: .easeIn
        )
    }
}

/// The panel that appears behind whichever exhibit you turn toward:
/// domain chip, the one-line promise, live progress, and a real Enter
/// button beside the pinch you can already do.
///
/// A menu of nine physics simulations cannot say what any of them ARE
/// while all nine are on screen — focus buys the room to say it.
struct HubFocusPanel: View {
    let module: ModuleDescriptor
    let enter: () -> Void
    @Environment(AppModel.self) private var appModel

    var body: some View {
        let domain = HubDomain.domain(for: module.id)
        let entries = ExperimentCatalog.experiments(for: module.id, appModel: appModel)
        let done = entries.filter {
            appModel.experiments.completed.contains($0.experiment.id)
        }.count
        let visited = appModel.visitedModuleIDs.contains(module.id)

        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text(domain.title)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(domain.color.opacity(0.22), in: Capsule())
                    .foregroundStyle(domain.color)
                Spacer(minLength: 0)
                if !visited {
                    Text("New")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(module.accent.opacity(0.9), in: Capsule())
                        .foregroundStyle(.white)
                } else if let last = appModel.lastPlayed(module.id) {
                    Text(last, format: .relative(presentation: .named))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Text(module.title)
                .font(.title3.bold())

            Text(HubDomain.promise(for: module.id))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                if !entries.isEmpty {
                    ZStack {
                        Circle().stroke(.tertiary, lineWidth: 3)
                        Circle()
                            .trim(from: 0, to: CGFloat(done) / CGFloat(entries.count))
                            .stroke(done == entries.count ? .yellow : domain.color,
                                    style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    .frame(width: 26, height: 26)
                    Text("\(done) of \(entries.count) experiments")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button(action: enter) {
                    Label("Enter", systemImage: "arrow.forward")
                        .font(.callout.weight(.semibold))
                        .padding(.horizontal, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(module.accent)
                .accessibilityHint("Opens \(module.title)")
            }
        }
        .padding(16)
        .frame(width: 340, alignment: .leading)
        .glassBackgroundEffect(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .transition(.opacity)
    }
}
