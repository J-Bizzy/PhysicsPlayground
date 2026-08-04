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
//    an electron on a genuinely TILTED orbit crossing the sign — a
//    planar ellipse whose depth amplitude overshoots the letter
//    extrusion, so the spark swings well in front on the bottom of the
//    lap and solidly behind on the top, with real parallax — sped up
//    through the near pass and eased over the far one, Kepler-fashion.
//    Mechanics gets a ball BOUNCING along the rule under the letters:
//    a chain of decaying parabolic hops, reversing at the ends — the
//    classic mechanics demo, and non-intersection with the type is
//    guaranteed by construction instead of hoped for (the 2026-08-03
//    pass caught the old single lob still clipping glyphs). Cadences
//    are signage cadences; the SHAPES (an ellipse, true parabolas, a
//    trail fading along them) are the honest part.
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
        let beadRadius: Float = domain == .mechanics
            ? Self.ballRadius : 0.011
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
            // A soft halo riding the spark — an electron is a point of
            // light, and a bare matte sphere read as a bead on a wire.
            var halo = UnlitMaterial(color: electron)
            halo.blending = .transparent(opacity: 0.22)
            bead.addChild(ModelEntity(mesh: .generateSphere(radius: 0.02),
                                      materials: [halo]))
            // A LONG wake: nine exposures close together, so the lap
            // reads as a streak of motion rather than four dots.
            trail = (0..<9).map { _ in Self.spark(radius: 0.007, color: electron) }
        case .mechanics:
            // The ball. No standing track — the TRAIL is the hop chain,
            // redrawn by motion every crossing, which is the honest way
            // to show a trajectory: it exists because something flew.
            let ball = UIColor(DesignTokens.Palette.projectile)
            bead = Self.spark(radius: Self.ballRadius, color: ball)
            trail = (0..<6).map { _ in Self.spark(radius: 0.0075, color: ball) }
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
        // trails — exposures of where the body just was, packed tighter
        // for the electron so its lap reads as a streak.
        let lagStep = domain == .electricity ? 0.04 : 0.055
        for (index, ghost) in trail.enumerated() {
            let lag = Double(index + 1) * lagStep
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
            // One lap every 4.5 s, counter-clockwise as read — with the
            // Kepler cadence: fastest through the near pass at the
            // bottom of the lap, easing over the far pass at the top.
            // θ(u) = u + k·cos(u) is monotonic for k < 1, leaves the
            // two poles exactly where uniform time would put them, and
            // its rate 1 − k·sin(u) peaks at the bottom — an honest
            // equal-areas flavour, not a tween.
            let u = Float(time / 4.5 * 2 * .pi)
            let theta = u + orbitSpeedShape * cos(u)
            return orbitPoint(theta: theta, halfWidth: halfWidth,
                              halfHeight: halfHeight,
                              frontLane: frontLane, backLane: backLane)
        case .mechanics:
            // THE TRAVELLING BOUNCE (owner's pick, 2026-08-03): the
            // ball crosses the rule under the letters as a chain of
            // decaying parabolic hops, then turns round and comes back.
            // The single over-the-top lob it replaces could not be made
            // safe — clearing a word six times wider than it is tall
            // needs a ~0.4 m apex over a door sign — and it clipped
            // glyphs on device. Down here, non-intersection is true BY
            // CONSTRUCTION: every hop's apex is capped below the
            // letters' baseline, so there is no frame in which ball and
            // type can meet. Each hop is a true parabola and the decay
            // is a restitution, which is the classic mechanics demo
            // anyway — a bouncing ball, losing a bit each bounce.
            let crossing = Int(floor(time / crossingPeriod))
            let s = Float(time / crossingPeriod
                          - floor(time / crossingPeriod))
            let direction: Float = crossing.isMultiple(of: 2) ? 1 : -1
            let x = direction * (s * 2 - 1) * (halfWidth * launchReach)

            // Which hop this instant of the crossing is in. Hop heights
            // decay geometrically; hop durations go as √h, as real
            // bounces do.
            var y = ruleY + ballRadius
            var start: Float = 0
            for (index, width) in hopFractions.enumerated() {
                let end = start + width
                if s <= end || index == hopFractions.count - 1 {
                    let u = min(max((s - start) / width, 0), 1)
                    let height = hopHeight * pow(hopDecay, Float(index))
                    y += 4 * height * u * (1 - u)
                    break
                }
                start = end
            }
            // The whole run happens in the front lane — below the
            // letters anyway, but a bounce half-buried in the plaque's
            // extrusion would still read wrong edge-on.
            return SIMD3(x, y, frontLane)
        }
    }

    /// The electron's orbit: a planar ellipse genuinely TILTED out of
    /// the sign — y and z both ride sin θ, so the path lies in one
    /// slanted plane — crossing the lockup so the top of the lap passes
    /// BEHIND real glyphs and the bottom swings well in front. The
    /// depth amplitude deliberately overshoots the measured lanes
    /// (`orbitDepthGain`): the spark is solidly clear of the letters
    /// for most of the lap and sweeps through the extrusion band only
    /// near θ = 0 and π — the far left and right, where the lockup's
    /// two lines leave a leading gap and there is nothing to clip.
    /// The overshoot is also the parallax: the near pass comes ~9 cm
    /// off the plaque toward the viewer, which is what makes the orbit
    /// read as a thing in space rather than a decal.
    ///
    /// It CROSSES the lockup on purpose. The first pass hung the ellipse
    /// outside the type on every side, which meant the "behind" half had
    /// no letter in front of it to be hidden by. A semi-axis inside the
    /// block's half-width puts the spark behind actual glyphs on the top
    /// of the lap, which is the entire effect this orbit exists to
    /// produce.
    nonisolated static func orbitPoint(
        theta: Float, halfWidth: Float, halfHeight: Float,
        frontLane: Float, backLane: Float
    ) -> SIMD3<Float> {
        let mid = (frontLane + backLane) / 2
        let swing = (frontLane - backLane) / 2
        return SIMD3(cos(theta) * (halfWidth * orbitReach),
                     sin(theta) * (halfHeight + orbitRise),
                     mid - sin(theta) * swing * orbitDepthGain)
    }

    // MARK: The numbers the two paths are cut to

    /// How far the ball's turnaround points sit outboard of the type,
    /// as a multiple of the lockup's half-width.
    nonisolated static let launchReach: Float = 1.06
    /// The rule's width as a multiple of the lockup's — wide enough that
    /// the ball's whole run stays on it, not past it.
    nonisolated static let ruleOverhang: Float = 1.16
    /// One left-to-right crossing of the rule, seconds.
    nonisolated static let crossingPeriod = 3.6
    /// The ball's radius — shared with the tests, because the hop cap
    /// is measured to the ball's SKIN, not its centre.
    nonisolated static let ballRadius: Float = 0.012
    /// The first hop's height. Capped so apex + a ball radius stays
    /// below the letters' baseline: the rule hangs 0.055 m under the
    /// block, and 0.030 + two radii = 0.054 clears it by a millimetre
    /// everywhere a sign can be built.
    nonisolated static let hopHeight: Float = 0.030
    /// Restitution between hops.
    nonisolated static let hopDecay: Float = 0.55
    /// Each hop's share of a crossing — durations ∝ √height, as real
    /// bounces are, normalised to sum to 1.
    nonisolated static let hopFractions: [Float] = {
        let roots = (0..<3).map { sqrt(pow(hopDecay, Float($0))) }
        let total = roots.reduce(0, +)
        return roots.map { $0 / total }
    }()
    /// The electron ellipse's horizontal semi-axis, as a multiple of the
    /// lockup's half-width. Inside 1, so the lap crosses the letters.
    nonisolated static let orbitReach: Float = 0.88
    /// How far the ellipse rises above the block, metres. Small: the
    /// lap has to spend real time INSIDE the letters' silhouette, and
    /// an ellipse that clears the block vertically never does.
    nonisolated static let orbitRise: Float = 0.035
    /// How far the depth amplitude overshoots the measured lanes. 1
    /// would just graze them at the poles and leave the spark half-sunk
    /// for most of the lap.
    nonisolated static let orbitDepthGain: Float = 2.2
    /// How hard the Kepler cadence leans — 0 is uniform speed.
    nonisolated static let orbitSpeedShape: Float = 0.35
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
