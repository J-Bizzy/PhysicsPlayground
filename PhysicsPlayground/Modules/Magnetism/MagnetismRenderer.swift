//
//  MagnetismRenderer.swift
//  Physics Playground — Magnetism module
//
//  Renders the magnetic sandbox, fully volumetric:
//
//  · bar magnets — a red north half and a blue south half, grabbable,
//    oriented along their live moment;
//  · the looping field lines, traced off-main on a GeometryPipeline and
//    drawn as a glowing tube (a bright core inside a soft halo);
//  · a room-filling 3-D grid of compass needles that swing to point
//    along the local field every frame.
//
//  Frame-rate contract: field lines rebuild only when the magnets move
//  (change-gated, vertex math on a worker); the per-frame path is the
//  magnets' transforms and the compass needle orientations — a few dozen
//  dipole evaluations. Ticked from SceneEvents.Update.
//

import Foundation
import PhysicsCore
import RealityKit
import RenderKit
import SwiftUI
import simd

@MainActor
final class MagnetismRenderer {
    let root = Entity()
    /// Everything the two-hand scale gesture grows lives under here;
    /// pods and lighting stay on `root`, unscaled. The rig's transform
    /// is a pure view change — the model keeps its own coordinates, and
    /// every hand position converts through this root on its way in.
    let viewRoot = Entity()

    var subscriptions: [EventSubscription] = []

    static let northColor = DesignTokens.Palette.positiveUI
    static let southColor = DesignTokens.Palette.negativeUI
    static let lineColor = UIColor(red: 0.72, green: 0.6, blue: 1.0, alpha: 1)

    private var magnetEntities: [UUID: Entity] = [:]
    private var magnetHalos: [UUID: Entity] = [:]

    private let linesEntity = ModelEntity()
    private let lineCasingEntity = ModelEntity()
    private let lineGlowEntity = ModelEntity()
    /// Core radius of a field loop; the casing is swept from it.
    static let lineRadius: Float = 0.0016
    /// Direction cones riding the field loops, N→S outside the magnet.
    private let arrowHeads: EntityPool<ModelEntity>
    private let lineMaterial = UnlitMaterial(color: MagnetismRenderer.lineColor)
    /// The near-black outline the bright core sits against. Passthrough
    /// is a BRIGHT medium — cream walls, daylight — so a pale 1.6 mm
    /// loop drawn over it has almost no luminance contrast and simply
    /// disappears. Electric Fields has had this since it was written;
    /// the dipole loops are this module's entire subject and went
    /// without it.
    private let lineCasingMaterial =
        Materials.contrastLine(MagnetismRenderer.lineColor).casing
    private let lineGlowMaterial: UnlitMaterial = {
        var m = UnlitMaterial(color: MagnetismRenderer.lineColor)
        m.blending = .transparent(opacity: 0.2)
        return m
    }()
    private var linesPipeline: GeometryPipeline<LinesJob, LinesResult>?
    private var lastLineInputs: [BarMagnet]?

    init() {
        let headMesh = MeshResource.generateCone(height: 0.02, radius: 0.0078)
        let headMaterial = UnlitMaterial(color: MagnetismRenderer.lineColor)
        arrowHeads = EntityPool(budget: 600) { container in
            let head = ModelEntity(mesh: headMesh, materials: [headMaterial])
            container.addChild(head)
            return head
        }

        root.addChild(Lighting.keyLight())
        root.addChild(viewRoot)
        // Order is the treatment: casing (darkness) under the glow,
        // glow under the bright core.
        viewRoot.addChild(lineCasingEntity)
        viewRoot.addChild(lineGlowEntity)
        viewRoot.addChild(linesEntity)
        viewRoot.addChild(arrowHeads.root)

        linesPipeline = GeometryPipeline(
            compute: { Self.computeLines($0) },
            apply: { [weak self] in self?.applyLines($0) }
        )
    }

    // MARK: Per-frame

    /// World → model coordinates, through however the view is scaled
    /// and turned. Every hand and head position enters the model here.
    func displayPoint(fromWorld world: SIMD3<Float>) -> SIMD3<Double> {
        SIMD3<Double>(viewRoot.convert(position: world, from: nil))
    }

    func tick(_ model: MagnetismModel, viewer: SIMD3<Double>? = nil) {
        tickSounds(model)
        syncMagnets(model)
        syncFieldLines(model)
        syncHandCompass(model)
    }

    // MARK: The compass you carry

    static let handCompassName = "hand-compass"
    /// The orb's radius — the collider matches it, per the rule that an
    /// input-targetable collider must never exceed what it represents.
    private static let compassRadius: Float = 0.055
    private let handCompass = Entity()
    private var handCompassNeedle: Entity?
    private var handCompassCallout: Callout?

    private func buildHandCompass() {
        handCompass.name = Self.handCompassName

        // A SPHERE, not a pocket compass (2026-08-01, owner's call).
        //
        // It was a brass cylinder with a flat pale dial and a flat
        // needle, and that shape was making a promise the physics does
        // not keep. A magnetic field points wherever it likes — steeply
        // up between two attracting poles, straight down beside them —
        // and a dial can only ever show you the part of it lying in the
        // dial's plane. On Earth we get away with that because we only
        // ever ask a compass for a heading. In a room with bar magnets
        // in it the interesting answer is usually the one pointing out
        // of the dial.
        //
        // A CURIOUS DETAIL FOUND WHILE CHANGING IT: the needle was
        // already aiming in full 3-D — `simd_quatf(from: [0,1,0], to:
        // direction)` takes the whole vector — while the comment beside
        // it said "the needle lies in the dial's plane, so project B onto
        // it: a real compass only shows the component it can turn to."
        // The code did not project. So the instrument was telling the
        // truth and its case and its comment were both lying about it,
        // and the needle spent its life poking through a brass lid.
        //
        // The orb is the honest housing: a glass ball with the needle
        // swinging freely inside, gimbal rings for a sense of which way
        // is which, and nothing anywhere that suggests a plane.
        var shell = Materials.frostedGlass(
            UIColor(white: 0.62, alpha: 1), opacity: 0.20, frost: 0.35)
        shell.emissiveIntensity = 0.08
        let orb = ModelEntity(mesh: .generateSphere(radius: Self.compassRadius),
                              materials: [shell])
        handCompass.addChild(orb)

        // NO GIMBAL RINGS. Two were tried here and they were a bug: a
        // ring needs a torus, RealityKit has no `generateTorus`, and a
        // thin box with `cornerRadius` equal to its half-width is not a
        // ring — it is a rounded SLAB. So what rendered was two solid
        // brass-coloured discs intersecting inside the glass, which the
        // owner correctly reported as "an odd yellowish plane cutting
        // through it."
        //
        // They were there to give the eye a reference for depth, so that
        // "pointing 30 degrees up" and "pointing at you" would not look
        // alike. The honest way to build one is a swept circle
        // (`TubeMesh`, the way the reset orb's ring icon is made), but a
        // clean glass ball with a needle in it reads well enough, and a
        // ring is furniture until something proves it is needed.

        // The needle: red north, white south, free to point ANYWHERE —
        // the same alignment a free magnet finds, now in a case that
        // admits it. Thicker and squarer in section than the flat blade
        // it replaces, because a blade seen edge-on disappears, and
        // edge-on is exactly the view a 3-D needle keeps giving you.
        let needle = Entity()
        let north = ModelEntity(
            mesh: .generateBox(size: [0.008, 0.040, 0.008], cornerRadius: 0.003),
            materials: [Materials.energized(DesignTokens.Palette.positiveUI, glow: 0.35)])
        north.position = [0, 0.020, 0]
        let south = ModelEntity(
            mesh: .generateBox(size: [0.008, 0.040, 0.008], cornerRadius: 0.003),
            materials: [Materials.energized(UIColor(white: 0.9, alpha: 1),
                                            metallic: 0.6, glow: 0.0)])
        south.position = [0, -0.020, 0]
        needle.addChild(north)
        needle.addChild(south)
        // A dark bead at the pivot, so the needle reads as suspended at
        // the centre rather than as two bars floating in glass.
        let hub = ModelEntity(
            mesh: .generateSphere(radius: 0.007),
            materials: [Materials.machined(UIColor(white: 0.22, alpha: 1))])
        needle.addChild(hub)
        handCompass.addChild(needle)
        handCompassNeedle = needle

        let callout = Callout(color: UIColor(red: 0.95, green: 0.78, blue: 0.42, alpha: 1),
                              textSize: 0.024, offset: SIMD3(0, 0.09, 0))
        callout.setAccessibilityName("Field at the compass")
        handCompassCallout = callout
        handCompass.addChild(callout.root)

        // Matched to the orb itself rather than a hand-typed 0.06 that
        // outgrew it — the collider rule again.
        Grabbable.configureTouchTarget(handCompass,
                                       collisionRadius: Self.compassRadius * 1.08)
        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = "Compass. Carry it around the magnets and watch the needle swing to the field."
        handCompass.components.set(accessibility)
        viewRoot.addChild(handCompass)
    }

    private func syncHandCompass(_ model: MagnetismModel) {
        if handCompassNeedle == nil { buildHandCompass() }
        handCompass.isEnabled = model.compassOn
        guard model.compassOn else { return }
        // EVERY frame, including while a hand owns it. This used to be
        // gated on `isCarryingCompass`, so dragging the compass moved the
        // MODEL and left the orb sitting where it was — you could swing
        // the needle (it re-aims to the field at the model's new spot)
        // and never move the instrument.
        //
        // The exact bug this module already fixed once, for the magnets,
        // in 86106b9: these are RELATIVE drags, so the model owns motion
        // and the renderer must follow it unconditionally. A guard of
        // this shape only makes sense against a system-driven
        // `ManipulationComponent`, and `configureTouchTarget` does not
        // install one — it sets a collider and nothing else. The compass
        // kept the defect for months because nobody had tried to carry
        // it.
        handCompass.position = SIMD3<Float>(model.compassPosition)
        let field = model.compassField
        let magnitude = simd_length(field)
        if magnitude > 1e-12 {
            // The WHOLE vector, which is what it always was — see
            // `buildHandCompass` on the comment that used to sit here
            // claiming a projection the code never did. The orb can show
            // this honestly; the flat dial could not.
            let direction = SIMD3<Float>(field / magnitude)
            handCompassNeedle?.orientation = simd_quatf(from: [0, 1, 0], to: direction)
        }
        handCompassCallout?.setText(String(format: "%.1f µT", model.compassMicroTesla))
        handCompassCallout?.anchor(at: SIMD3(0, 0.05, 0))
    }

    // MARK: Magnets

    // MARK: Sound — the module's first voice
    //
    // A pop as a magnet is born, a thud as two snap into contact —
    // the only silent module finally answers the hand.

    private var knownMagnetIDs: Set<UUID> = []
    private var contactPairs: Set<String> = []

    private func tickSounds(_ model: MagnetismModel) {
        let ids = Set(model.magnets.map(\.id))
        for id in ids.subtracting(knownMagnetIDs) {
            // Skip the opening scene: three pops at once is a fanfare
            // nobody asked for.
            if !knownMagnetIDs.isEmpty, let entity = magnetEntities[id] {
                SoundPalette.play(.pop, on: entity, volume: 0.5)
            }
        }
        knownMagnetIDs = ids

        let contact = MagnetismModel.magnetLength * 0.98
        var current: Set<String> = []
        for (index, a) in model.magnets.enumerated() {
            for b in model.magnets.dropFirst(index + 1) {
                let key = [a.id.uuidString, b.id.uuidString].sorted().joined(separator: "-")
                if simd_distance(a.position, b.position) < contact {
                    current.insert(key)
                    if !contactPairs.contains(key), let entity = magnetEntities[a.id] {
                        SoundPalette.play(.thud, on: entity, volume: 0.45)
                    }
                }
            }
        }
        contactPairs = current
    }

    private func syncMagnets(_ model: MagnetismModel) {
        let live = Set(model.magnets.map(\.id))
        for (id, entity) in magnetEntities where !live.contains(id) {
            entity.removeFromParent()
            magnetEntities[id] = nil
            magnetHalos[id] = nil
        }
        for magnet in model.magnets {
            let entity = magnetEntities[magnet.id] ?? makeMagnet(magnet)
            // The model owns motion (relative drag, no system manipulation),
            // so the entity follows it EVERY frame — including while held,
            // or the magnet lags the hand until release.
            entity.position = SIMD3<Float>(magnet.position)
            // Orient the bar's +Y along the moment (S→N).
            entity.orientation = simd_quatf(
                from: [0, 1, 0], to: SIMD3<Float>(magnet.axis))
            magnetHalos[magnet.id]?.isEnabled = magnet.id == model.selectedID
        }
    }

    /// An extruded, centred pole letter in warm ivory — generateText's
    /// origin is the baseline's left edge, so the glyph is re-centred
    /// from its measured bounds.
    private static func poleLetter(_ text: String) -> ModelEntity {
        let mesh = MeshResource.generateText(
            text,
            extrusionDepth: 0.006,
            font: .systemFont(ofSize: 0.034, weight: .heavy),
            containerFrame: .zero,
            alignment: .center,
            lineBreakMode: .byClipping)
        let entity = ModelEntity(
            mesh: mesh,
            materials: [Materials.energized(UIColor(red: 0.98, green: 0.96, blue: 0.90, alpha: 1),
                                            roughness: 0.3, glow: 0.12)])
        let bounds = entity.visualBounds(relativeTo: nil)
        entity.position = [-bounds.center.x, -bounds.center.y, 0]
        let pivot = ModelEntity()
        pivot.addChild(entity)
        return pivot
    }

    /// The magnet as the WELL shows it, before you have one.
    ///
    /// Built from the same halves, the same colours, the same chrome
    /// waist band and the same embossed pole letters as the real thing —
    /// the point of a preview is that pulling it out is recognisably
    /// getting the object you were looking at. It is only the selection
    /// halo and the collider that are missing, because a preview is not
    /// selectable and the well owns the touch target.
    ///
    /// Static, and free of `magnet`-derived state, so `Well` can call it
    /// without a model.
    static func magnetPreview() -> Entity {
        let container = Entity()
        let half = Float(MagnetismModel.magnetLength) / 2
        let w: Float = 0.05

        let north = ModelEntity(
            mesh: .generateBox(size: [w, half, w], cornerRadius: 0.006),
            materials: [Materials.energized(northColor, roughness: 0.28, glow: 0.16)])
        north.position = [0, half / 2, 0]
        let south = ModelEntity(
            mesh: .generateBox(size: [w, half, w], cornerRadius: 0.006),
            materials: [Materials.energized(southColor, roughness: 0.28, glow: 0.16)])
        south.position = [0, -half / 2, 0]
        container.addChild(north)
        container.addChild(south)

        for (text, y) in [("N", half / 2), ("S", -half / 2)] {
            for zSign: Float in [1, -1] {
                let letter = poleLetter(text)
                letter.position = [0, y, zSign * (w / 2)]
                if zSign < 0 {
                    letter.orientation = simd_quatf(angle: .pi, axis: [0, 1, 0])
                }
                container.addChild(letter)
            }
        }

        let band = ModelEntity(
            mesh: .generateBox(size: [w + 0.006, 0.014, w + 0.006], cornerRadius: 0.004),
            materials: [Materials.machined(UIColor(white: 0.86, alpha: 1))])
        container.addChild(band)

        // Lying along the bar's own axis, tipped a little toward the
        // viewer so both poles read at a glance rather than one hiding
        // behind the other.
        container.orientation = simd_quatf(angle: -0.42, axis: [0, 0, 1])
        return container
    }

    private func makeMagnet(_ magnet: BarMagnet) -> Entity {
        let container = Entity()
        container.name = magnet.id.uuidString
        let half = Float(MagnetismModel.magnetLength) / 2
        let w: Float = 0.05

        let north = ModelEntity(
            mesh: .generateBox(size: [w, half, w], cornerRadius: 0.006),
            materials: [Materials.energized(Self.northColor, roughness: 0.28, glow: 0.16)])
        north.position = [0, half / 2, 0]
        let south = ModelEntity(
            mesh: .generateBox(size: [w, half, w], cornerRadius: 0.006),
            materials: [Materials.energized(Self.southColor, roughness: 0.28, glow: 0.16)])
        south.position = [0, -half / 2, 0]
        container.addChild(north)
        container.addChild(south)

        // Embossed pole letters — raised 3-D type on the front and back
        // faces, like the stamped lettering on a real lab magnet.
        for (text, y) in [("N", half / 2), ("S", -half / 2)] {
            for zSign: Float in [1, -1] {
                let letter = Self.poleLetter(text)
                letter.position = [0, y, zSign * (w / 2)]
                if zSign < 0 {
                    letter.orientation = simd_quatf(angle: .pi, axis: [0, 1, 0])
                }
                container.addChild(letter)
            }
        }

        // A polished chrome band at the waist — the seam of a real bar
        // magnet, and a crisp divider between the poles.
        let band = ModelEntity(
            mesh: .generateBox(size: [w + 0.006, 0.014, w + 0.006], cornerRadius: 0.004),
            materials: [Materials.machined(UIColor(white: 0.86, alpha: 1))])
        container.addChild(band)

        // Selection halo (a soft box shell), hidden until selected.
        var haloMaterial = UnlitMaterial(color: DesignTokens.Palette.selectionHaloUI)
        haloMaterial.blending = .transparent(opacity: 0.22)
        let halo = ModelEntity(
            mesh: .generateBox(size: [w + 0.03, half * 2 + 0.03, w + 0.03], cornerRadius: 0.012),
            materials: [haloMaterial])
        halo.isEnabled = false
        container.addChild(halo)
        magnetHalos[magnet.id] = halo

        Grabbable.configureTouchTarget(container, collisionRadius: half * 1.6)
        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = "Bar magnet. Grab it and carry it — nearby magnets attract, repel, and swing to align."
        container.components.set(accessibility)

        container.position = SIMD3<Float>(magnet.position)
        viewRoot.addChild(container)
        magnetEntities[magnet.id] = container
        return container
    }

    // MARK: Field lines (background, change-gated)

    private nonisolated struct LinesJob: Sendable { var magnets: [BarMagnet] }
    private nonisolated struct LinesResult: Sendable {
        var core = TubeBuffers()
        var casing = TubeBuffers()
        var glow = TubeBuffers()
        /// Sample points along the loops where arrowheads ride, with
        /// the local line direction — B points N→S outside the magnet,
        /// and the arrows finally SAY so.
        var arrowPoints: [SIMD3<Double>] = []
        var arrowDirections: [SIMD3<Double>] = []
    }

    /// Arc-length spacing of the direction arrowheads riding each loop.
    /// Widened 0.26 → 0.42 with the room-scale bounds: loops are metres
    /// long now, and the head pool has to cover them all.
    private nonisolated static let arrowSpacing = 0.42
    /// No arrowheads this close to a magnet, where loops bunch tightly.
    private nonisolated static let arrowExclusion = 0.14

    /// How many loops a bench this strong deserves. Monotonic in the
    /// strongest magnet's |m|, so the strength bead visibly changes the
    /// picture — the fixed budget of 26 did not, which read as a dead
    /// control (owner, 2026-08-03). Clamped so a weak bench still draws
    /// a legible field and a strong one does not drown the frame.
    nonisolated static func lineBudget(forStrength strength: Double) -> Int {
        let scaled = 26.0 * strength / MagnetismModel.defaultStrength
        return Int(min(max(scaled, 12), 48).rounded())
    }

    private nonisolated static func computeLines(_ job: LinesJob) -> LinesResult {
        var config = MagneticFieldLineTracer.Config()
        config.boundsCenter = MagnetismModel.regionCenter
        // ROOM-SCALE (owner, 2026-08-03): the loops used to be confined
        // to a ~0.6 m box, which read as a field in a display case. The
        // tracing bounds now span metres so the user stands inside the
        // field; the coarser step keeps the longer far-field loops cheap
        // while near loops still read as drawn curves.
        config.boundsRadius = 3.5
        // The bar the lines belong to. Everything the tracer does with
        // geometry — where seeds sit, where loops close, which field
        // model it integrates — comes off this one number, so it must
        // be the length the RENDERER actually draws.
        config.magnetLength = MagnetismModel.magnetLength
        config.seedsPerMagnet = 12
        config.referenceStrength = MagnetismModel.defaultStrength
        config.maxSteps = 2400
        config.stepSize = 0.008
        // EVEN THROUGH THE ROOM, not bundled around the bar (owner,
        // 2026-08-01). Seeds are spread through a room-scale box and
        // each candidate loop is rejected if it mostly retraces one
        // already drawn — see `traceThroughVolume`.
        let strongest = job.magnets.map(\.strength).max()
            ?? MagnetismModel.defaultStrength
        let traced = MagneticFieldLineTracer.traceThroughVolume(
            magnets: job.magnets,
            config: config,
            center: MagnetismModel.regionCenter,
            halfExtents: SIMD3(2.2, 1.2, 2.2),
            budget: lineBudget(forStrength: strongest))
        let lines = traced.map { $0.map(SIMD3<Float>.init) }
        var result = LinesResult()
        result.core = TubeMesh.buffers(lines: lines, radius: MagnetismRenderer.lineRadius)
        result.casing = TubeMesh.buffers(
            lines: lines,
            radius: Materials.casingRadius(forCore: MagnetismRenderer.lineRadius))
        result.glow = TubeMesh.buffers(lines: lines, radius: 0.0044)

        for line in traced {
            var walked = 0.0
            var nextAt = arrowSpacing / 2
            for index in 1..<line.count {
                let step = simd_distance(line[index], line[index - 1])
                walked += step
                if walked >= nextAt {
                    let point = line[index]
                    let nearMagnet = job.magnets.contains {
                        simd_distance($0.position, point) < arrowExclusion
                    }
                    if !nearMagnet {
                        result.arrowPoints.append(point)
                        result.arrowDirections.append(line[index] - line[index - 1])
                    }
                    nextAt += arrowSpacing
                }
            }
        }
        return result
    }

    private func applyLines(_ result: LinesResult) {
        linesEntity.model = TubeMesh.mesh(from: result.core).map {
            ModelComponent(mesh: $0, materials: [lineMaterial])
        }
        lineCasingEntity.model = TubeMesh.mesh(from: result.casing).map {
            ModelComponent(mesh: $0, materials: [lineCasingMaterial])
        }
        lineGlowEntity.model = TubeMesh.mesh(from: result.glow).map {
            ModelComponent(mesh: $0, materials: [lineGlowMaterial])
        }
        syncArrowHeads(points: result.arrowPoints,
                       directions: result.arrowDirections)
    }

    /// Re-aims the arrowhead pool, each cone rotated from its rest +y
    /// onto the loop's local direction there — the same treatment the
    /// electric field lines wear.
    private func syncArrowHeads(points: [SIMD3<Double>], directions: [SIMD3<Double>]) {
        for (index, slot) in arrowHeads.slots.enumerated() {
            guard index < points.count, index < directions.count else {
                slot.entity.isEnabled = false
                continue
            }
            let direction = directions[index]
            let length = simd_length(direction)
            guard length > 1e-12 else {
                slot.entity.isEnabled = false
                continue
            }
            slot.entity.isEnabled = true
            slot.entity.position = SIMD3<Float>(points[index])
            slot.entity.orientation = simd_quatf(
                from: [0, 1, 0], to: SIMD3<Float>(direction / length))
        }
    }

    private func syncFieldLines(_ model: MagnetismModel) {
        linesEntity.isEnabled = model.showFieldLines
        lineCasingEntity.isEnabled = model.showFieldLines
        lineGlowEntity.isEnabled = model.showFieldLines
        arrowHeads.root.isEnabled = model.showFieldLines
        guard model.showFieldLines else { return }
        let sources = model.magnets
        guard sources != lastLineInputs else { return }
        lastLineInputs = sources
        linesPipeline?.submit(LinesJob(magnets: sources))
    }

    // The 245-needle compass grid stood here until 2026-08-03, when the
    // owner cut it: with the field-line loops carrying the shape, the
    // lattice of tiny arrows was noise, and it was the thing that grew
    // when the strength bead moved while the loops did not. The hand
    // compass — the same instrument, one of it, in your hand — stays.
}
