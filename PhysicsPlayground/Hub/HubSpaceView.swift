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
    }
    private var exhibits: [Exhibit] = []
    private var time = 0.0
    /// The 3-D bubble title the exhibits ring, bobbing at the centre.
    private let titleAnchor = Entity()

    /// The ring encircles the title: a vertical circle in the frontal
    /// plane, a step beyond it in depth.
    private static let ringCenter = SIMD3<Float>(0, 1.6, -2.2)
    private static let ringRadius: Float = 0.95
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
            let basePosition = Self.ringCenter + SIMD3(
                Self.ringRadius * cos(angle),
                Self.ringRadius * sin(angle),
                0
            )
            buildExhibit(for: module, at: basePosition)
        }
    }

    // MARK: The 3-D bubble title

    /// "Physics / Playground" as two lines of fat rounded 3-D letters —
    /// glossy bubbles with a soft glow behind, floating at the centre of
    /// the ring.
    /// Centred in the ring, a step forward in depth from the exhibits —
    /// and lifted above the hub window, which grew a catalog grid and
    /// now reaches well up into the old title height.
    private static let titleOffset = SIMD3<Float>(0, 0.34, 0.12)
    /// The title reads as smoky, semi-transparent glass rather than
    /// coloured candy — a quiet frosted grey.
    private static let titleColor = UIColor(white: 0.62, alpha: 1)
    private static let titleOpacity: Float = 0.8

    private func buildBubbleTitle() {
        titleAnchor.position = Self.ringCenter + Self.titleOffset
        // Two centred lines of fat rounded glyphs — inflated bubbles.
        let physics = Self.bubbleText(
            "Physics", size: 0.17, color: Self.titleColor,
            opacity: Self.titleOpacity, emissive: 0.12)
        physics.position.y = 0.12
        let playground = Self.bubbleText(
            "Playground", size: 0.17, color: Self.titleColor,
            opacity: Self.titleOpacity, emissive: 0.12)
        playground.position.y = -0.12
        titleAnchor.addChild(physics)
        titleAnchor.addChild(playground)
        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = "Physics Playground"
        titleAnchor.components.set(accessibility)
        root.addChild(titleAnchor)
    }

    /// The app's signature 3-D "bubble" type, in one reusable builder:
    /// fat rounded heavy glyphs extruded into a glossy clear-coated
    /// solid. Centred on its own origin and returned as a group. The hub
    /// title and every exhibit name plate share this one treatment.
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
        letters.position = [centerX, 0, 0]
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
            vignette: vignette, basePosition: basePosition))
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
        positive.position = [-0.045, 0, 0]
        let negative = ModelEntity(
            mesh: .generateSphere(radius: 0.026),
            materials: [SimpleMaterial(color: DesignTokens.Palette.negativeUI,
                                       roughness: 0.35, isMetallic: false)])
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
