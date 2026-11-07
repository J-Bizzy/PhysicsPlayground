//
//  MagnetismRenderer.swift
//  Physics Playground — Magnetism module
//
//  Renders the magnetic sandbox: bar magnets, the looping field lines
//  (traced off-main on a GeometryPipeline, drawn as a glowing tube), and
//  the hand compass.
//
//  Frame-rate contract: field lines rebuild only when the magnets move;
//  the per-frame path is transforms and needle orientation. Ticked from
//  SceneEvents.Update.
//

import Foundation
import PhysicsCore
import RealityKit
import RenderKit
import SwiftUI
import simd

@MainActor
final class MagnetismRenderer {
    /// The SpaceView's tap router, so a carried object can be operated
    /// without hands. A tap opens the magnet's control ring.
    var onObjectTap: ((Entity) -> Void)?

    let root = Entity()
    /// Everything the two-hand scale gesture grows lives under here;
    /// lighting stays on `root`. A pure view change — the model keeps its
    /// own coordinates, and every hand position converts through this root.
    let viewRoot = Entity()

    var subscriptions: [EventSubscription] = []

    /// Called from the SpaceView's `onDisappear`: an `EventSubscription`
    /// outlives the view and holds the entity graph alive, and a
    /// `GeometryPipeline` job in flight uploads into a dead scene (see
    /// `GeometryPipeline.cancel`).
    func teardown() {
        subscriptions.forEach { $0.cancel() }
        subscriptions = []
        linesPipeline?.cancel()
    }

    static let northColor = DesignTokens.Palette.positiveUI
    static let southColor = DesignTokens.Palette.negativeUI
    static let lineColor = DesignTokens.Palette.magnetismLineUI
    /// The hand compass's readout gold — module-local vocabulary.
    static let compassGold = UIColor(red: 0.95, green: 0.78, blue: 0.42, alpha: 1)

    private var magnetEntities: [UUID: Entity] = [:]
    private var magnetHalos: [UUID: Entity] = [:]

    private let linesEntity = ModelEntity()
    private let lineCasingEntity = ModelEntity()
    private let lineGlowEntity = ModelEntity()
    /// Core radius of a field loop; the casing is swept from it.
    nonisolated static let lineRadius: Float = 0.0016
    /// The core tube carries the direction cones too (N→S outside the
    /// magnet), appended to its buffers in `computeLines`: an arrowhead was
    /// an entity each, 300 draws on the opening bench (2026-11-06).
    private let lineMaterial = UnlitMaterial(color: MagnetismRenderer.lineColor)
    /// The near-black outline the bright core sits against — passthrough
    /// is a bright medium, so a pale loop needs the contrast casing.
    private let lineCasingMaterial =
        Materials.contrastLine(MagnetismRenderer.lineColor).casing
    private let lineGlowMaterial: UnlitMaterial = {
        let m = Materials.unlit(MagnetismRenderer.lineColor, opacity: 0.2)
        return m
    }()
    private var linesPipeline: GeometryPipeline<LinesJob, LinesResult>?
    private var lastLineInputs: [BarMagnet]?

    init() {
        root.addChild(Lighting.keyLight())
        root.addChild(viewRoot)
        // Order is the treatment: casing (darkness) under the glow,
        // glow under the bright core.
        viewRoot.addChild(lineCasingEntity)
        viewRoot.addChild(lineGlowEntity)
        viewRoot.addChild(linesEntity)

        // At most 30 times a second while a magnet moves: each result is
        // three tubes written in place (`GeometryPipeline.minimumInterval`).
        linesPipeline = GeometryPipeline(
            compute: { Self.computeLines($0) },
            apply: { [weak self] in self?.applyLines($0) },
            minimumInterval: 1.0 / 30
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
        syncCoils(model)
        acknowledgePull()
        syncFieldLines(model)
        syncHandCompass(model)
    }

    // MARK: Pickup coils

    /// The milled coil (`Tools/pickupcoil.py`) and the LED Swift lights in
    /// its socket. The asset's bore runs along +x.
    private struct CoilVisual {
        let container: Entity
        let dome: ModelEntity
        let glow: ModelEntity
        /// The LED's light on the copper beside it: the winding blushes red
        /// or green as the current runs.
        let light: Entity
        let halo: Entity
        /// The LED's drawn state: 0 dark, ±1…±8 red or green levels.
        var level: Int = 0
        /// The sign VoiceOver last heard: the colour is the only other
        /// way to tell which way the current runs.
        var spokenSign: Int = 0
    }

    private var coilVisuals: [UUID: CoilVisual] = [:]

    /// A magnet or coil just pulled from a well and carried by the view's
    /// own drag, not a grab session: it wears the glow from its first drawn
    /// frame and ticks where it is let go (2026-11-02). The well's pop is
    /// its grab sound.
    var pulledID: UUID? {
        didSet {
            guard pulledID != oldValue else { return }
            if let entity = pulledEntity { Grasp.letGo(entity) }
            pulledEntity = nil
        }
    }
    private weak var pulledEntity: Entity?

    private func acknowledgePull() {
        guard let id = pulledID, pulledEntity == nil,
              let entity = magnetEntities[id] ?? coilVisuals[id]?.container else { return }
        pulledEntity = entity
        Grasp.take(entity, tick: false)
    }

    /// Where the LED's dome stands on the coil: the socket's top, as the
    /// asset is milled (`LED_SEAT` in the script).
    nonisolated static let ledSeat: Float = 0.077
    nonisolated static let ledRadius: Float = 0.0065
    /// A red LED at 625 nm and a green one at 565 nm: the colours are the
    /// wavelengths a bicolour LED actually emits.
    static let ledRed = Spectrum.color(nanometers: 625)
    static let ledGreen = Spectrum.color(nanometers: 565)

    /// How bright the LED draws for a current: the square root of its share
    /// of a full 10 mA, so the faint glow of a slow push still shows.
    nonisolated static func ledLevel(current: Double) -> Int {
        let share = (abs(current) / 0.010).squareRoot()
        guard abs(current) > 5e-5 else { return 0 }
        let level = max(1, min(8, Int((share * 8).rounded())))
        return current > 0 ? level : -level
    }

    /// The coil's body, unlit: the milled asset, or a plain copper drum if
    /// it is missing (`VignettePropTests` would say so).
    static func coilBody() -> Entity {
        if let prototype = PropCache.prototype(named: "PickupCoil") {
            return prototype.clone(recursive: true)
        }
        let drum = ModelEntity(
            mesh: Primitives.cylinder(height: Float(MagnetismModel.coilLength),
                                      radius: Float(MagnetismModel.coilFlangeRadius)),
            materials: [Materials.machined(UIColor(red: 0.74, green: 0.43, blue: 0.22, alpha: 1))])
        drum.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
        return drum
    }

    /// The LED as it stands in its socket: a short body and a domed lens.
    static func ledDome() -> ModelEntity {
        let dome = ModelEntity(mesh: Primitives.sphere(radius: ledRadius, segments: 16),
                               materials: [ledOffMaterial])
        dome.position = [0, ledSeat + ledRadius * 0.85, 0]
        let body = ModelEntity(mesh: Primitives.cylinder(height: ledRadius, radius: ledRadius),
                               materials: [ledOffMaterial])
        body.position = [0, -ledRadius * 0.5, 0]
        dome.addChild(body)
        return dome
    }

    private static let ledOffMaterial = Materials.opticalGlass(
        UIColor(red: 0.96, green: 0.93, blue: 0.90, alpha: 1), opacity: 0.7)

    /// The coil as the well shows it: the real thing with its LED dark.
    static func coilPreview() -> Entity {
        let holder = Entity()
        let body = coilBody()
        body.addChild(ledDome())
        // Turned a little toward the viewer, so the bore reads as a bore.
        body.orientation = simd_quatf(angle: -0.5, axis: [0, 1, 0])
        holder.addChild(body)
        return holder
    }

    private func makeCoil(_ coil: MagnetismModel.Coil) -> CoilVisual {
        let container = Entity()
        container.name = coil.id.uuidString
        let body = Self.coilBody()
        container.addChild(body)
        let dome = Self.ledDome()
        container.addChild(dome)
        let glow = GlowSprite.make(size: 0.13)
        glow.position = dome.position
        glow.isEnabled = false
        container.addChild(glow)
        let light = Entity()
        light.position = dome.position + SIMD3(0, 0.012, 0)
        container.addChild(light)

        // A halo the coil's own shape — a drum along the bore — not a box,
        // which on a round part read as a frosted crate around it.
        let halo = SelectionHalo.make(mesh: Primitives.cylinder(
            height: Float(MagnetismModel.coilLength) + 0.03,
            radius: Float(MagnetismModel.coilFlangeRadius) + 0.01))
        halo.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
        container.addChild(halo)

        Grabbable.configureTouchTarget(container, matchingVisualBoundsOf: body,
                                       activate: { [weak self, weak container] in
                                           guard let container else { return }
                                           self?.onObjectTap?(container)
                                       })
        SpatialActions.describe(container, label: "Pickup coil", value: "dark")
        viewRoot.addChild(container)
        return CoilVisual(container: container, dome: dome, glow: glow, light: light, halo: halo)
    }

    private func syncCoils(_ model: MagnetismModel) {
        let live = Set(model.coils.map(\.id))
        for (id, visual) in coilVisuals where !live.contains(id) {
            Retire.entity(visual.container)
            coilVisuals[id] = nil
        }
        for coil in model.coils {
            var visual = coilVisuals[coil.id] ?? makeCoil(coil)
            visual.container.position = SIMD3<Float>(coil.position)
            visual.container.orientation = simd_quatf(from: [1, 0, 0], to: SIMD3<Float>(coil.axis))
            Fade.tick(visual.halo, visible: coil.id == model.selectedID)
            let level = Self.ledLevel(current: coil.current)
            if level != visual.level {
                visual.level = level
                Self.light(visual, level: level)
            }
            let sign = level.signum()
            if sign != visual.spokenSign {
                visual.spokenSign = sign
                SpatialActions.republish(value: sign == 0 ? "dark"
                                         : sign > 0 ? "lit red, current one way"
                                                    : "lit green, current the other way",
                                         on: visual.container)
            }
            coilVisuals[coil.id] = visual
        }
    }

    private static func mix(_ a: UIColor, _ b: UIColor, _ t: CGFloat) -> UIColor {
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        return UIColor(red: ar + (br - ar) * t, green: ag + (bg - ag) * t,
                       blue: ab + (bb - ab) * t, alpha: 1)
    }

    /// The LED at a level: the lens itself goes from milky to its colour,
    /// and a soft glow swells round it.
    private static func light(_ visual: CoilVisual, level: Int) {
        paintLED(dome: visual.dome, glow: visual.glow, light: visual.light, level: level)
    }

    /// Lights an LED dome at `ledLevel` — the lab's coil and the home's
    /// miniature of it, one look. `reach` is the point light's radius,
    /// which a miniature shrinks with itself.
    static func paintLED(dome: ModelEntity, glow: ModelEntity, light: Entity, level: Int,
                         reach: Float = 0.30) {
        guard level != 0 else {
            dome.model?.materials = [ledOffMaterial]
            dome.children.compactMap { $0 as? ModelEntity }
                .forEach { $0.model?.materials = [ledOffMaterial] }
            glow.isEnabled = false
            light.components.remove(PointLightComponent.self)
            return
        }
        let strength = Float(abs(level)) / 8
        let colour = level > 0 ? ledRed : ledGreen
        // Brighter is whiter at the core, as a real LED's lens saturates.
        let lit = Materials.unlit(mix(colour, .white, CGFloat(0.35 * strength)))
        dome.model?.materials = [lit]
        dome.children.compactMap { $0 as? ModelEntity }
            .forEach { $0.model?.materials = [lit] }
        glow.isEnabled = true
        GlowSprite.paint(glow, colour, strength: strength)
        // A few centimetres of reach: enough to colour the winding and the
        // flanges, not the room.
        light.components.set(PointLightComponent(
            color: colour, intensity: 900 * strength, attenuationRadius: reach))
    }

    // MARK: The compass you carry

    static let handCompassName = "hand-compass"
    /// The orb's radius — the collider matches it, per the rule that an
    /// input-targetable collider must never exceed what it represents.
    private static let compassRadius: Float = 0.055
    private let handCompass = Entity()
    private var handCompassNeedle: Entity?
    private var handCompassCallout: Callout?
    /// The reading last pushed, at display precision — skips rebuilding
    /// the string ninety times a second. NaN so the first frame writes.
    private var lastCompassReading: Double = .nan

    private func buildHandCompass() {
        handCompass.name = Self.handCompassName

        // A sphere, not a flat dial: a magnetic field points wherever it
        // likes (steeply up between two poles), and a flat dial can only
        // show the component lying in its plane. The needle aims in full
        // 3-D — `rotation(from:to:)` takes the whole vector.
        var shell = Materials.frostedGlass(
            UIColor(white: 0.62, alpha: 1), opacity: 0.20, frost: 0.35)
        shell.emissiveIntensity = 0.08
        let orb = ModelEntity(mesh: Primitives.sphere(radius: Self.compassRadius, segments: 48),
                              materials: [shell])
        handCompass.addChild(orb)

        // The needle: red north, white south, free to point anywhere. Square
        // in section, because a blade seen edge-on disappears.
        let needle = Entity()
        let north = ModelEntity(
            mesh: Self.bar(width: 0.008, length: 0.040, cornerRadius: 0.003),
            materials: [Materials.energized(DesignTokens.Palette.positiveUI, glow: 0.35)])
        north.position = [0, 0.020, 0]
        north.orientation = Self.barUpright
        let south = ModelEntity(
            mesh: Self.bar(width: 0.008, length: 0.040, cornerRadius: 0.003),
            materials: [Materials.energized(UIColor(white: 0.9, alpha: 1),
                                            metallic: 0.6, glow: 0.0)])
        south.position = [0, -0.020, 0]
        south.orientation = Self.barUpright
        needle.addChild(north)
        needle.addChild(south)
        // The poles say their names: the same extruded ivory letters the bar
        // magnets wear, doubled back-to-back so they read from either side.
        // They ride the needle, as painted labels would.
        for (text, tip) in [("N", Float(0.046)), ("S", Float(-0.046))] {
            for flip in [Float(0), .pi] {
                let letter = Self.poleLetter(text)
                letter.scale = SIMD3(repeating: 0.28)
                letter.position = [0, tip, 0]
                letter.orientation = simd_quatf(angle: flip, axis: [0, 1, 0])
                needle.addChild(letter)
            }
        }
        // A dark bead at the pivot, so the needle reads as suspended at
        // the centre rather than as two bars floating in glass.
        let hub = ModelEntity(
            mesh: Primitives.sphere(radius: 0.007, segments: 12),
            materials: [Materials.machined(UIColor(white: 0.22, alpha: 1))])
        needle.addChild(hub)
        handCompass.addChild(needle)
        handCompassNeedle = needle

        let callout = Callout(color: Self.compassGold,
                              textSize: 0.024, offset: SIMD3(0, 0.09, 0))
        callout.setAccessibilityName("Field at the compass")
        handCompassCallout = callout
        handCompass.addChild(callout.root)

        // Matched to the orb itself rather than a hand-typed 0.06 that
        // outgrew it — the collider rule again.
        Grabbable.configureTouchTarget(
            handCompass, collisionRadius: Self.compassRadius * 1.08,
            activate: { [weak self, weak handCompass] in
                guard let handCompass else { return }
                self?.onObjectTap?(handCompass)
            })
        SpatialActions.describe(handCompass, label: "Compass")
        viewRoot.addChild(handCompass)
    }

    private func syncHandCompass(_ model: MagnetismModel) {
        if handCompassNeedle == nil { buildHandCompass() }
        // Faded, as a layer from More is everywhere (2026-11-02).
        Fade.tick(handCompass, visible: model.compassOn)
        guard model.compassOn else { return }
        // Every frame, including while a hand owns it: these are relative
        // drags, so the model owns motion and the renderer follows it
        // unconditionally.
        handCompass.position = SIMD3<Float>(model.compassPosition)
        let field = model.compassField
        let magnitude = simd_length(field)
        if magnitude > 1e-12 {
            // The whole vector; the orb can show it, a flat dial could not.
            let direction = SIMD3<Float>(field / magnitude)
            // Under a south pole the field points straight down, which
            // is the antiparallel case.
            handCompassNeedle?.orientation = rotation(from: [0, 1, 0], to: direction)
        }
        // Formatted only when the displayed decimal actually moves; the
        // anchor is a transform and stays per-frame.
        // Recorded only once the callout takes it: a value its rate limit
        // held back is offered again next frame, not frozen on the one before.
        let reading = (model.compassMicroTesla * 10).rounded()
        if reading != lastCompassReading,
           handCompassCallout?.setText(
               PhysicsFormat.measurement(model.compassMicroTesla, "µT", decimals: 1)) == true {
            lastCompassReading = reading
        }
        handCompassCallout?.anchor(at: SIMD3(0, 0.05, 0))
    }

    // MARK: Magnets

    // MARK: Sound — the module's first voice
    // A pop as a magnet is born, a thud as two snap into contact.

    private var knownMagnetIDs: Set<UUID> = []
    /// Which magnets are currently touching, so a thud plays once on
    /// contact. Keyed on a struct: building strings from two UUIDs per
    /// pair, every frame, over an O(n²) loop, was 140 allocations a frame.
    private struct ContactPair: Hashable {
        let a: UUID, b: UUID

        init(_ a: UUID, _ b: UUID) {
            self.a = a
            self.b = b
        }

        /// Symmetric rather than sorted: ordering UUIDs would mean the
        /// `uuidString` allocation this type exists to remove.
        static func == (lhs: Self, rhs: Self) -> Bool {
            (lhs.a == rhs.a && lhs.b == rhs.b)
                || (lhs.a == rhs.b && lhs.b == rhs.a)
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(a.hashValue ^ b.hashValue)
        }
    }

    private var contactPairs: Set<ContactPair> = []

    /// Where the model's own sounds come from, moved to each as it plays.
    private let audioEmitter = Entity()
    /// Nil until the first frame, which adopts the model's last event
    /// rather than replaying it on entry.
    private var lastSoundID: Int?

    private func tickSounds(_ model: MagnetismModel) {
        if let event = model.soundEvent {
            if let lastSoundID, event.id != lastSoundID {
                if audioEmitter.parent == nil { viewRoot.addChild(audioEmitter) }
                audioEmitter.position = SIMD3<Float>(event.position)
                SoundPalette.play(event.kind, on: audioEmitter, volume: event.volume)
            }
            lastSoundID = event.id
        } else {
            lastSoundID = 0
        }

        // The arrival set is rebuilt only when the census changes — by
        // membership, not count: a reset swaps the lone default magnet for a
        // fresh id at the same count.
        let rosterChanged = model.magnets.count != knownMagnetIDs.count
            || model.magnets.contains { !knownMagnetIDs.contains($0.id) }
        if rosterChanged {
            let ids = Set(model.magnets.map(\.id))
            // Pop only for a roster that grew, and not for the opening scene.
            if ids.count > knownMagnetIDs.count, !knownMagnetIDs.isEmpty {
                for id in ids.subtracting(knownMagnetIDs) {
                    if let entity = magnetEntities[id] {
                        SoundPalette.play(.pop, on: entity, volume: 0.5)
                    }
                }
            }
            knownMagnetIDs = ids
        }

        let contact = MagnetismModel.magnetLength * 0.98
        var current: Set<ContactPair> = []
        for (index, a) in model.magnets.enumerated() {
            for b in model.magnets.dropFirst(index + 1) {
                let key = ContactPair(a.id, b.id)
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
        // The removal sweep has work when an entity outlives its magnet: a
        // count mismatch, or a fresh id at an unchanged count, which the follow
        // loop notices when it mints the entity.
        var mintedNew = false
        for magnet in model.magnets {
            if magnetEntities[magnet.id] == nil { mintedNew = true }
            let entity = magnetEntities[magnet.id] ?? makeMagnet(magnet)
            // The model owns motion (relative drag, no system manipulation),
            // so the entity follows it every frame — including while held,
            // or the magnet lags the hand until release.
            entity.position = SIMD3<Float>(magnet.position)
            // Orient the bar's +Y along the moment (S→N).
            entity.orientation = simd_quatf(
                from: [0, 1, 0], to: SIMD3<Float>(magnet.axis))
            if let halo = magnetHalos[magnet.id] {
                Fade.tick(halo, visible: magnet.id == model.selectedID)
            }
        }
        if mintedNew || magnetEntities.count != model.magnets.count {
            let live = Set(model.magnets.map(\.id))
            for (id, entity) in magnetEntities where !live.contains(id) {
                Retire.entity(entity)
                magnetEntities[id] = nil
                magnetHalos[id] = nil
            }
        }
    }

    /// An extruded, centred pole letter in warm ivory — generateText's
    /// origin is the baseline's left edge, so the glyph is re-centred
    /// from its measured bounds.
    private static var poleLetterMeshes: [String: MeshResource] = [:]

    private static func poleLetter(_ text: String) -> ModelEntity {
        // Two letters, milled once: every magnet and the well's preview
        // built four fresh extrusions each (2026-11-06).
        let mesh: MeshResource
        if let cached = poleLetterMeshes[text] {
            mesh = cached
        } else {
            mesh = MeshResource.generateText(
                text,
                extrusionDepth: 0.006,
                font: .systemFont(ofSize: 0.034, weight: .heavy),
                containerFrame: .zero,
                alignment: .center,
                lineBreakMode: .byClipping)
            poleLetterMeshes[text] = mesh
        }
        let entity = ModelEntity(
            mesh: mesh,
            materials: [Materials.energized(UIColor(red: 0.98, green: 0.96, blue: 0.90, alpha: 1),
                                            roughness: 0.3, glow: 0.12)])
        entity.name = "pole-letter"
        let bounds = entity.visualBounds(relativeTo: nil)
        entity.position = [-bounds.center.x, -bounds.center.y, 0]
        let pivot = ModelEntity()
        pivot.addChild(entity)
        return pivot
    }

    /// A square-section bar standing along y with its long edges rounded
    /// and its ends flat — a bar magnet's half, its chrome band, a compass
    /// needle. `Primitives.roundedBar` rounds in x/y and extrudes along z,
    /// so the bar is milled lying and stood up with `barUpright`: 80
    /// triangles where a rounded `generateBox` was 13 000 (2026-11-06).
    static func bar(width: Float, length: Float, cornerRadius: Float) -> MeshResource {
        Primitives.roundedBar(size: [width, width, length], cornerRadius: cornerRadius)
    }
    static let barUpright = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])

    /// The magnet as the well shows it: the same halves, colours, chrome
    /// band and pole letters as the real thing, minus the halo and the
    /// collider. Static, so `Well` can call it without a model.
    static func magnetPreview() -> Entity {
        let container = Entity()
        let half = Float(MagnetismModel.magnetLength) / 2
        let w: Float = 0.05

        let north = ModelEntity(
            mesh: bar(width: w, length: half, cornerRadius: 0.006),
            materials: [Materials.energized(northColor, roughness: 0.28, glow: 0.16)])
        north.position = [0, half / 2, 0]
        north.orientation = barUpright
        let south = ModelEntity(
            mesh: bar(width: w, length: half, cornerRadius: 0.006),
            materials: [Materials.energized(southColor, roughness: 0.28, glow: 0.16)])
        south.position = [0, -half / 2, 0]
        south.orientation = barUpright
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
            mesh: bar(width: w + 0.006, length: 0.014, cornerRadius: 0.004),
            materials: [Materials.machined(UIColor(white: 0.86, alpha: 1))])
        band.orientation = barUpright
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
            mesh: Self.bar(width: w, length: half, cornerRadius: 0.006),
            materials: [Materials.energized(Self.northColor, roughness: 0.28, glow: 0.16)])
        north.position = [0, half / 2, 0]
        north.orientation = Self.barUpright
        let south = ModelEntity(
            mesh: Self.bar(width: w, length: half, cornerRadius: 0.006),
            materials: [Materials.energized(Self.southColor, roughness: 0.28, glow: 0.16)])
        south.position = [0, -half / 2, 0]
        south.orientation = Self.barUpright
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
            mesh: Self.bar(width: w + 0.006, length: 0.014, cornerRadius: 0.004),
            materials: [Materials.machined(UIColor(white: 0.86, alpha: 1))])
        band.orientation = Self.barUpright
        container.addChild(band)

        // Selection halo (a soft shell the bar's own shape), hidden until
        // selected — and the opening selects a magnet, so it is drawn.
        let halo = SelectionHalo.make(mesh: Self.bar(
            width: w + 0.03, length: half * 2 + 0.03, cornerRadius: 0.012))
        halo.orientation = Self.barUpright
        container.addChild(halo)
        magnetHalos[magnet.id] = halo

        // A bar is not a ball: a sphere sized to the long axis shielded
        // neighbouring magnets broadside. Measured from the halo, the magnet's
        // own silhouette.
        Grabbable.configureTouchTarget(
            container, matchingVisualBoundsOf: container,
            activate: { [weak self, weak container] in
                guard let container else { return }
                self?.onObjectTap?(container)
            })
        SpatialActions.describe(container, label: "Bar magnet")

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
    }

    /// The direction cones riding each loop, in the core tube's own mesh.
    nonisolated static let arrowHeight: Float = 0.02
    nonisolated static let arrowRadius: Float = 0.0078

    /// Arc-length spacing of the direction arrowheads riding each loop;
    /// loops are metres long at room scale.
    private nonisolated static let arrowSpacing = 0.42
    /// No arrowheads this close to a magnet, where loops bunch tightly.
    private nonisolated static let arrowExclusion = 0.14

    /// How many loops a bench this strong deserves — monotonic in the
    /// strongest |m|, so the strength bead visibly changes the picture;
    /// clamped so a weak bench still draws and a strong one does not drown
    /// the frame.
    nonisolated static func lineBudget(forStrength strength: Double) -> Int {
        let scaled = 26.0 * strength / MagnetismModel.defaultStrength
        return Int(min(max(scaled, 12), 48).rounded())
    }

    private nonisolated static func computeLines(_ job: LinesJob) -> LinesResult {
        var config = MagneticFieldLineTracer.Config()
        config.boundsCenter = MagnetismModel.regionCenter
        // Room-scale bounds, so the user stands inside the field; the coarser
        // step keeps the long far-field loops cheap.
        config.boundsRadius = 3.5
        // The bar the lines belong to: seeds, loop closure and the field model
        // all come off this one number, so it must be the length the renderer
        // draws.
        config.magnetLength = MagnetismModel.magnetLength
        config.seedsPerMagnet = 12
        config.referenceStrength = MagnetismModel.defaultStrength
        config.maxSteps = 2400
        config.stepSize = 0.008
        // Even through the room, not bundled around the bar: seeds spread
        // through a room-scale box, and a loop that mostly retraces one already
        // drawn is rejected.
        let strongest = job.magnets.map(\.strength).max()
            ?? MagnetismModel.defaultStrength
        let traced = MagneticFieldLineTracer.traceThroughVolume(
            magnets: job.magnets,
            config: config,
            center: MagnetismModel.regionCenter,
            halfExtents: SIMD3(2.2, 1.2, 2.2),
            budget: lineBudget(forStrength: strongest))
        // Thin the polylines before they become tubes: the tracer walks 8 mm
        // steps and three tubes are built from the same lines, so 48 full loops
        // were ~576 000 vertices per tube. `decimated` keeps every point a
        // curve needs.
        let lines = TubeMesh.decimated(
            traced.map { $0.map(SIMD3<Float>.init) },
            spacing: 0.05, maximumTurn: .pi / 18)
        var result = LinesResult()
        result.core = TubeMesh.buffers(lines: lines, radius: MagnetismRenderer.lineRadius)
        result.casing = TubeMesh.buffers(
            lines: lines,
            radius: Materials.casingRadius(forCore: MagnetismRenderer.lineRadius))
        result.glow = TubeMesh.buffers(lines: lines, radius: 0.0044)

        // Sample points along the loops where arrowheads ride, with the
        // local line direction — B points N→S outside the magnet, and the
        // arrows finally say so. They ride in the core tube's own mesh.
        var arrowPoints: [SIMD3<Float>] = []
        var arrowDirections: [SIMD3<Float>] = []
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
                        arrowPoints.append(SIMD3<Float>(point))
                        arrowDirections.append(SIMD3<Float>(line[index] - line[index - 1]))
                    }
                    nextAt += arrowSpacing
                }
            }
        }
        TubeMesh.appendCones(to: &result.core, at: arrowPoints, directions: arrowDirections,
                             height: arrowHeight, radius: arrowRadius)
        return result
    }

    private func applyLines(_ result: LinesResult) {
        // Rewritten in place (`LiveTube`): a moving magnet re-meshes the
        // lines every frame.
        LiveTube.apply(result.core, to: linesEntity, material: lineMaterial)
        LiveTube.apply(result.casing, to: lineCasingEntity, material: lineCasingMaterial)
        LiveTube.apply(result.glow, to: lineGlowEntity, material: lineGlowMaterial)
    }

    /// Whether the bench has moved enough to be worth tracing again. Exact
    /// inequality re-traced every frame of every glide; 2 mm and ~1.1° are
    /// below what 8 mm steps through a 3.5 m volume can express. Adding or
    /// removing a magnet always retraces.
    private nonisolated static func fieldLinesWorthRetracing(
        _ sources: [BarMagnet], versus previous: [BarMagnet]?
    ) -> Bool {
        guard let previous else { return true }
        guard previous.count == sources.count else { return true }
        for (magnet, was) in zip(sources, previous) {
            if magnet.id != was.id { return true }
            if simd_distance(magnet.position, was.position) > 0.002 { return true }
            // Compares the moment itself, so a strength change counts as
            // much as a rotation — the strength bead redraws the field.
            if simd_distance(magnet.moment, was.moment)
                > 0.02 * MagnetismModel.defaultStrength { return true }
        }
        return false
    }

    private func syncFieldLines(_ model: MagnetismModel) {
        // Faded rather than switched (2026-11-02): the layer comes and goes
        // as everything else in the room does.
        for layer in [linesEntity, lineCasingEntity, lineGlowEntity] {
            Fade.tick(layer, visible: model.showFieldLines)
        }
        guard model.showFieldLines else { return }
        let sources = model.magnets
        guard Self.fieldLinesWorthRetracing(sources, versus: lastLineInputs) else { return }
        lastLineInputs = sources
        linesPipeline?.submit(LinesJob(magnets: sources))
    }

}
