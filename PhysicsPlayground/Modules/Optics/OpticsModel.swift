//
//  OpticsModel.swift
//  Physics Playground — Light & Optics
//
//  Optics that stand anywhere in the room: a laser and a white-light torch,
//  and mirrors, prisms, lenses and a glass bar a hand places and turns. The
//  light is traced through them by `PhysicsCore.LightTracer` every time
//  anything moves — exact surfaces, Snell, Fresnel and each wavelength's
//  own index — and lands on the room's real walls and floor.
//
//  Every piece has an aim: the way its face (a mirror), its axis (a lens,
//  the bar) or its apex (a prism, kept level) points. A hand turns a piece
//  by moving its aim bead; the laser, held, points where the hand points.
//

import Foundation
import Observation
import PhysicsCore
import simd

@MainActor
@Observable
final class OpticsModel {

    // MARK: The kit

    enum Kind: String, CaseIterable, Equatable, Sendable {
        case mirror, prism, lens, block
    }

    struct Piece: Identifiable, Equatable, Sendable {
        let id: UUID
        var kind: Kind
        var position: SIMD3<Double>
        /// Which way it faces: a mirror's face, a lens's or the bar's axis,
        /// a prism's apex (always level — the prism stands upright).
        var aim: SIMD3<Double>
    }

    /// A light: where it stands, where it points, whether it is lit.
    struct Source: Equatable, Sendable {
        var position: SIMD3<Double>
        var aim: SIMD3<Double>
        var isOn: Bool
    }

    /// How the torch's light leaves it.
    enum TorchBeam: String, Equatable, Sendable {
        /// One narrow white beam, every colour together — a prism fans it.
        case slit
        /// A broad parallel beam of a few colours — a lens focuses it, and
        /// shows that the rim and the colours each focus in their own place.
        case open
    }

    /// The fixed ids of the two lights, so a hand and a ring address them
    /// as they do a piece.
    nonisolated static let laserID = UUID(uuidString: "0B71C5A5-0000-4000-8000-00000000A5E2")!
    nonisolated static let torchID = UUID(uuidString: "0B71C5A5-0000-4000-8000-0000000070C4")!

    // MARK: Sizes — the physics and the meshes share them

    nonisolated static let regionCenter = SIMD3<Double>(0, 1.25, -1.1)
    nonisolated static let mirrorRadius = 0.06
    /// Protected aluminium, the front-surface mirror of a school optics kit.
    nonisolated static let mirrorReflectance = 0.92
    nonisolated static let prismApex = Double.pi / 3
    nonisolated static let prismSide = 0.10
    nonisolated static let prismHeight = 0.10
    /// A biconvex lens of 15 cm radii: about 15 cm focal length in crown.
    nonisolated static let lensRadius = 0.15
    nonisolated static let lensThickness = 0.018
    nonisolated static let lensDiameter = 0.09
    /// A glass bar, long along its aim: a light pipe, 24 cm by 36 mm square.
    nonisolated static let blockHalfExtents = SIMD3<Double>(0.018, 0.018, 0.12)
    /// The laser and torch bodies, along their aims.
    nonisolated static let laserLength = 0.14
    nonisolated static let torchLength = 0.16
    /// The torch's open beam: this many parallel rays across this width.
    nonisolated static let openRays = 7
    nonisolated static let openWidth = 0.05
    nonisolated static let openColours: [Double] = [460, 550, 640]
    /// The three lines a school laser comes in, nanometres.
    nonisolated static let laserColours: [Double] = [650, 532, 405]
    nonisolated static let pieceBudget = 8
    /// The floor of the room, metres: the immersive space's origin.
    nonisolated static let floorY = 0.0

    // MARK: State

    private(set) var pieces: [Piece] = []
    var laser = Source(position: .zero, aim: SIMD3(1, 0, 0), isOn: true)
    var torch = Source(position: .zero, aim: SIMD3(1, 0, 0), isOn: true)
    var laserNanometers = 532.0
    var torchBeam: TorchBeam = .slit
    /// What every glass piece is made of.
    var glass: Glass = .sf11 { didSet { traceKey = nil } }

    private(set) var selectedID: UUID?
    /// Everything a hand is holding.
    private(set) var heldIDs: Set<UUID> = []

    var isPaused = false
    /// Follow the partial reflections every glass surface makes — real (a
    /// flint face at 63° reflects 15 %), and off until asked for, so the
    /// light's main path reads first.
    var showsWeakReflections = false { didSet { traceKey = nil } }
    /// Draw each surface's normal and the angles the light makes with it.
    var showsAngles = false

    /// The room the light lands in, in this lab's coordinates.
    var room = LightTracer.Room(floorY: OpticsModel.floorY, maxSegment: 6) {
        didSet { if room != oldValue { traceKey = nil } }
    }

    // MARK: Time Capsule

    @ObservationIgnored var capsule = TimeCapsule<CapsuleSnapshot>()
    @ObservationIgnored var capsuleClock = 0.0
    var scrubTime: Double?
    var scrubNonce = 0

    // MARK: Light

    /// The light as last traced, and what it was traced from.
    @ObservationIgnored private(set) var trace = LightTracer.Result()
    @ObservationIgnored private var traceKey: TraceKey?
    /// Bumped each time the trace changes, so a renderer redraws only then.
    @ObservationIgnored private(set) var traceVersion = 0

    private struct TraceKey: Equatable {
        var pieces: [Piece]
        var laser: Source
        var torch: Source
        var laserNanometers: Double
        var torchBeam: TorchBeam
    }

    /// Re-traces if anything the light depends on has changed since the
    /// last trace. Cheap either way: a full trace is tens of microseconds.
    @discardableResult
    func traceIfNeeded() -> LightTracer.Result {
        let key = TraceKey(pieces: pieces, laser: laser, torch: torch,
                           laserNanometers: laserNanometers, torchBeam: torchBeam)
        guard key != traceKey else { return trace }
        traceKey = key
        trace = LightTracer.trace(rays(), elements: elements(), room: room,
                                  options: .init(followsPartialReflections: showsWeakReflections))
        traceVersion &+= 1
        return trace
    }

    /// The optics as the tracer sees them.
    func elements() -> [OpticalElement] {
        pieces.map(element)
    }

    func element(_ piece: Piece) -> OpticalElement {
        let shape: OpticalElement.Shape = switch piece.kind {
        case .mirror:
            .mirror(radius: Self.mirrorRadius, reflectance: Self.mirrorReflectance)
        case .prism:
            .prism(apexAngle: Self.prismApex, side: Self.prismSide, length: Self.prismHeight)
        case .lens:
            .lens(frontRadius: Self.lensRadius, backRadius: Self.lensRadius,
                  thickness: Self.lensThickness, diameter: Self.lensDiameter)
        case .block:
            .block(halfExtents: Self.blockHalfExtents)
        }
        return OpticalElement(id: piece.id, position: piece.position,
                              orientation: Self.orientation(kind: piece.kind, aim: piece.aim),
                              shape: shape, glass: glass)
    }

    /// The light the two sources give off.
    func rays() -> [LightTracer.Ray] {
        var rays: [LightTracer.Ray] = []
        if laser.isOn {
            rays.append(.init(origin: Self.aperture(of: laser, length: Self.laserLength),
                              direction: laser.aim, nanometers: laserNanometers))
        }
        if torch.isOn {
            let origin = Self.aperture(of: torch, length: Self.torchLength)
            switch torchBeam {
            case .slit:
                let share = 1 / Double(LightTracer.visibleSpectrum.count)
                for nm in LightTracer.visibleSpectrum {
                    rays.append(.init(origin: origin, direction: torch.aim,
                                      nanometers: nm, power: share))
                }
            case .open:
                let frame = Self.frame(aim: torch.aim)
                let share = 1 / Double(Self.openRays * Self.openColours.count)
                for index in 0..<Self.openRays {
                    let t = Double(index) / Double(Self.openRays - 1) - 0.5
                    let start = origin + frame.x * (t * Self.openWidth)
                    for nm in Self.openColours {
                        rays.append(.init(origin: start, direction: torch.aim,
                                          nanometers: nm, power: share))
                    }
                }
            }
        }
        return rays
    }

    /// Where a source's light leaves it: the front of its body.
    nonisolated static func aperture(of source: Source, length: Double) -> SIMD3<Double> {
        source.position + simd_normalize(source.aim) * (length / 2)
    }

    // MARK: Orientation

    /// A level frame whose z is `aim`: x across, y as near world-up as the
    /// aim allows (world −z when the aim is vertical).
    nonisolated static func frame(aim: SIMD3<Double>)
        -> (x: SIMD3<Double>, y: SIMD3<Double>, z: SIMD3<Double>) {
        let z = simd_normalize(aim)
        let up = SIMD3<Double>(0, 1, 0)
        var y = up - simd_dot(up, z) * z
        if simd_length(y) < 1e-6 { y = SIMD3(0, 0, -1) - simd_dot(SIMD3(0, 0, -1), z) * z }
        y = simd_normalize(y)
        return (simd_cross(y, z), y, z)
    }

    /// A piece's orientation from its aim. A mirror, lens and bar point
    /// their local +z along it; the prism stands upright (local +z up) and
    /// turns its apex (local +y) to the aim's level direction.
    nonisolated static func orientation(kind: Kind, aim: SIMD3<Double>) -> simd_quatd {
        let columns: (SIMD3<Double>, SIMD3<Double>, SIMD3<Double>)
        if kind == .prism {
            let apex = level(aim)
            let z = SIMD3<Double>(0, 1, 0)
            columns = (simd_cross(apex, z), apex, z)
        } else {
            let f = frame(aim: aim)
            columns = (f.x, f.y, f.z)
        }
        return simd_quatd(simd_double3x3(columns: columns))
    }

    /// `v` with its vertical part removed, normalised (+x if nothing is left).
    nonisolated static func level(_ v: SIMD3<Double>) -> SIMD3<Double> {
        let flat = SIMD3(v.x, 0, v.z)
        return simd_length(flat) > 1e-9 ? simd_normalize(flat) : SIMD3(1, 0, 0)
    }

    // MARK: Addressing

    var selectedPiece: Piece? {
        guard let selectedID else { return nil }
        return pieces.first { $0.id == selectedID }
    }

    func isSource(_ id: UUID) -> Bool { id == Self.laserID || id == Self.torchID }

    func contains(_ id: UUID) -> Bool {
        isSource(id) || pieces.contains { $0.id == id }
    }

    func position(of id: UUID) -> SIMD3<Double>? {
        switch id {
        case Self.laserID: laser.position
        case Self.torchID: torch.position
        default: pieces.first { $0.id == id }?.position
        }
    }

    func aim(of id: UUID) -> SIMD3<Double>? {
        switch id {
        case Self.laserID: laser.aim
        case Self.torchID: torch.aim
        default: pieces.first { $0.id == id }?.aim
        }
    }

    // MARK: Handling

    func grab(id: UUID) {
        guard contains(id) else { return }
        heldIDs.insert(id)
        selectedID = id
    }

    func release(id: UUID) { heldIDs.remove(id) }

    func releaseAll() { heldIDs.removeAll() }

    func select(id: UUID?) {
        guard let id else { selectedID = nil; return }
        guard contains(id) else { return }
        selectedID = id
    }

    /// Carries a piece or a light to `point`. A held laser also points
    /// from the wearer's eyes through the hand, the way a pointer is aimed.
    func move(id: UUID, to point: SIMD3<Double>, viewer: SIMD3<Double>? = nil) {
        var target = point
        target.y = max(target.y, Self.floorY + 0.05)
        switch id {
        case Self.laserID:
            laser.position = target
            if let viewer, simd_distance(viewer, target) > 0.15 {
                laser.aim = simd_normalize(target - viewer)
            }
        case Self.torchID:
            torch.position = target
        default:
            guard let index = pieces.firstIndex(where: { $0.id == id }) else { return }
            pieces[index].position = target
        }
    }

    /// Turns a piece or a light to face `point` — what its aim bead does.
    func aim(id: UUID, toward point: SIMD3<Double>) {
        guard let position = position(of: id) else { return }
        let offset = point - position
        guard simd_length(offset) > 1e-4 else { return }
        let direction = simd_normalize(offset)
        switch id {
        case Self.laserID: laser.aim = direction
        case Self.torchID: torch.aim = direction
        default:
            guard let index = pieces.firstIndex(where: { $0.id == id }) else { return }
            pieces[index].aim = pieces[index].kind == .prism ? Self.level(direction) : direction
        }
    }

    // MARK: Editing

    @discardableResult
    func addPiece(_ kind: Kind, at point: SIMD3<Double>) -> UUID? {
        guard pieces.count < Self.pieceBudget else { return nil }
        // Born facing the wearer's line of sight, so the first thing it does is
        // catch whatever light is coming the way they look.
        let piece = Piece(id: UUID(), kind: kind,
                          position: SIMD3(point.x, max(point.y, Self.floorY + 0.05), point.z),
                          aim: kind == .prism ? SIMD3(1, 0, 0) : SIMD3(0, 0, 1))
        pieces.append(piece)
        selectedID = piece.id
        return piece.id
    }

    func removePiece(id: UUID) {
        pieces.removeAll { $0.id == id }
        heldIDs.remove(id)
        if selectedID == id { selectedID = nil }
    }

    /// Clears every piece; the lights stay where they stand.
    func clearPieces() {
        pieces.removeAll()
        heldIDs = heldIDs.filter(isSource)
        if let selectedID, !isSource(selectedID) { self.selectedID = nil }
    }

    func toggleLight(id: UUID) {
        if id == Self.laserID { laser.isOn.toggle() }
        if id == Self.torchID { torch.isOn.toggle() }
    }

    /// Red, green, violet, and round again.
    func cycleLaserColour() {
        let index = Self.laserColours.firstIndex(of: laserNanometers) ?? 0
        laserNanometers = Self.laserColours[(index + 1) % Self.laserColours.count]
    }

    func toggleTorchBeam() {
        torchBeam = torchBeam == .slit ? .open : .slit
    }

    // MARK: Clock

    /// Light needs no stepping — it is traced whenever anything moves — so a
    /// step only records the bench for the Time Capsule.
    func step(dt: Double) {
        guard !isPaused else { return }
        defer { recordCapsuleFrame(dt: min(dt, 1.0 / 30.0)) }
    }

    func togglePause() { togglePauseRespectingScrub() }

    // MARK: Reset

    func reset() {
        // ResetCoverageTests enumerates every Bool, so a new flag obliges a
        // line here.
        isPaused = false
        showsWeakReflections = false
        showsAngles = false
        glass = .sf11
        laserNanometers = 532
        torchBeam = .slit
        heldIDs.removeAll()
        selectedID = nil
        let scene = Self.openingScene(glass: glass)
        torch = scene.torch
        laser = scene.laser
        pieces = scene.pieces
        traceKey = nil
        clearCapsule()
    }

    /// What the lab opens on, so it never opens dead: white light through a
    /// prism at its least deviation, fanning a spectrum straight ahead onto
    /// the wall; and the green laser turned by a mirror into the end of the
    /// glass bar, which it cannot leave through the sides.
    nonisolated static func openingScene(glass: Glass)
        -> (torch: Source, laser: Source, pieces: [Piece]) {
        // At least deviation the light crosses the prism parallel to its base,
        // from the middle of one face to the middle of the other, turning by
        // δ_min; aimed so the fan leaves straight ahead (−z). The torch aims at
        // its entry face's middle — aimed at the centroid, the beam would catch
        // the base first.
        let delta = LightTracer.minimumDeviation(
            apexAngle: prismApex, index: glass.index(nanometers: 550))
        let incoming = SIMD3(sin(delta), 0, -cos(delta))
        let apex = SIMD3(cos(delta / 2), 0, sin(delta / 2))
        let prismAt = SIMD3(0.12, 1.38, -1.5)
        let prism = Piece(id: UUID(), kind: .prism, position: prismAt, aim: apex)
        let corners = OpticalElement.prismCorners(apexAngle: prismApex, side: prismSide)
        // The face the light enters is the one on the prism's local +x side.
        let faceMiddle = (corners[0] + corners[2]) / 2
        let entry = OpticalElement(position: prismAt,
                                   orientation: orientation(kind: .prism, aim: apex),
                                   shape: .prism(apexAngle: prismApex, side: prismSide,
                                                 length: prismHeight))
            .toWorld(point: SIMD3(faceMiddle.x, faceMiddle.y, 0))
        let torch = Source(position: entry - (0.36 + torchLength / 2) * incoming,
                           aim: incoming, isOn: true)

        // The laser sends its beam left; a mirror turns it ahead into the bar's
        // end at 25°, steep enough to refract in and shallow enough that every
        // side face reflects it totally.
        let beamHeight = 1.12
        let mirrorAt = SIMD3(-0.16, beamHeight, -1.0)
        let laser = Source(position: SIMD3(0.5, beamHeight, -1.0),
                           aim: SIMD3(-1, 0, 0), isOn: true)
        let tilt = 25 * Double.pi / 180
        let barAim = SIMD3(-sin(tilt), 0, -cos(tilt))
        let barEntry = mirrorAt + SIMD3(0, 0, -0.26)
        let barAt = barEntry + barAim * blockHalfExtents.z

        let pieces = [
            prism,
            Piece(id: UUID(), kind: .mirror, position: mirrorAt,
                  aim: simd_normalize(SIMD3(1, 0, -1))),
            Piece(id: UUID(), kind: .block, position: barAt, aim: barAim),
        ]
        return (torch, laser, pieces)
    }

    init() {
        reset()
        #if DEBUG
        // `-optGlass crown|flint` opens with that glass.
        switch UserDefaults.standard.string(forKey: "optGlass") {
        case "crown": glass = .nbk7
        case "flint": glass = .sf11
        default: break
        }
        // `-optLambda <nm>` sets the laser's line.
        let lambda = UserDefaults.standard.double(forKey: "optLambda")
        if lambda >= 380, lambda <= 750 { laserNanometers = lambda }
        if UserDefaults.standard.bool(forKey: "optAngles") { showsAngles = true }
        if UserDefaults.standard.string(forKey: "optBeam") == "open" { torchBeam = .open }
        #endif
    }
}

// MARK: - Time Capsule

extension OpticsModel: TimeCapsuleRecording {
    /// The bench: every piece and both lights, and the glass, which changes
    /// where the light goes. Out: the display layers and the selection.
    struct CapsuleSnapshot: Equatable {
        var pieces: [Piece]
        var laser: Source
        var torch: Source
        var laserNanometers: Double
        var torchBeam: TorchBeam
        var glass: Glass
    }

    func captureCapsuleSnapshot() -> CapsuleSnapshot {
        CapsuleSnapshot(pieces: pieces, laser: laser, torch: torch,
                        laserNanometers: laserNanometers, torchBeam: torchBeam, glass: glass)
    }

    func restoreCapsuleSnapshot(_ snapshot: CapsuleSnapshot) {
        // What a hand holds stays where the hand has it.
        var restored = snapshot.pieces
        for index in restored.indices where heldIDs.contains(restored[index].id) {
            if let live = pieces.first(where: { $0.id == restored[index].id }) {
                restored[index] = live
            }
        }
        for held in heldIDs where !isSource(held) && !restored.contains(where: { $0.id == held }) {
            if let live = pieces.first(where: { $0.id == held }) { restored.append(live) }
        }
        pieces = restored
        if !heldIDs.contains(Self.laserID) { laser = snapshot.laser }
        if !heldIDs.contains(Self.torchID) { torch = snapshot.torch }
        laserNanometers = snapshot.laserNanometers
        torchBeam = snapshot.torchBeam
        glass = snapshot.glass
        if let selectedID, !contains(selectedID) { self.selectedID = nil }
    }
}
