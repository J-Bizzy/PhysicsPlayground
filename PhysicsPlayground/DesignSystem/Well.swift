//
//  Well.swift
//  Physics Playground — Design System
//
//  Creation, as a physical act. Every lab has one or two of these: a
//  small source you reach into and PULL something out of. The new
//  object is born at your fingertips and follows your hand until you
//  let go of it, which means placing a charge and moving a charge are
//  the same gesture — you never learn a second one.
//
//  This replaces "Add +" and "Add −" buttons on a floating card. A
//  button tells you a thing exists somewhere; a well hands it to you.
//
//  THE GLASS CAME OFF (2026-08-01, owner's call). Every well in the app
//  used to be the same tinted glass sphere with a different letter
//  floating inside it — "+" in three modules, "N" in one, "q" in
//  another. So the one affordance whose entire job is to say WHAT YOU
//  ARE ABOUT TO MAKE said only "something comes out of here", and said
//  it identically in five places.
//
//  What you see now is the thing itself: a bar magnet with its red and
//  blue poles in Magnetism, a bob on a cable in Pendulums, a world in
//  Gravity Lab, a red or blue charge in Electric Fields — at the size it
//  will be when you have it, with its name written under it. The
//  metaphor survives the glass going: it still breathes, still recoils
//  when it gives something up, and still dims when the lab is full and
//  it has nothing to give.
//
//  Callers supply the miniature, because only the module knows what its
//  own object looks like. The rule for a good one: build it out of the
//  SAME materials and proportions the renderer uses, so the preview and
//  the thing you pull out are recognisably one object.
//

import RealityKit
import SwiftUI
import RenderKit
import simd

@MainActor
final class Well {
    /// One source: what it makes, and what it looks like beforehand.
    struct Spec {
        let name: String
        let tint: UIColor
        /// The words under the object — "Add magnet", "Add world".
        let label: String
        /// Builds the miniature that stands here. Called once, on the
        /// main actor, at construction.
        let preview: @MainActor () -> Entity
        let position: SIMD3<Float>
        /// Makes the object at a world point and returns its id, so the
        /// caller can hand the new thing straight to the drag it was
        /// born from.
        let spawn: (SIMD3<Double>) -> UUID?
    }

    let root = Entity()
    private var specs: [Spec] = []
    private var sources: [Entity] = []
    /// The preview model inside each source, scaled by the breath — kept
    /// separately from the source root so the LABEL does not breathe
    /// with it. A name that pulsed would read as an animation; a name
    /// should just be readable.
    private var previews: [Entity] = []
    private var dip: [Float] = []
    /// The refusal fade when a pull comes up empty — the lab is at its
    /// object budget and nothing came out, so the preview dims briefly
    /// instead of popping. (This comment said "dark pulse" long after
    /// the pulse became a fade — the doc-rot this project keeps
    /// catching.)
    private var refusal: [Float] = []
    private var time: Double = 0

    init(_ specs: [Spec]) {
        self.specs = specs
        dip = Array(repeating: 0, count: specs.count)
        refusal = Array(repeating: 0, count: specs.count)
        for spec in specs {
            let (source, preview) = Self.makeSource(spec)
            source.position = spec.position
            root.addChild(source)
            sources.append(source)
            previews.append(preview)
        }
    }

    /// Per frame: the idle breath, and the recoil after a spawn.
    func update(dt: Double) {
        time += dt
        for (index, preview) in previews.enumerated() {
            dip[index] = max(0, dip[index] - Float(dt) * 2.6)
            refusal[index] = max(0, refusal[index] - Float(dt) * 2.2)
            let breath = 1 + 0.035 * Float(sin(time * 1.4 + Double(index) * 1.1))
            // The dip is a recoil: it shrinks on giving, then swells back.
            preview.scale = SIMD3(repeating: breath * (1 - 0.42 * dip[index]))
            // Refusal used to darken a glass halo. With the glass gone
            // the object itself fades instead, which says the same thing
            // about the same object: nothing came out of here.
            let opacity = 1 - 0.6 * refusal[index]
            if opacity < 0.999 {
                preview.components.set(OpacityComponent(opacity: opacity))
            } else {
                preview.components.remove(OpacityComponent.self)
            }
        }
    }

    /// If `entity` belongs to a source, makes its object at `hand` and
    /// returns the new id — the caller then drags it like anything else.
    func pull(_ entity: Entity, at hand: SIMD3<Double>) -> UUID? {
        guard let name = Self.sourceName(of: entity, under: root),
              let index = sources.firstIndex(where: { $0.name == name })
        else { return nil }
        // The recoil and the pop are the well SAYING it just gave
        // something up, so they only happen when it did. A lab at its
        // budget used to chirp and flinch and hand back nothing — the
        // gesture read as working and the object simply never arrived,
        // which is the worst of both answers.
        guard let id = specs[index].spawn(hand) else {
            refusal[index] = 1
            return nil
        }
        dip[index] = 1
        SoundPalette.play(.pop, on: sources[index], volume: 0.5)
        return id
    }

    private static func sourceName(of entity: Entity, under root: Entity) -> String? {
        var current: Entity? = entity
        while let candidate = current {
            if candidate.parent === root { return candidate.name }
            if candidate === root { return nil }
            current = candidate.parent
        }
        return nil
    }

    private static func applyGroundingShadow(_ entity: Entity) {
        if entity is ModelEntity {
            entity.components.set(GroundingShadowComponent(castsShadow: true))
        }
        for child in entity.children { applyGroundingShadow(child) }
    }

    private static func makeSource(_ spec: Spec) -> (source: Entity, preview: Entity) {
        let source = Entity()
        source.name = "well-\(spec.name)"

        // The object, at the size it will be when you are holding it.
        // A pivot sits between it and the source so the breath can scale
        // the model without touching the label beneath.
        let preview = Entity()
        let model = spec.preview()
        // The preview is caller-supplied and arbitrarily nested, so the
        // contact shadow is applied to every model in it — the component
        // renders per mesh, not per subtree.
        applyGroundingShadow(model)
        preview.addChild(model)
        source.addChild(preview)

        // The name, below the object and NOT breathing with it.
        let plate = HubScene.namePlate(spec.label, accent: spec.tint, size: 0.0132)
        plate.components.set(BillboardComponent())
        source.addChild(plate)

        // The collider is sized to what is actually there, per the rule
        // that an input-targetable collider must never be larger than
        // the thing it represents (DECISIONS.md, 2026-07-29 — an
        // oversized one shields everything behind it from every pinch,
        // and these stand among the objects they make).
        //
        // Measured from the preview rather than assumed, because callers
        // build their own miniatures and a magnet is not a sphere.
        let bounds = preview.visualBounds(relativeTo: source)
        // A small generous margin so a near miss still counts — the well
        // is a target you reach for, not one you have to hit.
        let padded = bounds.extents + SIMD3<Float>(repeating: 0.028)
        source.components.set(InputTargetComponent())
        source.components.set(CollisionComponent(
            shapes: [.generateBox(size: padded).offsetBy(translation: bounds.center)]))
        source.components.set(HoverEffectComponent())

        plate.position = [0, bounds.min.y - 0.034, 0]

        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = LocalizedStringResource(
            stringLiteral: "\(spec.label). Pinch and pull to make one.")
        source.components.set(accessibility)
        return (source, preview)
    }
}
