//
//  RoomModel.swift
//  Physics Playground — Shell
//
//  ONE shared understanding of the user's room, for every module.
//
//  The app previously ignored the real world entirely: every apparatus
//  was pinned to hard-coded immersive-space coordinates, field lines
//  drove out through the walls, prediction arcs left through the
//  ceiling, and nothing was ever occluded by real geometry. Two modules
//  had their own private ARKit sessions (Kinematics for walls, Wind
//  Tunnel for hands + furniture) and nothing else knew the room existed.
//
//  This consolidates that: one ARKitSession, reference-counted so any
//  number of modules can share it, publishing
//
//    • `bounds`     — a RoomBox every renderer clips its lines against,
//    • `walls`      — finite rectangles the projectiles genuinely bounce off,
//    • `obstacles`  — hands, forearms and furniture as spheres for the CFD,
//    • `occluder`   — the reconstructed mesh, rendered with an occlusion
//                     material so virtual light passes BEHIND real furniture.
//
//  All providers are device-only and permission-gated. In the simulator
//  every one of them is simply unsupported, so `bounds` stays at
//  RoomBox.unscanned and the app behaves exactly as it does today —
//  the fallback is a generous room, never an empty one.
//

import ARKit
import Foundation
import Observation
import PhysicsCore
import RealityKit
import RenderKit
import SwiftUI
import simd

@MainActor
@Observable
final class RoomModel {
    // MARK: Published understanding of the room

    /// The clip volume. Renderers cut field lines, rays and predicted
    /// paths against this so virtual geometry stops at the real walls.
    private(set) var bounds: RoomBox = .unscanned

    /// Vertical planes as bounceable rectangles (Kinematics).
    private(set) var walls: [RoomWalls.Wall] = []

    /// Hands, forearms and nearby furniture as spheres (Wind Tunnel).
    private(set) var obstacles = ObstacleField()

    /// True once anything real has actually been detected — modules use
    /// it to decide whether to promise room-aware behaviour in the UI.
    private(set) var hasScannedRoom = false

    /// The scene-reconstruction mesh, wearing an occlusion material.
    /// Add it to a module's scene and real furniture starts hiding
    /// virtual content behind it.
    let occluder = Entity()

    // MARK: Session

    // ALL of these are rebuilt on every start, and that is the whole
    // point — see `retain()`. A stopped ARKit data provider is DEAD; it
    // can never run again.
    private var session = ARKitSession()
    private var planes = PlaneDetectionProvider(alignments: [.horizontal, .vertical])
    private var hands = HandTrackingProvider()
    private var sceneMesh = SceneReconstructionProvider()
    private var worldTracking = WorldTrackingProvider()

    /// Where the user's head is, right now, in immersive-space
    /// coordinates — the one piece of state that lets a module respond
    /// to the user MOVING rather than to the user's hands. Waves reads
    /// it to sound the field at the listener's own ears.
    ///
    /// nil until world tracking is running (always, in the simulator),
    /// so every caller has to have a sensible answer without it.
    var headPosition: SIMD3<Double>? {
        lookRay?.origin
    }

    /// Where the user is LOOKING, as a ray from between their eyes.
    ///
    /// visionOS deliberately does not hand an app raw eye gaze — the
    /// system uses it for highlighting and never reports it, which is
    /// the right privacy call. What IS available is the device pose, so
    /// this is head direction: turn your head toward something and it
    /// points at it. It is not eye tracking, and nothing in the app
    /// claims it is; it is enough to let you MEASURE by looking, which
    /// is the interaction that was missing.
    var lookRay: (origin: SIMD3<Double>, direction: SIMD3<Double>)? {
        guard worldTracking.state == .running,
              let anchor = worldTracking.queryDeviceAnchor(atTimestamp: CACurrentMediaTime())
        else { return nil }
        let m = anchor.originFromAnchorTransform
        let origin = SIMD3(Double(m.columns.3.x), Double(m.columns.3.y),
                           Double(m.columns.3.z))
        // The device looks along its own −Z, as cameras do.
        let forward = -SIMD3(Double(m.columns.2.x), Double(m.columns.2.y),
                             Double(m.columns.2.z))
        let length = simd_length(forward)
        guard length > 1e-9 else { return nil }
        return (origin, forward / length)
    }

    private var clients = 0
    private var isRunning = false
    /// Set BEFORE the first await in `retain()`, not after. See below.
    private var isStarting = false
    private var tasks: [Task<Void, Never>] = []
    private var shutdown: Task<Void, Never>?

    /// How long the session stays up after the last client leaves.
    ///
    /// Switching modules tears the old scene down and builds the new one,
    /// and SwiftUI does not promise which happens first. Without a grace
    /// period, every single module switch stopped the session and started
    /// a fresh one a frame later — sensor churn, a re-scan of the room,
    /// and the plane/mesh anchors the user had already accumulated thrown
    /// away each time. Two seconds spans any switch and still releases the
    /// sensors promptly when you actually go back to the hub and stay.
    private static let lingerSeconds: Double = 2

    /// Test seam: the linger window, and whether anything still holds
    /// the room. RoomSessionTests drives the retain/release sequence
    /// that used to abort the process.
    static var testLingerSeconds: Double { lingerSeconds }
    var hasClients: Bool { clients > 0 }
    var clientCount: Int { clients }

    /// Reference-counted start: the first module in brings the session
    /// up, the last one out takes it down. Modules call `retain()` in
    /// their scene's task and `release()` on disappear.
    func retain() async {
        clients += 1
        // Cancel a pending shutdown — this is the module-switch case, and
        // the session that is already running is exactly the one we want.
        shutdown?.cancel()
        shutdown = nil

        // `isRunning` is only true AFTER the await below returns, so
        // checking it alone let two overlapping retains both reach
        // `session.run`. Several views retain at once (the module scene,
        // the occlusion view, the lab anchor), so overlapping is the
        // normal case, not a rare race — and a double run is one of the
        // ways ARKit aborts the process.
        guard !isRunning, !isStarting else { return }
        isStarting = true
        defer { isStarting = false }

        // A STOPPED PROVIDER CANNOT BE RE-RUN.
        //
        // This crashed the app, and it crashed it in the exact shape the
        // bug report described: the first module you open is fine, and
        // opening another one kills the process. `session.stop()` retires
        // its providers permanently; handing those same objects back to
        // `run` makes ARKit raise an Objective-C exception. Which is why
        // the `catch` below never helped — an NSException is not a Swift
        // error, it unwinds straight past `catch` into abort(). The only
        // fix is to never re-run a used provider: build a fresh session
        // and fresh providers for every start.
        session = ARKitSession()
        planes = PlaneDetectionProvider(alignments: [.horizontal, .vertical])
        hands = HandTrackingProvider()
        sceneMesh = SceneReconstructionProvider()
        worldTracking = WorldTrackingProvider()

        var providers: [any DataProvider] = []
        if PlaneDetectionProvider.isSupported { providers.append(planes) }
        if HandTrackingProvider.isSupported { providers.append(hands) }
        if SceneReconstructionProvider.isSupported { providers.append(sceneMesh) }
        if WorldTrackingProvider.isSupported { providers.append(worldTracking) }
        guard !providers.isEmpty else { return }   // simulator: nothing to run

        // Authorization is asked for explicitly rather than implicitly by
        // running: a denied provider is another way `run` throws, and
        // asking first turns that into an ordinary early return.
        let authorization = await session.requestAuthorization(
            for: providers.flatMap { type(of: $0).requiredAuthorizations })
        guard authorization.values.allSatisfy({ $0 == .allowed }) else { return }

        do {
            try await session.run(providers)
        } catch {
            return
        }
        isRunning = true
        if PlaneDetectionProvider.isSupported {
            tasks.append(Task { await self.consumePlanes() })
        }
        if HandTrackingProvider.isSupported {
            tasks.append(Task { await self.consumeHands() })
        }
        if SceneReconstructionProvider.isSupported {
            tasks.append(Task { await self.consumeMeshes() })
        }
    }

    func release() {
        clients = max(0, clients - 1)
        guard clients == 0, isRunning else { return }
        shutdown?.cancel()
        shutdown = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.lingerSeconds))
            guard !Task.isCancelled else { return }
            await self?.stopNow()
        }
    }

    /// Actually takes the sensors down. Only the linger task calls this.
    private func stopNow() {
        guard clients == 0, isRunning else { return }
        tasks.forEach { $0.cancel() }
        tasks = []
        session.stop()
        isRunning = false
        shutdown = nil
    }

    // MARK: Planes → bounds + walls

    private var wallsByAnchor: [UUID: RoomWalls.Wall] = [:]
    private var planeCorners: [UUID: [SIMD3<Double>]] = [:]

    private func consumePlanes() async {
        for await update in planes.anchorUpdates {
            let anchor = update.anchor
            if update.event == .removed {
                wallsByAnchor[anchor.id] = nil
                planeCorners[anchor.id] = nil
            } else {
                if anchor.alignment == .vertical {
                    wallsByAnchor[anchor.id] = Self.wall(from: anchor)
                }
                planeCorners[anchor.id] = Self.corners(of: anchor)
            }
            walls = Array(wallsByAnchor.values)
            recomputeBounds()
        }
    }

    private func recomputeBounds() {
        let points = planeCorners.values.flatMap { $0 }
        guard !points.isEmpty else { return }
        hasScannedRoom = true
        // A little slack so content isn't clipped flush against paint.
        bounds = RoomBox.enclosing(points: points).inset(by: -0.05)
    }

    /// A plane anchor's extent rectangle in world space. The anchor's Y
    /// axis is the plane normal; the extent spans local X and Z.
    private static func basis(of anchor: PlaneAnchor)
    -> (center: SIMD3<Double>, normal: SIMD3<Double>,
        u: SIMD3<Double>, v: SIMD3<Double>, halfU: Double, halfV: Double) {
        let originFromExtent = anchor.originFromAnchorTransform
            * anchor.geometry.extent.anchorFromExtentTransform
        let columns = originFromExtent.columns
        func axis(_ column: SIMD4<Float>) -> SIMD3<Double> {
            simd_normalize(SIMD3(Double(column.x), Double(column.y), Double(column.z)))
        }
        return (SIMD3(Double(columns.3.x), Double(columns.3.y), Double(columns.3.z)),
                axis(columns.1), axis(columns.0), axis(columns.2),
                Double(anchor.geometry.extent.width) / 2,
                Double(anchor.geometry.extent.height) / 2)
    }

    private static func wall(from anchor: PlaneAnchor) -> RoomWalls.Wall {
        let b = basis(of: anchor)
        return RoomWalls.Wall(center: b.center, normal: b.normal,
                              uAxis: b.u, vAxis: b.v,
                              halfU: b.halfU, halfV: b.halfV)
    }

    private static func corners(of anchor: PlaneAnchor) -> [SIMD3<Double>] {
        let b = basis(of: anchor)
        return [
            b.center + b.u * b.halfU + b.v * b.halfV,
            b.center + b.u * b.halfU - b.v * b.halfV,
            b.center - b.u * b.halfU + b.v * b.halfV,
            b.center - b.u * b.halfU - b.v * b.halfV,
        ]
    }

    // MARK: Hands & furniture → obstacle spheres

    /// The joints that sketch a hand + forearm. Fingertips are small,
    /// the palm and forearm larger.
    private static let trackedJoints: [(HandSkeleton.JointName, Double)] = [
        (.wrist, 0.045), (.middleFingerKnuckle, 0.04),
        (.thumbTip, 0.02), (.indexFingerTip, 0.02), (.middleFingerTip, 0.02),
        (.ringFingerTip, 0.02), (.littleFingerTip, 0.02),
        (.forearmWrist, 0.05), (.forearmArm, 0.06),
    ]

    /// Keyed by chirality so each hand replaces only its own spheres.
    private var handSpheres: [HandAnchor.Chirality: [ObstacleField.Sphere]] = [:]
    private var meshSpheres: [UUID: [ObstacleField.Sphere]] = [:]

    /// Fingertip positions of whichever hand is tracked, for the modules
    /// that want the hand itself as an instrument (a probe, a compass).
    private(set) var fingertips: [SIMD3<Double>] = []

    private func consumeHands() async {
        for await update in hands.anchorUpdates {
            let anchor = update.anchor
            guard anchor.isTracked, let skeleton = anchor.handSkeleton else { continue }
            var spheres: [ObstacleField.Sphere] = []
            var tips: [SIMD3<Double>] = []
            for (joint, radius) in Self.trackedJoints {
                let transform = anchor.originFromAnchorTransform
                    * skeleton.joint(joint).anchorFromJointTransform
                let c = transform.columns.3
                let point = SIMD3(Double(c.x), Double(c.y), Double(c.z))
                spheres.append(ObstacleField.Sphere(center: point, radius: radius))
                if joint == .indexFingerTip { tips.append(point) }
            }
            handSpheres[anchor.chirality] = spheres
            fingertips = tips
            rebuildObstacles()
        }
    }

    private func rebuildObstacles() {
        obstacles = ObstacleField(
            spheres: handSpheres.values.flatMap { $0 } + meshSpheres.values.flatMap { $0 })
    }

    private static let voxelSize = 0.14
    private static let maxVoxelsPerAnchor = 40

    private func consumeMeshes() async {
        for await update in sceneMesh.anchorUpdates {
            let anchor = update.anchor
            if update.event == .removed {
                meshSpheres[anchor.id] = nil
                occluder.findEntity(named: anchor.id.uuidString)?.removeFromParent()
            } else {
                meshSpheres[anchor.id] = Self.voxelize(anchor)
                updateOccluder(for: anchor)
            }
            rebuildObstacles()
        }
    }

    /// Coarse spheres from the anchor's vertices, snapped to a voxel
    /// grid and capped so a fully-scanned room can't flood the field.
    private static func voxelize(_ anchor: MeshAnchor) -> [ObstacleField.Sphere] {
        let vertices = anchor.geometry.vertices
        guard vertices.count > 0 else { return [] }
        let transform = anchor.originFromAnchorTransform
        var occupied = Set<SIMD3<Int>>()
        var spheres: [ObstacleField.Sphere] = []
        let stride = max(1, vertices.count / 400)
        for index in Swift.stride(from: 0, to: vertices.count, by: stride) {
            let raw = vertices.buffer.contents()
                .advanced(by: vertices.offset + vertices.stride * index)
                .assumingMemoryBound(to: SIMD3<Float>.self).pointee
            let world = transform * SIMD4(raw.x, raw.y, raw.z, 1)
            let point = SIMD3(Double(world.x), Double(world.y), Double(world.z))
            let cell = SIMD3(Int((point.x / voxelSize).rounded()),
                             Int((point.y / voxelSize).rounded()),
                             Int((point.z / voxelSize).rounded()))
            guard !occupied.contains(cell) else { continue }
            occupied.insert(cell)
            spheres.append(ObstacleField.Sphere(
                center: SIMD3(Double(cell.x) * voxelSize,
                              Double(cell.y) * voxelSize,
                              Double(cell.z) * voxelSize),
                radius: voxelSize * 0.55))
            if spheres.count >= maxVoxelsPerAnchor { break }
        }
        return spheres
    }

    /// Mirrors the reconstructed mesh into `occluder` wearing an
    /// occlusion material — this is what makes a field line vanish
    /// behind the couch instead of painting over it.
    private func updateOccluder(for anchor: MeshAnchor) {
        let name = anchor.id.uuidString
        guard let shape = Self.mesh(from: anchor.geometry) else { return }
        if let model = occluder.findEntity(named: name) as? ModelEntity {
            model.model = ModelComponent(mesh: shape, materials: [Materials.occlusion()])
            model.transform = Transform(matrix: anchor.originFromAnchorTransform)
            return
        }
        let model = ModelEntity(mesh: shape, materials: [Materials.occlusion()])
        model.name = name
        model.transform = Transform(matrix: anchor.originFromAnchorTransform)
        occluder.addChild(model)
    }

    /// Turns a scene-reconstruction anchor's raw buffers into a mesh.
    /// The geometry arrives as loosely-typed vertex/index buffers with
    /// their own stride and index width, so both have to be walked by
    /// hand rather than handed straight to RealityKit.
    private static func mesh(from geometry: MeshAnchor.Geometry) -> MeshResource? {
        let vertexSource = geometry.vertices
        let faces = geometry.faces
        guard vertexSource.count > 0, faces.count > 0,
              faces.primitive == .triangle else { return nil }

        var positions: [SIMD3<Float>] = []
        positions.reserveCapacity(vertexSource.count)
        let vertexBase = vertexSource.buffer.contents().advanced(by: vertexSource.offset)
        for index in 0..<vertexSource.count {
            let pointer = vertexBase.advanced(by: vertexSource.stride * index)
                .assumingMemoryBound(to: (Float, Float, Float).self).pointee
            positions.append(SIMD3(pointer.0, pointer.1, pointer.2))
        }

        let indexCount = faces.count * 3
        var indices: [UInt32] = []
        indices.reserveCapacity(indexCount)
        let indexBase = faces.buffer.contents()
        switch faces.bytesPerIndex {
        case 2:
            let typed = indexBase.assumingMemoryBound(to: UInt16.self)
            for index in 0..<indexCount { indices.append(UInt32(typed[index])) }
        case 4:
            let typed = indexBase.assumingMemoryBound(to: UInt32.self)
            for index in 0..<indexCount { indices.append(typed[index]) }
        default:
            return nil
        }

        var descriptor = MeshDescriptor(name: "room-occluder")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [descriptor])
    }
}

/// Attaches the shared room occlusion mesh to a module's scene, and
/// keeps the ARKit session alive for as long as the module is on
/// screen. One line in each module's space view.
struct RoomOcclusionView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        RealityView { content in
            content.add(appModel.room.occluder)
        }
        .task { await appModel.room.retain() }
        .onDisappear { appModel.room.release() }
    }
}
