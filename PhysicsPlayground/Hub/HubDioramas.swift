//
//  HubDioramas.swift
//  Physics Playground — Hub
//
//  Each portal holds its lab in miniature: the lab's own apparatus, built
//  from the parts the lab itself draws (its wells' previews, its milled
//  props, its tracer and its solver), standing on one shared stage and
//  moved by the lab's real physics. Not an emblem of the lab — the lab,
//  small:
//    • Pendulums — Newton's cradle, the lab's opening scene, its end balls
//      on the exact large-amplitude swing of the lab's 0.55 m cables.
//    • Light — the torch, the flint prism and a screen; the light traced
//      by `LightTracer`, rocking through least deviation.
//    • Electric Fields — the dipole inside its glass equipotentials
//      (`Isosurface.meshes`), field lines with riding heads.
//    • Magnetism — the bar magnet through the pickup coil, the LED lit
//      red going in and green coming out by `PickupCoil`'s own EMF.
//    • Projectiles — the launcher, a true arc and the hoop it drops through.
//    • Circuits — battery, switch and bulb: the lever closes, the bulb
//      lights, the electrons go round.
//    • Orbital Mechanics — an orrery: the four inner planets on their real
//      ellipses, perihelia and period ratios, on arms from the Sun's post.
//
//  THE STAGE (`Tools/hubdioramas.py`) is the same size and height in every
//  portal, so seven differently shaped labs read as one row of exhibits.
//  Diorama space is metres, y up, the stage's top at y = 0; a lab built at
//  its own size hangs off a `bench` scaled into it.
//

import Foundation
import PhysicsCore
import RealityKit
import RenderKit
import SwiftUI
import simd

extension HubVignettes {

    // MARK: The stage

    /// The stage entity's name, so a test can find it in any portal.
    static let stageName = "diorama-stage"

    /// The stage's radius in diorama space, as `hubdioramas.py` mills it.
    static let stageRadius: Float = 0.100
    /// How far every stage is turned toward the reader: enough that its top
    /// reads as a surface from a standing eye, little enough that a cable
    /// still hangs plumb to it.
    static let stageTilt: Float = 10 * .pi / 180
    /// The stage's share of the common square's width.
    static let stageShare: Float = 0.92
    /// What share of the stage's radius a lab's footprint fills.
    static let benchShare: Float = 0.9
    /// The tallest a lab may stand above its stage, m of diorama space:
    /// what the square leaves over the stage at `stageShare`.
    static let benchHeight: Float = 0.165

    /// One lab on its stage: `scene` is diorama space.
    struct Diorama {
        let root = Entity()
        let frame = Entity()
        let scene = Entity()

        init() {
            root.addChild(frame)
            scene.orientation = simd_quatf(angle: HubVignettes.stageTilt, axis: [1, 0, 0])
            frame.addChild(scene)
            let stage = HubVignettes.stage()
            stage.name = HubVignettes.stageName
            scene.addChild(stage)
        }

        /// A group for a lab built at its own size in the lab's own metres;
        /// `fitStage` scales it to fill the stage. `yaw` turns it about the
        /// vertical, so a lab whose action runs left to right can run a
        /// little into the depth instead, and use more of a round stage.
        func bench(yaw: Float = 0) -> Entity {
            let pivot = Entity()
            pivot.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
            scene.addChild(pivot)
            let bench = Entity()
            pivot.addChild(bench)
            return bench
        }
    }

    static func stage() -> Entity {
        if let milled = placed("HubStage") { return milled }
        let disc = ModelEntity(mesh: Primitives.cylinder(height: 0.010, radius: stageRadius),
                               materials: [Materials.graphite()])
        disc.position.y = -0.005
        return disc
    }

    /// A milled prop at its authored size and origin — the stage and the
    /// cradle are placed by their numbers, not recentred like `prop`.
    static func placed(_ name: String) -> Entity? {
        PropCache.prototype(named: name)?.clone(recursive: true)
    }

    /// The bounds of `entity` in `space`, swept over a whole cycle.
    private static func swept(_ entity: Entity, in space: Entity, cycle: Double,
                              animate: (Double) -> Void) -> (lower: SIMD3<Float>, upper: SIMD3<Float>) {
        var lower = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var upper = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        for step in 0..<24 {
            animate(cycle * Double(step) / 24)
            let box = entity.visualBounds(relativeTo: space)
            lower = simd_min(lower, box.min)
            upper = simd_max(upper, box.max)
        }
        return (lower, upper)
    }

    /// Fits a diorama by its stage: the stage the same size in every
    /// portal, whatever stands on it. A `bench` is first scaled about the
    /// stage's centre so its footprint, swept over its whole motion, fills
    /// the stage — and no higher than `benchHeight`. Then the whole is
    /// centred in the square by its own height, so a low lab and a tall
    /// one both sit in the middle of their portals.
    static func fitStage(_ diorama: Diorama, bench: Entity? = nil, cycle: Double,
                         animate: @escaping (Double) -> Void) -> Built {
        if let bench {
            bench.scale = .one
            bench.position = .zero
            let span = swept(bench, in: diorama.scene, cycle: cycle, animate: animate)
            let centre = (span.lower + span.upper) / 2
            let reach = max(max(span.upper.x - centre.x, span.upper.z - centre.z), 1e-4)
            let scale = min(benchShare * stageRadius / reach, benchHeight / max(span.upper.y, 1e-4))
            bench.scale = SIMD3(repeating: scale)
            // Recentre the footprint on the stage, in the bench's parent.
            let offset = SIMD3<Float>(centre.x, 0, centre.z) * scale
            if let pivot = bench.parent {
                bench.position = -(pivot.orientation.inverse.act(offset))
            }
        }

        diorama.frame.scale = SIMD3(repeating: stageShare * frameHalf / stageRadius)
        diorama.frame.position = .zero
        var (lower, upper) = swept(diorama.frame, in: diorama.root, cycle: cycle, animate: animate)
        let lift = -(lower.y + upper.y) / 2
        diorama.frame.position = [0, lift, 0]
        lower.y += lift
        upper.y += lift

        let proxy = ModelEntity(
            mesh: Primitives.box(size: [frameHalf * 2, frameHalf * 2, 0.0005]),
            materials: [Materials.unlit(.white, opacity: 0)])
        proxy.name = "vignette-square"
        proxy.components.set(OpacityComponent(opacity: 0))
        diorama.root.addChild(proxy)

        animate(0)
        return Built(entity: diorama.root, animate: animate, contentExtents: upper - lower)
    }

    /// A unit cylinder stretched between two points: a thread, a wire, a
    /// beam. Transform only, so it moves every frame for nothing.
    static func stretch(_ entity: Entity, from a: SIMD3<Float>, to b: SIMD3<Float>,
                        radius: Float) {
        let span = b - a
        let length = simd_length(span)
        guard length > 1e-6 else {
            entity.scale = SIMD3(repeating: 1e-5)
            return
        }
        entity.position = (a + b) / 2
        entity.orientation = rotation(from: [0, 1, 0], to: span / length)
        entity.scale = [radius, length, radius]
    }

    static let unitCylinder = Primitives.cylinder(height: 1, radius: 1)

    // MARK: Pendulums — Newton's cradle

    /// One pendulum's swing released from rest at `amplitude`, exactly:
    /// θ'' = −(g/L) sin θ integrated once (RK4) over a quarter period and
    /// played back by symmetry, so a 31° release keeps its large-angle
    /// period rather than the small-angle 2π√(L/g).
    nonisolated struct PendulumSwing: Sendable {
        let amplitude: Double
        /// θ every `step` seconds from release to the bottom.
        let fall: [Double]
        let step: Double

        init(length: Double, gravity: Double, amplitude: Double, step: Double = 1.0 / 600) {
            self.amplitude = amplitude
            self.step = step
            var theta = amplitude, omega = 0.0
            var fall = [theta]
            let k = gravity / length
            func accel(_ t: Double) -> Double { -k * sin(t) }
            while theta > 0 {
                let k1t = omega, k1w = accel(theta)
                let k2t = omega + step / 2 * k1w, k2w = accel(theta + step / 2 * k1t)
                let k3t = omega + step / 2 * k2w, k3w = accel(theta + step / 2 * k2t)
                let k4t = omega + step * k3w, k4w = accel(theta + step * k3t)
                theta += step / 6 * (k1t + 2 * k2t + 2 * k3t + k4t)
                omega += step / 6 * (k1w + 2 * k2w + 2 * k3w + k4w)
                fall.append(theta)
            }
            self.fall = fall
        }

        /// Release to the bottom, s: a quarter of the period.
        var quarter: Double {
            // The last sample has crossed zero; interpolate the crossing.
            let n = fall.count
            let before = fall[n - 2], after = fall[n - 1]
            return (Double(n - 2) + before / (before - after)) * step
        }

        var period: Double { 4 * quarter }

        /// θ at `t` after release, for 0 ≤ t ≤ quarter.
        func falling(_ t: Double) -> Double {
            let exact = min(max(t / step, 0), Double(fall.count - 1))
            let index = min(Int(exact), fall.count - 2)
            let blend = exact - Double(index)
            return max(fall[index] + (fall[index + 1] - fall[index]) * blend, 0)
        }

        /// The cradle's two end balls at `time`: the left released from
        /// −amplitude falls, strikes, stops; the right carries the swing out
        /// and back; the left swings out again. Angles positive to the right.
        func cradle(at time: Double) -> (left: Double, right: Double) {
            let q = quarter
            let p = time.truncatingRemainder(dividingBy: 4 * q)
            switch p {
            case ..<q: return (-falling(p), 0)
            case ..<(2 * q): return (0, falling(2 * q - p))
            case ..<(3 * q): return (0, falling(p - 2 * q))
            default: return (-falling(4 * q - p), 0)
            }
        }
    }

    /// The cradle's dimensions on the stage (`hubdioramas.py`).
    static let cradleRailHeight: Float = 0.118
    static let cradleRailOffset: Float = 0.026
    static let cradleRailHalf: Float = 0.091
    static let cradleFootRadius: Float = 0.005
    static let cradleBallRadius: Float = 0.0105
    static let cradleRestHeight: Float = 0.043

    /// The lab's own cradle (`PendulumsModel.loadNewtonsCradle`): 0.55 m
    /// cables, the end ball released from 0.55 rad. The miniature is a
    /// scale model of it, so it swings at its period, not a desk toy's.
    static let cradleSwing = PendulumSwing(length: 0.55, gravity: 9.81, amplitude: 0.55)

    static func cradleDiorama() -> Built {
        let diorama = Diorama()
        let scene = diorama.scene
        if let frame = placed("HubCradle") {
            scene.addChild(frame)
        } else {
            for z in [-cradleRailOffset, cradleRailOffset] {
                let rail = ModelEntity(mesh: unitCylinder, materials: [Materials.machined()])
                stretch(rail, from: [-cradleRailHalf, cradleRailHeight, z],
                        to: [cradleRailHalf, cradleRailHeight, z],
                        radius: 0.0024)
                scene.addChild(rail)
            }
        }

        let radius = cradleBallRadius
        let length = cradleRailHeight - cradleRestHeight
        let steel = Materials.machined(UIColor(white: 0.92, alpha: 1), roughness: 0.12)
        let thread = Materials.machined(UIColor(white: 0.18, alpha: 1), roughness: 0.6)
        var balls: [(ball: ModelEntity, threads: [Entity], x: Float)] = []
        for index in 0..<5 {
            let x = Float(index - 2) * 2 * radius
            let ball = ModelEntity(mesh: Primitives.sphere(radius: radius), materials: [steel])
            scene.addChild(ball)
            let threads = (0..<2).map { _ -> Entity in
                let entity = ModelEntity(mesh: unitCylinder, materials: [thread])
                scene.addChild(entity)
                return entity
            }
            balls.append((ball, threads, x))
        }

        func hang(_ entry: (ball: ModelEntity, threads: [Entity], x: Float), angle: Float) {
            let down = SIMD3<Float>(sin(angle), -cos(angle), 0)
            let pivot = SIMD3<Float>(entry.x, cradleRailHeight, 0)
            entry.ball.position = pivot + down * length
            // Bifilar: each thread from its rail to the eye on top of the
            // ball, so the ball swings in one plane, as a cradle's must.
            let eye = pivot + down * (length - radius)
            for (thread, side) in zip(entry.threads, [Float(1), -1]) {
                stretch(thread, from: [entry.x, cradleRailHeight, side * cradleRailOffset],
                        to: eye, radius: 0.00045)
            }
        }

        let swing = cradleSwing
        return fitStage(diorama, cycle: swing.period) { time in
            let ends = swing.cradle(at: time)
            for (index, entry) in balls.enumerated() {
                let angle = index == 0 ? ends.left : index == 4 ? ends.right : 0
                hang(entry, angle: Float(angle))
            }
        }
    }

    // MARK: Light — torch, prism and screen

    /// The flint the lab's prism is made of.
    static let dioramaGlass = Glass.sf11

    /// Where the light runs, in the lab's own metres: the prism raised on a
    /// stand with its triangle toward the reader, white light rising into
    /// its left face at least deviation for 550 nm, the spectrum falling
    /// out of its right face onto a screen.
    struct OpticsBench {
        let prismCentre: SIMD3<Double>
        let incoming: SIMD3<Double>
        let start: SIMD3<Double>
        let screenPoint: SIMD3<Double>
        let screenNormal: SIMD3<Double>

        static let shared: OpticsBench = {
            let apex = OpticsModel.prismApex
            let n = HubVignettes.dioramaGlass.index(nanometers: 550)
            let delta = LightTracer.minimumDeviation(apexAngle: apex, index: n)
            let corners = OpticalElement.prismCorners(apexAngle: apex, side: OpticsModel.prismSide)
            let centre = SIMD3<Double>(0, 0.150, 0)
            let incoming = SIMD3<Double>(cos(delta / 2), sin(delta / 2), 0)
            let entry = SIMD3<Double>((corners[0].x + corners[1].x) / 2,
                                      (corners[0].y + corners[1].y) / 2, 0) + centre
            let exitFace = SIMD3<Double>((corners[0].x + corners[2].x) / 2,
                                         (corners[0].y + corners[2].y) / 2, 0) + centre
            let outgoing = SIMD3<Double>(cos(delta / 2), -sin(delta / 2), 0)
            return OpticsBench(prismCentre: centre, incoming: incoming,
                               start: entry - 0.11 * incoming,
                               screenPoint: exitFace + 0.15 * outgoing,
                               screenNormal: simd_normalize(SIMD3(-cos(delta / 2), sin(delta / 2), 0.55)))
        }()
    }

    static let spectrumColours: [Double] = [420, 460, 500, 540, 580, 620, 660]

    static func opticsDiorama() -> Built {
        let diorama = Diorama()
        let bench = diorama.bench()
        let layout = OpticsBench.shared
        let centre = SIMD3<Float>(layout.prismCentre)
        let apex = OpticsModel.prismApex
        let height = Float(OpticsModel.prismSide * cos(apex / 2))

        // The prism on a lab stand: a graphite table on a champagne pillar.
        let champagne = Materials.machined(UIColor(red: 0.83, green: 0.70, blue: 0.45, alpha: 1),
                                           roughness: 0.3)
        let graphite = Materials.graphite()
        let tableTop = centre.y - height / 3
        let table = ModelEntity(mesh: Primitives.cylinder(height: 0.008, radius: 0.05),
                                materials: [graphite])
        table.position = [centre.x, tableTop - 0.004, 0]
        bench.addChild(table)
        let pillar = ModelEntity(mesh: unitCylinder, materials: [champagne])
        stretch(pillar, from: [centre.x, 0, 0], to: [centre.x, tableTop - 0.008, 0], radius: 0.006)
        bench.addChild(pillar)

        let prism = Entity()
        prism.position = centre
        prism.addChild(OpticsRenderer.pieceModel(.prism))
        bench.addChild(prism)

        // The torch, on its own short pillar, aimed along the light.
        let (torch, _) = OpticsRenderer.torchModel()
        let torchLength = Float(OpticsModel.torchLength)
        let incoming = SIMD3<Float>(layout.incoming)
        torch.orientation = simd_quatf(from: [0, 0, 1], to: incoming)
        torch.position = SIMD3<Float>(layout.start) - incoming * (torchLength / 2)
        bench.addChild(torch)
        let torchPost = ModelEntity(mesh: unitCylinder, materials: [champagne])
        stretch(torchPost, from: [torch.position.x, 0, 0], to: torch.position, radius: 0.005)
        bench.addChild(torchPost)

        // The screen: a white card in a graphite frame, turned to face both
        // the light and the reader.
        let screen = Entity()
        screen.position = SIMD3<Float>(layout.screenPoint)
        screen.orientation = simd_quatf(from: [0, 0, 1], to: SIMD3<Float>(layout.screenNormal))
        let card = ModelEntity(mesh: Primitives.box(size: [0.07, 0.10, 0.003], cornerRadius: 0.002),
                               materials: [Materials.machined(UIColor(white: 0.93, alpha: 1), roughness: 0.8)])
        screen.addChild(card)
        let cardFrame = ModelEntity(mesh: Primitives.box(size: [0.078, 0.108, 0.002], cornerRadius: 0.003),
                                    materials: [graphite])
        cardFrame.position.z = -0.002
        screen.addChild(cardFrame)
        bench.addChild(screen)
        let screenPost = ModelEntity(mesh: unitCylinder, materials: [champagne])
        stretch(screenPost, from: [screen.position.x, 0, screen.position.z],
                to: screen.position - [0, 0.05, 0], radius: 0.004)
        bench.addChild(screenPost)

        // The beams: a bright core in a soft sleeve of its own colour, and
        // a spot where each colour lands on the card.
        let beamCount = 16
        let cores = (0..<beamCount).map { _ -> ModelEntity in
            let core = ModelEntity(mesh: unitCylinder, materials: [])
            core.scale = SIMD3(repeating: 1e-5)
            bench.addChild(core)
            return core
        }
        let sleeves = (0..<beamCount).map { _ -> ModelEntity in
            let sleeve = ModelEntity(mesh: unitCylinder, materials: [])
            sleeve.scale = SIMD3(repeating: 1e-5)
            bench.addChild(sleeve)
            return sleeve
        }
        let spots = spectrumColours.map { _ -> ModelEntity in
            let spot = ModelEntity(mesh: Primitives.sphere(radius: 0.0075), materials: [])
            spot.isEnabled = false
            bench.addChild(spot)
            return spot
        }

        let screenPoint = layout.screenPoint, screenNormal = layout.screenNormal
        let period = 10.0
        return fitStage(diorama, bench: bench, cycle: period) { time in
            let rock = 0.07 * sin(2 * .pi * time / period)
            let turn = simd_quatd(angle: rock, axis: SIMD3(0, 0, 1))
            prism.orientation = OpticsRenderer.single(turn)
            let element = OpticalElement(
                position: layout.prismCentre, orientation: turn,
                shape: .prism(apexAngle: apex, side: OpticsModel.prismSide,
                              length: OpticsModel.prismHeight),
                glass: dioramaGlass)
            let trace = LightTracer.trace(
                spectrumColours.map { LightTracer.Ray(origin: layout.start, direction: layout.incoming,
                                                      nanometers: $0, power: 1 / 7) },
                elements: [element], room: LightTracer.Room(maxSegment: 0.4),
                options: .init(followsPartialReflections: false))
            // Cut every stretch of light at the card.
            var landed: [Int: SIMD3<Float>] = [:]
            var cut = trace
            for index in cut.segments.indices {
                let segment = cut.segments[index]
                guard segment.inside == nil, simd_dot(segment.direction, layout.incoming) > -0.5 else { continue }
                let denominator = simd_dot(segment.b - segment.a, screenNormal)
                guard abs(denominator) > 1e-9 else { continue }
                let t = simd_dot(screenPoint - segment.a, screenNormal) / denominator
                guard t > 0, t < 1 else { continue }
                let hit = segment.a + (segment.b - segment.a) * t
                cut.segments[index].b = hit
                if let colour = spectrumColours.firstIndex(of: segment.nanometers) {
                    landed[colour] = SIMD3<Float>(hit)
                }
            }
            let strokes = OpticsBeamLayout.strokes(cut)
            for index in 0..<beamCount {
                guard index < strokes.count else {
                    cores[index].scale = SIMD3(repeating: 1e-5)
                    sleeves[index].scale = SIMD3(repeating: 1e-5)
                    continue
                }
                let stroke = strokes[index]
                let colour = OpticsRenderer.color(stroke.color)
                stretch(cores[index], from: stroke.a, to: stroke.b, radius: 0.0032)
                stretch(sleeves[index], from: stroke.a, to: stroke.b, radius: 0.0085)
                cores[index].model?.materials = [Materials.unlit(colour)]
                sleeves[index].model?.materials = [Materials.unlit(colour, opacity: 0.28)]
            }
            for (index, spot) in spots.enumerated() {
                guard let at = landed[index] else { spot.isEnabled = false; continue }
                spot.isEnabled = true
                spot.position = at + SIMD3<Float>(screenNormal) * 0.003
                let rgb = Spectrum.linearRGB(nanometers: spectrumColours[index])
                spot.model?.materials = [Materials.unlit(OpticsRenderer.color(rgb), opacity: 0.85)]
            }
        }
    }

    // MARK: Electric Fields — the dipole in its equipotentials

    static func fieldsDiorama() -> Built {
        let diorama = Diorama()
        let bench = diorama.bench()
        // The lab's dipole, closer: ±1 µC 0.22 m apart, 0.15 m above the
        // stage, in the lab's metres.
        let height = 0.15
        let charges = [
            PointCharge(position: SIMD3(-0.11, height, 0), charge: 1e-6),
            PointCharge(position: SIMD3(0.11, height, 0), charge: -1e-6),
        ]
        for (charge, isPositive) in zip(charges, [true, false]) {
            let sphere = FieldRenderer.chargePreview(isPositive: isPositive)
            sphere.scale = SIMD3(repeating: 0.030 / FieldRenderer.wellPreviewRadius)
            sphere.position = SIMD3<Float>(charge.position)
            bench.addChild(sphere)
        }

        // The surfaces of equal potential, glass as in the lab, on the
        // lab's ladder: the ones that close inside a box the stage holds.
        let ladder = FieldModel.equipotentialLevels(charges)
        let ceiling = 2 * (ladder.levels.map(abs).max() ?? 1)
        let meshes = Isosurface.meshes(
            levels: ladder.levels,
            scalar: { min(max(ElectricField.potential(at: $0, dueTo: charges), -ceiling), ceiling) },
            gradient: { -ElectricField.vector(at: $0, dueTo: charges) },
            center: SIMD3(0, height, 0), extents: SIMD3(0.52, 0.44, 0.44),
            resolution: 30, maxTriangles: 30_000)
            .filter(\.isClosed)
        for mesh in meshes {
            guard let resource = TubeMesh.mesh(from: TubeBuffers(
                positions: mesh.positions, normals: mesh.normals, indices: mesh.indices)) else { continue }
            let rank = ladder.step > 0 ? Int((mesh.level / ladder.step).rounded()) : 0
            bench.addChild(ModelEntity(mesh: resource,
                                       materials: [FieldRenderer.shellMaterial(rank: rank)]))
        }

        // Field lines in the reader's plane, leaving + and landing on −.
        let plus = SIMD3<Float>(charges[0].position), minus = SIMD3<Float>(charges[1].position)
        let poles = [Pole(at: plus, strength: 1), Pole(at: minus, strength: -1)]
        // Only lines that land on the −: the arcs that close inside the
        // shells, the dipole's picture, not its far field.
        var paths: [[SIMD3<Float>]] = []
        for tilt in [Float(0), 0.6, 1.2] {
            for flip in tilt == 0 ? [Float(1)] : [1, -1] {
                let out = SIMD3<Float>(cos(tilt), sin(tilt) * flip, 0)
                let path = fieldLine(from: plus + out * 0.033, poles: poles, step: 0.003,
                                     escape: 10, sinks: [(at: minus, radius: 0.032)], maxSteps: 400)
                if let end = path.last, simd_distance(end, minus) < 0.034 { paths.append(path) }
            }
        }
        if let flux = lines(paths, radius: 0.0032, DesignTokens.Palette.fieldLineUI) {
            bench.addChild(flux)
        }
        let head = Primitives.cone(height: 0.016, radius: 0.007)
        let (casingMaterial, headMaterial) = Materials.contrastLine(DesignTokens.Palette.fieldLineUI)
        var riders: [(head: ModelEntity, path: [SIMD3<Float>])] = []
        for path in paths {
            let entity = ModelEntity(mesh: head, materials: [headMaterial])
            let casing = ModelEntity(mesh: Primitives.cone(height: 0.019, radius: 0.0088),
                                     materials: [casingMaterial])
            casing.position.y = -0.0008
            entity.addChild(casing)
            bench.addChild(entity)
            riders.append((entity, path))
        }

        let cycle = 3.6
        return fitStage(diorama, bench: bench, cycle: cycle) { time in
            let travel = Float((time / cycle).truncatingRemainder(dividingBy: 1))
            for rider in riders {
                let last = rider.path.count - 1
                let exact = travel * Float(last)
                let index = min(Int(exact), last - 1)
                let here = rider.path[index], next = rider.path[index + 1]
                rider.head.position = here + (next - here) * (exact - Float(index))
                rider.head.orientation = rotation(from: [0, 1, 0], to: simd_normalize(next - here))
                rider.head.components.set(OpacityComponent(opacity: min(1, min(travel, 1 - travel) * 8)))
            }
        }
    }

    // MARK: Magnetism — the magnet through the coil

    /// The magnet's stroke through the coil, in the lab's metres and
    /// seconds: a brisk push in and out, 1.0 m/s through the bore.
    static let coilStroke = (amplitude: 0.12, period: 0.75)
    static let coilHeight = 0.076

    /// The LED's level across one stroke, sampled: the coil's real linkage
    /// to the moving dipole, ε = −dΛ/dt, and the current the LED pair lets
    /// through (`PickupCoil`, `BicolourLED`), at the lab's 4000 turns.
    static let coilLEDLevels: [Int] = {
        let samples = 180
        let coil = PickupCoil(center: SIMD3(0, coilHeight, 0), axis: SIMD3(1, 0, 0),
                              radius: MagnetismModel.coilRadius, length: MagnetismModel.coilLength,
                              turns: 4000, wireDiameter: MagnetismModel.coilWireDiameter)
        let dt = coilStroke.period / Double(samples)
        func linkage(_ t: Double) -> Double {
            let x = coilStroke.amplitude * sin(2 * .pi * t / coilStroke.period)
            return coil.linkage(magnets: [BarMagnet(position: SIMD3(x, coilHeight, 0),
                                                    moment: SIMD3(MagnetismModel.defaultStrength, 0, 0))])
        }
        return (0..<samples).map { index in
            let t = Double(index) * dt
            let emf = -(linkage(t + dt / 2) - linkage(t - dt / 2)) / dt
            return MagnetismRenderer.ledLevel(
                current: BicolourLED.current(emf: emf, resistance: coil.resistance))
        }
    }()

    static func magnetismDiorama() -> Built {
        let diorama = Diorama()
        let bench = diorama.bench(yaw: -0.45)
        let coil = MagnetismRenderer.coilBody()
        coil.position = [0, Float(coilHeight), 0]
        bench.addChild(coil)
        let dome = MagnetismRenderer.ledDome()
        coil.addChild(dome)
        let glow = GlowSprite.make(size: 0.13)
        glow.position = dome.position
        glow.isEnabled = false
        coil.addChild(glow)
        let light = Entity()
        light.position = dome.position
        coil.addChild(light)

        // Two graphite saddles the coil rests in.
        for x in [Float(-0.03), 0.03] {
            let saddle = ModelEntity(mesh: Primitives.box(size: [0.012, 0.010, 0.07], cornerRadius: 0.003),
                                     materials: [Materials.graphite()])
            saddle.position = [x, 0.005, 0]
            bench.addChild(saddle)
        }

        // The lab's magnet, lying along the bore with north toward +x.
        let magnet = MagnetismRenderer.magnetPreview()
        magnet.orientation = simd_quatf(angle: -.pi / 2, axis: [0, 0, 1])
        let rider = Entity()
        rider.addChild(magnet)
        bench.addChild(rider)

        let levels = coilLEDLevels
        var shown = Int.min
        let period = coilStroke.period
        return fitStage(diorama, bench: bench, cycle: period) { time in
            let phase = (time / period).truncatingRemainder(dividingBy: 1)
            let x = coilStroke.amplitude * sin(2 * .pi * phase)
            rider.position = [Float(x), Float(coilHeight), 0]
            let level = levels[min(Int(phase * Double(levels.count)), levels.count - 1)]
            if level != shown {
                shown = level
                MagnetismRenderer.paintLED(dome: dome, glow: glow, light: light, level: level,
                                           reach: 0.12)
            }
        }
    }

    // MARK: Projectiles — the launcher, an arc and a hoop

    /// The shot, in the lab's metres: 2.3 m/s at 60° from the muzzle, drag
    /// free, through a hoop on the way down.
    static let shot = (speed: 2.3, elevation: 60 * Double.pi / 180)

    static func projectilesDiorama() -> Built {
        let diorama = Diorama()
        let bench = diorama.bench(yaw: -0.55)
        let g = 9.81
        let elevation = shot.elevation
        let aim = SIMD3<Float>(Float(cos(elevation)), Float(sin(elevation)), 0)
        let barrelLength = Float(KinematicsModel.barrelLength)
        let base = SIMD3<Float>(0, 0.05, 0)
        let muzzle = base + aim * barrelLength

        // The launcher as the lab builds it: a machined sphere and the
        // milled barrel, aimed.
        let launcherMaterial = Materials.machined(DesignTokens.Palette.launcherUI)
        let sphere = ModelEntity(mesh: Primitives.sphere(radius: 0.05), materials: [launcherMaterial])
        sphere.position = base
        bench.addChild(sphere)
        let barrel = Entity()
        barrel.position = base + aim * (barrelLength / 2)
        barrel.orientation = rotation(from: [0, 1, 0], to: aim)
        if let loaded = PropCache.instance(named: "LauncherBarrel") {
            loaded.scale = SIMD3(repeating: barrelLength / 0.30)
            loaded.position = [0, -barrelLength / 2, 0]
            barrel.addChild(loaded)
        } else {
            barrel.addChild(ModelEntity(mesh: Primitives.cylinder(height: barrelLength, radius: 0.02),
                                        materials: [launcherMaterial]))
        }
        bench.addChild(barrel)

        // The arc, exactly: x = v cos θ t, y = v sin θ t − ½gt².
        let vx = shot.speed * cos(elevation), vy = shot.speed * sin(elevation)
        func at(_ t: Double) -> SIMD3<Float> {
            muzzle + SIMD3<Float>(Float(vx * t), Float(vy * t - 0.5 * g * t * t), 0)
        }
        // The hoop stands where the ball has fallen 0.12 m below the muzzle.
        let drop = 0.12
        let flight = (vy + (vy * vy + 2 * g * drop).squareRoot()) / g
        let hoopCentre = at(flight)
        let hoopRadius: Float = 0.07
        let circle = (0...40).map { step -> SIMD3<Float> in
            let angle = Float(step) / 40 * 2 * .pi
            return SIMD3(cos(angle) * hoopRadius, 0, sin(angle) * hoopRadius)
        }
        let hoop = Entity()
        hoop.position = hoopCentre
        if let mesh = TubeMesh.tube(lines: [circle], radius: 0.007, sides: 10) {
            hoop.addChild(ModelEntity(mesh: mesh, materials: [
                Materials.energized(DesignTokens.Palette.targetUI, roughness: 0.2, glow: 0.3)]))
        }
        bench.addChild(hoop)
        let mast = ModelEntity(mesh: unitCylinder, materials: [Materials.graphite()])
        stretch(mast, from: [hoopCentre.x + hoopRadius, 0, 0],
                to: [hoopCentre.x + hoopRadius, hoopCentre.y, 0], radius: 0.007)
        bench.addChild(mast)
        let arm = ModelEntity(mesh: unitCylinder, materials: [Materials.graphite()])
        stretch(arm, from: [hoopCentre.x + hoopRadius, hoopCentre.y, 0],
                to: [hoopCentre.x + hoopRadius + 0.02, hoopCentre.y, 0], radius: 0.006)
        bench.addChild(arm)

        // The whole arc, faint, as the lab's ghost draws it: the shot reads
        // between shots.
        let ghost = (0...40).map { at(flight * 1.04 * Double($0) / 40) }
        if let arc = line(ghost, radius: 0.005, DesignTokens.Palette.projectileUI, opacity: 0.35) {
            bench.addChild(arc)
        }

        // The ball and the dots it leaves, as the lab lays them.
        let ballRadius: Float = 0.03
        let ball = ModelEntity(mesh: Primitives.sphere(radius: ballRadius),
                               materials: [Materials.energized(DesignTokens.Palette.projectileUI, glow: 0.45)])
        bench.addChild(ball)
        let dotMaterial = Materials.unlit(DesignTokens.Palette.projectileUI, opacity: 0.6)
        let dotSpacing = 0.035
        let dots = (0..<Int(flight / dotSpacing) + 2).map { _ -> ModelEntity in
            let dot = ModelEntity(mesh: Primitives.sphere(radius: 0.008), materials: [dotMaterial])
            bench.addChild(dot)
            return dot
        }

        let through = flight + 0.06
        let rest = 1.1
        let period = through + rest
        return fitStage(diorama, bench: bench, cycle: period) { time in
            let t = time.truncatingRemainder(dividingBy: period)
            let flying = min(t, through)
            ball.position = at(flying)
            // Out of the barrel and down through the hoop, then gone.
            let fadeIn = min(1, t / 0.05), fadeOut = max(0, min(1, (through - t) / 0.06))
            ball.components.set(OpacityComponent(opacity: Float(t < through ? min(fadeIn, max(fadeOut, 0.0)) : 0)))
            let trailFade = t < through ? 1 : max(0, 1 - (t - through) / rest)
            for (index, dot) in dots.enumerated() {
                let stamp = Double(index + 1) * dotSpacing
                dot.isEnabled = stamp < flying
                dot.position = at(stamp)
                dot.components.set(OpacityComponent(opacity: Float(trailFade)))
            }
            let since = t - flight
            let pulse = since > 0 && since < 0.4 ? sin(.pi * since / 0.4) : 0
            hoop.scale = SIMD3(repeating: 1 + 0.12 * Float(pulse))
        }
    }

    // MARK: Circuits — battery, switch and bulb

    static func circuitsDiorama() -> Built {
        let diorama = Diorama()
        let bench = diorama.bench(yaw: 0.35)
        let lift: Float = 0.026
        let lead = Float(CircuitsModel.terminalOffset)
        let copper = Materials.machined(DesignTokens.Palette.copperUI, roughness: 0.35)

        func part(_ kind: CircuitsModel.ComponentKind, at centre: SIMD3<Float>,
                  along axis: SIMD3<Float>) -> (body: ModelEntity, ends: [SIMD3<Float>]) {
            let holder = Entity()
            holder.position = centre
            holder.orientation = simd_quatf(from: [1, 0, 0], to: axis)
            let body = CircuitsRenderer.partPreview(for: kind)
            holder.addChild(body)
            for x in [-lead, lead] {
                let terminal = ModelEntity(mesh: Primitives.sphere(radius: 0.013), materials: [copper])
                terminal.position = [x, 0, 0]
                holder.addChild(terminal)
            }
            bench.addChild(holder)
            return (body, [centre - axis * lead, centre + axis * lead])
        }

        let battery = part(.battery, at: [0, lift, 0.10], along: [1, 0, 0])
        // The bulb in its holder on a pedestal, as a kit stands one, so the
        // circuit rises off the board and its light stands over it.
        let raised: Float = 0.06
        let pedestal = ModelEntity(mesh: Primitives.box(size: [0.05, raised, 0.05], cornerRadius: 0.006),
                                   materials: [Materials.graphite()])
        pedestal.position = [0, raised / 2, -0.10]
        bench.addChild(pedestal)
        let bulb = part(.bulb, at: [0, lift + raised, -0.10], along: [1, 0, 0])
        let switcher = part(.switcher, at: [-0.17, lift, 0], along: [0, 0, -1])

        // The switch's lever, as the lab hangs it: pivoting at one contact.
        let lever = Entity()
        lever.position = [-0.028, 0.008, 0]
        let blade = ModelEntity(mesh: Primitives.box(size: [0.06, 0.008, 0.014], cornerRadius: 0.003),
                                materials: [Materials.machined(UIColor(white: 0.75, alpha: 1), roughness: 0.3)])
        blade.position = [0.028, 0.006, 0]
        lever.addChild(blade)
        switcher.body.addChild(lever)

        // The bulb's filament and the light round it.
        let filament = ModelEntity(mesh: Primitives.box(size: [0.016, 0.004, 0.004]),
                                   materials: [Materials.unlit(UIColor(white: 0.35, alpha: 1))])
        filament.position = [0, 0.012, 0]
        bulb.body.addChild(filament)
        let halo = ModelEntity(mesh: Primitives.sphere(radius: 0.055),
                               materials: [Materials.unlit(UIColor(red: 1, green: 0.85, blue: 0.4, alpha: 1),
                                                           opacity: 0.5)])
        halo.position = [0, 0.012, 0]
        bulb.body.addChild(halo)
        let warm = Entity()
        warm.position = [0, 0.03 + raised, -0.10]
        bench.addChild(warm)

        // Straight wires, terminal to terminal: battery + to the switch, the
        // switch to the bulb, the bulb back to battery −.
        let runs: [(SIMD3<Float>, SIMD3<Float>)] = [
            (battery.ends[0], switcher.ends[0]),
            (switcher.ends[1], bulb.ends[0]),
            (bulb.ends[1], battery.ends[1]),
        ]
        for run in runs {
            let wire = ModelEntity(mesh: unitCylinder, materials: [copper])
            stretch(wire, from: run.0, to: run.1, radius: 0.0045)
            bench.addChild(wire)
        }

        // The electrons' road, from − round to +: through the bulb, the
        // switch, into the battery's + and through it.
        let road: [SIMD3<Float>] = [battery.ends[1], bulb.ends[1], bulb.ends[0],
                                    switcher.ends[1], switcher.ends[0], battery.ends[0],
                                    battery.ends[1]]
        var cumulative: [Float] = [0]
        for (a, b) in zip(road, road.dropFirst()) { cumulative.append(cumulative.last! + simd_distance(a, b)) }
        let total = cumulative.last!
        func onRoad(_ s: Float) -> SIMD3<Float> {
            let d = s.truncatingRemainder(dividingBy: total)
            let leg = max(0, min(cumulative.lastIndex { $0 <= d } ?? 0, road.count - 2))
            let blend = (d - cumulative[leg]) / max(cumulative[leg + 1] - cumulative[leg], 1e-6)
            return road[leg] + (road[leg + 1] - road[leg]) * blend
        }
        let electronMaterial = Materials.energized(DesignTokens.Palette.electronUI, glow: 0.9)
        let electrons = (0..<14).map { _ -> ModelEntity in
            let electron = ModelEntity(mesh: Primitives.sphere(radius: 0.0075), materials: [electronMaterial])
            electron.position.y = lift + 0.01
            bench.addChild(electron)
            return electron
        }

        let closedFor = 3.2, openFor = 1.6, throwTime = 0.25
        let period = closedFor + openFor
        let litFilament = Materials.unlit(UIColor(red: 1, green: 0.75, blue: 0.3, alpha: 1))
        let darkFilament = Materials.unlit(UIColor(white: 0.35, alpha: 1))
        var wasLit: Bool?
        return fitStage(diorama, bench: bench, cycle: period) { time in
            let t = time.truncatingRemainder(dividingBy: period)
            // Closed, then thrown open, then closed again.
            let openness: Double
            switch t {
            case ..<closedFor: openness = 0
            case ..<(closedFor + throwTime): openness = (t - closedFor) / throwTime
            case ..<(period - throwTime): openness = 1
            default: openness = (period - t) / throwTime
            }
            lever.orientation = simd_quatf(angle: Float(0.6 * openness), axis: [0, 0, 1])
            let lit = openness < 0.05
            filament.model?.materials = [lit ? litFilament : darkFilament]
            halo.isEnabled = lit
            halo.scale = SIMD3(repeating: 0.92 + 0.08 * Float(sin(time * 2.1)))
            if lit != wasLit {
                wasLit = lit
                if lit {
                    warm.components.set(PointLightComponent(
                        color: UIColor(red: 1, green: 0.82, blue: 0.5, alpha: 1),
                        intensity: 600, attenuationRadius: 0.2))
                } else {
                    warm.components.remove(PointLightComponent.self)
                }
            }
            // The carriers move only while the loop is closed.
            let drift = Float(min(t, closedFor)) * 0.12
            for (index, electron) in electrons.enumerated() {
                let s = drift + Float(index) / Float(electrons.count) * total
                electron.position = onRoad(s) + [0, 0.012, 0]
                electron.components.set(OpacityComponent(opacity: lit ? 1 : 0.35))
            }
        }
    }

    // MARK: Orbital Mechanics — an orrery

    /// The inner planets' real orbits: semi-major axis (AU), eccentricity,
    /// longitude of perihelion (degrees) and sidereal period (years).
    static let orreryPlanets: [(name: String, a: Double, e: Double, perihelion: Double,
                                period: Double, radius: Float)] = [
        ("Mercury", 0.387, 0.2056, 77.46, 0.2408, 0.0042),
        ("Venus", 0.723, 0.0068, 131.6, 0.6152, 0.0066),
        ("Earth", 1.000, 0.0167, 102.9, 1.0000, 0.0070),
        ("Mars", 1.524, 0.0934, 336.0, 1.8808, 0.0054),
    ]
    /// One Earth year, played in seconds.
    static let orreryYear = 12.0
    /// Metres of diorama per AU.
    static let orreryScale: Float = 0.058

    /// True anomaly from mean anomaly, by Newton's method on Kepler's
    /// equation M = E − e sin E.
    nonisolated static func trueAnomaly(meanAnomaly: Double, eccentricity e: Double) -> Double {
        var E = meanAnomaly
        for _ in 0..<8 { E -= (E - e * sin(E) - meanAnomaly) / (1 - e * cos(E)) }
        return 2 * atan(sqrt((1 + e) / (1 - e)) * tan(E / 2))
    }

    static func orreryDiorama() -> Built {
        let diorama = Diorama()
        let scene = diorama.scene
        CelestialTextures.warmUp()
        let champagne = Materials.machined(UIColor(red: 0.83, green: 0.70, blue: 0.45, alpha: 1),
                                           roughness: 0.3)
        let plane: Float = 0.082
        let post = ModelEntity(mesh: unitCylinder, materials: [champagne])
        stretch(post, from: [0, 0, 0], to: [0, plane - 0.012, 0], radius: 0.0035)
        scene.addChild(post)
        let sun = world("Sun", radius: 0.011)
        sun.position = [0, plane, 0]
        scene.addChild(sun)

        func position(_ planet: (name: String, a: Double, e: Double, perihelion: Double,
                                 period: Double, radius: Float), at time: Double) -> SIMD3<Float> {
            let mean = 2 * .pi * (time / (planet.period * orreryYear)).truncatingRemainder(dividingBy: 1)
            let nu = trueAnomaly(meanAnomaly: mean, eccentricity: planet.e)
            let r = planet.a * (1 - planet.e * planet.e) / (1 + planet.e * cos(nu))
            let angle = nu + planet.perihelion * .pi / 180
            return [Float(r * cos(angle)) * orreryScale, plane, Float(-r * sin(angle)) * orreryScale]
        }

        var bodies: [(entity: ModelEntity, arm: Entity, planet: (name: String, a: Double, e: Double,
                                                               perihelion: Double, period: Double,
                                                               radius: Float))] = []
        for planet in orreryPlanets {
            // The ellipse, a fine champagne line.
            let path = (0...120).map { step -> SIMD3<Float> in
                let nu = Double(step) / 120 * 2 * .pi
                let r = planet.a * (1 - planet.e * planet.e) / (1 + planet.e * cos(nu))
                let angle = nu + planet.perihelion * .pi / 180
                return [Float(r * cos(angle)) * orreryScale, plane, Float(-r * sin(angle)) * orreryScale]
            }
            if let orbit = line(path, radius: 0.0007, UIColor(red: 0.83, green: 0.70, blue: 0.45, alpha: 1),
                                opacity: 0.75) {
                scene.addChild(orbit)
            }
            let body = world(planet.name, radius: planet.radius)
            scene.addChild(body)
            // Its arm from the Sun's post, each a little lower than the last,
            // as an orrery's arms are stacked.
            let arm = ModelEntity(mesh: unitCylinder, materials: [champagne])
            scene.addChild(arm)
            bodies.append((body, arm, planet))
        }

        var appliedTextureVersion = CelestialTextures.version
        let cycle = orreryYear * 2
        return fitStage(diorama, cycle: cycle) { time in
            if appliedTextureVersion != CelestialTextures.version {
                appliedTextureVersion = CelestialTextures.version
                sun.model?.materials = [celestialMaterial("Sun")]
                for body in bodies { body.entity.model?.materials = [celestialMaterial(body.planet.name)] }
            }
            for (index, body) in bodies.enumerated() {
                let at = position(body.planet, at: time)
                body.entity.position = at
                body.entity.orientation = simd_quatf(angle: Float(time) * 0.9, axis: [0, 1, 0])
                let drop = Float(index + 1) * 0.0022
                stretch(body.arm, from: [0, plane - drop, 0], to: at - [0, drop, 0], radius: 0.0007)
            }
        }
    }
}
