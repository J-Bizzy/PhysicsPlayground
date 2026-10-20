//
//  Callout.swift
//  RenderKit
//
//  A billboarded label tethered to a point by a dot and leader line.
//  One line is set from cached glyphs (`GlyphRun`), so a live reading
//  moves glyphs instead of generating text; a wrapped paragraph's mesh is
//  cached by (string, size, width) — per-frame generation is the classic
//  way to tank a scene.
//

import QuartzCore
import RealityKit
import UIKit
import simd

/// A billboarded label tethered to a point in space by a leader line.
@MainActor
public final class Callout {
    /// Add this to the scene. Positioned at the anchor; the label hangs
    /// at `offset` with the leader drawn between.
    public let root = Entity()

    private let dot = Entity()
    private let leader = Entity()
    private let labelPivot = Entity()
    /// A wrapped paragraph, as one generated mesh.
    private var labelEntity: ModelEntity?
    /// One line, from cached glyphs (`GlyphRun`): what a live number is.
    private var run: GlyphRun?

    private let color: UIColor
    private let textSize: CGFloat
    private var offset: SIMD3<Float>
    private var lastText: String?
    private var lastTextTime: Double = -1

    /// Whether the text wears the house dark backing plate. On by
    /// default; takes effect on the next text change.
    public var showsBacking = true

    /// Wrap the label at this width, metres; 0 keeps it on one line.
    public var wrapWidth: CGFloat = 0 {
        didSet {
            guard wrapWidth != oldValue else { return }
            // Cached mesh is keyed on width; force the next setText through.
            lastText = nil
        }
    }
    private var backingEntity: ModelEntity?

    /// What VoiceOver calls this readout — the quantity, not the number.
    /// A text mesh is invisible to VoiceOver unless something says otherwise.
    private var accessibilityName: String?

    /// - color: accent for dot/leader/type (saturated survives white walls);
    ///   textSize: glyph height in metres; offset: label position from anchor.
    public init(color: UIColor,
                textSize: CGFloat = 0.035,
                offset: SIMD3<Float> = SIMD3(0, 0.11, 0)) {
        self.color = color
        self.textSize = textSize
        self.offset = offset

        let dotMesh = Primitives.sphere(radius: 0.006)
        let dotModel = ModelEntity(mesh: dotMesh,
                                   materials: [Materials.energized(color, glow: 0.8)])
        dot.addChild(dotModel)
        root.addChild(dot)

        root.addChild(leader)

        labelPivot.components.set(BillboardComponent())
        labelPivot.position = offset
        root.addChild(labelPivot)

        rebuildLeader()
    }

    /// Where the callout points. Set every frame if the subject moves.
    public func anchor(at worldPosition: SIMD3<Float>) {
        root.position = worldPosition
    }

    /// How often a changing readout may regenerate glyphs — a live number
    /// differs every frame, and "skip when unchanged" protects nothing.
    /// 8 Hz is faster than reading. Shared with `BackedLabel` so the two rates cannot drift.
    static let minimumLabelInterval: Double = 1.0 / 8
    private static var minimumInterval: Double { minimumLabelInterval }

    /// Updates the text. Free when unchanged, and rate-limited when it
    /// changes, because generating glyphs is not free. Returns whether the
    /// callout now shows `text`: false means the rate limit held it back,
    /// and a caller that caches "what I last showed" must not record it, or
    /// the readout freezes on the value before.
    @discardableResult
    public func setText(_ text: String) -> Bool {
        guard text != lastText else { return true }
        // Clearing jumps the queue — same exemption as `BackedLabel.setText`.
        if !text.isEmpty {
            let now = CACurrentMediaTime()
            guard now - lastTextTime >= Self.minimumInterval else { return false }
            lastTextTime = now
        }
        lastText = text
        labelEntity?.removeFromParent()
        labelEntity = nil
        guard !text.isEmpty else {
            run?.root.removeFromParent()
            backingEntity?.removeFromParent()
            backingEntity = nil
            return true
        }
        let bounds: BoundingBox
        if wrapWidth > 0 {
            // A paragraph does not tick: one generated mesh.
            run?.root.removeFromParent()
            let mesh = Self.textMesh(text, size: textSize, wrapWidth: wrapWidth)
            var material = UnlitMaterial(color: color)
            material.blending = .opaque
            let model = ModelEntity(mesh: mesh, materials: [material])
            // Centre the glyph run on the pivot.
            bounds = mesh.bounds
            model.position = [-(bounds.min.x + bounds.max.x) / 2,
                              -(bounds.min.y + bounds.max.y) / 2, 0]
            labelEntity = model
        } else {
            let run = self.run ?? GlyphRun(size: textSize, color: color)
            self.run = run
            bounds = run.set(text)
        }
        if showsBacking {
            // A sibling of the centred glyphs, never a child — parenting to
            // the shifted model lands the plate off by the centring shift.
            if let plate = backingEntity {
                BackedLabel.reshape(plate, behind: bounds, size: textSize)
            } else {
                let plate = BackedLabel.backing(behind: bounds, size: textSize)
                labelPivot.addChild(plate)
                backingEntity = plate
            }
        } else {
            backingEntity?.removeFromParent()
            backingEntity = nil
        }
        if let labelEntity {
            labelPivot.addChild(labelEntity)
        } else if let run, run.root.parent == nil {
            labelPivot.addChild(run.root)
        }
        publishAccessibility()
        return true
    }

    /// Names the quantity for VoiceOver; the value is whatever `setText`
    /// last wrote, so set once and the reading follows.
    public func setAccessibilityName(_ name: String) {
        guard name != accessibilityName else { return }
        accessibilityName = name
        publishAccessibility()
    }

    private func publishAccessibility() {
        // Label and value both — a readout VoiceOver can name but not
        // read is merely listed.
        guard let text = lastText, !text.isEmpty else {
            root.components.remove(AccessibilityComponent.self)
            return
        }
        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = LocalizedStringResource(
            stringLiteral: accessibilityName ?? "Reading")
        accessibility.value = LocalizedStringResource(stringLiteral: text)
        root.components.set(accessibility)
    }

    public var isEnabled: Bool {
        get { root.isEnabled }
        set { root.isEnabled = newValue }
    }

    // MARK: Leader

    private func rebuildLeader() {
        leader.children.forEach { $0.removeFromParent() }
        let length = simd_length(offset)
        guard length > 1e-4 else { return }
        let material = Materials.unlit(color, opacity: 0.7)
        let rod = ModelEntity(
            mesh: Primitives.cylinder(height: length, radius: 0.0011),
            materials: [material])
        // generateCylinder runs along +Y; a straight-down offset is the
        // antiparallel case `rotation(from:to:)` exists for.
        rod.orientation = rotation(from: [0, 1, 0], to: offset / length)
        rod.position = offset / 2
        leader.addChild(rod)
    }

    // MARK: Text mesh cache

    private static var cache: [String: MeshResource] = [:]

    /// Cached text meshes keyed by content+size+wrap. `wrapWidth` in
    /// metres wraps at word boundaries; 0 leaves one line.
    public static func textMesh(_ text: String, size: CGFloat,
                                wrapWidth: CGFloat = 0) -> MeshResource {
        let key = "\(size)|\(wrapWidth)|\(text)"
        if let cached = cache[key] { return cached }
        // The container must be tall: `generateText` clips to the frame,
        // silently dropping the last line if the height is guessed small.
        let frame = wrapWidth > 0
            ? CGRect(x: -wrapWidth / 2, y: -size * 14,
                     width: wrapWidth, height: size * 14)
            : .zero
        let mesh = MeshResource.generateText(
            text,
            extrusionDepth: Float(size) * 0.06,
            font: .systemFont(ofSize: size, weight: .semibold),
            containerFrame: frame,
            alignment: .center,
            lineBreakMode: wrapWidth > 0 ? .byWordWrapping : .byTruncatingTail)
        // Bounded so a varying number can't grow the cache without limit.
        if cache.count > 400 { cache.removeAll(keepingCapacity: true) }
        cache[key] = mesh
        return mesh
    }
}
