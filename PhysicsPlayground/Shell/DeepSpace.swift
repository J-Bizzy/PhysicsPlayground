//
//  DeepSpace.swift
//  Physics Playground — Shell
//
//  Deep space: the surroundings a wearer can choose in place of their room
//  (`Surroundings`). Full immersion, and four things only:
//    • the sky — the real one (`Sky`): every naked-eye star at its place,
//      colour and brightness, the Milky Way along the galactic plane;
//    • the Sun, far off — where it stands seen from Pluto's distance on
//      the sky's date: magnitude −19, too small for a disc, a white-hot
//      point in its own glare. Put away while a lab draws a Sun of its own;
//    • the platform — smoked glass 3.6 m across, its top at the real
//      floor, a champagne edge: the wearer keeps their footing and sees
//      the stars under it;
//    • the floor's reach — the physics floor goes on past the platform (a
//      ball lands on it out to 30 m, where it is retired), so a dark pane
//      marks it, fading to nothing by then.
//  Nothing glows: in this app a glow means "live". The labs keep the
//  system's lighting, so a lab looks the same in both surroundings.
//

import PhysicsCore
import RealityKit
import RenderKit
import SwiftUI

struct DeepSpaceView: View {
    /// False while the lab on screen draws a Sun of its own.
    let showsSun: Bool
    @State private var stage = DeepSpaceStage()

    var body: some View {
        RealityView { content in
            stage.build(showsSun: showsSun)
            content.add(stage.root)
            // `[weak stage]`: the subscription is held on the stage.
            stage.subscription = content.subscribe(to: SceneEvents.Update.self) { [weak stage] _ in
                stage?.tick()
            }
        } update: { _ in
            stage.showsSun = showsSun
        }
        // An EventSubscription outlives the view that made it.
        .onDisappear {
            stage.subscription?.cancel()
            stage.subscription = nil
        }
    }
}

/// The environment on screen, and its two fades: the whole in over
/// `DeepSpace.arrival`, and the Sun in and out as labs come and go.
@MainActor
final class DeepSpaceStage {
    let root = Entity()
    var showsSun = true
    var subscription: EventSubscription?
    private var sun: Entity?

    /// Built in the RealityView's make closure, not in `init`: a `@State`
    /// initial value is constructed on every evaluation of the view.
    func build(showsSun: Bool) {
        guard root.children.isEmpty else { return }
        let made = DeepSpace.make(resources: SkyResources.shared)
        // A copy: reparenting a child shortens the collection being walked.
        for child in Array(made.children) { root.addChild(child) }
        root.name = made.name
        sun = root.findEntity(named: DeepSpace.sunName)
        sun?.isEnabled = showsSun
        self.showsSun = showsSun
        root.components.set(OpacityComponent(opacity: 0))
    }

    func tick() {
        Fade.tick(root, visible: true, duration: DeepSpace.arrival)
        if let sun { Fade.tick(sun, visible: showsSun, duration: DeepSpace.sunFade) }
    }
}

@MainActor
enum DeepSpace {
    static let rootName = "deep-space"
    static let sunName = "deep-space-sun"
    static let platformName = "deep-space-platform"
    static let reachName = "deep-space-reach"

    /// How long the whole takes to come up as the room goes.
    static let arrival = 0.8
    /// The Sun's fade as a lab with its own comes or goes.
    static let sunFade = 0.4

    /// The platform's radius and thickness, metres; its top is the floor.
    static let platformRadius: Float = 1.8
    static let platformThickness: Float = 0.02
    /// How far the floor's pane reaches: where a ball is retired.
    static let reach = Float(KinematicsModel.escapeRadius)

    /// The four parts, in their sort order after the sky's: the Sun, then
    /// the floor's pane, then the platform, so each transparent layer lies
    /// over what is beyond it.
    static func make(resources: SkyResources?) -> Entity {
        let root = Entity()
        root.name = rootName
        let group = ModelSortGroup(depthPass: nil)
        if let resources {
            root.addChild(Sky.make(overRoom: false, resources: resources, group: group))
        } else {
            // Before the sky is built (a test that never prepared it).
            let placeholder = Entity()
            placeholder.name = "sky"
            root.addChild(placeholder)
        }
        root.addChild(makeSun(group: group, after: Sky.lastOrder))
        root.addChild(makeReach(group: group, order: Sky.lastOrder + 2))
        root.addChild(makePlatform(group: group, order: Sky.lastOrder + 3))
        return root
    }

    // MARK: The Sun

    /// Inside the stars' sphere, so it is drawn on the sky, not beyond it.
    static let sunDistance: Float = 44
    /// The white-hot core's angular width, and the glare's whole extent.
    static let sunCore = 10.0 / 60 * Double.pi / 180
    static let sunGlare = 3.0 * Double.pi / 180
    /// The Sun's effective temperature, K (IAU 2015 nominal).
    static let sunTemperature = 5772.0
    /// The glare's level just outside the core, against the core's 1.
    static let glareLevel = 0.4

    static func makeSun(group: ModelSortGroup, after order: Int32) -> Entity {
        let sun = Entity()
        sun.name = sunName
        // In the sky's own frame, so it turns with the stars.
        sun.position = Sky.centre
        sun.orientation = Sky.orientation
        let seen = MeanElements.pluto.sunSeen(julianDate: Sky.epoch)
        let tint = StellarColour.displayColour(temperature: sunTemperature)
        var material = UnlitMaterial(color: UIColor(red: tint.x, green: tint.y, blue: tint.z, alpha: 1))
        if let mask = sunMask() {
            material.blending = .transparent(opacity: .init(scale: 1, texture: .init(mask)))
        } else {
            material.blending = .transparent(opacity: .init(floatLiteral: 0.5))
        }
        // Light, not a surface.
        material.writesDepth = false
        let light = ModelEntity(mesh: Primitives.plane(width: span(sunGlare), height: span(sunGlare)),
                                materials: [material])
        light.name = "deep-space-sun-light"
        light.position = SIMD3<Float>(simd_normalize(seen.direction)) * sunDistance
        light.components.set(BillboardComponent())
        light.components.set(ModelSortGroupComponent(group: group, order: order + 1))
        sun.addChild(light)
        return sun
    }

    /// The width of a sprite that spans `angle` at the Sun's distance.
    static func span(_ angle: Double) -> Float {
        2 * sunDistance * Float(tan(angle / 2))
    }

    /// A point too small for a disc, seen through an eye: a white-hot core
    /// `sunCore` across and a glare falling as 1/(1 + (r/3r₀)²) — a star's
    /// scattered light, not a ball — brought smoothly to nothing at the
    /// sprite's edge.
    private static func sunMask() -> TextureResource? {
        let size = 256
        let core = sunCore / sunGlare           // the core's share of the sprite's width
        var pixels = [UInt8](repeating: 0, count: size * size)
        for y in 0..<size {
            for x in 0..<size {
                let u = (Double(x) + 0.5) / Double(size) * 2 - 1
                let v = (Double(y) + 0.5) / Double(size) * 2 - 1
                let rho = min((u * u + v * v).squareRoot(), 1)
                let r = rho / core * 2            // in core radii
                let level = exp(-r * r) + glareLevel / (1 + r * r / 9)
                let edge = (1 - rho * rho) * (1 - rho * rho)
                pixels[y * size + x] = UInt8((min(level, 1) * edge * 255).rounded())
            }
        }
        guard let image = SkyDrawing.image(gray: pixels, width: size, height: size) else { return nil }
        return try? TextureResource(image: image, options: .init(semantic: .raw))
    }

    // MARK: The floor

    static func makeReach(group: ModelSortGroup, order: Int32) -> Entity {
        var material = UnlitMaterial(color: UIColor(red: 0.010, green: 0.012, blue: 0.020, alpha: 1))
        if let mask = reachMask() {
            material.blending = .transparent(opacity: .init(scale: reachOpacity, texture: .init(mask)))
        } else {
            material.blending = .transparent(opacity: .init(floatLiteral: reachOpacity * 0.3))
        }
        // A tint over the stars below, not a surface: it hides nothing.
        material.writesDepth = false
        let pane = ModelEntity(mesh: Primitives.plane(width: 2 * reach, depth: 2 * reach,
                                                      cornerRadius: reach),
                               materials: [material])
        pane.name = reachName
        // Just under the platform's underside.
        pane.position.y = -platformThickness - 0.01
        pane.components.set(ModelSortGroupComponent(group: group, order: order))
        return pane
    }

    /// The pane's darkest, at the wearer's feet.
    static let reachOpacity: Float = 0.5

    /// Dark at the centre, falling as (1 − r/R)² to nothing at the rim.
    private static func reachMask() -> TextureResource? {
        let size = 512
        var pixels = [UInt8](repeating: 0, count: size * size)
        for y in 0..<size {
            for x in 0..<size {
                let u = (Double(x) + 0.5) / Double(size) * 2 - 1
                let v = (Double(y) + 0.5) / Double(size) * 2 - 1
                let r = min((u * u + v * v).squareRoot(), 1)
                pixels[y * size + x] = UInt8(((1 - r) * (1 - r) * 255).rounded())
            }
        }
        guard let image = SkyDrawing.image(gray: pixels, width: size, height: size) else { return nil }
        return try? TextureResource(image: image, options: .init(semantic: .raw))
    }

    static func makePlatform(group: ModelSortGroup, order: Int32) -> Entity {
        let platform = Entity()
        platform.name = platformName
        let slab = ModelEntity(
            mesh: Primitives.cylinder(height: platformThickness, radius: platformRadius),
            materials: [Materials.frostedGlass(UIColor(red: 0.030, green: 0.034, blue: 0.044, alpha: 1),
                                               opacity: 0.72, frost: 0.30)])
        slab.name = "deep-space-platform-glass"
        slab.position.y = -platformThickness / 2
        slab.components.set(ModelSortGroupComponent(group: group, order: order))
        platform.addChild(slab)

        // The edge: a fine champagne band round the top, machined, not lit.
        let points = (0...192).map { step -> SIMD3<Float> in
            let angle = Float(step) / 192 * 2 * .pi
            return SIMD3(cos(angle) * platformRadius, 0, sin(angle) * platformRadius)
        }
        if let mesh = TubeMesh.tube(lines: [points], radius: 0.004, sides: 12) {
            let edge = ModelEntity(mesh: mesh,
                                   materials: [Materials.machined(HubTitleStyle.champagne,
                                                                  roughness: 0.35)])
            edge.name = "deep-space-platform-edge"
            edge.position.y = -0.004
            platform.addChild(edge)
        }
        return platform
    }
}
