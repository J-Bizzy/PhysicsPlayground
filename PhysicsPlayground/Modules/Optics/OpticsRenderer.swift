//
//  OpticsRenderer.swift
//  Physics Playground — Light & Optics
//
//  Draws the optics, the light and where it lands. Frame-rate contract:
//  the pieces follow the model every frame (transforms only); the beams
//  and spots are rebuilt only when the trace changes, and then only
//  transforms and a handful of cached materials — a beam is a pooled unit
//  cylinder stretched between its two ends, like a circuit's wire.
//
//  A beam is light, so it is drawn as light: an unlit core in its own
//  colour inside a faint glow of the same colour, at a strength that is
//  its share of the power. Where it lands on the room, a soft spot.
//

import Foundation
import PhysicsCore
import RealityKit
import RenderKit
import SwiftUI
import simd

@MainActor
final class OpticsRenderer {
    /// The SpaceView's tap router, so a piece can be operated without hands.
    var onObjectTap: ((Entity) -> Void)?

    let root = Entity()
    let viewRoot = Entity()
    var subscriptions: [EventSubscription] = []

    func teardown() {
        subscriptions.forEach { $0.cancel() }
        subscriptions = []
    }

    static let aimBeadName = "optics-aim-bead"
    /// How far out along its aim a piece's bead stands.
    static let aimReach: Float = 0.17
    static let accent = UIColor(DesignTokens.Palette.opticsAccent)

    private var pieceEntities: [UUID: Entity] = [:]
    private var halos: [UUID: Entity] = [:]
    private let laserEntity = Entity()
    private let torchEntity = Entity()
    private var laserGlow: ModelEntity?
    private var torchGlow: ModelEntity?

    private let beams: EntityPool<(core: ModelEntity, glow: ModelEntity)>
    private let spots: EntityPool<ModelEntity>
    private let normals: EntityPool<ModelEntity>
    private let aimBead = Entity()
    private let aimStalk: ModelEntity

    private var drawnVersion = -1
    private var drawnAngles = false
    /// What each beam slot last wore, so a re-trace — every frame while a
    /// piece is carried — sets materials only on the beams whose look
    /// changed, not on all of them.
    private struct BeamLook: Equatable {
        var colour: UIColor
        var level: Float
        var inGlass: Bool
    }
    private var beamLooks: [Int: BeamLook] = [:]
    /// The same for the landing spots: a colour and a level.
    private var spotLooks: [Int: BeamLook] = [:]

    /// Core and glow radii, metres: a laser pointer's millimetre beam.
    private static let coreRadius: Float = 0.0011
    private static let glowRadius: Float = 0.0042
    /// How big a landing looks: a few times the beam, softened.
    private static let spotSize: Float = 0.06

    init() {
        let unit = Primitives.cylinder(height: 1, radius: 1)
        beams = EntityPool(budget: 320) { container in
            let core = ModelEntity(mesh: unit, materials: [])
            let glow = ModelEntity(mesh: unit, materials: [])
            container.addChild(glow)
            container.addChild(core)
            return (core, glow)
        }
        let square = Primitives.plane(width: 1, height: 1, cornerRadius: 0)
        spots = EntityPool(budget: 96) { container in
            let sprite = ModelEntity(mesh: square, materials: [])
            container.addChild(sprite)
            return sprite
        }
        let normalMaterial = Materials.unlit(UIColor(white: 0.96, alpha: 1), opacity: 0.55)
        normals = EntityPool(budget: 48) { container in
            let line = ModelEntity(mesh: unit, materials: [normalMaterial])
            container.addChild(line)
            return line
        }
        aimStalk = ModelEntity(mesh: unit,
                               materials: [Materials.unlit(Self.accent, opacity: 0.6)])

        root.addChild(Lighting.keyLight())
        root.addChild(viewRoot)
        viewRoot.addChild(beams.root)
        viewRoot.addChild(spots.root)
        viewRoot.addChild(normals.root)
        buildSources()
        buildAimBead()
    }

    /// World → lab coordinates.
    func displayPoint(fromWorld world: SIMD3<Float>) -> SIMD3<Double> {
        SIMD3<Double>(viewRoot.convert(position: world, from: nil))
    }

    // MARK: Per frame

    func tick(_ model: OpticsModel) {
        syncPieces(model)
        syncSources(model)
        let trace = model.traceIfNeeded()
        if model.traceVersion != drawnVersion || model.showsAngles != drawnAngles {
            drawnVersion = model.traceVersion
            drawnAngles = model.showsAngles
            drawLight(trace, angles: model.showsAngles)
        }
        syncAimBead(model)
        playSound(model)
    }

    /// Where the model's sounds come from, moved to each as it plays.
    private let audioEmitter = Entity()
    /// Nil until the first frame, which adopts the model's last event
    /// rather than replaying it on entry.
    private var lastSoundID: Int?

    private func playSound(_ model: OpticsModel) {
        guard let event = model.soundEvent else { lastSoundID = 0; return }
        defer { lastSoundID = event.id }
        guard let lastSoundID, event.id != lastSoundID else { return }
        if audioEmitter.parent == nil { viewRoot.addChild(audioEmitter) }
        audioEmitter.position = SIMD3<Float>(event.position)
        SoundPalette.play(event.kind, on: audioEmitter, volume: event.volume)
    }

    // MARK: The light

    private func drawLight(_ trace: LightTracer.Result, angles: Bool) {
        let strokes = OpticsBeamLayout.strokes(trace)
        for (index, slot) in beams.slots.enumerated() {
            guard index < strokes.count else {
                slot.entity.isEnabled = false
                continue
            }
            let stroke = strokes[index]
            let length = simd_distance(stroke.a, stroke.b)
            guard length > 1e-5 else {
                slot.entity.isEnabled = false
                continue
            }
            slot.entity.isEnabled = true
            slot.entity.position = (stroke.a + stroke.b) / 2
            slot.entity.orientation = rotation(from: [0, 1, 0], to: (stroke.b - stroke.a) / length)
            let level = OpticsBeamLayout.level(stroke.strength)
            let colour = Self.color(stroke.color)
            slot.payload.core.scale = [Self.coreRadius, length, Self.coreRadius]
            slot.payload.glow.scale = [Self.glowRadius, length, Self.glowRadius]
            let look = BeamLook(colour: colour, level: level, inGlass: stroke.inGlass)
            guard beamLooks[index] != look else { continue }
            beamLooks[index] = look
            slot.payload.core.model?.materials = [Materials.unlit(colour, opacity: level)]
            // Inside glass the glow is the light scattering in the piece; outside,
            // the haze a beam shows in a room.
            slot.payload.glow.model?.materials = [Materials.unlit(colour,
                                                                  opacity: (stroke.inGlass ? 0.32 : 0.16) * level)]
        }

        let landed = OpticsBeamLayout.spots(trace)
        for (index, slot) in spots.slots.enumerated() {
            guard index < landed.count else {
                slot.entity.isEnabled = false
                continue
            }
            let spot = landed[index]
            slot.entity.isEnabled = true
            // A hair off the surface, facing out of it.
            slot.entity.position = spot.point + spot.normal * 0.002
            slot.entity.orientation = rotation(from: [0, 0, 1], to: spot.normal)
            slot.entity.scale = SIMD3(repeating: Self.spotSize)
            let look = BeamLook(colour: Self.color(spot.color),
                                level: OpticsBeamLayout.level(spot.strength), inGlass: false)
            guard spotLooks[index] != look else { continue }
            spotLooks[index] = look
            slot.payload.model?.materials = [Self.spotMaterial(look.colour, level: look.level)]
        }

        // Each surface's normal, where light met it: a short white line through
        // the point, the thing the angles of incidence and refraction are
        // measured from.
        let shown = angles ? Self.normalMarks(trace) : []
        for (index, slot) in normals.slots.enumerated() {
            guard index < shown.count else {
                slot.entity.isEnabled = false
                continue
            }
            let mark = shown[index]
            slot.entity.isEnabled = true
            slot.entity.position = mark.point
            slot.entity.orientation = rotation(from: [0, 1, 0], to: mark.normal)
            slot.payload.scale = [0.0007, 0.09, 0.0007]
        }
    }

    /// One mark per surface the strong light met, not one per wavelength.
    private static func normalMarks(_ trace: LightTracer.Result)
        -> [(point: SIMD3<Float>, normal: SIMD3<Float>)] {
        let peak = OpticsBeamLayout.peaks(trace.segments)
        var marks: [(SIMD3<Float>, SIMD3<Float>)] = []
        for event in trace.events {
            let strength = event.power / max(peak[event.nanometers] ?? event.power, 1e-12)
            guard strength > 0.2 else { continue }
            let point = SIMD3<Float>(event.point)
            guard !marks.contains(where: { simd_distance($0.0, point) < 0.004 }) else { continue }
            marks.append((point, SIMD3<Float>(event.normal)))
        }
        return marks
    }

    static func color(_ linear: SIMD3<Double>) -> UIColor {
        func encode(_ v: Double) -> CGFloat {
            let c = min(max(v, 0), 1)
            return CGFloat(c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055)
        }
        // Quantised, so a colour the trace repeats is one cached material.
        func step(_ v: CGFloat) -> CGFloat { (v * 32).rounded() / 32 }
        return UIColor(red: step(encode(linear.x)), green: step(encode(linear.y)),
                       blue: step(encode(linear.z)), alpha: 1)
    }

    // MARK: Spots

    private static var spotMaterials: [String: UnlitMaterial] = [:]
    private static let glowTexture: TextureResource? = {
        let size = 96
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format)
            .image { context in
                UIColor.black.setFill()
                context.fill(CGRect(x: 0, y: 0, width: size, height: size))
                let stops: [(CGFloat, CGFloat)] = [(0, 1), (0.22, 0.8), (0.5, 0.22), (1, 0)]
                guard let gradient = CGGradient(
                    colorsSpace: CGColorSpaceCreateDeviceGray(),
                    colors: stops.map { UIColor(white: $0.1, alpha: 1).cgColor } as CFArray,
                    locations: stops.map(\.0)) else { return }
                let centre = CGPoint(x: size / 2, y: size / 2)
                context.cgContext.drawRadialGradient(
                    gradient, startCenter: centre, startRadius: 0,
                    endCenter: centre, endRadius: CGFloat(size) / 2, options: [])
            }
        guard let cg = image.cgImage else { return nil }
        return try? TextureResource(image: cg, options: .init(semantic: .raw))
    }()

    /// A soft round glow: the colour, with its opacity read from the radial
    /// mask (a colour texture's alpha draws a pale square). Light, not a
    /// surface, so it writes no depth.
    private static func spotMaterial(_ colour: UIColor, level: Float) -> UnlitMaterial {
        let key = "\(colour.description)|\(level)"
        if let cached = spotMaterials[key] { return cached }
        var material = UnlitMaterial(color: colour)
        if let glowTexture {
            material.blending = .transparent(opacity: .init(scale: level, texture: .init(glowTexture)))
        } else {
            material.blending = .transparent(opacity: .init(floatLiteral: 0.6 * level))
        }
        material.writesDepth = false
        if spotMaterials.count > 200 { spotMaterials.removeAll() }
        spotMaterials[key] = material
        return material
    }

    // MARK: The pieces

    private func syncPieces(_ model: OpticsModel) {
        var minted = false
        for piece in model.pieces {
            if pieceEntities[piece.id] == nil { minted = true }
            let entity = pieceEntities[piece.id] ?? makePiece(piece)
            entity.position = SIMD3<Float>(piece.position)
            entity.orientation = Self.single(OpticsModel.orientation(kind: piece.kind, aim: piece.aim))
            if let halo = halos[piece.id] {
                Fade.tick(halo, visible: piece.id == model.selectedID)
            }
        }
        if minted || pieceEntities.count != model.pieces.count {
            let live = Set(model.pieces.map(\.id))
            for (id, entity) in pieceEntities where !live.contains(id) {
                entity.removeFromParent()
                pieceEntities[id] = nil
                halos[id] = nil
            }
        }
    }

    /// A piece as it stands in the room, in its tracer frame.
    static func pieceModel(_ kind: OpticsModel.Kind) -> Entity {
        let holder = Entity()
        switch kind {
        case .mirror:
            // The silvered face at z = 0, where the tracer reflects; the
            // backing behind it.
            let face = ModelEntity(mesh: Primitives.cylinder(height: 0.002,
                                                             radius: Float(OpticsModel.mirrorRadius)),
                                   materials: [Materials.opticalMirror()])
            face.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
            face.position = [0, 0, -0.001]
            let back = ModelEntity(mesh: Primitives.cylinder(height: 0.008,
                                                             radius: Float(OpticsModel.mirrorRadius) + 0.004),
                                   materials: [Materials.graphite()])
            back.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
            back.position = [0, 0, -0.0062]
            holder.addChild(back)
            holder.addChild(face)
        case .prism:
            holder.addChild(ModelEntity(mesh: OpticsMeshes.prism,
                                        materials: [Materials.opticalGlass()]))
        case .lens:
            holder.addChild(ModelEntity(mesh: OpticsMeshes.lens,
                                        materials: [Materials.opticalGlass()]))
        case .block:
            let size = SIMD3<Float>(OpticsModel.blockHalfExtents * 2)
            holder.addChild(ModelEntity(mesh: Primitives.box(size: size),
                                        materials: [Materials.opticalGlass()]))
        }
        // The bright hairlines along a glass piece's edges: what makes clear
        // glass read as a solid with faces rather than a pale haze.
        if let edges = OpticsMeshes.edges(kind),
           let mesh = TubeMesh.tube(lines: edges, radius: 0.0008, sides: 5) {
            holder.addChild(ModelEntity(mesh: mesh, materials: [Materials.glassEdge(opacity: 0.55)]))
        }
        return holder
    }

    private func makePiece(_ piece: OpticsModel.Piece) -> Entity {
        let container = Entity()
        container.name = piece.id.uuidString
        let body = Self.pieceModel(piece.kind)
        container.addChild(body)

        let bounds = body.visualBounds(relativeTo: container)
        let halo = SelectionHalo.make(mesh: Primitives.box(size: bounds.extents + 0.03,
                                                           cornerRadius: 0.01))
        halo.position = bounds.center
        container.addChild(halo)
        halos[piece.id] = halo

        Grabbable.configureTouchTarget(container, matchingVisualBoundsOf: body,
                                       activate: { [weak self, weak container] in
                                           guard let container else { return }
                                           self?.onObjectTap?(container)
                                       })
        SpatialActions.describe(container, label: Self.spokenName(piece.kind))
        viewRoot.addChild(container)
        pieceEntities[piece.id] = container
        return container
    }

    private static func spokenName(_ kind: OpticsModel.Kind) -> String {
        switch kind {
        case .mirror: "Mirror. Carry it into the light and turn it by its handle."
        case .prism: "Prism. White light through it fans into a spectrum."
        case .lens: "Lens. It brings parallel light to a focus."
        case .block: "Glass bar. Light inside it reflects totally off its sides."
        }
    }

    // MARK: The lights

    /// A light's body along +z, its aperture at the front.
    static func laserModel(glow: UIColor) -> (Entity, ModelEntity) {
        let holder = Entity()
        let length = Float(OpticsModel.laserLength)
        let body = ModelEntity(mesh: Primitives.box(size: [0.03, 0.03, length], cornerRadius: 0.006),
                               materials: [Materials.graphite(UIColor(white: 0.2, alpha: 1))])
        holder.addChild(body)
        let collar = ModelEntity(mesh: Primitives.cylinder(height: 0.012, radius: 0.0125),
                                 materials: [Materials.machined()])
        collar.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        collar.position = [0, 0, length / 2 + 0.004]
        holder.addChild(collar)
        let lamp = ModelEntity(mesh: Primitives.sphere(radius: 0.004),
                               materials: [Materials.unlit(glow)])
        lamp.position = [0, 0, length / 2 + 0.01]
        holder.addChild(lamp)
        return (holder, lamp)
    }

    static func torchModel() -> (Entity, ModelEntity) {
        let holder = Entity()
        let length = Float(OpticsModel.torchLength)
        let body = ModelEntity(mesh: Primitives.cylinder(height: length, radius: 0.024),
                               materials: [Materials.machined(UIColor(white: 0.62, alpha: 1))])
        body.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        holder.addChild(body)
        let head = ModelEntity(mesh: Primitives.cylinder(height: 0.02, radius: 0.03),
                               materials: [Materials.graphite()])
        head.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        head.position = [0, 0, length / 2 - 0.01]
        holder.addChild(head)
        let lens = ModelEntity(mesh: Primitives.cylinder(height: 0.002, radius: 0.026),
                               materials: [Materials.unlit(UIColor(white: 1, alpha: 1))])
        lens.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        lens.position = [0, 0, length / 2 + 0.001]
        holder.addChild(lens)
        return (holder, lens)
    }

    private func buildSources() {
        for (entity, id, name) in [(laserEntity, OpticsModel.laserID, "Laser. Carry it and it points where you point it."),
                                   (torchEntity, OpticsModel.torchID, "Torch. Its white light is every colour at once.")] {
            entity.name = id.uuidString
            let (body, glow) = id == OpticsModel.laserID
                ? Self.laserModel(glow: Spectrum.color(nanometers: 532))
                : Self.torchModel()
            entity.addChild(body)
            if id == OpticsModel.laserID { laserGlow = glow } else { torchGlow = glow }
            let bounds = body.visualBounds(relativeTo: entity)
            let halo = SelectionHalo.make(mesh: Primitives.box(size: bounds.extents + 0.03,
                                                               cornerRadius: 0.01))
            halo.position = bounds.center
            entity.addChild(halo)
            halos[id] = halo
            Grabbable.configureTouchTarget(entity, matchingVisualBoundsOf: body,
                                           activate: { [weak self, weak entity] in
                                               guard let entity else { return }
                                               self?.onObjectTap?(entity)
                                           })
            SpatialActions.describe(entity, label: name)
            viewRoot.addChild(entity)
        }
    }

    private var drawnLaserColour: Double = 0

    private func syncSources(_ model: OpticsModel) {
        for (entity, source, id) in [(laserEntity, model.laser, OpticsModel.laserID),
                                     (torchEntity, model.torch, OpticsModel.torchID)] {
            entity.position = SIMD3<Float>(source.position)
            entity.orientation = Self.single(OpticsModel.orientation(kind: .lens, aim: source.aim))
            if let halo = halos[id] { Fade.tick(halo, visible: id == model.selectedID) }
        }
        laserGlow?.isEnabled = model.laser.isOn
        torchGlow?.isEnabled = model.torch.isOn
        if model.laserNanometers != drawnLaserColour {
            drawnLaserColour = model.laserNanometers
            laserGlow?.model?.materials = [Materials.unlit(Spectrum.color(nanometers: model.laserNanometers))]
        }
    }

    // MARK: The aim bead

    private func buildAimBead() {
        aimBead.name = Self.aimBeadName
        let bead = ModelEntity(mesh: Primitives.sphere(radius: 0.013),
                               materials: [Materials.energized(Self.accent, glow: 0.5)])
        aimBead.addChild(bead)
        Grabbable.configureTouchTarget(
            aimBead, collisionRadius: Grabbable.sphereTargetRadius(baseRadius: 0.013, scale: 1))
        SpatialActions.describe(aimBead, label: "Aim. Move it to turn the selected piece.")
        aimBead.isEnabled = false
        aimStalk.isEnabled = false
        viewRoot.addChild(aimStalk)
        viewRoot.addChild(aimBead)
    }

    /// Where the selected object's aim bead stands, if one is selected.
    static func aimBeadPosition(_ model: OpticsModel) -> SIMD3<Float>? {
        guard let id = model.selectedID, let position = model.position(of: id),
              let aim = model.aim(of: id) else { return nil }
        let direction = model.selectedPiece?.kind == .prism ? OpticsModel.level(aim) : aim
        return SIMD3<Float>(position) + SIMD3<Float>(simd_normalize(direction)) * aimReach
    }

    private func syncAimBead(_ model: OpticsModel) {
        guard let bead = Self.aimBeadPosition(model), let id = model.selectedID,
              let position = model.position(of: id) else {
            aimBead.isEnabled = false
            aimStalk.isEnabled = false
            return
        }
        aimBead.isEnabled = true
        aimStalk.isEnabled = true
        aimBead.position = bead
        let from = SIMD3<Float>(position)
        let length = simd_distance(from, bead)
        aimStalk.position = (from + bead) / 2
        aimStalk.orientation = rotation(from: [0, 1, 0], to: (bead - from) / max(length, 1e-5))
        aimStalk.scale = [0.0012, length, 0.0012]
    }

    /// The bead's entity, for a hit test.
    var aimBeadEntity: Entity { aimBead }

    /// The model's double-precision orientation as the scene's float one.
    static func single(_ q: simd_quatd) -> simd_quatf {
        simd_quatf(ix: Float(q.imag.x), iy: Float(q.imag.y), iz: Float(q.imag.z), r: Float(q.real))
    }
}
