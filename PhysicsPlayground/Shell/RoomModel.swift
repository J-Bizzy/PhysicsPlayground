//
//  RoomModel.swift
//  Physics Playground — Shell
//
//  One shared understanding of the user's room: a single ARKitSession,
//  reference-counted so any number of modules can share it, publishing
//  `bounds` (a RoomBox every renderer clips against), `walls` (finite
//  rectangles projectiles bounce off) and `obstacles` (hands, forearms
//  and furniture as spheres). All providers are device-only and
//  permission-gated; in the simulator `bounds` stays `RoomBox.unscanned`.
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

    /// Why the room is not being sensed, when it is not. The cases stay
    /// distinct because each calls for a different sentence.
    enum Sensing: Equatable {
        /// Running, or not asked for yet. Nothing to say.
        case fine
        /// No provider on this device supports what we need (the simulator,
        /// mostly). Not fixable by the user.
        case unsupported
        /// The user said no. This one has a remedy.
        case denied
        /// Authorized, but `session.run` threw anyway.
        case failed

        /// The one-line version, for a title bar or a card. The copy lives on
        /// the case so the hub and the title bar say the same thing.
        var headline: String {
            switch self {
            case .fine: ""
            case .unsupported: "This device can't sense your room"
            case .denied: "Physics Playground can't see your room"
            case .failed: "Room sensing didn't start"
            }
        }

        /// What is lost, and what to do about it. A warning with no
        /// remedy is a complaint.
        var detail: String {
            switch self {
            case .fine:
                ""
            case .unsupported:
                "The labs run in open space instead. The physics is "
                + "identical — only the parts that use your real walls and "
                + "furniture are missing."
            case .denied:
                "Balls won't bounce off your real walls or floor, and "
                + "apparatus won't be hidden behind your furniture. To turn "
                + "it back on, open Settings › Privacy & Security › World "
                + "Sensing and allow Physics Playground."
            case .failed:
                "Something went wrong starting it. Leaving this lab and "
                + "opening it again usually fixes it."
            }
        }

        /// Said before the system asks, so the permission sheet is not the
        /// first the user hears of it.
        static let preExplanation =
            "visionOS will ask to use your room, so labs can stand on your "
            + "floor and balls can bounce off your real walls."
    }

    /// Read by the shell to explain a lesser room. See `Sensing`.
    private(set) var sensing: Sensing = .fine

    #if DEBUG
    /// `-roomSensing denied|unsupported|failed` forces the flag so the copy
    /// can be photographed; applied after `retain()` so it overrides the
    /// real result.
    func forceSensingForDebug() {
        switch UserDefaults.standard.string(forKey: "roomSensing") {
        case "denied": sensing = .denied
        case "unsupported": sensing = .unsupported
        case "failed": sensing = .failed
        default: break
        }
        // `-roomTable <y>` stands a 0.9 × 0.7 m table top at that height in the
        // launcher's line and marks the room scanned; the simulator has no
        // furniture to classify.
        let tableHeight = UserDefaults.standard.double(forKey: "roomTable")
        if tableHeight > 0 {
            wallsByAnchor[Self.debugTableID] = RoomWalls.Wall(
                center: SIMD3(-0.6, tableHeight, -2.3), normal: SIMD3(0, 1, 0),
                uAxis: SIMD3(1, 0, 0), vAxis: SIMD3(0, 0, 1), halfU: 0.45, halfV: 0.35)
            walls = Array(wallsByAnchor.values)
            hasScannedRoom = true
            recomputeCollisionWalls()
        }
        // `-roomWall <m>` stands a 6 × 3 m wall across the room that far in front
        // of the wearer and marks the room scanned — what Light & Optics' beams
        // land on in a simulator that has no walls. A distance, not a z: an
        // argument value starting with "-" is read as the next key.
        let wallDistance = UserDefaults.standard.double(forKey: "roomWall")
        if wallDistance > 0 {
            wallsByAnchor[Self.debugWallID] = RoomWalls.Wall(
                center: SIMD3(0, 1.5, -wallDistance), normal: SIMD3(0, 0, 1),
                uAxis: SIMD3(1, 0, 0), vAxis: SIMD3(0, 1, 0), halfU: 3, halfV: 1.5)
            walls = Array(wallsByAnchor.values)
            hasScannedRoom = true
            recomputeCollisionWalls()
        }
    }
    private static let debugTableID = UUID()
    private static let debugWallID = UUID()
    #endif

    // MARK: Session

    // Rebuilt on every start: a stopped ARKit data provider can never run
    // again.
    private var session = ARKitSession()
    private var planes = PlaneDetectionProvider(alignments: [.horizontal, .vertical])
    private var hands = HandTrackingProvider()
    private var sceneMesh = SceneReconstructionProvider()
    private var worldTracking = WorldTrackingProvider()

    /// The user's head, in immersive-space coordinates; nil until world
    /// tracking runs (always, in the simulator).
    var headPosition: SIMD3<Double>? {
        lookRay?.origin
    }

    /// Where the user is looking, as a ray from between the eyes. Head
    /// direction, not eye gaze: visionOS never reports gaze to an app.
    var lookRay: (origin: SIMD3<Double>, direction: SIMD3<Double>)? {
        // Asked for by a dozen things a frame, and each query is a round trip
        // to world tracking: within one frame the answer is the same.
        let now = CACurrentMediaTime()
        if now - lookRayTime < Self.lookRayLifetime { return cachedLookRay }
        let ray = queryLookRay(at: now)
        lookRayTime = now
        cachedLookRay = ray
        return ray
    }

    /// Shorter than a 90 Hz frame, so no frame reads its predecessor's head.
    private static let lookRayLifetime = 0.004
    @ObservationIgnored private var lookRayTime = -Double.infinity
    @ObservationIgnored private var cachedLookRay: (origin: SIMD3<Double>, direction: SIMD3<Double>)?

    private func queryLookRay(at now: Double) -> (origin: SIMD3<Double>, direction: SIMD3<Double>)? {
        guard worldTracking.state == .running,
              let anchor = worldTracking.queryDeviceAnchor(atTimestamp: now)
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
    /// Anything other than `.fine` implies not running; `.fine` does not
    /// imply running — it means "nothing to tell the user".
    private(set) var isRunning = false
    /// Set before the first await in `retain()`, not after. See below.
    private var isStarting = false
    private var tasks: [Task<Void, Never>] = []
    private var shutdown: Task<Void, Never>?

    /// How long the session stays up after the last client leaves: a module
    /// switch tears one scene down and builds the next in no promised
    /// order, and two seconds spans it without a sensor restart.
    private static let lingerSeconds: Double = 2

    /// Test seam for `RoomSessionTests`.
    static var testLingerSeconds: Double { lingerSeconds }
    var hasClients: Bool { clients > 0 }
    var clientCount: Int { clients }

    /// Reference-counted start: the first module in brings the session up,
    /// the last one out takes it down.
    func retain() async {
        clients += 1
        // A pending shutdown is the module-switch case: keep the running session.
        shutdown?.cancel()
        shutdown = nil

        // `isRunning` only becomes true after the await below, so overlapping
        // retains (several views retain at once) need the second flag; a double
        // `run` aborts the process.
        guard !isRunning, !isStarting else { return }
        isStarting = true
        defer { isStarting = false }

        // A stopped provider cannot be re-run: `session.stop()` retires its
        // providers, and handing them back to `run` raises an NSException that
        // unwinds past `catch`. Fresh session, fresh providers, every start.
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
        guard !providers.isEmpty else {
            sensing = .unsupported
            #if DEBUG
            forceSensingForDebug()
            #endif
            return   // simulator: nothing to run
        }

        // Asked for explicitly: a denied provider is another way `run` throws.
        let authorization = await session.requestAuthorization(
            for: providers.flatMap { type(of: $0).requiredAuthorizations })
        // The await above can be seconds long (the permission sheet) and the
        // user can leave meanwhile.
        guard clients > 0 else { return }
        // Run with whatever was granted; one denied permission must not kill
        // the whole sensing layer.
        let denied = Set(authorization.filter { $0.value != .allowed }.map(\.key))
        providers = providers.filter { provider in
            type(of: provider).requiredAuthorizations.allSatisfy {
                !denied.contains($0)
            }
        }
        guard !providers.isEmpty else {
            // Everything asked for was refused; a partial denial keeps what was
            // granted.
            sensing = .denied
            return
        }

        do {
            try await session.run(providers)
        } catch {
            sensing = .failed
            return
        }
        sensing = .fine
        isRunning = true
        // …and again after `run`: the start can outlive every client, and the
        // consumer tasks below must not spawn for nobody.
        guard clients > 0 else {
            // `sensing` stays `.fine`: a session taken down because nobody wants it
            // is not a fault to report.
            stopNow()
            return
        }
        #if DEBUG
        forceSensingForDebug()
        #endif
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
        // Not guarded on `isRunning`: a release during the authorization await
        // must still schedule the teardown. `stopNow` no-ops on a session that
        // never ran.
        guard clients == 0 else { return }
        shutdown?.cancel()
        shutdown = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.lingerSeconds))
            guard !Task.isCancelled else { return }
            self?.stopNow()
        }
    }

    /// Actually takes the sensors down. Called by the linger task, and
    /// by `retain` itself when the last client leaves during a start.
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
                } else if anchor.surfaceClassification == .table || anchor.surfaceClassification == .seat {
                    // A classified table or seat is a finite two-sided wall like any other,
                    // so a ball lands on it and rolls off. Unclassified horizontal planes
                    // would be invisible shelves; the floor is the model's own contact law.
                    wallsByAnchor[anchor.id] = Self.wall(from: anchor)
                }
                planeCorners[anchor.id] = Self.corners(of: anchor)
            }
            walls = Array(wallsByAnchor.values)
            recomputeBounds()
            recomputeCollisionWalls()
        }
    }

    /// Detected walls plus a synthesized boundary box from the scanned
    /// bounds, 5 cm beyond the detected planes so a real wall always strikes
    /// first. Plane detection only yields walls the user has looked at.
    private(set) var collisionWalls: [RoomWalls.Wall] = []

    private func recomputeCollisionWalls() {
        var result = Array(wallsByAnchor.values)
        if hasScannedRoom {
            result.append(contentsOf: RoomWalls.box(of: bounds))
        }
        collisionWalls = result
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

    /// The joints that sketch a hand and forearm; fingertips small, palm
    /// and forearm larger.
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

    /// The tracked fingertip nearest `point`, or nil when no hand is
    /// tracked. Drives `Recession`; nil means "no hand", not "far away", so
    /// callers must not dim on it.
    func nearestFingertip(to point: SIMD3<Float>) -> SIMD3<Float>? {
        let target = SIMD3<Double>(point)
        return fingertips
            .min { simd_distance($0, target) < simd_distance($1, target) }
            .map { SIMD3<Float>($0) }
    }

    /// The hands as things a ball can bounce off: the obstacle joints with
    /// the velocity each moved at since its last update. A hand that
    /// reappears after a gap starts at rest.
    private(set) var handStrikes: [SphereStrike.Sphere] = []
    /// One velocity per entry of `fingertips`, same order — so a module
    /// can tell a hand held out to catch from a hand swung to swat.
    private(set) var fingertipVelocities: [SIMD3<Double>] = []
    private var previousHandSamples: [HandAnchor.Chirality: (time: Double, centers: [SIMD3<Double>])] = [:]
    private var handStrikesByChirality: [HandAnchor.Chirality: [SphereStrike.Sphere]] = [:]

    private func consumeHands() async {
        for await update in hands.anchorUpdates {
            let anchor = update.anchor
            guard anchor.isTracked, let skeleton = anchor.handSkeleton else { continue }
            var spheres: [ObstacleField.Sphere] = []
            var tips: [SIMD3<Double>] = []
            var centers: [SIMD3<Double>] = []
            for (joint, radius) in Self.trackedJoints {
                let transform = anchor.originFromAnchorTransform
                    * skeleton.joint(joint).anchorFromJointTransform
                let c = transform.columns.3
                let point = SIMD3(Double(c.x), Double(c.y), Double(c.z))
                spheres.append(ObstacleField.Sphere(center: point, radius: radius))
                centers.append(point)
                if joint == .indexFingerTip { tips.append(point) }
            }
            // A gap longer than a quarter second is a reappearance, not a sprint.
            let now = CACurrentMediaTime()
            var velocities = Array(repeating: SIMD3<Double>.zero, count: centers.count)
            if let previous = previousHandSamples[anchor.chirality],
               previous.centers.count == centers.count {
                let dt = now - previous.time
                if dt > 1e-4, dt < 0.25 {
                    for index in centers.indices {
                        velocities[index] = (centers[index] - previous.centers[index]) / dt
                    }
                }
            }
            previousHandSamples[anchor.chirality] = (now, centers)
            handStrikesByChirality[anchor.chirality] = zip(spheres, velocities).map {
                SphereStrike.Sphere(center: $0.center, radius: $0.radius, velocity: $1)
            }
            handStrikes = handStrikesByChirality.values.flatMap { $0 }
            handSpheres[anchor.chirality] = spheres
            fingertips = tips
            if let tipIndex = Self.trackedJoints.firstIndex(where: { $0.0 == .indexFingerTip }) {
                fingertipVelocities = [velocities[tipIndex]]
            }
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
            } else {
                meshSpheres[anchor.id] = Self.voxelize(anchor)
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

}

/// Keeps the shared ARKit room-sensing session alive while a module is
/// on screen; one line in `PlaygroundSpaceView`'s module branch.
struct RoomSensingView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        Color.clear
            .task { await appModel.room.retain() }
            .onDisappear { appModel.room.release() }
    }
}
