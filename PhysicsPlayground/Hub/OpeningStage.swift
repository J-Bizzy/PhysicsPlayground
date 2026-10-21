//
//  OpeningStage.swift
//  Physics Playground — Hub
//
//  "Birth of a System", drawn: `OpeningPlan`'s star, its dust disk, the
//  seven worlds and the paths they fly, and — in the room — the night it
//  all happens in (in deep space the sky is already there). Built once;
//  every frame after is a pure function of the opening's clock: transforms
//  and opacities, written only when they change, and the paths at most
//  thirty times a second (`trailInterval`), each led to its world between
//  commits by a segment moved by its transform alone.
//
//  Sorted as one group so each transparent layer lies over what is beyond
//  it: the night, then the Milky Way and the stars over the room, then the
//  disk, the star's glow, and the worlds' paths.
//

import PhysicsCore
import QuartzCore
import RealityKit
import RenderKit
import UIKit

@MainActor
final class OpeningStage {
    let root = Entity()
    private let plan: OpeningPlan

    private var night: ModelEntity?
    private var sky: Entity?
    private let star = Entity()
    private let starCore: ModelEntity
    private let starGlow: ModelEntity
    private let starLight = Entity()
    private let disk = Entity()
    private var annuli: [ModelEntity] = []
    private var worlds: [ModelEntity] = []
    private let trails: TrailRibbons?
    /// One per world: a unit cylinder stretched from the head its path was
    /// last written with to where the world is now.
    private var leaders: [ModelEntity] = []
    /// The opening's simulated time the paths were last written at, and
    /// the wall time they were — the paths change only while it runs.
    private var trailsSimTime: Double?
    private var trailsWall = -Double.infinity
    private var committedHeads: [SIMD3<Float>?] = []
    private var shown: [ObjectIdentifier: Float] = [:]
    private var lightLevel: Float = -1
    private var texturesApplied = -1

    /// The night's sphere, inside the 16 m shell's reach and the sky's.
    static let nightRadius: Float = 47
    /// The night is never quite black: the room stays a trace through it.
    static let nightAlpha: Float = 235.0 / 255.0
    static let starCoreSize: Float = 0.2
    static let starGlowSize: Float = 0.7
    static let starColour = UIColor(red: 1.0, green: 0.86, blue: 0.68, alpha: 1)
    static let dustColour = UIColor(red: 0.96, green: 0.82, blue: 0.64, alpha: 1)
    /// How opaque the disk is at its brightest.
    static let dustStrength: Float = 0.7
    static let trailRadius: Float = 0.0035
    static let trailSamples = 40
    /// How often the paths go to the renderer. Every frame left the main
    /// thread waiting on it for 44 % of the flight (2026-10-21): each
    /// `LowLevelMesh` write takes a payload from a pool the renderer
    /// refills only as it draws, and three meshes in turn do not change how
    /// many payloads a frame takes. Orbital Mechanics' trails run at the
    /// same rate (`trailGrowInterval`).
    static let trailInterval = 1.0 / 30

    /// - inSpace: deep space supplies its own sky, so there is no night.
    init(plan: OpeningPlan = .shared, inSpace: Bool) {
        self.plan = plan
        root.name = "opening"
        let group = ModelSortGroup(depthPass: nil)

        // The night and its sky, over the room only.
        if !inSpace {
            // The house recipe, then made light-like: it must not write depth
            // or it would cut the sky out of everything drawn after it.
            var dark = Materials.unlit(UIColor(red: 0.004, green: 0.005, blue: 0.010, alpha: 1),
                                       opacity: Self.nightAlpha)
            dark.writesDepth = false
            let sphere = ModelEntity(mesh: Primitives.sphere(radius: Self.nightRadius), materials: [dark])
            sphere.name = "opening-night"
            sphere.scale = SIMD3(-1, 1, 1)
            sphere.position = Sky.centre
            sphere.components.set(ModelSortGroupComponent(group: group, order: -1))
            root.addChild(sphere)
            night = sphere
            if let resources = SkyResources.shared {
                let made = Sky.make(overRoom: true, resources: resources, group: group)
                root.addChild(made)
                sky = made
            }
        }

        // The disk: one band mesh, a scaled copy per annulus, every one in
        // the disk's plane at the star, turned about its normal.
        disk.name = "opening-disk"
        disk.position = SIMD3<Float>(plan.star)
        let u = SIMD3<Float>(plan.diskAxisU), n = SIMD3<Float>(plan.diskNormal)
        disk.orientation = simd_quatf(simd_float3x3(columns: (u, n, simd_cross(u, n))))
        root.addChild(disk)
        if let band = Self.bandMesh() {
            let dust = Self.dustMaterial()
            for k in 0..<OpeningPlan.annulusCount {
                let annulus = ModelEntity(mesh: band, materials: [dust])
                annulus.name = "opening-annulus"
                let outer = Float(OpeningPlan.annulus(k).outer)
                annulus.scale = SIMD3(outer, 1, outer)
                annulus.components.set(ModelSortGroupComponent(group: group, order: 2))
                annulus.isEnabled = false
                disk.addChild(annulus)
                annuli.append(annulus)
            }
        }

        // The star: a white-hot core in a warm glow, lighting the worlds.
        star.name = "opening-star"
        star.position = SIMD3<Float>(plan.star)
        starGlow = GlowSprite.make(size: Self.starGlowSize)
        GlowSprite.paint(starGlow, Self.starColour, strength: 0.35)
        starGlow.components.set(ModelSortGroupComponent(group: group, order: 3))
        star.addChild(starGlow)
        starCore = GlowSprite.make(size: Self.starCoreSize)
        GlowSprite.paint(starCore, .white, strength: 1)
        starCore.components.set(ModelSortGroupComponent(group: group, order: 3))
        star.addChild(starCore)
        star.addChild(starLight)
        star.isEnabled = false
        root.addChild(star)

        // The worlds, textured as Orbital Mechanics draws them.
        let sphere = Primitives.sphere(radius: 1)
        for world in plan.worlds {
            let entity = ModelEntity(mesh: sphere, materials: [Self.worldMaterial(world.name)])
            entity.name = "opening-world"
            entity.isEnabled = false
            root.addChild(entity)
            worlds.append(entity)
        }

        // Their paths: one ribbon mesh, a slot per world, fading to the tail.
        // Three meshes in turn: every path is rewritten every frame.
        trails = TrailRibbons(slots: max(plan.worlds.count, 1), capacity: Self.trailSamples,
                              rotation: 3)
        if let trails {
            trails.entity.name = "opening-trails"
            trails.entity.components.set(ModelSortGroupComponent(group: group, order: 4))
            root.addChild(trails.entity)
            let names = plan.worlds.map(\.name)
            Task {
                guard let ramp = await Materials.fadeRamp() else { return }
                for (slot, name) in names.enumerated() {
                    trails.setMaterial(Materials.fadedLine(Self.trailColour(name), ramp: ramp), slot: slot)
                }
            }
            // The leaders hang from the paths, so they share their fade; each
            // is a path's head, the ramp's full opacity.
            let segment = Primitives.cylinder(height: 1, radius: 1)
            for world in plan.worlds {
                let leader = ModelEntity(mesh: segment, materials: [Materials.unlit(Self.trailColour(world.name))])
                leader.name = "opening-leader"
                leader.components.set(ModelSortGroupComponent(group: group, order: 4))
                leader.isEnabled = false
                trails.entity.addChild(leader)
                leaders.append(leader)
            }
            committedHeads = Array(repeating: nil, count: plan.worlds.count)
        }
    }

    // MARK: Every frame

    func update(at t: Double) {
        // The night and the sky over the room.
        let darkness = Float(plan.nightOpacity(at: t))
        if let night { setOpacity(night, darkness) }
        if let sky { setOpacity(sky, darkness) }

        // The star: lit, glowing, and lighting the worlds.
        let light = Float(plan.starBrightness(at: t))
        setOpacity(star, light)
        let flare = 0.7 + 0.3 * light
        starCore.scale = SIMD3(repeating: flare)
        if abs(light - lightLevel) > 0.01 {
            lightLevel = light
            if light > 0.001 {
                starLight.components.set(PointLightComponent(
                    color: Self.starColour, intensity: 4_000 * light, attenuationRadius: 6))
            } else {
                starLight.components.remove(PointLightComponent.self)
            }
        }

        // The disk: each annulus at its own Kepler angle.
        for (k, annulus) in annuli.enumerated() {
            let opacity = Float(plan.annulusOpacity(k, at: t)) * Self.dustStrength
            setOpacity(annulus, opacity)
            if annulus.isEnabled {
                annulus.orientation = simd_quatf(angle: Float(plan.annulusAngle(k, at: t)),
                                                 axis: [0, 1, 0])
            }
        }

        // The worlds, where the plan has them, as much of each as there is.
        if texturesApplied != CelestialTextures.version {
            texturesApplied = CelestialTextures.version
            for (index, world) in plan.worlds.enumerated() {
                worlds[index].model?.materials = [Self.worldMaterial(world.name)]
            }
        }
        for (index, world) in plan.worlds.enumerated() {
            let entity = worlds[index]
            let growth = Float(plan.growth(ofWorld: index, at: t))
            entity.isEnabled = growth > 0.001
            guard entity.isEnabled else { continue }
            entity.position = SIMD3<Float>(plan.position(ofWorld: index, at: t))
            entity.scale = SIMD3(repeating: Float(world.radius) * growth)
            // A day's turn as it goes, so a world reads as a globe.
            entity.orientation = simd_quatf(angle: Float(t) * 0.9, axis: simd_normalize([0.2, 1, 0.1]))
        }

        // Their paths, in closed form, fading out as the worlds open.
        if let trails {
            let fade = Float(1 - OpeningPlan.ramp(t, from: OpeningPlan.landingTime,
                                                  over: OpeningPlan.worldOpen))
            setOpacity(trails.entity, fade)
            if fade > 0.001 { updateTrails(trails, at: t) }
        }
    }

    /// Rewrites the paths when the clock has moved and a commit is due, and
    /// every frame leads each one on from its written head to its world.
    private func updateTrails(_ trails: TrailRibbons, at t: Double) {
        let sim = OpeningPlan.simTime(at: t)
        let wall = CACurrentMediaTime()
        if sim != trailsSimTime, wall - trailsWall >= Self.trailInterval {
            trailsSimTime = sim
            trailsWall = wall
            for index in plan.worlds.indices {
                let path = plan.trail(ofWorld: index, at: t, samples: Self.trailSamples)
                if path.points.count > 1, let head = path.points.last {
                    trails.update(slot: index, points: path.points.map(SIMD3<Float>.init),
                                  ages: path.ages.map(Float.init), radius: Self.trailRadius)
                    committedHeads[index] = SIMD3<Float>(head)
                } else {
                    trails.clear(slot: index)
                    committedHeads[index] = nil
                }
            }
            trails.commit()
        }
        for (index, leader) in leaders.enumerated() {
            guard let from = committedHeads[index] else {
                leader.isEnabled = false
                continue
            }
            let span = SIMD3<Float>(plan.position(ofWorld: index, at: t)) - from
            let length = simd_length(span)
            leader.isEnabled = length > 0.0005
            guard leader.isEnabled else { continue }
            leader.position = from + span / 2
            leader.orientation = VectorFieldArrows.rotationFromYAxis(to: span / length)
            leader.scale = SIMD3(Self.trailRadius, length, Self.trailRadius)
        }
    }

    /// Writes an opacity only when it changes; at zero the entity is not drawn.
    private func setOpacity(_ entity: Entity, _ value: Float) {
        let key = ObjectIdentifier(entity)
        guard shown[key] != value else { return }
        shown[key] = value
        entity.isEnabled = value > 0.001
        if value >= 0.999 {
            entity.components.remove(OpacityComponent.self)
        } else {
            entity.components.set(OpacityComponent(opacity: value))
        }
    }

    // MARK: Making

    /// A flat band in its own XZ plane, facing +Y, from 1/annulusRatio to 1:
    /// u runs round it, v across it.
    static func bandMesh() -> MeshResource? {
        let segments = 96
        let inner = Float(1 / OpeningPlan.annulusRatio)
        var positions: [SIMD3<Float>] = [], normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = [], indices: [UInt32] = []
        for step in 0...segments {
            let u = Float(step) / Float(segments)
            let angle = u * 2 * .pi
            let direction = SIMD3<Float>(cos(angle), 0, -sin(angle))
            positions += [direction * inner, direction]
            normals += [[0, 1, 0], [0, 1, 0]]
            uvs += [[u, 0], [u, 1]]
        }
        for step in 0..<segments {
            let a = UInt32(step * 2)
            indices += [a, a + 1, a + 2, a + 1, a + 3, a + 2]
        }
        var descriptor = MeshDescriptor(name: "opening-band")
        descriptor.positions = MeshBuffer(positions)
        descriptor.normals = MeshBuffer(normals)
        descriptor.textureCoordinates = MeshBuffer(uvs)
        descriptor.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [descriptor])
    }

    /// Dust: a warm unlit colour whose opacity is a mask of spokes round
    /// the band — the same angles in every annulus, so the spokes run
    /// straight across the disk when its rings stand at zero and wind into
    /// spirals as they shear.
    static func dustMaterial() -> UnlitMaterial {
        var material = UnlitMaterial(color: dustColour)
        if let mask = dustMask() {
            material.blending = .transparent(opacity: .init(scale: 1, texture: .init(mask)))
        } else {
            material.blending = .transparent(opacity: .init(floatLiteral: 0.4))
        }
        material.writesDepth = false
        return material
    }

    private static func dustMask() -> TextureResource? {
        let width = 1_024, height = 8
        // Whole numbers of turns, so the pattern closes round the band.
        let waves: [(frequency: Double, amplitude: Double, phase: Double)] = [
            (3, 0.30, 0.7), (5, 0.24, 2.1), (8, 0.18, 4.0), (13, 0.14, 1.3),
            (21, 0.10, 5.2), (34, 0.07, 3.3), (55, 0.05, 0.4),
        ]
        var state: UInt64 = 0xD057
        var pixels = [UInt8](repeating: 0, count: width * height)
        for x in 0..<width {
            let u = Double(x) / Double(width)
            var level = 0.0
            for wave in waves {
                level += wave.amplitude * (0.5 + 0.5 * cos(2 * .pi * wave.frequency * u + wave.phase))
            }
            // Deepened, so the lanes between the spokes read as lanes and
            // the shear shows as arms, not as a smooth band.
            level = pow(min(level / 0.9, 1), 1.8) * 0.95 + 0.05
            for y in 0..<height {
                state = state &* 6364136223846793005 &+ 1442695040888963407
                let grain = Double(state >> 40) / Double(1 << 24) * 0.16 - 0.08
                pixels[y * width + x] = UInt8((min(max(level + grain, 0), 1) * 255).rounded())
            }
        }
        guard let image = SkyDrawing.image(gray: pixels, width: width, height: height) else { return nil }
        return try? TextureResource(image: image, options: .init(semantic: .raw))
    }

    static func worldMaterial(_ name: String) -> RealityKit.Material {
        if let texture = CelestialTextures.texture(for: name) {
            var material = PhysicallyBasedMaterial()
            material.baseColor = .init(tint: .white, texture: .init(texture))
            material.roughness = 0.7
            material.metallic = 0.0
            return material
        }
        return Materials.machined(DesignTokens.Palette.celestialUI(name), roughness: 0.6)
    }

    static func trailColour(_ name: String) -> UIColor {
        DesignTokens.Palette.celestialUI(name)
    }
}
