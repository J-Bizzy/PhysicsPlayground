//
//  HubVignettes.swift
//  Physics Playground — Hub
//
//  What the home's portals hold. Each lab stands in its portal in
//  miniature, on one shared stage (`HubDioramas.swift`); this file is the
//  frame they are fitted into and the parts they share. Three rules:
//    1. A vignette NEVER writes its own root transform; content hangs off
//       an inner `frame`.
//    2. `fit`/`fitStage` own `frame.position`/`frame.scale`; an animation
//       needing its own scale gets a third level beneath the frame.
//    3. Every drawn line goes through `lines(_:)` (dark casing, bright core).
//

import Foundation
import PhysicsCore
import RealityKit
import RenderKit
import SwiftUI
import simd

@MainActor
enum HubVignettes {
    /// A miniature and the per-frame animation that brings it to life.
    struct Built {
        let entity: Entity
        /// Called every frame with the elapsed time, in seconds.
        let animate: (Double) -> Void
        /// What the miniature's own geometry fills, swept across its whole
        /// cycle — whether what sits inside the square is a picture or a streak.
        let contentExtents: SIMD3<Float>

        init(entity: Entity,
             animate: @escaping (Double) -> Void,
             contentExtents: SIMD3<Float> = .zero) {
            self.entity = entity
            self.animate = animate
            self.contentExtents = contentExtents
        }
    }

    /// The half-extent of the square every miniature is normalised into, so
    /// differently shaped exhibits read as one set whatever a host
    /// divides by.
    static let frameHalf: Float = 0.085

    static func make(for moduleID: String) -> Built {
        switch moduleID {
        case "electrostatics": fieldsDiorama()
        case "circuits": circuitsDiorama()
        case "magnetism": magnetismDiorama()
        case "optics": opticsDiorama()
        case "kinematics": projectilesDiorama()
        case "pendulums": cradleDiorama()
        case "gravitylab": orreryDiorama()
        default: fallback()
        }
    }

    // MARK: The common frame

    /// Centres `frame` on the root's origin and normalises it to the common
    /// square, sampling a whole cycle of the motion (the resting pose would
    /// overflow mid-swing). `centredOn` picks the point that lands in the
    /// middle.
    static func fit(root: Entity, frame: Entity,
                            cycle: Double,
                            centredOn pivot: SIMD3<Float>? = nil,
                            animate: @escaping (Double) -> Void) -> Built {
        frame.position = .zero
        frame.scale = .one

        var lower = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var upper = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        let samples = 24
        for step in 0..<samples {
            animate(cycle * Double(step) / Double(samples))
            let box = frame.visualBounds(relativeTo: root)
            lower = simd_min(lower, box.min)
            upper = simd_max(upper, box.max)
        }

        // Half-extents measured outward from the centre, larger side —
        // keeps an off-centre anchor's long side inside the square.
        let centre = pivot ?? (lower + upper) / 2
        let reach = simd_max(upper - centre, centre - lower)
        let span = max(reach.x, max(reach.y, 1e-4)) * 2
        let scale = frameHalf * 2 / span
        // The offset is the scaled centre negated (the frame scale applies
        // to the centre just measured).
        frame.scale = SIMD3(repeating: scale)
        frame.position = -centre * scale

        // An invisible square proxy on the root so both hosts measure one
        // pose-independent box.
        let proxy = ModelEntity(
            mesh: Primitives.box(size: [frameHalf * 2, frameHalf * 2, 0.0005]),
            materials: [{
                let clear = Materials.unlit(.white, opacity: 0)
                return clear
            }()])
        proxy.name = "vignette-square"
        proxy.components.set(OpacityComponent(opacity: 0))
        root.addChild(proxy)

        animate(0)
        return Built(entity: root, animate: animate,
                     contentExtents: reach * 2 * scale)
    }

    // MARK: Shared parts

    static func ball(_ radius: Float, _ color: UIColor,
                             glow: Float = 0.45) -> ModelEntity {
        ModelEntity(mesh: Primitives.sphere(radius: radius, segments: 32),
                    materials: [Materials.energized(color, glow: glow)])
    }

    static func rod(length: Float, radius: Float, _ color: UIColor,
                            glow: Float = 0.2) -> ModelEntity {
        ModelEntity(mesh: Primitives.cylinder(height: length, radius: radius),
                    materials: [Materials.energized(color, glow: glow)])
    }

    /// A bundle of drawn lines in the two design-system passes (dark casing
    /// under a bright core). All paths share one mesh per pass, so a
    /// sixteen-line bundle is two draw calls.
    static func lines(_ paths: [[SIMD3<Float>]], radius: Float,
                              _ color: UIColor, opacity: Float = 1) -> Entity? {
        let usable = paths.filter { $0.count > 1 }
        guard !usable.isEmpty,
              let core = TubeMesh.tube(lines: usable, radius: radius, sides: 5),
              let casing = TubeMesh.tube(
                lines: usable,
                radius: Materials.casingRadius(forCore: radius), sides: 5)
        else { return nil }

        let (casingMaterial, coreMaterial) = Materials.contrastLine(color)
        let entity = Entity()
        entity.addChild(ModelEntity(mesh: casing, materials: [casingMaterial]))
        entity.addChild(ModelEntity(mesh: core, materials: [coreMaterial]))
        if opacity < 1 {
            entity.components.set(OpacityComponent(opacity: opacity))
        }
        return entity
    }

    static func line(_ points: [SIMD3<Float>], radius: Float,
                             _ color: UIColor, opacity: Float = 1) -> Entity? {
        lines([points], radius: radius, color, opacity: opacity)
    }

    static func ring(radius: Float, tube: Float, _ color: UIColor,
                             opacity: Float = 1, segments: Int = 40) -> Entity? {
        let points = (0...segments).map { step -> SIMD3<Float> in
            let angle = Float(step) / Float(segments) * 2 * .pi
            return SIMD3(cos(angle) * radius, 0, sin(angle) * radius)
        }
        return line(points, radius: tube, color, opacity: opacity)
    }

    // MARK: Modeled props

    /// A prop from the shared `PropCache`, centred on its origin and scaled
    /// so its longest dimension is `longest`. Measured rather than assumed;
    /// every call site keeps its old geometry as the fallback.
    static func prop(_ name: String, longest: Float) -> Entity? {
        guard let prototype = PropCache.prototype(named: name) else { return nil }

        let model = prototype.clone(recursive: true)
        let box = model.visualBounds(relativeTo: nil)
        let span = max(box.extents.x, max(box.extents.y, box.extents.z))
        guard span > 1e-5 else { return nil }
        let scale = longest / span

        let holder = Entity()
        model.scale = SIMD3(repeating: scale)
        model.position = -box.center * scale
        holder.addChild(model)
        return holder
    }

    // MARK: Worlds

    /// A celestial body wearing the same procedural texture Orbital Mechanics
    /// gives it, falling back to its accent until the texture has been drawn
    /// (`CelestialTextures` renders off the main path).
    static func celestialMaterial(_ name: String) -> RealityKit.Material {
        let texture = CelestialTextures.texture(for: name)
        if name.hasPrefix("Sun") {
            // Unlit: a star is self-luminous, and at this size a lit
            // sphere with a terminator across it reads as a moon.
            var material = UnlitMaterial(
                color: DesignTokens.Palette.celestialUI(name))
            if let texture {
                material.color = .init(tint: .white, texture: .init(texture))
            }
            return material
        }
        if let texture {
            var material = PhysicallyBasedMaterial()
            material.baseColor = .init(tint: .white, texture: .init(texture))
            material.roughness = 0.7
            material.metallic = 0.0
            return material
        }
        return Materials.energized(DesignTokens.Palette.celestialUI(name),
                                   glow: 0.2)
    }

    static func world(_ name: String, radius: Float) -> ModelEntity {
        ModelEntity(mesh: Primitives.sphere(radius: radius, segments: 32),
                    materials: [celestialMaterial(name)])
    }

    // MARK: Field lines, integrated

    /// A point source of a `1/r²` field: a charge, or one end of a bar
    /// magnet under the magnetic-charge model.
    struct Pole {
        let at: SIMD3<Float>
        let strength: Float
    }

    static func fieldDirection(at point: SIMD3<Float>,
                                       poles: [Pole]) -> SIMD3<Float>? {
        var field = SIMD3<Float>.zero
        for pole in poles {
            let offset = point - pole.at
            let distance = simd_length(offset)
            guard distance > 1e-5 else { return nil }
            field += pole.strength * offset / (distance * distance * distance)
        }
        let magnitude = simd_length(field)
        guard magnitude > 1e-9 else { return nil }
        return field / magnitude
    }

    /// One field line, integrated through a set of point sources by midpoint
    /// marching `dr/ds = Ê`. A few thousand multiplies at build time gets the
    /// topology right, including the lines that never close.
    static func fieldLine(from seed: SIMD3<Float>,
                                  poles: [Pole],
                                  step: Float,
                                  escape: Float,
                                  sinks: [(at: SIMD3<Float>, radius: Float)],
                                  maxSteps: Int = 700) -> [SIMD3<Float>] {
        var point = seed
        var path = [seed]
        for _ in 0..<maxSteps {
            guard let first = fieldDirection(at: point, poles: poles),
                  let mid = fieldDirection(at: point + first * (step / 2),
                                           poles: poles)
            else { break }
            point += mid * step
            path.append(point)
            if sinks.contains(where: { simd_distance(point, $0.at) < $0.radius }) {
                break
            }
            if simd_length(point) > escape { break }
        }
        return path
    }

    // MARK: Fallback — a new module gets something until it has art

    private static func fallback() -> Built {
        let root = Entity()
        let frame = Entity()
        root.addChild(frame)
        let sphere = ball(0.030, UIColor(white: 0.7, alpha: 1), glow: 0.3)
        frame.addChild(sphere)
        return fit(root: root, frame: frame, cycle: 4.5) { time in
            sphere.scale = SIMD3(repeating: 1 + 0.06 * Float(sin(time * 1.4)))
        }
    }
}

/// `sign` for Float without importing anything heavier.
private func sign(_ value: Float) -> Float {
    value < 0 ? -1 : 1
}
