//
//  WaveMediumModel.swift
//  Physics Playground — Elastic Field (Springs module)
//
//  The elastic membrane you reach into: a floating sheet of coupled
//  springs (PhysicsCore ElasticSheet — the exact 2-D wave equation).
//  Grab any point and the medium follows your hand; let go and the
//  disturbance ripples out, reflects off the rim, and — on a clamped
//  frame — settles into standing modes. This is the mechanical field:
//  many degrees of freedom, one live global response, walkable from
//  every side.
//
//  The sheet lives in a horizontal plane at `restHeight`; local grid
//  coordinates map to the room so the renderer and the gestures agree.
//

import Foundation
import Observation
import PhysicsCore
import simd

@MainActor
@Observable
final class WaveMediumModel {
    // MARK: Placement in the room

    /// Center of the sheet's rest plane.
    nonisolated static let center = SIMD3<Double>(0, 1.15, -0.85)
    nonisolated static let gridCount = 24
    nonisolated static let spacing = 0.058
    /// Half the sheet's side, for clamping and framing.
    nonisolated static var halfSide: Double { Double(gridCount - 1) * spacing / 2 }

    nonisolated static let waveSpeedRange = 0.4...2.4
    nonisolated static let dampingRange = 0.0...2.5
    nonisolated static let pluckClamp = 0.28
    /// The free field can't rise past this — a governor so driving a
    /// point can't make the sheet run away and glitch (just above the
    /// pull clamp, so a single deliberate pull isn't touched).
    nonisolated static let amplitudeCeiling = 0.3

    private(set) var sheet: ElasticSheet
    var isPaused = false

    /// Wave speed, exposed to the pod; writing it retunes the medium.
    var waveSpeed: Double {
        didSet { sheet.waveSpeed = waveSpeed; if waveSpeed != oldValue { retuneInsight() } }
    }
    var damping: Double {
        didSet { sheet.damping = damping }
    }
    var boundaryFixed: Bool {
        didSet {
            guard boundaryFixed != oldValue else { return }
            sheet.boundary = boundaryFixed ? .fixed : .free
            insightText = boundaryFixed
                ? "Clamped rim — a drumhead. Waves reflect inverted off the fixed edge and lock into standing modes."
                : "Free rim — the edges are loose. Waves reflect upright, and the whole sheet can heave."
        }
    }

    private(set) var insightText = ""
    /// The hand-held node, if any (grid indices), so the renderer can
    /// halo it.
    private(set) var heldNode: (i: Int, j: Int)?
    private var heldStartHeight = 0.0
    private var heldStartHandY = 0.0

    init() {
        var sheet = ElasticSheet(
            n: Self.gridCount, spacing: Self.spacing,
            waveSpeed: 1.2, damping: 0.1, boundary: .fixed)
        sheet.amplitudeLimit = Self.amplitudeCeiling
        self.sheet = sheet
        self.waveSpeed = sheet.waveSpeed
        self.damping = sheet.damping
        self.boundaryFixed = true
        // Open ALIVE — a gently ringing mode so the sheet is never a
        // dead slab (EM opens with its field already flowing).
        self.sheet.setStandingMode(m: 2, p: 1, amplitude: 0.11)
        insightText = "Reach into the sheet and pull a point up, then let go — a wave spreads at speed c, bounces off the rim, and rings the drumhead's modes. Walk around and underneath it."
    }

    // MARK: Clock

    func step(dt: Double) {
        guard !isPaused else { return }
        sheet.step(dt: min(dt, 1.0 / 60.0))
    }

    // MARK: Local ⇄ world

    /// A grid node's world position at its current height.
    func world(i: Int, j: Int) -> SIMD3<Double> {
        let x = Double(i) * Self.spacing - Self.halfSide
        let z = Double(j) * Self.spacing - Self.halfSide
        return Self.center + SIMD3(x, sheet.height[sheet.index(i, j)], z)
    }

    /// The rest-plane world position (height ignored) — used to frame
    /// the grab collider.
    nonisolated static func restWorld(i: Int, j: Int) -> SIMD3<Double> {
        let x = Double(i) * spacing - halfSide
        let z = Double(j) * spacing - halfSide
        return center + SIMD3(x, 0, z)
    }

    /// The node nearest a world point (by its x/z footprint).
    func nearestNode(toWorld p: SIMD3<Double>) -> (i: Int, j: Int) {
        sheet.nearestNode(localX: p.x - Self.center.x + Self.halfSide,
                           localY: p.z - Self.center.z + Self.halfSide)
    }

    // MARK: Manipulation — the whole point

    /// Grabs the node nearest a world point and pins it AT its current
    /// height — no jump. From here the node tracks the hand's vertical
    /// displacement (the app-wide relative-drag feel).
    func grab(atWorld p: SIMD3<Double>) {
        let node = nearestNode(toWorld: p)
        // The clamped rim can't be grabbed on a drumhead.
        if boundaryFixed, sheet.isEdge(node.i, node.j) { return }
        heldNode = node
        heldStartHeight = sheet.height[sheet.index(node.i, node.j)]
        heldStartHandY = p.y
        sheet.pin(node.i, node.j, to: heldStartHeight)
    }

    /// Moves the held node by the hand's vertical displacement.
    func moveHeld(toWorld p: SIMD3<Double>) {
        guard let node = heldNode else { return }
        let h = min(max(heldStartHeight + (p.y - heldStartHandY),
                        -Self.pluckClamp), Self.pluckClamp)
        sheet.pin(node.i, node.j, to: h)
    }

    /// Releases the held node — the pinned height snaps free and the
    /// stored tension launches the wave.
    func release() {
        guard let node = heldNode else { return }
        sheet.unpin(node.i, node.j)
        heldNode = nil
    }

    // MARK: Presets — instant wonder

    func flatten() {
        sheet.flatten()
        insightText = "Flat and still. Pluck it, or ring a mode."
    }

    func ringMode(m: Int, p: Int) {
        sheet.unpinAll()
        heldNode = nil
        sheet.setStandingMode(m: m, p: p, amplitude: 0.13)
        insightText = "A pure (\(m), \(p)) standing mode — every point oscillates in step, the nodal lines never move. Real drumheads ring these same shapes."
    }

    func centerPluck() {
        sheet.unpinAll()
        heldNode = nil
        let c = Self.gridCount / 2
        sheet.pluck(i: c, j: c, amplitude: 0.2, radius: 0.1)
        insightText = "Struck at the center — circular waves race out at speed c and reflect off the rim. Change the wave speed and watch them slow or quicken."
    }

    private func retuneInsight() {
        insightText = "Wave speed c = \(String(format: "%.1f", waveSpeed)) m/s. Stiffer medium, faster waves — the ripples visibly race. Modes climb in frequency with c."
    }

    // MARK: Reset

    func reset() {
        sheet = ElasticSheet(
            n: Self.gridCount, spacing: Self.spacing,
            waveSpeed: 1.2, damping: 0.1, boundary: .fixed)
        sheet.amplitudeLimit = Self.amplitudeCeiling
        waveSpeed = 1.2
        damping = 0.1
        boundaryFixed = true
        heldNode = nil
        isPaused = false
        centerPluck()
    }
}
