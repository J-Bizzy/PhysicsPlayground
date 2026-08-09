//
//  BackedLabel.swift
//  RenderKit
//
//  A live in-room number, built to survive the room behind it.
//
//  The hub's nameplates solved this on 2026-08-01: bright type over
//  passthrough has no floor under its contrast — cyan on a white wall,
//  white on a sunlit one — and the fix that survives every wall is a
//  small near-black plate sized to the words it carries. The gallery got
//  that treatment; the modules' live numerals (circuit values, tower
//  volts, ring scores) stayed naked unlit text, which is the same defect
//  the nameplate was built for, one meter further into the room.
//
//  This is that plate, for numbers. The geometry is the nameplate's,
//  imported not imitated: padding scales WITH the type (fixed padding
//  authored at one size made a small label wear a plate three
//  text-heights wide), the corner radius is half the height, and the
//  backing sits behind the glyphs by a distance that also scales, so a
//  20 mm label is not floating 6 mm off its own card.
//
//  The backing is DECORATION: no collider, no input target, ever — a
//  readout that intercepts a pinch is `SpatialScaleHandle` again.
//

import QuartzCore
import RealityKit
import UIKit

/// A billboard-ready label: centred glyphs over a dark rounded backing.
/// The caller owns position and any billboarding pivot; this owns what
/// the label looks like.
@MainActor
public final class BackedLabel {
    /// Add this under the caller's (usually billboarded) pivot. The
    /// label is centred on it, horizontally and vertically.
    public let root = Entity()

    private let size: CGFloat
    /// The last text and colour, kept SEPARATELY rather than as one
    /// interpolated key.
    ///
    /// The key used to be `"\(text)|\(color.description)"`, built on
    /// every call — so a caller that re-asserts an unchanged label every
    /// frame (which is most of them; the whole design is "say what it
    /// should be, let the label decide") paid a String interpolation
    /// AND `UIColor.description`, itself an allocation, ninety times a
    /// second per label. The cheap path through this function has to be
    /// genuinely cheap or "free when nothing changed" is a claim rather
    /// than a fact.
    private var lastText: String?
    private var lastColor: UIColor?
    private var lastTextTime: Double = 0

    public init(size: CGFloat) {
        self.size = size
    }

    /// Rebuilds the glyphs and their backing. Free when nothing changed;
    /// glyph meshes come from `Callout`'s shared cache, so repeated
    /// values ("9.0 V") cost a dictionary lookup.
    ///
    /// RATE-LIMITED SINCE 2026-08-09, for the reason `Callout` was two
    /// days earlier — and this is the type that needed it more. "Skip
    /// when unchanged" protects nothing from a live number: a voltage
    /// skyline over an AC source relabels every node every frame, and
    /// each relabel tore down two entities and built a fresh plate
    /// mesh. `Callout` is the module callouts; `BackedLabel` is every
    /// numeral standing ON the apparatus, which is more of them.
    ///
    /// The limit cannot strand a value: the early return deliberately
    /// does NOT advance `lastKey`, so the pending text lands on the
    /// first frame past the interval rather than being dropped.
    public func setText(_ text: String, color: UIColor) {
        guard text != lastText || color != lastColor else { return }
        // CLEARING IS NEVER RATE-LIMITED. An empty string does not mean
        // "the number changed", it means the thing this label described
        // is gone — a part deselected, a probe removed. Throttling that
        // leaves a stale reading hanging in the room over nothing for up
        // to an eighth of a second, which is the one artifact worse than
        // the cost the throttle is saving. `BackedLabelTests`
        // caught this the day the limit landed.
        //
        // It is also not the case the limit exists for: labels clear on
        // a state change, not on every frame of a live value.
        if !text.isEmpty {
            let now = CACurrentMediaTime()
            guard now - lastTextTime >= Callout.minimumLabelInterval else { return }
            lastTextTime = now
        }
        lastText = text
        lastColor = color
        // Snapshot first: `children` is a live collection, and removing
        // while iterating it skips every other element — the test for
        // "empty text leaves nothing" caught exactly one orphaned plate.
        for child in Array(root.children) { child.removeFromParent() }
        guard !text.isEmpty else { return }

        let mesh = Callout.textMesh(text, size: size)
        var material = UnlitMaterial(color: color)
        material.blending = .opaque
        let glyphs = ModelEntity(mesh: mesh, materials: [material])
        let bounds = mesh.bounds
        glyphs.position = [-(bounds.min.x + bounds.max.x) / 2,
                           -(bounds.min.y + bounds.max.y) / 2, 0]

        root.addChild(Self.backing(behind: bounds, size: size))
        root.addChild(glyphs)
    }

    /// The plate alone — for a caller composing its own glyphs that
    /// still wants the one house backing. `Callout` and
    /// `SpatialTrackControl` are the two.
    ///
    /// It was `public` from 2026-08-08 for `CircuitsInsightCard`, which
    /// the owner deleted the following day; demoted back to `internal`
    /// on 2026-08-09 now that every caller is inside RenderKit. The
    /// reason for having it at all is unchanged and is not about
    /// visibility: a second copy of the inset-and-corner arithmetic is
    /// how two labels in one room end up wearing different backings.
    static func backing(behind bounds: BoundingBox,
                        size: CGFloat) -> ModelEntity {
        let padX = Float(size) * 0.5
        let padY = Float(size) * 0.44
        let width = (bounds.max.x - bounds.min.x) + padX * 2
        let height = (bounds.max.y - bounds.min.y) + padY * 2
        var material = UnlitMaterial(color: UIColor(white: 0.02, alpha: 1))
        material.blending = .transparent(opacity: 0.58)
        // A PILL FOR A BADGE, A ROUNDED RECT FOR A PARAGRAPH.
        //
        // `height / 2` alone was written for the one-line number badges
        // this started as, where it makes a stadium. Give it a wrapped
        // paragraph and the same rule makes a lozenge whose curved ends
        // eat the first and last words of every line — visible in the
        // first photograph of the in-room teach (2026-08-08), where
        // "Grab" and "so" hung outside their own backing.
        //
        // Capping at a little over the glyph height keeps the badge
        // exactly as it was (a single line is barely taller than the cap)
        // and gives anything taller an honest corner.
        let radius = min(height / 2, Float(size) * 1.2)
        let card = ModelEntity(
            mesh: plate(width: width, height: height, cornerRadius: radius),
            materials: [material])
        card.position.z = -Float(size) * 0.17
        return card
    }

    /// Plate meshes, keyed by their rounded dimensions.
    ///
    /// `generatePlane` is a mesh build like any other, and this one is
    /// asked for on every relabel — so a live numeral was paying for a
    /// rounded rectangle 90 times a second to say a number that had
    /// changed in its last digit. The plate is a function of the text's
    /// EXTENT, not its content, so "12.3 V" and "12.4 V" want the same
    /// plate and every digit of a monospaced-ish run wants it again.
    ///
    /// Quantised to 0.1 mm, which is far below what a plate edge can
    /// show at arm's length and is what makes the cache hit at all —
    /// keyed on raw Floats, glyph extents differ in the last bit and
    /// nothing would ever match. The cache is bounded the way
    /// `Callout`'s glyph cache is: a room has a few dozen distinct
    /// labels, and a run that somehow makes thousands should not hold
    /// them all.
    private static var plates: [PlateKey: MeshResource] = [:]

    private struct PlateKey: Hashable {
        let width: Int32, height: Int32, radius: Int32
        init(_ width: Float, _ height: Float, _ radius: Float) {
            self.width = Int32((width * 10_000).rounded())
            self.height = Int32((height * 10_000).rounded())
            self.radius = Int32((radius * 10_000).rounded())
        }
    }

    private static func plate(width: Float, height: Float,
                              cornerRadius: Float) -> MeshResource {
        let key = PlateKey(width, height, cornerRadius)
        if let cached = plates[key] { return cached }
        let mesh = MeshResource.generatePlane(
            width: width, height: height, cornerRadius: cornerRadius)
        if plates.count > 400 { plates.removeAll() }
        plates[key] = mesh
        return mesh
    }
}
