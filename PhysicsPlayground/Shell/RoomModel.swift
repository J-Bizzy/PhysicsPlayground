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
//    • `obstacles`  — hands, forearms and furniture as spheres for the CFD.
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

    /// Why the room is not being sensed, when it is not.
    ///
    /// Every failure path in `retain()` used to be a bare `return`. That
    /// is correct behaviour — the app runs fine without walls, it just
    /// runs a lesser version of itself — but it was also SILENT. Deny the
    /// permission and Projectiles quietly stops bouncing off anything,
    /// occlusion never appears, and Recenter is disabled with a caption
    /// blaming the simulator. A grep for permission copy across the whole
    /// app found comments and nothing else: not one user-facing string.
    ///
    /// The cases are kept distinct because they call for different
    /// sentences, and collapsing them would produce the worst kind of
    /// message — one that tells a simulator user to open Settings.
    enum Sensing: Equatable {
        /// Running, or not asked for yet. Nothing to say.
        case fine
        /// No provider on this device supports what we need. The
        /// simulator, mostly. Not the user's fault and not fixable by
        /// them, so this is FYI rather than a call to action.
        case unsupported
        /// The user said no. This one has a remedy.
        case denied
        /// Authorized, but `session.run` threw anyway.
        case failed

        /// The one-line version, for a title bar or a card.
        ///
        /// THE COPY LIVES ON THE CASE, not on a view. It was two private
        /// static functions on `ModuleHostView`, which meant the only
        /// place in the app that could explain a lesser room was a
        /// warning triangle in a MODULE's title bar — reachable only
        /// after the user has already chosen a lab, and only if they
        /// look at a window they may have left behind them. The ask
        /// itself happens on the gallery, about a second after launch,
        /// so the hub is where an explanation actually belongs; that
        /// needed one authority for the sentences rather than two.
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
                "Experiments run in open space instead. The physics is "
                + "identical — only the parts that use your real walls and "
                + "furniture are missing."
            case .denied:
                "Experiments won't bounce off your real walls or floor, and "
                + "apparatus won't be hidden behind your furniture. To turn "
                + "it back on, open Settings › Privacy & Security › World "
                + "Sensing and allow Physics Playground."
            case .failed:
                "Something went wrong starting it. Leaving this lab and "
                + "opening it again usually fixes it."
            }
        }

        /// Said BEFORE the system asks, so the permission sheet is not
        /// the first the user hears of it. One line: the sheet itself is
        /// where the detail belongs, and a wall of text in front of a
        /// dialog is how people learn to dismiss both.
        static let preExplanation =
            "visionOS will ask to use your room, so labs can stand on your "
            + "floor and balls can bounce off your real walls."
    }

    /// Read by the shell to explain a lesser room. See `Sensing`.
    private(set) var sensing: Sensing = .fine

    #if DEBUG
    /// `-roomSensing denied|unsupported|failed` forces the flag, so the
    /// warning and its copy can be screenshot from the CLI.
    ///
    /// This is not optional polish. The three sentences behind this flag
    /// are user-facing text that ships, and on a headset that granted the
    /// permission — and in the simulator, which grants it too — there is
    /// no way to see any of them. Untestable shipping copy is how this
    /// project ended up with an ARKit prompt advertising a module that
    /// had been deleted. Applied AFTER `retain()`, so it overrides the
    /// real result rather than racing it.
    func forceSensingForDebug() {
        switch UserDefaults.standard.string(forKey: "roomSensing") {
        case "denied": sensing = .denied
        case "unsupported": sensing = .unsupported
        case "failed": sensing = .failed
        default: break
        }
    }
    #endif

    // (An `occluder` entity mirrored the scene-reconstruction mesh here
    // until 2026-08-03, wearing an occlusion material so real furniture
    // hid virtual content. On device it read as black shadows moulded to
    // the room that cut off anything behind them, and the owner asked
    // for it to go. The sensing session below is untouched — lookRay,
    // hands, planes and the obstacle field all still need it.)

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
    /// Readable so `RoomSessionTests` can assert the relationship
    /// between running and reporting.
    ///
    /// The invariant is one-directional, and saying so precisely matters
    /// because an earlier comment here claimed an "iff" that the code
    /// does not hold: anything OTHER than `.fine` implies we are not
    /// running, but `.fine` does not imply we are. `.fine` means
    /// "nothing to tell the user", and a session that is down because
    /// nobody asked for it — either teardown path — is not a fault to
    /// report.
    private(set) var isRunning = false
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
        guard !providers.isEmpty else {
            sensing = .unsupported
            #if DEBUG
            forceSensingForDebug()
            #endif
            return   // simulator: nothing to run
        }

        // Authorization is asked for explicitly rather than implicitly by
        // running: a denied provider is another way `run` throws, and
        // asking first turns that into an ordinary early return.
        let authorization = await session.requestAuthorization(
            for: providers.flatMap { type(of: $0).requiredAuthorizations })
        // THE AWAIT ABOVE IS SECONDS LONG on first launch — it is the
        // system permission sheet — and the user can leave the lab while
        // it is up. If everybody has gone, start nothing.
        guard clients > 0 else { return }
        // Run with whatever was GRANTED. This used to be all-or-nothing:
        // one denied permission killed the entire sensing layer — no
        // walls, no look ray, no hands — silently, which read as every
        // device feature being broken at once.
        let denied = Set(authorization.filter { $0.value != .allowed }.map(\.key))
        providers = providers.filter { provider in
            type(of: provider).requiredAuthorizations.allSatisfy {
                !denied.contains($0)
            }
        }
        guard !providers.isEmpty else {
            // Everything we asked for was refused. (A PARTIAL denial
            // does not land here — the filter above keeps whatever was
            // granted, so losing hands still leaves you walls.)
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
        // …and again after `run`. This is the window the leak lived in:
        // `release()` used to be guarded on `isRunning`, which is still
        // false all the way down to this line, so leaving during the
        // start did nothing at all — and then the three consumer tasks
        // below spawned with `clients == 0`. Plane detection, hand
        // tracking and scene reconstruction then ran for the lifetime of
        // the process, with the sensing indicator lit and nobody reading
        // any of it. Trivial to hit: it is the first launch, where the
        // permission sheet holds the start open for seconds.
        guard clients > 0 else {
            // `sensing` is already `.fine` from two lines up, and that
            // is the right answer rather than an oversight: `.fine`
            // means "nothing to tell the user", and a session taken
            // down because nobody wants it is not a fault to report.
            // The same is true of the ordinary linger teardown. (An
            // earlier version of this branch re-assigned `.fine` here
            // with a comment claiming it was fixing something; it was
            // writing the value that was already there.)
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
        // NOT guarded on `isRunning`, and that was the bug. A release
        // that arrives while `retain` is still awaiting authorization
        // sees `isRunning == false` and used to return, leaving nothing
        // to take the session down. The linger task is the right answer
        // either way: two seconds later the start has resolved one way
        // or the other, and `stopNow` stops a session that ran and
        // no-ops on one that never did.
        guard clients == 0 else { return }
        shutdown?.cancel()
        shutdown = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.lingerSeconds))
            guard !Task.isCancelled else { return }
            await self?.stopNow()
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
                }
                planeCorners[anchor.id] = Self.corners(of: anchor)
            }
            walls = Array(wallsByAnchor.values)
            recomputeBounds()
            recomputeCollisionWalls()
        }
    }

    /// Detected walls PLUS a synthesized boundary box — four vertical
    /// rects and a ceiling from the scanned bounds. Plane detection
    /// only yields walls the user has looked at, so on its own the
    /// bounce feature let balls sail through half the room; the box
    /// guarantees every ball meets the room's edge. The bounds sit
    /// 5 cm beyond the detected planes, so where a real wall exists it
    /// always strikes first.
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

    /// The tracked fingertip nearest `point`, or nil when no hand is
    /// tracked at all.
    ///
    /// This is what drives `Recession`: instruments stand back until a
    /// hand comes near them. Fingertips rather than the whole obstacle
    /// field, because the field also contains furniture and the scene
    /// mesh, and a bookshelf is not a reach.
    ///
    /// NIL IS MEANINGFUL and callers must not treat it as "far away":
    /// in the simulator, and in any device frame where the hands are out
    /// of view, there is no hand to be near anything. `Recession` reads
    /// nil as full brightness for exactly that reason — an instrument
    /// that dims because the system briefly lost your hands is an
    /// instrument that flickers.
    func nearestFingertip(to point: SIMD3<Float>) -> SIMD3<Float>? {
        let target = SIMD3<Double>(point)
        return fingertips
            .min { simd_distance($0, target) < simd_distance($1, target) }
            .map { SIMD3<Float>($0) }
    }

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

/// Keeps the shared ARKit room-sensing session alive for as long as a
/// module is on screen. One line in the module branch of
/// `PlaygroundSpaceView`. (Named `RoomOcclusionView` until 2026-08-03,
/// when it also mounted the room-shaped occlusion mesh; the mesh is
/// gone, the retain/release lifecycle is the part that was always
/// load-bearing.)
struct RoomSensingView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        Color.clear
            .task { await appModel.room.retain() }
            .onDisappear { appModel.room.release() }
    }
}
