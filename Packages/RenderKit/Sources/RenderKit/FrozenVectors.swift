//
//  FrozenVectors.swift
//  RenderKit
//
//  Frozen time is where spatial computing beats every flat screen: a
//  thrown ball stopped mid-arc is a sculpture you can walk around. But
//  pausing used to just stop the animation — nothing materialized,
//  nothing invited you closer.
//
//  This is the shared "freeze sculpts" primitive: when a module pauses,
//  every moving body grows its vectors — velocity and force as arrows
//  you read by walking up to them — eased in like frost forming, eased
//  out the moment time restarts. One primitive, one colour language,
//  every lab, in the VectorPalette canon — velocity blue, force red —
//  so an arrow learned frozen reads identically live, and vice versa.
//
//  Callers pass a unit direction plus a 0…1 magnitude they normalise
//  themselves — each module knows its own dynamic range, and pretending
//  one metre of arrow means the same newtons in an orrery and on a
//  spring bench would be a lie.
//

import RealityKit
import UIKit
import simd

@MainActor
public final class FrozenVectors {
    /// What a frozen arrow is showing. The colours are fixed app-wide —
    /// this consistency IS the feature.
    public enum Kind: Int, CaseIterable {
        case velocity
        case force

        var color: UIColor {
            switch self {
            case .velocity: VectorPalette.velocity
            case .force: VectorPalette.force
            }
        }
    }

    public struct Sample {
        public let position: SIMD3<Float>
        public let direction: SIMD3<Float>
        public let magnitude01: Float
        public let kind: Kind

        public init(position: SIMD3<Float>, direction: SIMD3<Float>,
                    magnitude01: Float, kind: Kind) {
            self.position = position
            self.direction = direction
            self.magnitude01 = magnitude01
            self.kind = kind
        }
    }

    /// Add to the same root the bodies live under, so lab placement and
    /// scale carry the arrows along with what they annotate.
    public let root = Entity()

    private struct Arrow {
        let container: Entity
        let shaft: ModelEntity
        let head: ModelEntity
        var paletteIndex: Int = -1
    }

    /// Opacity-stepped materials per kind, built once. Allocating a
    /// material per arrow per frame is the exact churn the profiler
    /// caught elsewhere in this app; a palette swap is a reference
    /// assignment, and only happens when the step actually changes.
    private static let opacitySteps = 10
    private let palettes: [[UnlitMaterial]] = Kind.allCases.map { kind in
        (0..<opacitySteps).map { step in
            var material = UnlitMaterial(color: kind.color)
            material.blending = .transparent(
                opacity: .init(floatLiteral: Float(step + 1) / Float(opacitySteps)))
            return material
        }
    }

    private var arrows: [Arrow] = []
    private let budget: Int
    /// 0 = invisible, 1 = fully materialised. Eased toward the frozen
    /// state every frame, which is what makes the arrows form like frost
    /// rather than pop like UI.
    private var reveal: Float = 0

    /// Arrow length for magnitude01 = 0 and 1. Sized to be read from a
    /// step away, not to be geometrically proportional to the scene —
    /// and per-instance, because a handful of arrows on orbiting bodies
    /// wants length while a dense field lattice wants restraint. The
    /// wind tunnel's first lattice used the default and became a wall
    /// of blue: arrows 24 cm long on a 32 cm grid touch each other.
    private let minLength: Float
    private let maxLength: Float

    public init(budget: Int,
                minLength: Float = 0.05,
                maxLength: Float = 0.24) {
        self.budget = budget
        self.minLength = minLength
        self.maxLength = maxLength
        root.isEnabled = false

        for _ in 0..<budget {
            let container = Entity()
            // Unit-height parts, scaled per frame: one mesh for every
            // arrow of a kind, transforms only in the update path.
            let shaft = ModelEntity(
                mesh: .generateCylinder(height: 1, radius: 0.0035),
                materials: [UnlitMaterial(color: Kind.velocity.color)])
            let head = ModelEntity(
                mesh: .generateCone(height: 0.022, radius: 0.009),
                materials: [UnlitMaterial(color: Kind.velocity.color)])
            container.addChild(shaft)
            container.addChild(head)
            container.isEnabled = false
            root.addChild(container)
            arrows.append(Arrow(container: container, shaft: shaft, head: head))
        }
    }

    /// Call once per frame from the renderer's tick, frozen or not —
    /// the fade needs the clock. Cheap while hidden: one early-out.
    public func update(frozen: Bool, dt: Double, samples: () -> [Sample]) {
        let target: Float = frozen ? 1 : 0
        if reveal == target, target == 0 {
            if root.isEnabled { root.isEnabled = false }
            return
        }
        let rate = Float(min(dt * 6, 1))
        reveal += (target - reveal) * rate
        if abs(reveal - target) < 0.01 { reveal = target }
        root.isEnabled = reveal > 0.01
        guard root.isEnabled else { return }

        let sampleList = samples()
        for (index, arrow) in arrows.enumerated() {
            guard index < sampleList.count else {
                arrow.container.isEnabled = false
                continue
            }
            let sample = sampleList[index]
            let lengthUnit = simd_length(sample.direction)
            guard lengthUnit > 1e-5, sample.magnitude01 > 0.02 else {
                arrow.container.isEnabled = false
                continue
            }
            arrow.container.isEnabled = true

            let clamped = min(max(sample.magnitude01, 0), 1)
            // The reveal doubles as a growth animation: arrows extend
            // out of the body as they fade in.
            let length = (minLength + (maxLength - minLength) * clamped) * reveal

            arrow.container.position = sample.position
            // A frozen gravity arrow points exactly straight down.
            arrow.container.orientation = rotation(
                from: [0, 1, 0], to: sample.direction / lengthUnit)
            arrow.shaft.scale = [1, length, 1]
            arrow.shaft.position = [0, length / 2, 0]
            arrow.head.position = [0, length + 0.011, 0]

            let step = min(Int(reveal * Float(Self.opacitySteps)),
                           Self.opacitySteps - 1)
            let paletteIndex = sample.kind.rawValue * Self.opacitySteps + step
            if arrows[index].paletteIndex != paletteIndex {
                arrows[index].paletteIndex = paletteIndex
                let material = palettes[sample.kind.rawValue][step]
                arrow.shaft.model?.materials = [material]
                arrow.head.model?.materials = [material]
            }
        }
    }
}
