//
//  OpticsSpaceView.swift
//  Physics Playground — Light & Optics
//
//  The optics room. Pieces come out of the well on the left; any piece or
//  light is carried by hand (one in each hand if you like), and turned by
//  its aim bead — a handle standing out along the way it faces, shown on
//  whatever is selected. Tap a piece for its ring. The light is re-traced
//  whenever anything moves, and lands on the room's real walls.
//

import PhysicsCore
import QuartzCore
import SwiftUI
import RealityKit
import RenderKit

struct OpticsSpaceView: View {
    @Environment(OpticsModel.self) private var model
    @Environment(AppModel.self) private var appModel
    @State private var renderer: OpticsRenderer?
    @State private var bloom = Bloom()
    @State private var sceneContent: RealityViewContent?
    @State private var ring = RingState()
    @State private var wells: Well?
    /// A piece pulled from the well, carried by the drag that pulled it.
    @State private var pull: RelativeDrag?
    /// The aim bead in a hand: which object it turns, and the drag.
    @State private var aiming: (id: UUID, drag: RelativeDrag)?

    /// The well's mouths, off the left shoulder: what the reach criterion
    /// measures. The bar stands upright in its slot, so it has more room.
    static let wellAnchors: [SIMD3<Float>] = [
        SIMD3(-0.72, 1.27, -0.55),
        SIMD3(-0.72, 1.11, -0.55),
        SIMD3(-0.72, 0.96, -0.55),
        SIMD3(-0.72, 0.76, -0.55),
    ]

    var body: some View {
        RealityView { content in
            let renderer = OpticsRenderer()
            renderer.onObjectTap = { handleTap(on: $0) }
            content.add(renderer.root)
            renderer.root.isEnabled = false
            sceneContent = content

            let kinds: [(OpticsModel.Kind, String, String)] = [
                (.mirror, "Mirror", "Add mirror"),
                (.prism, "Prism", "Add prism"),
                (.lens, "Lens", "Add lens"),
                (.block, "Bar", "Add glass bar"),
            ]
            let sources = Well(zip(kinds, Self.wellAnchors).map { entry, anchor in
                let (kind, name, label) = entry
                return Well.Spec(name: name,
                                 tint: OpticsRenderer.accent,
                                 label: label,
                                 preview: { Self.preview(kind) },
                                 position: anchor,
                                 spawn: { point in model.addPiece(kind, at: point) })
            })
            sources.spawnSpace = renderer.viewRoot
            renderer.viewRoot.addChild(sources.root)
            renderer.viewRoot.addChild(bloom.root)
            wells = sources

            // The lab shows once its scene has taken in the build (`Settle`):
            // it starts hidden and fades up then, rather than popping in and
            // stuttering through the long first frames after a mount.
            renderer.root.components.set(OpacityComponent(opacity: Settle.hiddenOpacity))
            var settle = Settle()
            renderer.subscriptions.append(
                content.subscribe(to: SceneEvents.Update.self) { [weak renderer] event in
                    if let renderer, settle.tick(dt: event.deltaTime) {
                        Fade.tick(renderer.root, visible: !appModel.isDeparting,
                                  duration: AppModel.departure)
                    }
                    expireStaleGrabs(now: CACurrentMediaTime())
                    let hand = appModel.room.nearestFingertip(to: Self.wellAnchors[1])
                    wells?.update(dt: event.deltaTime, nearestHand: hand)
                    if let renderer { syncBloom(renderer: renderer, dt: event.deltaTime) }
                    model.room = currentRoom()
                    model.step(dt: event.deltaTime)
                    renderer?.tick(model)
                    renderer?.root.position = appModel.labPlacement.offset
                }
            )
            #if DEBUG
            stageForScreenshot()
            #endif
            renderer.tick(model)
            self.renderer = renderer
        }
        .onDisappear {
            renderer?.teardown()
            bloom.endGrip()
            pull = nil
            aiming = nil
            for session in grabs.values { model.release(id: session.id) }
            grabs.removeAll()
        }
        .simultaneousGesture(
            TapGesture()
                .targetedToAnyEntity()
                .onEnded { value in handleTap(on: value.entity) }
        )
        .simultaneousGesture(
            SpatialEventGesture()
                .onChanged { events in handleGrabEvents(events) }
                .onEnded { events in handleGrabEvents(events) }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .targetedToAnyEntity()
                .onChanged { value in
                    guard let renderer else { return }
                    let hand = renderer.displayPoint(fromWorld: SIMD3<Float>(value.convert(
                        value.location3D, from: .local, to: .scene)))
                    if let aiming {
                        model.aim(id: aiming.id, toward: aiming.drag.position(forHand: hand))
                        return
                    }
                    if let pull {
                        if let id = UUID(uuidString: pull.name) {
                            model.move(id: id, to: pull.position(forHand: hand))
                        }
                        return
                    }
                    if Self.isAimBead(value.entity), let id = model.selectedID,
                       let bead = OpticsRenderer.aimBeadPosition(model) {
                        aiming = (id, RelativeDrag(name: "aim", target: SIMD3<Double>(bead), hand: hand))
                        LiveGlow.set(true, on: renderer.aimBeadEntity)
                        SoundPalette.play(.grabTick, on: renderer.aimBeadEntity, volume: 0.2)
                        return
                    }
                    if let id = wells?.pull(value.entity, at: hand) {
                        model.grab(id: id)
                        pull = RelativeDrag(name: id.uuidString, target: hand, hand: hand)
                    }
                }
                .onEnded { _ in
                    if aiming != nil, let renderer {
                        LiveGlow.set(false, on: renderer.aimBeadEntity)
                        SoundPalette.play(.releaseTick, on: renderer.aimBeadEntity, volume: 0.18)
                    }
                    aiming = nil
                    if let pull, let id = UUID(uuidString: pull.name) { model.release(id: id) }
                    pull = nil
                }
        )
    }

    private func currentRoom() -> LightTracer.Room {
        Self.room(for: appModel.room.tangible,
                  placement: SIMD3<Double>(appModel.labPlacement.offset))
    }

    /// The room the light lands in, in the lab's coordinates: the walls
    /// ARKit has found and the scanned bounds, and the floor. An unscanned
    /// room has no walls to land on — the light runs out instead of
    /// painting a wall that is not there — and neither has deep space,
    /// where the floor (the platform's plane) is all there is.
    static func room(for tangible: RoomModel.Tangible, placement: SIMD3<Double>) -> LightTracer.Room {
        let walls: [RoomWalls.Wall]
        if case .scanned(let found, _) = tangible {
            walls = found.map { $0.translated(by: -placement) }
        } else {
            walls = []
        }
        return LightTracer.Room(walls: walls, floorY: OpticsModel.floorY - placement.y,
                                maxSegment: 6)
    }

    /// A piece as its well shows it: the real thing, turned to read well.
    static func preview(_ kind: OpticsModel.Kind) -> Entity {
        let holder = Entity()
        let piece = OpticsRenderer.pieceModel(kind)
        switch kind {
        case .prism:
            // Upright, as it stands in the room, its apex toward the viewer's left.
            piece.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
                * simd_quatf(angle: 0.4, axis: [0, 0, 1])
        case .block:
            piece.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
        case .mirror, .lens:
            piece.orientation = simd_quatf(angle: 0.35, axis: [0, 1, 0])
        }
        holder.addChild(piece)
        return holder
    }

    private static func isAimBead(_ entity: Entity) -> Bool {
        var current: Entity? = entity
        while let candidate = current {
            if candidate.name == OpticsRenderer.aimBeadName { return true }
            current = candidate.parent
        }
        return false
    }

    // MARK: Grabbing — one session per hand

    private struct GrabSession {
        var id: UUID
        var drag: RelativeDrag
        var lastSeen: Double
        var entity: Entity
    }

    @State private var grabs: [SpatialEventCollection.Event.ID: GrabSession] = [:]
    private static let grabStaleAfter: Double = 0.5

    private func expireStaleGrabs(now: Double) {
        for (key, session) in grabs where now - session.lastSeen >= Self.grabStaleAfter {
            grabs.removeValue(forKey: key)
            release(session)
        }
    }

    private func release(_ session: GrabSession) {
        LiveGlow.set(false, on: session.entity)
        SoundPalette.play(.releaseTick, on: session.entity, volume: 0.18)
        model.release(id: session.id)
    }

    private func handleGrabEvents(_ events: SpatialEventCollection) {
        guard let renderer, let content = sceneContent else { return }
        let now = CACurrentMediaTime()
        defer { expireStaleGrabs(now: now) }
        let viewer = appModel.room.headPosition.map {
            renderer.displayPoint(fromWorld: SIMD3<Float>($0))
        }
        for event in events {
            guard event.phase == .active else {
                if let ended = grabs.removeValue(forKey: event.id) { release(ended) }
                continue
            }
            let world = content.convert(event.location3D, from: .local, to: .scene)
            let hand = renderer.displayPoint(fromWorld: world)
            if let session = grabs[event.id] {
                grabs[event.id]?.lastSeen = now
                model.move(id: session.id, to: session.drag.position(forHand: hand), viewer: viewer)
            } else if let session = beginGrab(on: event.targetedEntity, hand: hand, now: now) {
                grabs[event.id] = session
            }
        }
    }

    /// A fresh pinch on a piece or a light takes it; anything else — the
    /// well, the ring, the aim bead, a second pinch on a held piece —
    /// declines, and the other recognisers take it.
    private func beginGrab(on entity: Entity?, hand: SIMD3<Double>, now: Double) -> GrabSession? {
        var current: Entity? = entity
        while let candidate = current {
            if let id = UUID(uuidString: candidate.name), model.contains(id),
               let position = model.position(of: id) {
                guard !model.heldIDs.contains(id) else { return nil }
                model.grab(id: id)
                LiveGlow.set(true, on: candidate)
                SoundPalette.play(.grabTick, on: candidate, volume: 0.2)
                return GrabSession(id: id,
                                   drag: RelativeDrag(name: candidate.name, target: position, hand: hand),
                                   lastSeen: now, entity: candidate)
            }
            current = candidate.parent
        }
        return nil
    }

    // MARK: The ring

    /// A light offers its colour or its beam, and its switch; a piece offers
    /// to go. Everything a piece does is done by moving or turning it.
    private func syncBloom(renderer: OpticsRenderer, dt: Double) {
        if let open = ring.openID, !model.contains(open) { ring.openID = nil }
        guard let id = ring.openID, let position = model.position(of: id) else {
            bloom.update(anchor: .zero, viewer: nil, revealTarget: 0, dt: dt)
            bloom.clearTarget()
            return
        }
        let petals: [Bloom.Petal]
        switch id {
        case OpticsModel.laserID:
            petals = [
                .init(name: "Colour", symbol: "paintpalette",
                      tint: DesignTokens.Palette.neutralActionUI) { model.cycleLaserColour() },
                .init(name: "Light", symbol: "power",
                      tint: DesignTokens.Palette.neutralActionUI) { model.toggleLight(id: id) },
            ]
        case OpticsModel.torchID:
            petals = [
                .init(name: "Beam", symbol: "rays",
                      tint: DesignTokens.Palette.neutralActionUI) { model.toggleTorchBeam() },
                .init(name: "Light", symbol: "power",
                      tint: DesignTokens.Palette.neutralActionUI) { model.toggleLight(id: id) },
            ]
        default:
            petals = [
                .init(name: "Delete", symbol: "trash",
                      tint: DesignTokens.Palette.destructiveUI) { model.removePiece(id: id) },
            ]
        }
        bloom.retarget(id, petals: petals, grip: nil)
        let viewer = appModel.room.headPosition.map {
            renderer.viewRoot.convert(position: SIMD3<Float>($0), from: nil)
        }
        bloom.update(anchor: SIMD3<Float>(position), viewer: viewer, revealTarget: 1, dt: dt)
    }

    /// The tap routing, out of the gesture closure so VoiceOver reaches it.
    private func handleTap(on entity: Entity) {
        if bloom.handleTap(entity) { return }
        if Self.isAimBead(entity) { return }
        var current: Entity? = entity
        while let candidate = current {
            if let id = UUID(uuidString: candidate.name), model.contains(id) {
                if ring.openID == id {
                    ring.openID = nil
                    model.select(id: nil)
                    SoundPalette.play(.releaseTick, on: entity, volume: 0.3)
                } else {
                    model.select(id: id)
                    ring.openID = id
                    SoundPalette.play(.pop, on: entity, volume: 0.35)
                }
                return
            }
            current = candidate.parent
        }
        if ring.openID != nil {
            SoundPalette.play(.releaseTick, on: entity, volume: 0.3)
        }
        ring.openID = nil
        model.select(id: nil)
    }

    #if DEBUG
    /// `-optRing laser|torch|mirror|prism|lens|block` opens that object's ring
    /// (and so its aim bead), the only way to photograph them from the CLI.
    private func stageForScreenshot() {
        guard let name = UserDefaults.standard.string(forKey: "optRing") else { return }
        let id: UUID? = switch name {
        case "laser": OpticsModel.laserID
        case "torch": OpticsModel.torchID
        default: model.pieces.first { $0.kind.rawValue == name }?.id
        }
        guard let id else { return }
        model.select(id: id)
        ring.openID = id
    }
    #endif
}
