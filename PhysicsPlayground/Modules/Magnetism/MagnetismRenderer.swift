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

    // MARK: Induction — the coil's filament answers a waved magnet
    private let inductionGlow = ModelEntity(
        mesh: .generateSphere(radius: 0.016),
        materials: [UnlitMaterial(color: .white)])
    private var inductionCallout: Callout?
    private static let fullGlowVolts = 0.04
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

    // Compass needle grid.
    private let compassRoot = Entity()
    private var needles: [Entity] = []
    private nonisolated static let compassColumns = (x: 7, y: 5, z: 7)

    init() {
        let headMesh = MeshResource.generateCone(height: 0.02, radius: 0.0078)
        let headMaterial = UnlitMaterial(color: MagnetismRenderer.lineColor)
        arrowHeads = EntityPool(budget: 300) { container in
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
        viewRoot.addChild(compassRoot)
        buildCompassGrid()

        linesPipeline = GeometryPipeline(
            compute: { Self.computeLines($0) },
            apply: { [weak self] in self?.applyLines($0) }
        )
    }

    // MARK: Per-frame

    /// World → model coordinates, through however the view is scaled
    /// and turned. Every hand and head position enters the model here.
    /// Faraday's law with a face: a filament in the coil's bore that
    /// glows with the induced EMF, and a millivolt readout when it is
    /// worth reading. Wave a magnet through the coil — the harder you
    /// pump, the brighter it burns. The coil needs no battery for
    /// this; that is the entire point.
    /// Opacity steps for the induction filament, banked once.
    private static let filamentSteps = 12
    private static let filamentMaterials: [UnlitMaterial] =
        (0..<filamentSteps).map { step in
            var material = UnlitMaterial(
                color: UIColor(red: 1.0, green: 0.85, blue: 0.55, alpha: 1))
            let level = Float(step) / Float(filamentSteps - 1)
            material.blending = .transparent(
                opacity: .init(floatLiteral: 0.25 + 0.75 * level))
            return material
        }
    private var filamentBucket = -1

    private func syncInduction(_ model: MagnetismModel) {
        guard model.electromagnetOn else {
            inductionGlow.isEnabled = false
            inductionCallout?.isEnabled = false
            return
        }
        if inductionGlow.parent == nil { viewRoot.addChild(inductionGlow) }
        let level = Float(min(abs(model.inducedEMF) / Self.fullGlowVolts, 1))
        inductionGlow.position = SIMD3<Float>(model.electromagnetPosition)
        inductionGlow.isEnabled = level > 0.03
        if inductionGlow.isEnabled {
            // The brightness is continuous; the MATERIAL is not. This
            // used to build a fresh `UnlitMaterial` on every frame the
            // filament burned — which is every frame a magnet is moving,
            // the one time the module is busiest. Twelve banked steps
            // are indistinguishable from the ramp, and a step that has
            // not changed writes nothing.
            let bucket = min(max(Int(level * Float(Self.filamentSteps - 1) + 0.5), 0),
                             Self.filamentSteps - 1)
            if filamentBucket != bucket {
                filamentBucket = bucket
                inductionGlow.model?.materials = [Self.filamentMaterials[bucket]]
            }
            inductionGlow.scale = SIMD3(repeating: 0.7 + 0.9 * level)
        }
        if inductionCallout == nil {
            let callout = Callout(color: UIColor(red: 1.0, green: 0.85, blue: 0.55, alpha: 1),
                                  textSize: 0.018, offset: SIMD3(0, 0.10, 0))
            viewRoot.addChild(callout.root)
            inductionCallout = callout
        }
        let showText = level > 0.08
        inductionCallout?.isEnabled = showText
        if showText {
            inductionCallout?.anchor(at: SIMD3<Float>(model.electromagnetPosition))
            inductionCallout?.setText(String(format: "ε %.0f mV", model.inducedEMF * 1000))
        }
    }

    func displayPoint(fromWorld world: SIMD3<Float>) -> SIMD3<Double> {
        SIMD3<Double>(viewRoot.convert(position: world, from: nil))
    }

    func tick(_ model: MagnetismModel, viewer: SIMD3<Double>? = nil) {
        tickSounds(model)
        syncElectromagnet(model)
        syncMagnets(model)
        syncFieldLines(model)
        syncCompasses(model, viewer: viewer.map(SIMD3<Float>.init))
        syncHandCompass(model)
    }

    // MARK: The electromagnet the circuit bench powers

    static let electromagnetName = "electromagnet"
    private let coilRoot = Entity()
    private var coilBuilt = false
    private var coilCallout: Callout?

    private func buildElectromagnet() {
        coilBuilt = true
        coilRoot.name = Self.electromagnetName

        // An iron core with copper windings — a solenoid anyone would
        // recognise, sized to the coil radius the physics uses.
        let radius = Float(MagnetismModel.coilRadius)
        let core = ModelEntity(
            mesh: .generateCylinder(height: radius * 2.4, radius: radius * 0.52),
            materials: [Materials.machined(UIColor(white: 0.42, alpha: 1))])
        core.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
        coilRoot.addChild(core)

        // The winding, as a real helix swept along the axis.
        let turnsShown = 14
        let stepsPerTurn = 16
        var helix: [SIMD3<Float>] = []
        for step in 0...(turnsShown * stepsPerTurn) {
            let t = Float(step) / Float(turnsShown * stepsPerTurn)
            let angle = t * Float(turnsShown) * 2 * .pi
            helix.append(SIMD3((t - 0.5) * radius * 2.2,
                               cos(angle) * radius * 0.78,
                               sin(angle) * radius * 0.78))
        }
        if let mesh = TubeMesh.tube(lines: [helix], radius: 0.0045, sides: 5) {
            coilRoot.addChild(ModelEntity(
                mesh: mesh,
                // A driven winding is genuinely warm, so this is the
                // one metal here that keeps a glow.
                materials: [Materials.machined(DesignTokens.Palette.copperUI,
                                               glow: 0.12)]))
        }

        let callout = Callout(color: DesignTokens.Palette.copperUI,
                              textSize: 0.024, offset: SIMD3(0, 0.12, 0))
        coilCallout = callout
        coilRoot.addChild(callout.root)

        Grabbable.configureTouchTarget(coilRoot, collisionRadius: radius * 1.6)
        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = "Electromagnet. Its strength is the current your circuit bench is delivering."
        coilRoot.components.set(accessibility)
        viewRoot.addChild(coilRoot)
    }

    private func syncElectromagnet(_ model: MagnetismModel) {
        if !coilBuilt { buildElectromagnet() }
        coilRoot.isEnabled = model.electromagnetOn
        syncInduction(model)
        guard model.electromagnetOn else { return }
        // Every frame, held or not — see `syncHandCompass`.
        coilRoot.position = SIMD3<Float>(model.electromagnetPosition)
        coilRoot.orientation = simd_quatf(
            from: [1, 0, 0], to: SIMD3<Float>(simd_normalize(model.electromagnetAxis)))
        // The coil says what the circuit is giving it: no current, no
        // magnet — which is exactly what opening the switch does.
        coilCallout?.setText(String(
            format: "%.3f A   m = %.2f A·m²",
            model.coilCurrent, model.electromagnetMoment))
        coilCallout?.anchor(at: SIMD3(0, Float(MagnetismModel.coilRadius) * 1.2, 0))
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
        // and the coil kept the defect for months because nobody had
        // tried to carry either of them.
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
    private nonisolated static let arrowSpacing = 0.26
    /// No arrowheads this close to a magnet, where loops bunch tightly.
    private nonisolated static let arrowExclusion = 0.14

    private nonisolated static func computeLines(_ job: LinesJob) -> LinesResult {
        var config = MagneticFieldLineTracer.Config()
        config.boundsCenter = MagnetismModel.regionCenter
        // Let each loop run far enough to close — the full curvy dipole
        // pattern, not a few short arcs. The 6 mm step is what makes the
        // loops read as drawn curves instead of chained segments.
        config.boundsRadius = MagnetismModel.regionHalfExtent * 1.9
        // The bar the lines belong to. Everything the tracer does with
        // geometry — where seeds sit, where loops close, which field
        // model it integrates — comes off this one number, so it must
        // be the length the RENDERER actually draws.
        config.magnetLength = MagnetismModel.magnetLength
        config.seedsPerMagnet = 12
        config.referenceStrength = MagnetismModel.defaultStrength
        config.maxSteps = 950
        config.stepSize = 0.006
        // EVEN THROUGH THE ROOM, not bundled around the bar (owner,
        // 2026-08-01). Seeds are spread through the region's own box and
        // each candidate loop is rejected if it mostly retraces one
        // already drawn — see `traceThroughVolume`, which also spells out
        // what this trades away: line density no longer encodes field
        // strength, so the legend says the picture is the field's SHAPE.
        let traced = MagneticFieldLineTracer.traceThroughVolume(
            magnets: job.magnets,
            config: config,
            center: MagnetismModel.regionCenter,
            halfExtents: MagnetismModel.regionHalfExtents,
            budget: 26)
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
        let sources = model.allSources
        guard sources != lastLineInputs else { return }
        lastLineInputs = sources
        linesPipeline?.submit(LinesJob(magnets: sources))
    }

    // MARK: Compass needle grid

    private nonisolated static let gridPoints: [SIMD3<Float>] = {
        var points: [SIMD3<Float>] = []
        let (nx, ny, nz) = compassColumns
        let span = Float(MagnetismModel.regionHalfExtent) * 1.7
        let origin = SIMD3<Float>(MagnetismModel.regionCenter) - SIMD3(repeating: span / 2)
        func step(_ n: Int) -> Float { n > 1 ? span / Float(n - 1) : 0 }
        for i in 0..<nx { for j in 0..<ny { for k in 0..<nz {
            points.append(origin + SIMD3(Float(i) * step(nx),
                                         Float(j) * step(ny),
                                         Float(k) * step(nz)))
        } } }
        return points
    }()

    private func buildCompassGrid() {
        // Iron filings, not a swarm of darts.
        //
        // The needles were rendered at one fixed, generous size across
        // the whole 245-point lattice, which meant the ones nearest the
        // viewer became big opaque purple arrowheads clipping into the
        // camera and occluding the magnets, the field lines, and each
        // other. What a field of filings actually looks like is SMALL
        // and MANY: each needle short, dim, and fading with distance, so
        // the eye reads a texture with a direction rather than counting
        // individual objects.
        var shaftMaterial = UnlitMaterial(color: UIColor(white: 0.88, alpha: 1))
        shaftMaterial.blending = .transparent(opacity: 0.35)
        let headMaterial = Materials.energized(Self.lineColor, roughness: 0.18, glow: 0.45)
        let shaftMesh = MeshResource.generateCylinder(height: 0.042, radius: 0.0016)
        let headMesh = MeshResource.generateCone(height: 0.015, radius: 0.005)
        for point in Self.gridPoints {
            let needle = Entity()
            let shaft = ModelEntity(mesh: shaftMesh, materials: [shaftMaterial])
            let head = ModelEntity(mesh: headMesh, materials: [headMaterial])
            head.position = [0, 0.029, 0]
            needle.addChild(shaft)
            needle.addChild(head)
            needle.position = point
            needle.isEnabled = false
            compassRoot.addChild(needle)
            needles.append(needle)
        }
    }

    /// Needles this close to the viewer are hidden outright — a compass
    /// needle 20 cm from your eye is not information, it is an obstacle.
    private nonisolated static let compassNearCull: Float = 0.55

    private func syncCompasses(_ model: MagnetismModel, viewer: SIMD3<Float>?) {
        compassRoot.isEnabled = model.showCompasses
        guard model.showCompasses else { return }
        // Hide needles too close to a magnet (inside the singular near
        // field), where the field is too weak to read, or right in the
        // viewer's face.
        let magnets = model.allSources
        let eye = viewer ?? SIMD3<Float>(0, 1.5, 0)
        for (index, needle) in needles.enumerated() {
            let gridPoint = Self.gridPoints[index]
            let point = SIMD3<Double>(gridPoint)
            let tooClose = magnets.contains {
                simd_distance($0.position, point) < MagnetismModel.magnetLength
            }
            let distance = simd_distance(gridPoint, eye)
            let b = MagneticField.vector(at: point, dueTo: magnets)
            let mag = simd_length(b)
            if tooClose || mag < 2e-6 || distance < Self.compassNearCull {
                needle.isEnabled = false
                continue
            }
            needle.isEnabled = true
            needle.orientation = simd_quatf(from: [0, 1, 0], to: SIMD3<Float>(b / mag))
            // Near needles shrink toward nothing over the cull distance,
            // so the grid thins out around the viewer instead of
            // slamming into them, and never pops as they walk.
            let fade = min(max((distance - Self.compassNearCull) / 0.45, 0), 1)
            needle.scale = SIMD3(repeating: 0.35 + 0.65 * fade)
        }
    }
}
