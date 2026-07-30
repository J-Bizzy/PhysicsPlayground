//
//  HubTitleStyle.swift
//  Physics Playground — Hub
//
//  One typographic voice for the home's three display texts — the
//  wordmark and the two door signs — switchable, so candidate voices
//  can be auditioned in the room rather than argued about in the
//  abstract. `-titleStyle 1|2|3` (DEBUG) renders the whole home in a
//  candidate; absent, the shipping style applies.
//
//  DELIBERATELY NOT the style of every text in the hub. The exhibit
//  nameplates and the Well glyphs keep `HubScene.bubbleText` whatever
//  this enum says: they are labels on objects, this is display type,
//  and restyling forty labels because the marquee changed would be the
//  tail wagging the dog. If a candidate is chosen and the labels
//  should follow, that is its own decision.
//
//  The four voices:
//  · .bubble — the original: fat rounded glyphs, glossy clearcoat,
//    concentric plate/rim passes. Toy-museum warmth.
//  · .frosted — SF Pro semibold, shallow depth, translucent frosted
//    letters with a soft accent edge-light behind them. The room shows
//    through the type; the quietest, most visionOS voice.
//  · .plaque — widetracked-feeling uppercase bold, deep extrusion,
//    brushed metal with a polished clearcoat. Museum plaque, flight
//    hardware.
//  · .poster — near-flat black-weight grotesque in solid colour over a
//    hard offset shadow plate. The wordmark's own header derides hard
//    offset shadows for GLOSSY type, and it is right — but poster is a
//    GRAPHIC treatment, not a lighting model: the offset plate is the
//    design itself (Swiss poster, editorial), not a cheap cue for
//    depth the material should have carried.
//

import RealityKit
import SwiftUI
import UIKit

enum HubTitleStyle: Int, CaseIterable {
    case bubble = 0
    case frosted = 1
    case plaque = 2
    case poster = 3

    /// The style the home renders in. DEBUG launch arg `-titleStyle N`
    /// overrides for auditioning; otherwise the shipping choice.
    static var current: HubTitleStyle {
        #if DEBUG
        if let forced = HubTitleStyle(
            rawValue: UserDefaults.standard.integer(forKey: "titleStyle")),
           forced != .bubble || UserDefaults.standard.object(forKey: "titleStyle") != nil {
            return forced
        }
        #endif
        return .bubble
    }

    // MARK: The voice's parameters

    /// How the words are cased. The plaque speaks in capitals.
    func display(_ text: String) -> String {
        self == .plaque ? text.uppercased() : text
    }

    /// The face. All are the system family so dynamic content never
    /// falls back mid-word; the VOICE lives in design, weight and case.
    func font(size: CGFloat) -> MeshResource.Font {
        switch self {
        case .bubble:
            let base = UIFont.systemFont(ofSize: size, weight: .heavy)
            if let descriptor = base.fontDescriptor.withDesign(.rounded) {
                return UIFont(descriptor: descriptor, size: size)
            }
            return base
        case .frosted: return .systemFont(ofSize: size, weight: .semibold)
        case .plaque: return .systemFont(ofSize: size, weight: .bold)
        case .poster: return .systemFont(ofSize: size, weight: .black)
        }
    }

    /// Leading multiplier. The plaque needs more air: it is the only
    /// voice set in CAPITALS, so both lines are cap-height tall, and
    /// the flush lockup scales the shorter word up hard — two full-cap
    /// lines at different scales close the gap from both sides at once.
    var leadingFactor: Float {
        self == .plaque ? 0.62 : 0.34
    }

    /// Extrusion as a fraction of point size: the frosted pane and the
    /// poster are nearly flat, the plaque is milled from stock.
    var extrusionFactor: Float {
        switch self {
        case .bubble: 0.45
        case .frosted: 0.12
        case .plaque: 0.55
        case .poster: 0.07
        }
    }

    // MARK: Building

    func mesh(_ text: String, size: CGFloat) -> MeshResource {
        MeshResource.generateText(
            display(text), extrusionDepth: Float(size) * extrusionFactor,
            font: font(size: size), alignment: .center)
    }

    /// Measured extents in THIS voice — case, face and depth included,
    /// so the flush-width lockup math never mixes styles.
    func extents(_ text: String, size: CGFloat) -> SIMD3<Float> {
        mesh(text, size: size).bounds.extents
    }

    /// One line of display type, centred on its own origin.
    /// `accent` nil is the wordmark's neutral role; a colour is a door
    /// sign speaking in its domain's voice.
    @MainActor
    func line(_ text: String, size: CGFloat, accent: UIColor?) -> Entity {
        let group = Entity()
        let mesh = mesh(text, size: size)
        let bounds = mesh.bounds
        let recenter = SIMD3<Float>(-(bounds.min.x + bounds.max.x) / 2,
                                    -(bounds.min.y + bounds.max.y) / 2, 0)

        func pass(_ material: RealityKit.Material, scale: Float = 1,
                  offset: SIMD3<Float> = .zero) {
            let model = ModelEntity(mesh: mesh, materials: [material])
            model.position = recenter
            let wrapper = Entity()
            wrapper.addChild(model)
            wrapper.scale = SIMD3(repeating: scale)
            wrapper.position = offset
            group.addChild(wrapper)
        }

        let s = Float(size)
        switch self {
        case .bubble:
            // The original three concentric passes: dark plate for
            // contrast against any wall, lit rim just proud of the
            // glyphs, glossy letters on top.
            pass(Self.unlit(UIColor(white: 0.03, alpha: 1), opacity: 0.45),
                 scale: 1.10, offset: SIMD3(0, 0, -0.13 * s))
            let rimColor = accent.map(Self.lightened) ?? Self.champagne
            pass(Self.glossy(rimColor, opacity: 0.55, emissive: 0.85),
                 scale: 1.042, offset: SIMD3(0, 0, -0.055 * s))
            pass(Self.glossy(accent ?? Self.ivory, opacity: 1,
                             emissive: accent == nil ? 0.32 : 0.5))

        case .frosted:
            // A faint dark pane and a soft accent edge-light behind
            // translucent letters — the etched-glass gallery voice.
            pass(Self.unlit(UIColor(white: 0.05, alpha: 1), opacity: 0.22),
                 scale: 1.08, offset: SIMD3(0, 0, -0.10 * s))
            pass(Self.unlit(accent ?? Self.champagne, opacity: 0.42),
                 scale: 1.035, offset: SIMD3(0, 0, -0.05 * s))
            var glass = PhysicallyBasedMaterial()
            glass.baseColor = .init(tint: UIColor(white: 0.97, alpha: 1))
            glass.roughness = 0.5
            glass.metallic = 0.0
            glass.clearcoat = .init(floatLiteral: 0.6)
            glass.clearcoatRoughness = .init(floatLiteral: 0.2)
            glass.blending = .transparent(opacity: 0.55)
            glass.emissiveColor = .init(color: UIColor(white: 0.9, alpha: 1))
            glass.emissiveIntensity = 0.12
            pass(glass)

        case .plaque:
            // Milled from stock: a dark shadow directly behind, then
            // brushed metal — steel for the wordmark, the domain accent
            // alloyed 30% toward steel for the signs so the colour
            // reads as anodised rather than painted.
            //
            // The shadow is NOT scaled up. A 6% larger copy is only
            // invisible when the line is small; the flush lockup scales
            // a short word up hard, and 6% of a big line reads as a
            // second, ghosted set of letters. Depth alone here.
            pass(Self.unlit(UIColor(white: 0.02, alpha: 1), opacity: 0.55),
                 offset: SIMD3(0, 0, -0.30 * s))
            var metal = PhysicallyBasedMaterial()
            let stock = accent.map { Self.blend($0, toward: UIColor(white: 0.72, alpha: 1), by: 0.30) }
                ?? UIColor(white: 0.78, alpha: 1)
            metal.baseColor = .init(tint: stock)
            // Not a mirror. At metallic 1.0 a surface shows only what
            // it reflects, and a passthrough room gives RealityKit
            // almost nothing to reflect — the letters came out muddy
            // grey. Backing off to 0.75 with a little emissive keeps
            // the brushed read while letting base colour carry.
            metal.metallic = 0.75
            metal.roughness = 0.30
            metal.clearcoat = .init(floatLiteral: 0.7)
            metal.clearcoatRoughness = .init(floatLiteral: 0.15)
            metal.emissiveColor = .init(color: stock)
            metal.emissiveIntensity = 0.22
            pass(metal)

        case .poster:
            // Solid colour over a hard offset plate — down and to the
            // right, the classic print drop. See the header for why
            // this shadow is the one deliberate exception to the
            // no-offset-shadows rule.
            pass(Self.unlit(UIColor(white: 0.04, alpha: 1), opacity: 0.9),
                 offset: SIMD3(0.055 * s, -0.055 * s, -0.03 * s))
            pass(Self.unlit(accent ?? Self.ivory, opacity: 1))
        }
        return group
    }

    /// A finished flush-both-sides lockup in this voice: lines measured,
    /// scaled to a common width, stacked with cap-height leading,
    /// centred on the returned entity's origin. The wordmark and the
    /// door signs run this math inline (they need the intermediate
    /// heights for their own furniture); the audition wall just wants
    /// the finished block.
    @MainActor
    func lockup(_ lines: [String], width: Float, accent: UIColor?) -> Entity {
        let group = Entity()
        let reference: CGFloat = 0.12
        let built = lines.map { text -> (entity: Entity, extents: SIMD3<Float>) in
            (line(text, size: reference, accent: accent),
             extents(text, size: reference))
        }
        let scales = built.map { width / max($0.extents.x, 1e-4) }
        let heights = zip(built, scales).map { $0.0.extents.y * $0.1 }
        // Leading off the TALLEST line, not the average. The flush
        // lockup scales a short line up (7-character "Physics" against
        // 10-character "Playground"), so its cap height can far exceed
        // the mean — and an average-derived gap then lets the tall line
        // collide with its neighbour. Uppercase makes it worse, which
        // is how the plaque candidate exposed it.
        let gap = (heights.max() ?? 0) * leadingFactor
        let blockHeight = heights.reduce(0, +)
            + gap * Float(max(heights.count - 1, 0))
        var cursor = blockHeight / 2
        for (index, item) in built.enumerated() {
            item.entity.scale = SIMD3(repeating: scales[index])
            item.entity.position.y = cursor - heights[index] / 2
            group.addChild(item.entity)
            cursor -= heights[index] + gap
        }
        return group
    }

    // MARK: Shared tones

    /// The wordmark's neutral letters and its champagne — the same two
    /// tones the original bubble treatment set; every style speaks its
    /// neutral role in them so the podium rim and the title rule (also
    /// champagne) keep matching whatever voice is on.
    static let ivory = UIColor(red: 0.99, green: 0.98, blue: 0.95, alpha: 1)
    static let champagne = UIColor(red: 1.0, green: 0.88, blue: 0.70, alpha: 1)

    // MARK: Material helpers

    private static func unlit(_ color: UIColor, opacity: Float) -> UnlitMaterial {
        var material = UnlitMaterial(color: color)
        if opacity < 1 {
            material.blending = .transparent(opacity: .init(floatLiteral: opacity))
        }
        return material
    }

    private static func glossy(_ color: UIColor, opacity: Float,
                               emissive: Float) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: color)
        material.roughness = 0.16
        material.metallic = 0.0
        material.clearcoat = .init(floatLiteral: 1.0)
        material.clearcoatRoughness = .init(floatLiteral: 0.12)
        material.emissiveColor = .init(color: color)
        material.emissiveIntensity = emissive
        if opacity < 1 {
            material.blending = .transparent(opacity: .init(floatLiteral: opacity))
        }
        return material
    }

    /// A derived tint of a canonical colour, never a new hue.
    static func lightened(_ color: UIColor) -> UIColor {
        blend(color, toward: .white, by: 0.55)
    }

    static func blend(_ color: UIColor, toward target: UIColor,
                      by fraction: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        color.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        target.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(red: r1 + (r2 - r1) * fraction,
                       green: g1 + (g2 - g1) * fraction,
                       blue: b1 + (b2 - b1) * fraction,
                       alpha: a1)
    }
}
