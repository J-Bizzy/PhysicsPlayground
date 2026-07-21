//
//  WaveLabRenderer.swift
//  Physics Playground — Waves & Optics Studio
//
//  The Wave Lab area: emitters whose crests expand as translucent
//  shells from their EMISSION points (drag a source and Doppler
//  happens to you), a walkable interference lattice driven by the
//  phasor cache, and the room-scale double slit — barrier, Huygens
//  slit sources, and a floating fringe strip painted with the exact
//  screen formula, with an optional geometric-ray overlay connecting
//  the wave picture to the ray picture.
//
//  Frame-rate contract: shells and lattice dots are pooled; per-frame
//  work is transform writes plus the two-trig phasor pulse. Lattice
//  coefficients and fringe colors rebuild change-gated (the former on
//  a GeometryPipeline worker).
//

import Foundation
import PhysicsCore
import RealityKit
import RenderKit
import SwiftUI
import simd

@MainActor
final class WaveLabRenderer {
    let root = Entity()

    var manipulatingEmitterID: UUID?

    static let barrierName = "rig-barrier"
    static let screenName = "rig-screen"

    // MARK: Pools

    private var emitterEntities: [ModelEntity] = []
    private var emitterKeys: [String] = []

    private static let shellBudget = 44
    private var shellEntities: [ModelEntity] = []
    private var shellMaterials: [UnlitMaterial] = []

    private static let latticeSide = 8
    private var latticeDots: [ModelEntity] = []
    private var latticeC: [Float]
    private var latticeS: [Float]
    private var latticeScaleKeys: [Float]
    private var latticeTintKeys: [Int]
    private var latticePalette: [UnlitMaterial] = []
    private var latticeReference: Float = 1
    private var latticePipeline: GeometryPipeline<LatticeJob, LatticeResult>?
    private var lastLatticeInputs: LatticeInputs?

    // MARK: Rig

    private let rigRoot = Entity()
    private var rigSource: ModelEntity!
    private var barrierTop: ModelEntity!
    private var barrierMiddle: ModelEntity!
    private var barrierBottom: ModelEntity!
    private var screenPanel: ModelEntity!
    private static let fringeCount = 56
    private static let fringeHalfHeight = 0.45
    private var fringeBars: [ModelEntity] = []
    private var fringePalette: [UnlitMaterial] = []
    private let rayOverlay = ModelEntity()
    private let rayOverlayMaterial: UnlitMaterial = {
        var material = UnlitMaterial(color: UIColor(red: 1, green: 0.85, blue: 0.4, alpha: 1))
        material.blending = .transparent(opacity: 0.55)
        return material
    }()
    private var spacingLabelPivot: Entity!
    private var spacingLabel: ModelEntity!
    private var labelMeshCache: [String: MeshResource] = [:]
    private let labelMaterial = UnlitMaterial(color: UIColor(
        red: 0.35, green: 0.85, blue: 0.9, alpha: 1))
    private var lastRigKey = ""

    private struct LatticeInputs: Equatable {
        var sources: [WaveSource]
        var frequency: Double
        var speed: Double
    }

    init() {
        latticeC = Array(repeating: 0, count: Self.latticeSide * Self.latticeSide * Self.latticeSide)
        latticeS = latticeC
        latticeScaleKeys = latticeC
        latticeTintKeys = Array(repeating: -1, count: latticeC.count)

        buildEmitters()
        buildShells()
        buildLattice()
        buildRig()

        latticePipeline = GeometryPipeline(
            compute: { Self.computeLattice($0) },
            apply: { [weak self] in self?.applyLattice($0) }
        )
    }

    // MARK: Emitters

    private func buildEmitters() {
        let speakerPrototype = try? Entity.load(named: "WaveSpeaker")
        var shellTint = UnlitMaterial(color: DesignTokens.Palette.waveSourceUI)
        shellTint.blending = .transparent(opacity: 0.3)
        let sphere = MeshResource.generateSphere(radius: 0.045)
        for _ in 0..<OpticsModel.emitterBudget {
            let emitter = ModelEntity(mesh: sphere, materials: [shellTint])
            if let speakerPrototype {
                emitter.addChild(speakerPrototype.clone(recursive: true))
            }
            Grabbable.configureTouchTarget(emitter, collisionRadius: 0.07)
            var accessibility = AccessibilityComponent()
            accessibility.isAccessibilityElement = true
            accessibility.label = "Wave emitter. Drag it through the room and watch the crests bunch ahead of it."
            emitter.components.set(accessibility)
            emitter.isEnabled = false
            root.addChild(emitter)
            emitterEntities.append(emitter)
            emitterKeys.append("")
        }
    }

    // MARK: Shells (the crests)

    private func buildShells() {
        // Five opacity steps: young crests bright, old crests faint.
        shellMaterials = (0..<5).map { step in
            var material = UnlitMaterial(color: DesignTokens.Palette.waveSourceUI)
            material.blending = .transparent(
                opacity: .init(floatLiteral: 0.10 - 0.02 * Float(step)))
            material.faceCulling = .none
            return material
        }
        let mesh = MeshResource.generateSphere(radius: 1)
        for _ in 0..<Self.shellBudget {
            let shell = ModelEntity(mesh: mesh, materials: [shellMaterials[0]])
            shell.isEnabled = false
            root.addChild(shell)
            shellEntities.append(shell)
        }
    }

    private var shellBucketKeys = [Int](repeating: -1, count: 44)

    private func syncShells(_ model: OpticsModel) {
        let shells = model.labShells()
        for (index, entity) in shellEntities.enumerated() {
            guard index < shells.count else {
                entity.isEnabled = false
                continue
            }
            let shell = shells[index]
            entity.isEnabled = true
            entity.position = SIMD3<Float>(shell.center)
            entity.scale = SIMD3(repeating: Float(shell.radius))
            let bucket = min(Int(shell.radius / 1.7 * 5), 4)
            if shellBucketKeys[index] != bucket {
                shellBucketKeys[index] = bucket
                entity.model?.materials = [shellMaterials[bucket]]
            }
        }
    }

    // MARK: Lattice (walkable interference)

    private nonisolated static let latticePoints: [SIMD3<Double>] = {
        let side = latticeSide
        let spacing = 2 * OpticsModel.labHalfExtent * 0.9 / Double(side - 1)
        let origin = OpticsModel.labCenter
            - SIMD3(repeating: OpticsModel.labHalfExtent * 0.9)
        var points: [SIMD3<Double>] = []
        points.reserveCapacity(side * side * side)
        for i in 0..<side {
            for j in 0..<side {
                for k in 0..<side {
                    points.append(origin + spacing * SIMD3(Double(i), Double(j), Double(k)))
                }
            }
        }
        return points
    }()

    private func buildLattice() {
        latticePalette = (0..<6).map { step in
            let t = CGFloat(step) / 5
            var material = UnlitMaterial(color: UIColor(
                red: 0.25 + 0.3 * t, green: 0.6 + 0.3 * t, blue: 0.7 + 0.25 * t, alpha: 1))
            material.blending = .transparent(opacity: .init(floatLiteral: Float(0.15 + 0.5 * t)))
            return material
        }
        let mesh = MeshResource.generateSphere(radius: 0.0095)
        for point in Self.latticePoints {
            let dot = ModelEntity(mesh: mesh, materials: [latticePalette[2]])
            dot.position = SIMD3<Float>(point)
            root.addChild(dot)
            latticeDots.append(dot)
        }
    }

    private nonisolated struct LatticeJob: Sendable {
        var sources: [WaveSource]
        var frequency: Double
        var speed: Double
    }

    private nonisolated struct LatticeResult: Sendable {
        var c: [Float]
        var s: [Float]
        var tints: [Int]
        var reference: Float
    }

    private nonisolated static func computeLattice(_ job: LatticeJob) -> LatticeResult {
        let count = latticePoints.count
        var c = [Float](repeating: 0, count: count)
        var s = [Float](repeating: 0, count: count)
        var tints = [Int](repeating: 0, count: count)
        let reference = job.sources.map(\.amplitude).reduce(0, +) * WaveField.falloff(0.25)
        for index in 0..<count {
            let phasor = WaveField.phasorCoefficients(
                at: latticePoints[index], sources: job.sources,
                frequency: job.frequency, speed: job.speed)
            c[index] = Float(phasor.c)
            s[index] = Float(phasor.s)
            let envelope = (phasor.c * phasor.c + phasor.s * phasor.s).squareRoot()
            tints[index] = min(Int(envelope / max(reference, 1e-12) * 5), 5)
        }
        return LatticeResult(c: c, s: s, tints: tints, reference: Float(reference))
    }

    private func applyLattice(_ result: LatticeResult) {
        guard result.c.count == latticeDots.count else { return }
        latticeC = result.c
        latticeS = result.s
        latticeReference = result.reference
        for (index, dot) in latticeDots.enumerated()
        where latticeTintKeys[index] != result.tints[index] {
            latticeTintKeys[index] = result.tints[index]
            dot.model?.materials = [latticePalette[result.tints[index]]]
        }
    }

    private func syncLattice(_ model: OpticsModel) {
        let inputs = LatticeInputs(
            sources: model.labWaveSources, frequency: model.labFrequency,
            speed: model.labWaveSpeed)
        if inputs != lastLatticeInputs {
            lastLatticeInputs = inputs
            latticePipeline?.submit(LatticeJob(
                sources: inputs.sources, frequency: inputs.frequency, speed: inputs.speed))
        }
        // The two-trig pulse (see WaveFieldTests for the identity).
        let omega = 2 * .pi * model.labFrequency
        let cosT = Float(cos(omega * model.labTime))
        let sinT = Float(sin(omega * model.labTime))
        let reference = max(latticeReference, 1e-12)
        for index in latticeDots.indices {
            let u = latticeC[index] * cosT - latticeS[index] * sinT
            let normalized = min(abs(u) / reference, 1.6)
            let scale = 0.3 + 0.7 * normalized
            guard abs(scale - latticeScaleKeys[index]) > 0.015 else { continue }
            latticeScaleKeys[index] = scale
            latticeDots[index].scale = SIMD3(repeating: scale)
        }
    }

    // MARK: Double-slit rig

    private func buildRig() {
        let barrierMaterial = SimpleMaterial(
            color: UIColor(white: 0.22, alpha: 1), roughness: 0.6, isMetallic: false)
        func barrierPiece() -> ModelEntity {
            let piece = ModelEntity(
                mesh: .generateBox(size: [0.02, 1, 0.3], cornerRadius: 0.004),
                materials: [barrierMaterial])
            piece.name = Self.barrierName
            rigRoot.addChild(piece)
            return piece
        }
        barrierTop = barrierPiece()
        barrierMiddle = barrierPiece()
        barrierBottom = barrierPiece()
        Grabbable.configureTouchTarget(barrierMiddle, collisionRadius: 0.12)

        var panelMaterial = PhysicallyBasedMaterial()
        panelMaterial.baseColor = .init(tint: .white)
        panelMaterial.roughness = 0.9
        panelMaterial.blending = .transparent(opacity: .init(floatLiteral: 0.16))
        screenPanel = ModelEntity(
            mesh: .generateBox(size: [0.006, 2 * Float(Self.fringeHalfHeight) + 0.1, 0.3]),
            materials: [panelMaterial])
        screenPanel.name = Self.screenName
        Grabbable.configureTouchTarget(screenPanel, collisionRadius: 0.16)
        rigRoot.addChild(screenPanel)

        // The rig's own emitter: same speaker look, fixed in place.
        var tint = UnlitMaterial(color: DesignTokens.Palette.waveSourceUI)
        tint.blending = .transparent(opacity: 0.3)
        rigSource = ModelEntity(mesh: .generateSphere(radius: 0.045), materials: [tint])
        if let speaker = try? Entity.load(named: "WaveSpeaker") {
            rigSource.addChild(speaker.clone(recursive: true))
        }
        rigRoot.addChild(rigSource)

        // Fringe strip: brightness buckets of the studio teal.
        fringePalette = (0..<8).map { step in
            let t = CGFloat(step) / 7
            var material = UnlitMaterial(color: UIColor(
                red: 0.1 + 0.35 * t, green: 0.35 + 0.6 * t, blue: 0.45 + 0.5 * t, alpha: 1))
            material.blending = .transparent(opacity: .init(floatLiteral: Float(0.1 + 0.85 * t)))
            return material
        }
        let barHeight = Float(2 * Self.fringeHalfHeight) / Float(Self.fringeCount)
        let barMesh = MeshResource.generateBox(
            size: [0.012, barHeight * 0.92, 0.26])
        for _ in 0..<Self.fringeCount {
            let bar = ModelEntity(mesh: barMesh, materials: [fringePalette[0]])
            rigRoot.addChild(bar)
            fringeBars.append(bar)
        }

        rigRoot.addChild(rayOverlay)

        spacingLabelPivot = Entity()
        spacingLabelPivot.components.set(BillboardComponent())
        spacingLabel = ModelEntity()
        spacingLabelPivot.addChild(spacingLabel)
        rigRoot.addChild(spacingLabelPivot)

        rigRoot.isEnabled = false
        root.addChild(rigRoot)
    }

    private var fringeBucketKeys = [Int](repeating: -1, count: WaveLabRenderer.fringeCount)

    private func syncRig(_ model: OpticsModel) {
        rigRoot.isEnabled = model.slitRigOn
        guard model.slitRigOn else { return }

        let center = OpticsModel.labCenter
        let barrierX = Float(center.x + model.rigBarrierX)
        let screenX = Float(center.x + model.rigScreenX)
        let cy = Float(center.y)
        let cz = Float(center.z)

        rigSource.position = SIMD3<Float>(center + OpticsModel.rigSourceOffset)

        // Three barrier pieces leave two slits open.
        let d = Float(model.slitSeparation)
        let w = Float(model.slitWidth)
        let panelHalf: Float = 0.5
        let topOfUpperSlit = cy + d / 2 + w / 2
        let bottomOfLowerSlit = cy - d / 2 - w / 2
        let middleHeight = d - w
        barrierTop.position = SIMD3(barrierX, topOfUpperSlit + panelHalf, cz)
        barrierBottom.position = SIMD3(barrierX, bottomOfLowerSlit - panelHalf, cz)
        barrierMiddle.position = SIMD3(barrierX, cy, cz)
        barrierMiddle.scale = SIMD3(1, max(middleHeight, 0.001), 1)

        screenPanel.position = SIMD3(screenX, cy, cz)

        // Fringe strip + label + ray overlay, change-gated.
        let key = String(format: "%.3f|%.3f|%.3f|%.3f|%.3f|%d",
                         model.slitSeparation, model.slitWidth, model.labWavelength,
                         model.rigBarrierX, model.rigScreenX,
                         model.showFringeRays ? 1 : 0)
        guard key != lastRigKey else { return }
        lastRigKey = key

        let barHeight = 2 * Self.fringeHalfHeight / Double(Self.fringeCount)
        for (index, bar) in fringeBars.enumerated() {
            let y = -Self.fringeHalfHeight + (Double(index) + 0.5) * barHeight
            bar.position = SIMD3(screenX + 0.012, cy + Float(y), cz)
            let bucket = min(Int(model.fringeIntensity(y: y) * 7.99), 7)
            if fringeBucketKeys[index] != bucket {
                fringeBucketKeys[index] = bucket
                bar.model?.materials = [fringePalette[bucket]]
            }
        }

        setLabel(String(format: "Δy = λL/d = %.1f cm", model.fringeSpacing * 100))
        spacingLabelPivot.position = SIMD3(
            screenX, cy + Float(Self.fringeHalfHeight) + 0.09, cz)

        if model.showFringeRays {
            let maxima = model.fringeMaxima(count: 7)
                .filter { abs($0) < Self.fringeHalfHeight }
            let slits = model.slitCenters
            var lines: [[SIMD3<Float>]] = []
            for maximum in maxima {
                let target = SIMD3<Float>(
                    screenX, cy + Float(maximum), cz)
                lines.append([SIMD3<Float>(slits.a), target])
                lines.append([SIMD3<Float>(slits.b), target])
            }
            if let mesh = TubeMesh.tube(lines: lines, radius: 0.0014, sides: 3) {
                rayOverlay.model = ModelComponent(mesh: mesh, materials: [rayOverlayMaterial])
            }
        } else {
            rayOverlay.model = nil
        }
    }

    private func setLabel(_ string: String) {
        let mesh: MeshResource
        if let cached = labelMeshCache[string] {
            mesh = cached
        } else {
            if labelMeshCache.count > 200 { labelMeshCache.removeAll() }
            mesh = MeshResource.generateText(
                string, extrusionDepth: 0.002,
                font: .systemFont(ofSize: 0.03, weight: .semibold))
            labelMeshCache[string] = mesh
        }
        spacingLabel.model = ModelComponent(mesh: mesh, materials: [labelMaterial])
        let bounds = mesh.bounds
        spacingLabel.position = [-(bounds.min.x + bounds.max.x) / 2, 0, 0]
    }

    // MARK: Per-frame tick

    func tick(_ model: OpticsModel) {
        for (index, entity) in emitterEntities.enumerated() {
            guard index < model.emitters.count, !model.slitRigOn else {
                entity.isEnabled = false
                continue
            }
            let emitter = model.emitters[index]
            entity.isEnabled = true
            if emitterKeys[index] != emitter.id.uuidString {
                emitterKeys[index] = emitter.id.uuidString
                entity.name = emitter.id.uuidString
            }
            if emitter.id != manipulatingEmitterID {
                entity.position = SIMD3<Float>(emitter.position)
            }
        }
        syncShells(model)
        syncLattice(model)
        syncRig(model)
    }
}
