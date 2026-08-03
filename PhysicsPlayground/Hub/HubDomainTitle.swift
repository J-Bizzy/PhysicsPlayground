//
//  HubDomainTitle.swift
//  Physics Playground — Hub
//
//  The three-dimensional signage over each door: the domain's name in
//  the app's signature bubble type, set in the domain's own colour,
//  with one kinetic element apiece doing that domain's physics.
//
//  Owner's call, 2026-07-30 — and it reverses an earlier doctrine, so
//  the reversal is worth a word. The Gallery shipped with "no floating
//  text headers": four terraces of two modules each were legible as a
//  crescent, and colour alone could carry the grouping. Two terraces of
//  three are a different room. The terraces ARE the app's two doors
//  now, the domain IS the choice the Home Screen exists to offer, and a
//  door without a name over it reads as someone's shelf — the same
//  argument that brought the wordmark back (DECISIONS.md, 2026-07-29),
//  one level down.
//
//  The design language is inherited, not invented:
//  · The TYPE comes from `HubTitleStyle` — the same engine the wordmark
//    uses, so the home's three display texts cannot disagree. What
//    changes per sign is the colour: the
//    letters carry the DOMAIN accent, which until now appeared only in
//    each slab's hairline, the progress rings, and the focus chip.
//    Signage joins that short list.
//  · The LOCKUP is the wordmark's flush-both-sides two-line math:
//    lines measured, scaled to a common width, stacked with leading
//    derived from their real cap height.
//  · The MOTION follows the vignette doctrine — every animated thing
//    in the hub does the physics of the module it stands for. E&M gets
//    an electron riding a tilted orbit ACROSS the sign (in front at
//    the bottom of the lap, behind at the top — the pass that sells
//    the letters as solids). Mechanics gets a ball lobbed over the
//    sign on a parabola, launching and landing on the overhanging ends
//    of the rule. Cadences are signage cadences, chosen to be read
//    at a glance — the same licence the miniatures already take; the
//    SHAPES (an ellipse, a parabola, a trail fading along it) are the
//    honest part.
//  · The DEPTH is measured, not chosen. Both bodies fly in lanes
//    derived from the finished letters' own visual bounds, because the
//    letters are extruded solids whose depth changes with the voice,
//    the line and the sign's width. See `frontLane`.
//

import RealityKit
import RenderKit
import SwiftUI
import simd

@MainActor
final class HubDomainTitle {
    let root = Entity()

    private let domain: HubDomain
    /// Half-size of the finished lockup, for the kinetic paths.
    private let halfWidth: Float
    private let halfHeight: Float
    /// The rule under the lockup — shimmerable, like the hairline
    /// below it on the slab.
    private let rule: ModelEntity
    /// The moving body (electron or ball) and its fading wake.
    private let bead: ModelEntity
    private let trail: [ModelEntity]
    /// Where the rule sits, for the Mechanics launch/land points.
    private let ruleY: Float

    /// The two depth lanes the kinetic bodies fly in: clear of the
    /// letters' front faces, and clear of everything behind them.
    ///
    /// MEASURED, never assumed. `generateText` extrudes the glyphs along
    /// z into real solids, each voice stacks its own passes at its own
    /// offsets, and the flush lockup scales all of it per line — so the
    /// depth the letters occupy is a different number for every sign in
    /// the app. The ball flew at a hardcoded z = 0.02 for exactly as
    /// long as it took someone to put the headset on: the plaque's
    /// letters are ~55 mm deep, so 20 mm put the ball INSIDE the type it
    /// was supposed to clear. Nothing about that is visible in a
    /// screenshot taken head-on, which is the whole reason this file
    /// measures instead of guessing.
    private(set) var frontLane: Float = 0
    private(set) var backLane: Float = 0

    /// The signage face, built at this size and scaled per line.
    private static let reference: CGFloat = 0.12
    /// Leading between the two lines, as a fraction of cap height.
    private static let leading: Float = 0.34

    /// The two lines per domain — near-equal character counts, so the
    /// flush-width lockup scales them to almost the same letter size
    /// and the pair reads as set type rather than an accident.
    private static func lines(for domain: HubDomain) -> [String] {
        switch domain {
        case .electricity: ["Electricity", "& Magnetism"]
        case .mechanics: ["Mechanics", "& Energy"]
        }
    }

    init(domain: HubDomain, width: Float) {
        self.domain = domain
        halfWidth = width / 2

        let accent = UIColor(domain.color)
        let texts = Self.lines(for: domain)

        // The wordmark's lockup math: measure both lines, scale each to
        // the common width, stack with cap-height leading, centre the
        // block on the anchor.
        let built = texts.map { text -> (entity: Entity, extents: SIMD3<Float>) in
            (HubTitleStyle.line(text, size: Self.reference, accent: accent),
             HubTitleStyle.extents(text, size: Self.reference))
        }
        let scales = built.map { width / max($0.extents.x, 1e-4) }
        let heights = zip(built, scales).map { $0.0.extents.y * $0.1 }
        // Leading off the TALLEST line, not the average. The flush
        // lockup scales a short line up (7-character "Physics" against
        // 10-character "Playground"), so its cap height can far exceed
        // the mean — and an average-derived gap then lets the tall line
        // collide with its neighbour. Uppercase makes it worse, which
        // is how the plaque exposed it.
        let gap = (heights.max() ?? 0) * HubTitleStyle.leadingFactor
        let blockHeight = heights.reduce(0, +) + gap * Float(heights.count - 1)
        halfHeight = blockHeight / 2

        var cursor = blockHeight / 2
        for (index, item) in built.enumerated() {
            item.entity.scale = SIMD3(repeating: scales[index])
            item.entity.position.y = cursor - heights[index] / 2
            root.addChild(item.entity)
            cursor -= heights[index] + gap
        }

        // How deep the finished letters actually are. Only the two lines
        // are on `root` at this point, so this is the type and nothing
        // else — every pass, every per-style offset, every per-line
        // scale, in one measurement.
        let letters = root.visualBounds(relativeTo: root)
        let beadRadius: Float = domain == .mechanics ? 0.014 : 0.011
        frontLane = letters.max.z + beadRadius + Self.laneClearance
        backLane = letters.min.z - beadRadius - Self.laneClearance

        // The rule, in the domain accent — the same lit line as the
        // slab hairline below it, so sign and shelf read as one lamp.
        //
        // Wider than the type it underlines, by design: the Mechanics
        // ball launches and lands on its ends, and ends that sit UNDER
        // the letters (the original width * 0.92) meant every throw
        // began and finished inside the word. A rule that overhangs is
        // also just better signage — it reads as a bar the words rest
        // on rather than a shy dash trapped beneath them.
        var ruleMaterial = UnlitMaterial(color: accent)
        ruleMaterial.blending = .transparent(opacity: 0.7)
        ruleY = -blockHeight / 2 - 0.055
        rule = ModelEntity(
            mesh: .generateBox(width: width * Self.ruleOverhang, height: 0.0035,
                               depth: 0.0035, cornerRadius: 0.0017),
            materials: [ruleMaterial])
        rule.position = SIMD3(0, ruleY, 0)
        root.addChild(rule)

        // The kinetic element, per domain.
        switch domain {
        case .electricity:
            // The electron and its orbit track — a tilted ellipse
            // hugging the lockup. The track is drawn faint so the
            // moving spark reads against it the way the palette bead's
            // ring does: an orbit, not a firefly.
            let electron = UIColor(Color(uiColor: DesignTokens.Palette.electronUI))
            var trackMaterial = UnlitMaterial(color: electron)
            trackMaterial.blending = .transparent(opacity: 0.20)
            // Locals, not properties: the map's closure must not capture
            // self while `bead` and `trail` are still uninitialised.
            let (signHalfWidth, signHalfHeight) = (halfWidth, halfHeight)
            let (front, back) = (frontLane, backLane)
            let points = (0...64).map { step -> SIMD3<Float> in
                Self.orbitPoint(theta: Float(step) / 64 * 2 * .pi,
                                halfWidth: signHalfWidth,
                                halfHeight: signHalfHeight,
                                frontLane: front, backLane: back)
            }
            if let mesh = TubeMesh.tube(lines: [points], radius: 0.0015, sides: 5) {
                root.addChild(ModelEntity(mesh: mesh, materials: [trackMaterial]))
            }
            bead = Self.spark(radius: 0.011, color: electron)
            trail = (0..<4).map { _ in Self.spark(radius: 0.0075, color: electron) }
        case .mechanics:
            // The ball. No standing track — the TRAIL is the parabola,
            // redrawn by motion every crossing, which is the honest way
            // to show a trajectory: it exists because something flew.
            let ball = UIColor(DesignTokens.Palette.projectile)
            bead = Self.spark(radius: 0.014, color: ball)
            trail = (0..<5).map { _ in Self.spark(radius: 0.0085, color: ball) }
        }
        root.addChild(bead)
        trail.forEach { root.addChild($0) }

        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = LocalizedStringResource(stringLiteral: domain.title)
        root.components.set(accessibility)

        // Park everything at its rest pose so the first frame — and a
        // reduce-motion session's every frame — is composed, not raw.
        animate(time: 0, stillness: true)
    }

    // MARK: Per-frame

    /// Drive the sign. `stillness` (reduce-motion, or the room asleep)
    /// parks the kinetic body at its rest pose with its wake faded —
    /// the sign stays a finished object, it just stops performing.
    func animate(time: Double, stillness: Bool) {
        if stillness {
            place(beadAt: 0)
            for ghost in trail {
                ghost.components.set(OpacityComponent(opacity: 0))
            }
            rule.components.set(OpacityComponent(opacity: 0.7))
            return
        }

        // The rule shimmers on the same slow clock as the slab
        // hairlines, so lamp and lamp agree.
        let shimmer = 0.62 + 0.18 * Float(sin(time * 0.5 + Double(domain.hashValue % 5)))
        rule.components.set(OpacityComponent(opacity: shimmer))

        place(beadAt: time)
        // The wake rides the same path a beat behind, fading as it
        // trails — five exposures of where the body just was.
        for (index, ghost) in trail.enumerated() {
            let lag = Double(index + 1) * 0.055
            ghost.position = Self.path(for: domain, time: time - lag,
                                       halfWidth: halfWidth,
                                       halfHeight: halfHeight, ruleY: ruleY,
                                       frontLane: frontLane, backLane: backLane)
            ghost.components.set(OpacityComponent(
                opacity: 0.55 * (1 - Float(index) / Float(trail.count))))
        }
    }

    private func place(beadAt time: Double) {
        bead.position = Self.path(for: domain, time: time,
                                  halfWidth: halfWidth,
                                  halfHeight: halfHeight, ruleY: ruleY,
                                  frontLane: frontLane, backLane: backLane)
    }

    // MARK: The two paths — pure functions, so the tests can hold them

    /// Where the kinetic body is at `time`. Static and deterministic:
    /// the tests check the electron stays on its ellipse and the ball's
    /// arc actually clears the sign and lands back on the rule.
    nonisolated static func path(
        for domain: HubDomain, time: Double,
        halfWidth: Float, halfHeight: Float, ruleY: Float,
        frontLane: Float, backLane: Float
    ) -> SIMD3<Float> {
        switch domain {
        case .electricity:
            // One lap every 4.5 s, counter-clockwise as read.
            let theta = Float(time / 4.5 * 2 * .pi)
            return orbitPoint(theta: theta, halfWidth: halfWidth,
                              halfHeight: halfHeight,
                              frontLane: frontLane, backLane: backLane)
        case .mechanics:
            // A 2.8 s lob from one end of the rule to the other, then
            // back the other way — a ball kept in play, not a loop.
            // The arc is a true parabola: y is quadratic in horizontal
            // progress, apex clearing the top of the letters.
            //
            // It launches OUTBOARD of the type, off the overhanging
            // ends of the rule. It used to launch at 0.92 halfWidth —
            // under the letters — and a parabola that starts under a
            // word 6 times wider than it is tall has no way out through
            // the top: it would need a metre of apex over a 20 cm sign.
            // Starting outside the word is what buys the arc its
            // clearance at both shoulders.
            let period = 2.8
            let crossing = Int(floor(time / period))
            let s = Float(time / period - floor(time / period))
            let direction: Float = crossing.isMultiple(of: 2) ? 1 : -1
            let x = direction * (s * 2 - 1) * (halfWidth * launchReach)
            let apex = halfHeight + 0.13 - ruleY
            let y = ruleY + apex * 4 * s * (1 - s)
            // The whole flight happens in the front lane, so the ball
            // passes the letters instead of through them.
            return SIMD3(x, y, frontLane)
        }
    }

    /// The electron's ellipse: crossing the lockup, tilted in z so the
    /// lap passes IN FRONT across the bottom and BEHIND across the top
    /// — the depth crossing is what makes the letters read as solids.
    ///
    /// It CROSSES the lockup on purpose. The first pass hung the ellipse
    /// outside the type on every side (halfWidth + 0.09), which meant
    /// the "behind" half had no letter in front of it to be hidden by:
    /// the depth swap was real in the transform and invisible to the
    /// eye. A semi-axis inside the block's half-width puts the spark
    /// behind actual glyphs on the top of the lap, which is the entire
    /// effect this orbit exists to produce.
    nonisolated static func orbitPoint(
        theta: Float, halfWidth: Float, halfHeight: Float,
        frontLane: Float, backLane: Float
    ) -> SIMD3<Float> {
        let mid = (frontLane + backLane) / 2
        let swing = (frontLane - backLane) / 2
        // Depth eases like a tanh, not a sine. A sine spends most of
        // the lap part-buried in the letters and only reaches a clean
        // lane at the two poles — the spark reads as half-sunk for most
        // of the orbit and the crossing never resolves. Shaped this way
        // it sits SOLIDLY behind for most of the top half and SOLIDLY
        // in front for most of the bottom, and does its swapping at
        // theta 0 and pi, the far left and right of the ellipse, where
        // it is clear of the type anyway. x and y are untouched: the
        // spark is still exactly on its drawn track.
        let s = tanh(orbitSnap * sin(theta)) / tanh(orbitSnap)
        return SIMD3(cos(theta) * (halfWidth * orbitReach),
                     sin(theta) * (halfHeight + orbitRise),
                     mid - s * swing)
    }

    // MARK: The numbers the two paths are cut to

    /// How far the ball's launch and landing sit outboard of the type,
    /// as a multiple of the lockup's half-width.
    nonisolated static let launchReach: Float = 1.06
    /// The rule's width as a multiple of the lockup's — wide enough that
    /// the ball's landing points are on it, not past it.
    nonisolated static let ruleOverhang: Float = 1.16
    /// The electron ellipse's horizontal semi-axis, as a multiple of the
    /// lockup's half-width. Inside 1, so the lap crosses the letters.
    nonisolated static let orbitReach: Float = 0.88
    /// How far the ellipse rises above the block, metres. Small: the
    /// lap has to spend real time INSIDE the letters' silhouette, and
    /// an ellipse that clears the block vertically never does.
    nonisolated static let orbitRise: Float = 0.035
    /// How hard the depth eases between lanes. 0 would be a plain sine.
    nonisolated static let orbitSnap: Float = 2.2
    /// Air between a kinetic body's skin and the letters it passes.
    nonisolated static let laneClearance: Float = 0.013

    // MARK: Parts

    /// A small self-lit body for the kinetic elements — unlit, because
    /// an electron and a flying ball are the two brightest things on
    /// the sign by design.
    private static func spark(radius: Float, color: UIColor) -> ModelEntity {
        ModelEntity(mesh: .generateSphere(radius: radius),
                    materials: [UnlitMaterial(color: color)])
    }
}
