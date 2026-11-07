//
//  HubTitleGlyphs.swift
//  Physics Playground — Hub
//
//  The wordmark in the app's own voice, alive: "Physics" over "Playground"
//  in SF Pro Rounded Semibold — every label's face — as soft white solids
//  standing free (the glass plaque behind them went on 2026-10-21, owner's
//  call), the dot of the i a particle of champagne light
//  (Tools/hubwordmark.py mills the letters, one at a time). Each
//  letter is on its own hinge, so it can move; what moves and why is
//  `HubTitleMotion`, and this file only builds the hinges and applies the
//  curves.
//
//  Removable on purpose: `HubScene` asks for a line here first and falls
//  back to the machined plaque (`HubTitleStyle.milled`) when these assets
//  are missing, so deleting this file, `HubTitleMotion` and the two
//  `HubWordmark_*` assets restores it exactly.
//

import Foundation
import RealityKit
import RenderKit
import UIKit
import simd

@MainActor
final class HubTitleGlyphs {

    /// Per-letter assets, by line.
    private static let assets: [String: String] = [
        "Physics": "HubWordmark_Physics",
        "Playground": "HubWordmark_Playground",
    ]

    private enum Arrival { case drop, swing }

    private struct Letter {
        let line: Int
        /// What moves: the letter's parts hang under it.
        let hinge: Entity
        /// The hinge's resting place, in the line's own (unscaled) units.
        let rest: SIMD3<Float>
        /// The letter's body and its finish (its own instance, so the
        /// glint can light one letter at a time).
        let body: Entity?
        var finish: PhysicallyBasedMaterial?
        var lit: Float = 0
        /// The i's particle, if this is the i, and where it rests.
        let dot: Entity?
        let dotRest: SIMD3<Float>
        /// The letter's size, line units.
        let size: SIMD2<Float>
        let arrival: Arrival
        let release: Double
        /// When a tap last hopped it, scene seconds.
        var hopStart: Double?
        var visible: Float = 1
    }

    private var letters: [Letter] = []
    private var lineEntities: [Entity] = []
    /// Metres per line unit, per line — set once the lockup has scaled the
    /// lines (`HubScene.buildBubbleTitle`).
    var lineScales: [Float] = []

    /// Whether any line was built from the per-letter asset.
    var isAlive: Bool { !letters.isEmpty }

    // MARK: Building

    /// One line of the wordmark as hinged letters, or nil when this line
    /// has no asset. Same contract as `HubTitleStyle.milled`: a centred
    /// entity of scale 1 and its extents.
    func line(_ text: String) -> (entity: Entity, extents: SIMD3<Float>)? {
        guard let asset = Self.assets[text],
              let prototype = PropCache.prototype(named: asset) else { return nil }
        let lineIndex = lineEntities.count
        let arrival: Arrival = lineIndex == 0 ? .drop : .swing

        // `line` is what the lockup scales and stacks; `content` centres the
        // letters on its origin, as `HubTitleStyle.milled` centres its line.
        let line = Entity()
        let content = Entity()
        line.addChild(content)
        let model = prototype.clone(recursive: true)
        content.addChild(model)

        // Every mesh part, grouped by the glyph it belongs to. Found by its
        // ModelComponent, not by casting to ModelEntity, which a loaded USD
        // need not produce (`HubTitleStyle.milled` learned the same).
        var parts: [Int: [Entity]] = [:]
        func collect(_ entity: Entity) {
            if entity.components.has(ModelComponent.self),
               let index = Self.glyphIndex(entity.name) {
                parts[index, default: []].append(entity)
            }
            for child in entity.children { collect(child) }
        }
        collect(model)
        guard !parts.isEmpty else { return nil }

        var lower = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var upper = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)

        for (order, index) in parts.keys.sorted().enumerated() {
            let glyph = parts[index] ?? []
            var low = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
            var high = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
            for part in glyph {
                let box = part.visualBounds(relativeTo: content)
                low = simd_min(low, box.min)
                high = simd_max(high, box.max)
            }
            lower = simd_min(lower, low)
            upper = simd_max(upper, high)
            let centre = (low + high) / 2
            // A dropped letter moves about its middle; a swung one hangs
            // from the middle of its top edge.
            let pivot = arrival == .swing ? SIMD3(centre.x, high.y, centre.z) : centre
            let hinge = Entity()
            hinge.name = "title-letter"
            hinge.position = pivot
            content.addChild(hinge)

            var body: Entity?
            var finish: PhysicallyBasedMaterial?
            var dot: Entity?
            var dotRest = SIMD3<Float>.zero
            for part in glyph {
                if part.name.contains("Dot") {
                    // The tittle becomes a particle: a sphere of champagne
                    // light where the dot was, the app's one accent.
                    let box = part.visualBounds(relativeTo: hinge)
                    let radius = max(box.extents.x, box.extents.y) * 0.56
                    let particle = ModelEntity(mesh: Primitives.sphere(radius: radius, segments: 24),
                                               materials: [Self.particleFinish()])
                    particle.name = "title-dot"
                    particle.position = box.center
                    hinge.addChild(particle)
                    part.removeFromParent()
                    dot = particle
                    dotRest = box.center
                    continue
                }
                part.setParent(hinge, preservingWorldTransform: true)
                guard var model = part.components[ModelComponent.self] else { continue }
                let own = Self.letterFinish()
                model.materials = [own]
                part.components.set(model)
                body = part
                finish = own
            }

            // The letter is a target: a pinch hops it. Its box is its ink.
            let size = high - low
            hinge.components.set(InputTargetComponent())
            hinge.components.set(CollisionComponent(shapes: [
                Primitives.collisionBox(size: size, offset: centre - pivot),
            ]))
            hinge.components.set(HoverEffectComponent())

            letters.append(Letter(
                line: lineIndex, hinge: hinge, rest: pivot, body: body,
                finish: finish, dot: dot, dotRest: dotRest,
                size: SIMD2(size.x, size.y), arrival: arrival,
                release: arrival == .drop ? HubTitleMotion.dropRelease(order)
                                          : HubTitleMotion.swingRelease(order)))
        }
        model.removeFromParent()
        content.position = -(lower + upper) / 2
        lineEntities.append(line)
        return (line, upper - lower)
    }

    /// `G3_Letter` → 3.
    private static func glyphIndex(_ name: String) -> Int? {
        guard name.hasPrefix("G"), let underscore = name.firstIndex(of: "_") else { return nil }
        return Int(name[name.index(after: name.startIndex)..<underscore])
    }

    /// The letters' finish: soft white satin — the white of every label in
    /// the room, given a body. A whisper of its own light keeps it white in
    /// a dimmed room; the glint lifts that.
    private static func letterFinish() -> PhysicallyBasedMaterial {
        var satin = PhysicallyBasedMaterial()
        satin.baseColor = .init(tint: UIColor(white: 0.97, alpha: 1))
        satin.metallic = .init(floatLiteral: 0.0)
        satin.roughness = .init(floatLiteral: 0.42)
        satin.clearcoat = .init(floatLiteral: 0.35)
        satin.clearcoatRoughness = .init(floatLiteral: 0.25)
        satin.emissiveColor = .init(color: .white)
        satin.emissiveIntensity = finishRest
        return satin
    }

    /// The i's particle: champagne light, like the opening's particles and
    /// the bezels' alloy.
    private static func particleFinish() -> PhysicallyBasedMaterial {
        var light = PhysicallyBasedMaterial()
        light.baseColor = .init(tint: HubTitleStyle.champagne)
        light.metallic = .init(floatLiteral: 0.3)
        light.roughness = .init(floatLiteral: 0.3)
        light.emissiveColor = .init(color: HubTitleStyle.champagne)
        light.emissiveIntensity = 1.2
        return light
    }

    /// The letters' resting glow, and how far a glint lifts it.
    private static let finishRest: Float = 0.22
    private static let finishGlint: Float = 0.9

    // MARK: Every frame

    /// - Parameters:
    ///   - now: the scene's clock, seconds.
    ///   - arrival: seconds since the home's arrival began, or nil when the
    ///     title did not arrive this time (a walk back, Reduce Motion): it
    ///     is simply there.
    ///   - stillness: Reduce Motion — no wave, no glint, no hop.
    func update(now: Double, arrival: Double?, stillness: Bool) {
        // When the last letter has settled, the wave and the glints take over.
        let settled = arrivalSettles
        let glintClock: Double
        if let arrival {
            let first = Opening.firstGlint
            glintClock = arrival < first ? -1
                : (arrival - first).truncatingRemainder(dividingBy: HubTitleMotion.glintPeriod)
        } else {
            glintClock = now.truncatingRemainder(dividingBy: HubTitleMotion.glintPeriod)
        }

        for i in letters.indices {
            var letter = letters[i]
            let scale = letter.line < lineScales.count ? lineScales[letter.line] : 1
            let x = Double(letter.rest.x * scale)
            var lift = 0.0
            var angle = 0.0
            var visible: Float = 1
            var dotLift = 0.0

            if let arrival, !stillness {
                let since = arrival - letter.release
                if since < 0 {
                    visible = 0
                } else {
                    visible = Float(min(1, since / HubTitleMotion.fadeIn))
                    switch letter.arrival {
                    case .drop:
                        lift += HubTitleMotion.bounce(time: since, height: HubTitleMotion.dropHeight)
                    case .swing:
                        let rate = HubTitleMotion.swingRate(width: Double(letter.size.x * scale),
                                                           height: Double(letter.size.y * scale))
                        angle += HubTitleMotion.swing(time: since, rate: rate)
                    }
                }
                // The particle drops onto its i once the i has landed, and
                // bounces there — the last thing to arrive.
                if letter.dot != nil {
                    let dotSince = arrival - HubTitleMotion.dotRelease(after: letter.release)
                    dotLift = dotSince < 0 ? HubTitleMotion.dotHeight
                        : HubTitleMotion.bounce(time: dotSince, height: HubTitleMotion.dotHeight)
                }
            }

            if !stillness {
                // The wave fades in as the arrival dies away, so nothing jumps.
                let weight = arrival.map { a -> Double in
                    let x = min(max((a - settled) / 1.5, 0), 1)
                    return x * x * (3 - 2 * x)
                } ?? 1
                let wave = HubTitleMotion.wave(at: x, time: now, phase: Double(letter.line) * 0.9)
                lift += wave.lift * weight
                angle += wave.tilt * weight

                if let hop = letter.hopStart {
                    let since = now - hop
                    lift += HubTitleMotion.bounce(time: since, launchSpeed: HubTitleMotion.hopSpeed)
                    if since > HubTitleMotion.bounceDuration(launchSpeed: HubTitleMotion.hopSpeed) {
                        letter.hopStart = nil
                    }
                }
            }

            letter.hinge.position = letter.rest + SIMD3(0, Float(lift) / scale, 0)
            letter.hinge.orientation = simd_quatf(angle: Float(angle), axis: [0, 0, 1])
            letter.dot?.position = letter.dotRest + SIMD3(0, Float(dotLift) / scale, 0)
            if visible != letter.visible {
                if visible >= 1 {
                    letter.hinge.components.remove(OpacityComponent.self)
                } else {
                    letter.hinge.components.set(OpacityComponent(opacity: visible))
                }
                letter.visible = visible
            }

            // The glint: the letter's glow, written only when it changes.
            let lit = stillness ? 0 : Float(HubTitleMotion.glint(at: x, since: glintClock))
            if abs(lit - letter.lit) > 0.01, var finish = letter.finish,
               let body = letter.body, var model = body.components[ModelComponent.self] {
                finish.emissiveIntensity = Self.finishRest + Self.finishGlint * lit
                model.materials = [finish]
                body.components.set(model)
                letter.finish = finish
                letter.lit = lit
            }
            letters[i] = letter
        }
    }

    /// When the slowest letter (or the i's particle) has come to rest,
    /// seconds after the opening began.
    private var arrivalSettles: Double {
        letters.map { letter -> Double in
            let own: Double = switch letter.arrival {
            case .drop:
                letter.release + HubTitleMotion.bounceDuration(height: HubTitleMotion.dropHeight)
            case .swing:
                HubTitleMotion.swingSettles(after: letter.release)
            }
            guard letter.dot != nil else { return own }
            return max(own, HubTitleMotion.dotRelease(after: letter.release)
                       + HubTitleMotion.bounceDuration(height: HubTitleMotion.dotHeight))
        }.max() ?? 0
    }

    // MARK: Taps

    /// A pinch on a letter hops it. True when `entity` was a letter.
    func hop(_ entity: Entity, now: Double, stillness: Bool) -> Bool {
        var current: Entity? = entity
        while let candidate = current {
            if let index = letters.firstIndex(where: { $0.hinge === candidate }) {
                guard !stillness else { return true }
                // A letter already in the air is not thrown again mid-flight.
                if letters[index].hopStart == nil {
                    letters[index].hopStart = now
                    SoundPalette.play(.pop, on: candidate, volume: 0.4)
                }
                return true
            }
            current = candidate.parent
        }
        return false
    }

    /// Every letter hops, a beat apart, left to right and line by line —
    /// what activating the whole wordmark does.
    func hopAll(now: Double, stillness: Bool) {
        guard !stillness else { return }
        let order = letters.indices.sorted {
            (letters[$0].line, letters[$0].rest.x) < (letters[$1].line, letters[$1].rest.x)
        }
        for (step, index) in order.enumerated() where letters[index].hopStart == nil {
            letters[index].hopStart = now + Double(step) * 0.045
        }
        if let first = letters.first { SoundPalette.play(.chime, on: first.hinge, volume: 0.35) }
    }

    /// The letters are pinch targets, so the wordmark must be operable
    /// without hands too: it is one VoiceOver element, and activating it
    /// hops every letter in a ripple. One element for the whole title, not
    /// seventeen for its letters.
    func makeOperable(_ anchor: Entity, label: String,
                      now: @escaping () -> Double, stillness: @escaping () -> Bool) {
        SpatialActions.attach(to: anchor, label: label, activate: { [weak self] in
            self?.hopAll(now: now(), stillness: stillness())
        })
    }

    /// The hinges, for tests.
    var letterEntities: [Entity] { letters.map(\.hinge) }
    /// The i's particle, for tests.
    var dotEntity: Entity? { letters.lazy.compactMap(\.dot).first }
}

