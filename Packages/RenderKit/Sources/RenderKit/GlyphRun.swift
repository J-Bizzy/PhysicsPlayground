//
//  GlyphRun.swift
//  RenderKit
//
//  One line of text made of cached glyphs. A live readout — a ball's speed
//  in flight, the aim bead's angle while it is dragged — changes its string
//  several times a second, and `MeshResource.generateText` for every new
//  string cost a frame each time: Projectiles with its numbers on dropped a
//  frame every few tenths of a second. Here each character is generated
//  once per size and kept; a new string only hands the run's entities their
//  glyphs and moves them along the line by the font's own advances.
//
//  Kerning is the price: none is applied. For the numbers, units and short
//  names a readout carries, it does not show.
//

import RealityKit
import UIKit

@MainActor
public final class GlyphRun {
    /// Add this where the line should stand; the run is centred on it.
    public let root = Entity()
    /// The laid-out line's bounds, in `root`'s space, after centring.
    public private(set) var bounds = BoundingBox()

    private let size: CGFloat
    private var material: UnlitMaterial
    private var color: UIColor
    private var glyphs: [ModelEntity] = []

    public init(size: CGFloat, color: UIColor) {
        self.size = size
        self.color = color
        material = Self.material(color)
    }

    /// Recolours every glyph, only when the colour changes.
    public func setColor(_ color: UIColor) {
        guard color != self.color else { return }
        self.color = color
        material = Self.material(color)
        for glyph in glyphs { glyph.model?.materials = [material] }
    }

    /// Lays `text` out centred on `root`: one line, or one per "\n", each
    /// centred over the next as the whole-string mesh set them. A "\n"
    /// was a zero-width character here until 2026-10-27, and three
    /// readouts ran their lines together ("Caught2.31 m/s").
    @discardableResult
    public func set(_ text: String) -> BoundingBox {
        var lower = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var upper = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        var used = 0
        var placed: [(entity: ModelEntity, position: SIMD3<Float>)] = []
        let leading = Float(Self.font(size: size).lineHeight)
        for (row, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let baseline = -Float(row) * leading
            let lineStart = placed.count
            var lineLower = Float.greatestFiniteMagnitude
            var lineUpper = -Float.greatestFiniteMagnitude
            var pen: Float = 0
            for character in line {
                let glyph = Self.glyph(character, size: size)
                if let mesh = glyph.mesh {
                    let entity: ModelEntity
                    if used < glyphs.count {
                        entity = glyphs[used]
                        if entity.model?.mesh !== mesh { entity.model?.mesh = mesh }
                        entity.isEnabled = true
                    } else {
                        entity = ModelEntity(mesh: mesh, materials: [material])
                        root.addChild(entity)
                        glyphs.append(entity)
                    }
                    used += 1
                    placed.append((entity, SIMD3(pen, baseline, 0)))
                    let box = mesh.bounds
                    lineLower = min(lineLower, box.min.x + pen)
                    lineUpper = max(lineUpper, box.max.x + pen)
                    lower.y = min(lower.y, box.min.y + baseline)
                    upper.y = max(upper.y, box.max.y + baseline)
                    lower.z = min(lower.z, box.min.z)
                    upper.z = max(upper.z, box.max.z)
                }
                pen += glyph.advance
            }
            guard placed.count > lineStart else { continue }
            // Each line centred on the run's axis.
            let shift = -(lineLower + lineUpper) / 2
            for index in lineStart..<placed.count { placed[index].position.x += shift }
            lower.x = min(lower.x, lineLower + shift)
            upper.x = max(upper.x, lineUpper + shift)
        }
        for spare in glyphs.dropFirst(used) { spare.isEnabled = false }
        guard used > 0 else {
            bounds = BoundingBox()
            return bounds
        }
        // Centre the run on the root, as the whole-string mesh was.
        let centre = SIMD3((lower.x + upper.x) / 2, (lower.y + upper.y) / 2, 0)
        for (entity, position) in placed {
            entity.position = position - centre
        }
        bounds = BoundingBox(min: lower - centre, max: upper - centre)
        return bounds
    }

    // MARK: The glyph cache

    private struct Key: Hashable {
        let character: Character
        let size: CGFloat
    }

    private static var cache: [Key: (mesh: MeshResource?, advance: Float)] = [:]

    /// The font every readout is set in — the same `Callout.textMesh` uses.
    static func font(size: CGFloat) -> UIFont {
        .systemFont(ofSize: size, weight: .semibold)
    }

    /// One character's mesh (nil for a space) and how far it moves the
    /// pen, metres: `generateText` reads a font's points as metres.
    static func glyph(_ character: Character, size: CGFloat) -> (mesh: MeshResource?, advance: Float) {
        let key = Key(character: character, size: size)
        if let cached = cache[key] { return cached }
        let string = String(character)
        let font = font(size: size)
        let advance = Float((string as NSString).size(withAttributes: [.font: font]).width)
        let mesh: MeshResource? = character.isWhitespace ? nil : MeshResource.generateText(
            string, extrusionDepth: Float(size) * 0.06, font: font,
            containerFrame: .zero, alignment: .left, lineBreakMode: .byClipping)
        // Bounded, like every glyph cache here: sizes are few, characters fewer.
        if cache.count > 600 { cache.removeAll(keepingCapacity: true) }
        cache[key] = (mesh, advance)
        return (mesh, advance)
    }

    private static func material(_ color: UIColor) -> UnlitMaterial {
        var material = UnlitMaterial(color: color)
        material.blending = .opaque
        return material
    }
}
