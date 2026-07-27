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
            scene.build(modules: ModuleCatalog.all(appModel: appModel))
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

            scene.subscription = content.subscribe(to: SceneEvents.Update.self) { event in
                scene.animate(dt: event.deltaTime, lookRay: appModel.room.lookRay)
            }
        } attachments: {
            Attachment(id: "detail") {
                if let module = ModuleCatalog.all(appModel: appModel)
                    .first(where: { $0.id == scene.focusedModuleID }) {
                    HubDetailCard(module: module)
                }
            }
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
        /// Per-frame life beyond the shared bob and turn: the exhibit's
        /// own physics, running.
        var animate: ((Entity, Double) -> Void)?
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
    private static let vignetteScale: Float = 1.78

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

    func build(modules: [ModuleDescriptor]) {
        // The 3-D bubble title sits at the centre; the exhibits ring it
        // like a clock face, starting at twelve and going clockwise.
        buildBubbleTitle()
        for (index, module) in modules.enumerated() {
            buildExhibit(for: module, at: Self.arcPosition(index))
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

    private func buildExhibit(for module: ModuleDescriptor, at basePosition: SIMD3<Float>) {
        let anchor = Entity()
        anchor.name = module.id
        anchor.position = basePosition
        // Invisible gaze/pinch target wrapping the whole miniature; the
        // hover highlight lights the miniature itself — no shell.
        anchor.components.set(InputTargetComponent())
        anchor.components.set(CollisionComponent(shapes: [.generateSphere(radius: 0.24)]))
        anchor.components.set(HoverEffectComponent())
        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = LocalizedStringResource(
            stringLiteral: "Enter \(module.title). \(module.blurb)")
        anchor.components.set(accessibility)
        root.addChild(anchor)

        let pulser = Entity()
        anchor.addChild(pulser)

        // The card the exhibit stands on, and the accent rim that lights
        // when it is the one you are facing.
        let (card, rim) = Self.exhibitCard(accent: UIColor(module.accent))
        rim.components.set(OpacityComponent(opacity: 0))
        pulser.addChild(card)

        // The living miniature — big enough to read from across the room.
        let vignette = Self.vignette(for: module)
        vignette.scale = SIMD3(repeating: Self.vignetteScale)
        // Standing proud of the card, so it reads as an object in front
        // of a frame rather than as a picture printed on one.
        vignette.position = [0, 0.028, 0.02]
        pulser.addChild(vignette)

        // The floating name beneath, always facing the user — the same
        // 3-D bubble type as the title, tinted in the module's accent.
        let name = Self.bubbleText(
            module.title, size: 0.028, color: UIColor(module.accent),
            emissive: 0.7)
        let namePivot = Entity()
        // On the card's own face, at its foot — not floating over the
        // wallpaper, which is where nine labels used to end up.
        namePivot.position = [0, -Self.cardSize.y / 2 + 0.045, -0.088]
        namePivot.components.set(BillboardComponent())
        namePivot.addChild(name)
        pulser.addChild(namePivot)

        exhibits.append(Exhibit(
            moduleID: module.id, anchor: anchor, pulser: pulser,
            vignette: vignette, namePivot: namePivot, halo: rim,
            basePosition: basePosition,
            animate: Self.liveAnimation(for: module.id)))
    }

    /// The card an exhibit stands on.
    ///
    /// Nine bare miniatures scattered across a living room read as
    /// trinkets sprinkled over the furniture: no edges, no grouping,
    /// labels landing on picture frames and lampshades. A card gives
    /// each one a frame to be seen against, puts its name on a surface
    /// instead of on the wallpaper behind it, and makes nine of them
    /// read as one gallery.
    ///
    /// This is NOT the glass shell each exhibit used to wear — that
    /// wrapped the miniature in chrome and was rightly cut. The card
    /// sits BEHIND: smoked glass, a thin accent edge, and the miniature
    /// floating proud of it. At rest it is nearly invisible; the accent
    /// edge lights only for the exhibit you are facing.
    private static let cardSize = SIMD2<Float>(0.30, 0.38)

    private static func exhibitCard(accent: UIColor) -> (card: Entity, rim: Entity) {
        let card = Entity()

        // A whisper of the module's colour mixed into near-black, so the
        // nine cards read as a family with nine identities rather than
        // as nine identical grey slabs.
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        accent.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let mix: CGFloat = 0.16
        var glass = PhysicallyBasedMaterial()
        glass.baseColor = .init(tint: UIColor(red: 0.05 + red * mix,
                                              green: 0.05 + green * mix,
                                              blue: 0.06 + blue * mix, alpha: 1))
        glass.roughness = 0.28
        glass.metallic = 0.0
        glass.clearcoat = .init(floatLiteral: 0.7)
        glass.blending = .transparent(opacity: .init(floatLiteral: 0.46))
        let plate = ModelEntity(
            mesh: .generateBox(size: [cardSize.x, cardSize.y, 0.008],
                               cornerRadius: 0.032),
            materials: [glass])
        plate.position.z = -0.10
        card.addChild(plate)

        // The accent edge, built as four BARS rather than as a bigger
        // plate behind. A plate shows straight through the smoked glass
        // and floods the whole card with colour — which is what it did.
        // A frame can only ever be a frame.
        var edgeMaterial = UnlitMaterial(color: accent)
        edgeMaterial.blending = .transparent(opacity: 0.95)
        let rim = Entity()
        let thickness: Float = 0.007
        let halfX = cardSize.x / 2 + thickness / 2
        let halfY = cardSize.y / 2 + thickness / 2
        for (size, offset) in [
            (SIMD3<Float>(cardSize.x + thickness * 2, thickness, 0.006),
             SIMD3<Float>(0, halfY, 0)),
            (SIMD3<Float>(cardSize.x + thickness * 2, thickness, 0.006),
             SIMD3<Float>(0, -halfY, 0)),
            (SIMD3<Float>(thickness, cardSize.y, 0.006), SIMD3<Float>(halfX, 0, 0)),
            (SIMD3<Float>(thickness, cardSize.y, 0.006), SIMD3<Float>(-halfX, 0, 0)),
        ] {
            let bar = ModelEntity(
                mesh: .generateBox(size: size, cornerRadius: thickness / 2),
                materials: [edgeMaterial])
            bar.position = offset
            rim.addChild(bar)
        }
        rim.position.z = -0.099
        card.addChild(rim)

        // Faces the user wherever they stand.
        card.components.set(BillboardComponent())
        return (card, rim)
    }

    // MARK: Vignettes (miniatures of each experience)

    /// Blender-authored exhibit models. Each is auto-normalized from its
    /// real bounds — centered on its middle and sized to a shared
    /// footprint — so every exhibit sits dead-center on its ring slot.
    private static let vignetteAssets: [String: String] = [
        "electrostatics": "HubElectric",
        "kinematics": "HubProjectile",
        "gravitylab": "HubGravity",
        "waves": "HubWaves",
        "windtunnel": "HubWind",
        "circuits": "HubCircuit",
        "pendulums": "HubPendulums",
        "springs": "HubSprings",
        "optics": "HubOptics",
    ]
    /// Apparent exhibit size before the shared vignette scale.
    private static let vignetteTargetSize: Float = 0.13

    private static func vignette(for module: ModuleDescriptor) -> Entity {
        let vignette = Entity()
        // A detailed model when one exists; procedural sketches as the
        // always-working fallback.
        if let asset = vignetteAssets[module.id],
           let loaded = try? Entity.load(named: asset) {
            let bounds = loaded.visualBounds(relativeTo: nil)
            let extents = bounds.extents
            let largest = max(extents.x, max(extents.y, extents.z), 1e-4)
            let scale = Self.vignetteTargetSize / largest
            loaded.scale = SIMD3(repeating: scale)
            loaded.position = -bounds.center * scale
            vignette.addChild(loaded)
            return vignette
        }
        switch module.id {
        case "electrostatics": buildFieldVignette(in: vignette)
        case "kinematics": buildProjectileVignette(in: vignette)
        case "gravitylab": buildOrbitVignette(in: vignette)
        case "waves": buildWavesVignette(in: vignette)
        case "windtunnel": buildWindTunnelVignette(in: vignette)
        case "circuits": buildCircuitsVignette(in: vignette)
        case "elasticfield": buildElasticVignette(in: vignette)
        case "magnetism": buildMagnetismVignette(in: vignette)
        default:
            // A new module gets a simple accent sphere until it has art.
            vignette.addChild(ModelEntity(
                mesh: .generateSphere(radius: 0.035),
                materials: [SimpleMaterial(color: UIColor(module.accent),
                                           roughness: 0.4, isMetallic: false)]))
        }
        return vignette
    }

    /// A dipole: red and blue charges joined by two arcing field lines.
    private static func buildFieldVignette(in parent: Entity) {
        let positive = ModelEntity(
            mesh: .generateSphere(radius: 0.026),
            materials: [SimpleMaterial(color: DesignTokens.Palette.positiveUI,
                                       roughness: 0.35, isMetallic: false)])
        positive.name = "positive"
        positive.position = [-0.045, 0, 0]
        let negative = ModelEntity(
            mesh: .generateSphere(radius: 0.026),
            materials: [SimpleMaterial(color: DesignTokens.Palette.negativeUI,
                                       roughness: 0.35, isMetallic: false)])
        negative.name = "negative"
        negative.position = [0.045, 0, 0]
        parent.addChild(positive)
        parent.addChild(negative)

        var lineMaterial = UnlitMaterial(color: DesignTokens.Palette.fieldLineUI)
        lineMaterial.blending = .transparent(opacity: 0.85)
        for flip: Float in [1, -1] {
            let arc: [SIMD3<Float>] = (0...20).map { step in
                let theta = Float(step) / 20 * .pi
                return SIMD3(-0.045 * cos(theta), flip * 0.042 * sin(theta), 0)
            }
            if let mesh = TubeMesh.tube(lines: [arc], radius: 0.0022) {
                parent.addChild(ModelEntity(mesh: mesh, materials: [lineMaterial]))
            }
        }
    }

    /// A ball frozen mid-flight over its strobe-dot parabola.
    private static func buildProjectileVignette(in parent: Entity) {
        let ball = ModelEntity(
            mesh: .generateSphere(radius: 0.02),
            materials: [SimpleMaterial(color: DesignTokens.Palette.projectileUI,
                                       roughness: 0.5, isMetallic: false)])
        ball.position = [0.014, 0.037, 0]
        parent.addChild(ball)

        var dotMaterial = UnlitMaterial(color: DesignTokens.Palette.projectileUI)
        dotMaterial.blending = .transparent(opacity: 0.75)
        let dotMesh = MeshResource.generateSphere(radius: 0.0045)
        for step in 0...7 {
            let t = Float(step) / 7
            let x = -0.055 + t * 0.11
            // A parabola through the ball's position, peak just left of it.
            let y = 0.04 - 0.16 * (x - 0.01) * (x - 0.01)
            let dot = ModelEntity(mesh: dotMesh, materials: [dotMaterial])
            dot.position = [x, y - 0.01, 0]
            parent.addChild(dot)
        }
    }

    /// A tiny lit loop: battery, wire, glowing bulb.
    private static func buildCircuitsVignette(in parent: Entity) {
        let battery = ModelEntity(
            mesh: .generateCylinder(height: 0.036, radius: 0.009),
            materials: [SimpleMaterial(color: UIColor(red: 0.35, green: 0.45, blue: 0.35, alpha: 1),
                                       roughness: 0.3, isMetallic: true)])
        battery.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
        battery.position = [-0.035, 0, 0]
        parent.addChild(battery)

        var glow = UnlitMaterial(color: UIColor(red: 1, green: 0.85, blue: 0.4, alpha: 1))
        glow.blending = .transparent(opacity: 0.85)
        let bulb = ModelEntity(mesh: .generateSphere(radius: 0.014), materials: [glow])
        bulb.name = "bulb"
        bulb.position = [0.035, 0, 0]
        parent.addChild(bulb)

        let wireMaterial = UnlitMaterial(color: DesignTokens.Palette.copperUI)
        for flip: Float in [1, -1] {
            let arc: [SIMD3<Float>] = (0...20).map { step in
                let theta = Float(step) / 20 * .pi
                return SIMD3(-0.035 * cos(theta), flip * 0.03 * sin(theta), 0)
            }
            if let mesh = TubeMesh.tube(lines: [arc], radius: 0.0018) {
                parent.addChild(ModelEntity(mesh: mesh, materials: [wireMaterial]))
            }
        }
    }

    /// A cylinder with streamlines parting around it.
    private static func buildWindTunnelVignette(in parent: Entity) {
        let cylinder = ModelEntity(
            mesh: .generateCylinder(height: 0.05, radius: 0.016),
            materials: [SimpleMaterial(color: DesignTokens.Palette.launcherUI,
                                       roughness: 0.35, isMetallic: true)])
        parent.addChild(cylinder)

        var lineMaterial = UnlitMaterial(color: DesignTokens.Palette.streamlineUI)
        lineMaterial.blending = .transparent(opacity: 0.7)
        for offset: Float in [-0.034, -0.012, 0.012, 0.034] {
            let line: [SIMD3<Float>] = (0...24).map { step in
                let x = -0.055 + 0.11 * Float(step) / 24
                // Bend away from the cylinder, strongest near x = 0.
                let bulge = 0.014 * exp(-x * x / 0.0012) * (offset > 0 ? 1 : -1)
                    / max(abs(offset) / 0.02, 1)
                return SIMD3(x, 0, offset + bulge)
            }
            if let mesh = TubeMesh.tube(lines: [line], radius: 0.0013) {
                parent.addChild(ModelEntity(mesh: mesh, materials: [lineMaterial]))
            }
        }
    }

    /// Two source pucks with interleaving ripple rings.
    /// A little rippled membrane: a grid of tiles at a (2,1) standing-
    /// mode height, tinted warm on the crest and cool in the trough.
    private static func buildElasticVignette(in parent: Entity) {
        let side = 9
        let span: Float = 0.11
        let step = span / Float(side - 1)
        let tile = MeshResource.generateBox(size: [step * 0.92, 0.006, step * 0.92])
        for j in 0..<side {
            for i in 0..<side {
                let u = Float(i) / Float(side - 1)
                let v = Float(j) / Float(side - 1)
                let h = 0.03 * sin(2 * .pi * u) * sin(.pi * v)   // (2,1) mode
                let warmth = (h / 0.03 + 1) / 2                   // 0 trough … 1 crest
                let color = UIColor(
                    red: CGFloat(0.15 + 0.85 * warmth),
                    green: CGFloat(0.75 - 0.35 * abs(warmth - 0.5) * 2),
                    blue: CGFloat(0.9 - 0.6 * warmth), alpha: 1)
                var material = UnlitMaterial(color: color)
                material.blending = .transparent(opacity: 0.92)
                let cell = ModelEntity(mesh: tile, materials: [material])
                cell.name = "cell\(h)"
                cell.position = SIMD3(-span / 2 + Float(i) * step, h,
                                      -span / 2 + Float(j) * step)
                parent.addChild(cell)
            }
        }
    }

    private static func buildWavesVignette(in parent: Entity) {
        var ringMaterial = UnlitMaterial(color: DesignTokens.Palette.waveSourceUI)
        ringMaterial.blending = .transparent(opacity: 0.55)

        for (center, radii): (SIMD3<Float>, [Float]) in [
            (SIMD3(-0.035, -0.01, 0), [0.02, 0.038]),
            (SIMD3(0.035, -0.01, 0), [0.02, 0.038]),
        ] {
            let puck = ModelEntity(
                mesh: .generateCylinder(height: 0.008, radius: 0.011),
                materials: [UnlitMaterial(color: DesignTokens.Palette.waveSourceUI)])
            puck.position = center
            parent.addChild(puck)

            for radius in radii {
                let circle: [SIMD3<Float>] = (0...28).map { step in
                    let theta = 2 * Float.pi * Float(step) / 28
                    return center + SIMD3(radius * cos(theta), 0, radius * sin(theta))
                }
                if let mesh = TubeMesh.tube(lines: [circle], radius: 0.0014) {
                    parent.addChild(ModelEntity(mesh: mesh, materials: [ringMaterial]))
                }
            }
        }
    }

    /// A little bar magnet (red N over blue S) with two field-line loops
    /// arcing from pole to pole.
    private static func buildMagnetismVignette(in parent: Entity) {
        let half: Float = 0.032
        let w: Float = 0.02
        let north = ModelEntity(
            mesh: .generateBox(size: [w, half, w], cornerRadius: 0.004),
            materials: [SimpleMaterial(color: DesignTokens.Palette.positiveUI,
                                       roughness: 0.35, isMetallic: false)])
        north.position = [0, half / 2, 0]
        let south = ModelEntity(
            mesh: .generateBox(size: [w, half, w], cornerRadius: 0.004),
            materials: [SimpleMaterial(color: DesignTokens.Palette.negativeUI,
                                       roughness: 0.35, isMetallic: false)])
        south.position = [0, -half / 2, 0]
        parent.addChild(north)
        parent.addChild(south)

        var lineMaterial = UnlitMaterial(color: MagnetismRenderer.lineColor)
        lineMaterial.blending = .transparent(opacity: 0.85)
        for flip: Float in [1, -1] {
            let arc: [SIMD3<Float>] = (0...24).map { step in
                let theta = Float(step) / 24 * .pi
                return SIMD3(flip * 0.058 * sin(theta), half * cos(theta), 0)
            }
            if let mesh = TubeMesh.tube(lines: [arc], radius: 0.0016) {
                parent.addChild(ModelEntity(mesh: mesh, materials: [lineMaterial]))
            }
        }
    }

    /// A tiny sun, an orbit ring, and a planet parked on it.
    private static func buildOrbitVignette(in parent: Entity) {
        let sun = ModelEntity(
            mesh: .generateSphere(radius: 0.028),
            materials: [UnlitMaterial(color: DesignTokens.Palette.celestialUI("Sun"))])
        parent.addChild(sun)

        var ringMaterial = UnlitMaterial(color: .white)
        ringMaterial.blending = .transparent(opacity: 0.4)
        let ring: [SIMD3<Float>] = (0...36).map { step in
            let theta = Float(step) / 36 * 2 * .pi
            return SIMD3(0.062 * cos(theta), 0, 0.062 * sin(theta))
        }
        if let mesh = TubeMesh.tube(lines: [ring], radius: 0.0016) {
            let orbit = ModelEntity(mesh: mesh, materials: [ringMaterial])
            orbit.name = "orbit"
            orbit.orientation = simd_quatf(angle: 0.35, axis: [1, 0, 0])
            parent.addChild(orbit)

            let planet = ModelEntity(
                mesh: .generateSphere(radius: 0.011),
                materials: [SimpleMaterial(color: DesignTokens.Palette.celestialUI("Earth"),
                                           roughness: 0.5, isMetallic: false)])
            planet.position = SIMD3(0.062, 0, 0)
            orbit.addChild(planet)
        }
    }

    // MARK: Live exhibits
    //
    // A menu of nine physics simulations should not be nine statues that
    // bob. Each exhibit RUNS: the pendulum swings, the ripples ripple,
    // the orrery orbits, the fan turns. It costs a handful of transform
    // writes per frame — the vignettes are a few dozen entities in total
    // — and it turns the hub from a poster into the thing the app is
    // actually about, before the user has entered anything.
    //
    // These are cosmetic loops, deliberately: the hub is a menu, and
    // running nine real integrators to decorate it would be silly. Each
    // is the honest SHAPE of its module's motion.

    private static func liveAnimation(for moduleID: String) -> ((Entity, Double) -> Void)? {
        switch moduleID {
        case "pendulums":
            // Two bobs swinging at different rates, drifting in and out
            // of step — the beat the module opens on.
            return { vignette, t in
                for (index, child) in vignette.children.enumerated()
                where child.name.hasPrefix("swing") {
                    let rate = 1.6 + Double(index) * 0.22
                    child.orientation = simd_quatf(
                        angle: Float(0.5 * sin(t * rate)), axis: [0, 0, 1])
                }
            }
        case "gravitylab":
            // The planet goes round.
            return { vignette, t in
                for child in vignette.children where child.name == "orbit" {
                    child.orientation = simd_quatf(angle: 0.35, axis: [1, 0, 0])
                        * simd_quatf(angle: Float(t * 0.9), axis: [0, 1, 0])
                }
            }
        case "waves":
            // The rings expand and fade, over and over.
            return { vignette, t in
                for child in vignette.children where child.name.hasPrefix("ripple") {
                    let phase = Double(child.name.dropFirst(6)) ?? 0
                    let grow = Float((t * 0.6 + phase).truncatingRemainder(dividingBy: 1))
                    child.scale = SIMD3(repeating: 0.25 + grow * 1.4)
                    child.components.set(OpacityComponent(opacity: 1 - grow))
                }
            }
        case "windtunnel":
            return { vignette, t in
                for child in vignette.children where child.name == "blades" {
                    child.orientation = simd_quatf(angle: Float(t * 5), axis: [0, 0, 1])
                }
            }
        case "elasticfield":
            // The membrane breathes through its standing mode.
            return { vignette, t in
                let swing = Float(sin(t * 2.2))
                for child in vignette.children where child.name.hasPrefix("cell") {
                    let amplitude = Float(Double(child.name.dropFirst(4)) ?? 0)
                    child.position.y = amplitude * swing
                }
            }
        case "circuits":
            // The bulb pulses as if the current were being switched.
            return { vignette, t in
                for child in vignette.children where child.name == "bulb" {
                    let glow = 0.55 + 0.45 * Float(sin(t * 1.7))
                    child.scale = SIMD3(repeating: 0.9 + glow * 0.25)
                    child.components.set(OpacityComponent(opacity: 0.35 + glow * 0.6))
                }
            }
        case "electrostatics":
            // The dipole's field breathes — the charges ease apart and
            // back, so the arcs visibly reorganise.
            return { vignette, t in
                let breath = Float(0.008 * sin(t * 1.1))
                for child in vignette.children {
                    if child.name == "positive" { child.position.x = -0.045 - breath }
                    if child.name == "negative" { child.position.x = 0.045 + breath }
                }
            }
        default:
            return nil
        }
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

            exhibit.vignette.orientation = simd_quatf(
                angle: Float(time * 0.3 + Double(index)), axis: [0, 1, 0])
            // …and whatever this particular exhibit does for a living.
            exhibit.animate?(exhibit.vignette, time)
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
