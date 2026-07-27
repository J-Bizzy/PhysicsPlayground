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
        RealityView { content in
            scene.build(modules: ModuleCatalog.all(appModel: appModel))
            content.add(scene.root)

            scene.subscription = content.subscribe(to: SceneEvents.Update.self) { event in
                scene.animate(dt: event.deltaTime)
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
        let basePosition: SIMD3<Float>
        /// Per-frame life beyond the shared bob and turn: the exhibit's
        /// own physics, running.
        var animate: ((Entity, Double) -> Void)?
    }
    private var exhibits: [Exhibit] = []
    private var time = 0.0
    /// The 3-D bubble title the exhibits ring, bobbing at the centre.
    private let titleAnchor = Entity()

    /// The ring encircles the title: a vertical circle in the frontal
    /// plane, a step beyond it in depth.
    private static let ringCenter = SIMD3<Float>(0, 1.68, -2.3)
    /// An ELLIPSE, not a circle: rooms are wider than they are tall.
    /// A circle big enough to space nine exhibits put the top ones
    /// through the ceiling and the bottom ones inside the sofa. Widening
    /// it and flattening it keeps the same spacing along the ring while
    /// staying inside the wall the user is looking at.
    private static let ringRadiusX: Float = 1.42
    private static let ringRadiusY: Float = 0.82
    /// How far the ring's sides curve toward the user. A flat circle at
    /// one depth is a poster; bowing the edges forward makes it a space
    /// you are standing in the mouth of, and gives the side exhibits the
    /// parallax that tells you they are objects rather than pictures.
    private static let ringBow: Float = 0.55
    /// The miniatures, unbottled and enlarged.
    private static let vignetteScale: Float = 2.6

    // MARK: Build

    func build(modules: [ModuleDescriptor]) {
        // The 3-D bubble title sits at the centre; the exhibits ring it
        // like a clock face, starting at twelve and going clockwise.
        buildBubbleTitle()
        let count = max(modules.count, 1)
        for (index, module) in modules.enumerated() {
            let angle = Float.pi / 2 - 2 * .pi * Float(index) / Float(count)
            let x = Self.ringRadiusX * cos(angle)
            let y = Self.ringRadiusY * sin(angle)
            // Bow: the further round the sides an exhibit sits, the
            // further forward it comes.
            let basePosition = Self.ringCenter + SIMD3(
                x, y, Self.ringBow * (x * x) / (Self.ringRadiusX * Self.ringRadiusX))
            buildExhibit(for: module, at: basePosition)
        }
    }

    // MARK: The 3-D bubble title

    /// Where the title sits relative to the ring's centre.
    ///
    /// It used to sit 34 cm up, which put it against the top exhibit and
    /// left a hole in the middle of the composition. With the ring now a
    /// flatter ellipse and the hub window no longer carrying a catalog
    /// grid, the name can come down to where a name in the middle of a
    /// ring belongs.
    private static let titleOffset = SIMD3<Float>(0, 0.27, 0.12)

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
    private static let titleWidth: Float = 0.86
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
        titleAnchor.position = Self.ringCenter + Self.titleOffset

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

        // The living miniature — big enough to read from across the room.
        let vignette = Self.vignette(for: module)
        vignette.scale = SIMD3(repeating: Self.vignetteScale)
        pulser.addChild(vignette)

        // The floating name beneath, always facing the user — the same
        // 3-D bubble type as the title, tinted in the module's accent.
        let name = Self.bubbleText(
            module.title, size: 0.042, color: UIColor(module.accent),
            emissive: 0.35)
        let namePivot = Entity()
        namePivot.position = [0, -0.28, 0]
        namePivot.components.set(BillboardComponent())
        namePivot.addChild(name)
        pulser.addChild(namePivot)

        exhibits.append(Exhibit(
            moduleID: module.id, anchor: anchor, pulser: pulser,
            vignette: vignette, basePosition: basePosition,
            animate: Self.liveAnimation(for: module.id)))
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

    /// The exhibits hold their places on the ring — only the gentle bob
    /// and each miniature's slow turn keep them alive.
    func animate(dt: Double) {
        time += dt
        for (index, exhibit) in exhibits.enumerated() {
            let bob = 0.012 * Float(sin(time * 0.8 + Double(index) * 2.1))
            exhibit.anchor.position = exhibit.basePosition + SIMD3(0, bob, 0)
            exhibit.vignette.orientation = simd_quatf(
                angle: Float(time * 0.3 + Double(index)), axis: [0, 1, 0])
            // …and whatever this particular exhibit does for a living.
            exhibit.animate?(exhibit.vignette, time)
        }
        // The title floats and breathes, like a balloon on a string.
        let bob = 0.02 * Float(sin(time * 0.6))
        titleAnchor.position = Self.ringCenter + Self.titleOffset + SIMD3(0, bob, 0)
        let breathe = 1 + 0.015 * Float(sin(time * 0.9))
        titleAnchor.scale = SIMD3(repeating: breathe)
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
