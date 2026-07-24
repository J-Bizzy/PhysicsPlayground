//
//  WaveMediumModel.swift
//  Physics Playground — Elastic Field (Springs module)
//
//  A resonance drumhead you can hear. A vertical membrane of coupled
//  springs (PhysicsCore ElasticSheet — the exact 2-D wave equation)
//  faces you in the room. A shaker pushes its center with a force
//  F = A·sin(2πf·t); as you sweep the drive frequency f, the sheet
//  stays nearly still — until f nears one of the drumhead's natural
//  frequencies, when the matching standing mode blooms to full
//  amplitude (resonance). Scattered marker grains migrate to the
//  quiet nodal lines (Chladni figures), and a synthesized tone sings
//  louder the harder the sheet rings, so you HEAR the resonance peak.
//
//  You can still reach in and pull a point, or jump the drive straight
//  onto a mode. The sheet is vertical (its face toward you) so the
//  nodal patterns and mode shapes read straight on, and so its grab
//  volume sits well clear of the navigation orbs below.
//

import Foundation
import Observation
import PhysicsCore
import simd

@MainActor
@Observable
final class WaveMediumModel {
    // MARK: Placement in the room

    /// Center of the sheet's rest plane. The sheet stands VERTICAL — its
    /// face in the room's x–y plane, displacement toward/away along z —
    /// so you look straight at the pattern and its grab slab is well in
    /// front (more negative z) of the orb controls below.
    nonisolated static let center = SIMD3<Double>(0, 1.35, -1.2)
    nonisolated static let gridCount = 24
    nonisolated static let spacing = 0.036
    /// Half the sheet's side, for clamping and framing.
    nonisolated static var halfSide: Double { Double(gridCount - 1) * spacing / 2 }

    nonisolated static let waveSpeedRange = 0.4...2.4
    nonisolated static let dampingRange = 0.02...1.6
    nonisolated static let driveFrequencyRange = 0.3...4.6
    /// How far a hand can pull a point (m, toward/away).
    nonisolated static let pluckClamp = 0.18
    /// The free field can't ring past this — the governor that keeps a
    /// driven point from pumping the sheet to a glitch.
    nonisolated static let amplitudeCeiling = 0.22
    /// The shaker's force (as an acceleration); strong enough that even
    /// the higher modes ring up to a vivid amplitude at resonance (the
    /// governor caps the low modes so they can't run away).
    nonisolated static let driveForce = 11.0

    /// The center node the shaker pushes.
    nonisolated static var driveCoord: (i: Int, j: Int) { (gridCount / 2, gridCount / 2) }

    /// The center-excitable resonances (both mode numbers odd, so the
    /// mode has an antinode under the shaker), in rising frequency —
    /// the ones you can actually ring and seek.
    nonisolated static let drivableModes: [(m: Int, p: Int)] =
        [(1, 1), (1, 3), (3, 3), (3, 5), (5, 5)]

    private(set) var sheet: ElasticSheet
    var isPaused = false

    // MARK: Medium parameters (pods)

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
        }
    }

    // MARK: The shaker

    /// Whether the shaker is running.
    var driveOn: Bool {
        didSet {
            guard driveOn != oldValue else { return }
            sheet.driveNodes = driveOn ? [sheet.index(Self.driveCoord.i, Self.driveCoord.j)] : []
        }
    }
    /// Drive frequency (Hz) — the star control. Sweep it to hunt modes.
    var driveFrequency: Double {
        didSet { sheet.driveFrequency = driveFrequency }
    }

    /// A smoothed measure of how hard the sheet is ringing (raw RMS m).
    private(set) var responseRMS = 0.0
    /// The same, normalized to 0…1 for meters, sound, and bloom.
    var resonance: Double { min(responseRMS / (Self.amplitudeCeiling * 0.42), 1) }

    private(set) var insightText = ""
    /// The hand-held node, if any (grid indices), so the renderer can
    /// halo it.
    private(set) var heldNode: (i: Int, j: Int)?
    private var heldStartHeight = 0.0
    private var heldStartHandZ = 0.0

    init() {
        var sheet = ElasticSheet(
            n: Self.gridCount, spacing: Self.spacing,
            waveSpeed: 1.2, damping: 0.14, boundary: .fixed)
        sheet.amplitudeLimit = Self.amplitudeCeiling
        sheet.driveAmplitude = Self.driveForce
        self.sheet = sheet
        self.waveSpeed = sheet.waveSpeed
        self.damping = sheet.damping
        self.boundaryFixed = true
        self.driveOn = true
        // Open ALIVE, ringing the fundamental resonance.
        let f11 = sheet.modeFrequency(m: 1, p: 1)
        self.driveFrequency = f11
        self.sheet.driveFrequency = f11
        self.sheet.driveNodes = [sheet.index(Self.driveCoord.i, Self.driveCoord.j)]
        self.sheet.setStandingMode(m: 1, p: 1, amplitude: 0.12)
        insightText = "A shaker drives the sheet's center. Sweep the drive frequency: nothing much happens — until you hit a natural frequency and the drumhead blooms into a standing mode. Watch the grains gather on the still nodal lines, and listen for the peak."
    }

    // MARK: Clock

    func step(dt: Double) {
        guard !isPaused else { return }
        sheet.step(dt: min(dt, 1.0 / 60.0))
        responseRMS += 0.12 * (sheet.rms - responseRMS)
    }

    // MARK: Local ⇄ world  (vertical plate: x,y span the face; z = height)

    /// A grid node's world position at its current displacement.
    func world(i: Int, j: Int) -> SIMD3<Double> {
        let x = Double(i) * Self.spacing - Self.halfSide
        let y = Double(j) * Self.spacing - Self.halfSide
        return Self.center + SIMD3(x, y, sheet.height[sheet.index(i, j)])
    }

    /// The rest-plane world position (displacement ignored).
    nonisolated static func restWorld(i: Int, j: Int) -> SIMD3<Double> {
        let x = Double(i) * spacing - halfSide
        let y = Double(j) * spacing - halfSide
        return center + SIMD3(x, y, 0)
    }

    /// The node nearest a world point (by its x/y footprint on the face).
    func nearestNode(toWorld p: SIMD3<Double>) -> (i: Int, j: Int) {
        sheet.nearestNode(localX: p.x - Self.center.x + Self.halfSide,
                           localY: p.y - Self.center.y + Self.halfSide)
    }

    // MARK: Reach in and pull

    /// Grabs the node nearest a world point and pins it at its current
    /// displacement — no jump — then tracks the hand toward/away (z).
    func grab(atWorld p: SIMD3<Double>) {
        let node = nearestNode(toWorld: p)
        if boundaryFixed, sheet.isEdge(node.i, node.j) { return }
        heldNode = node
        heldStartHeight = sheet.height[sheet.index(node.i, node.j)]
        heldStartHandZ = p.z
        sheet.pin(node.i, node.j, to: heldStartHeight)
    }

    /// Moves the held node by the hand's displacement toward/away (z).
    func moveHeld(toWorld p: SIMD3<Double>) {
        guard let node = heldNode else { return }
        let h = min(max(heldStartHeight + (p.z - heldStartHandZ),
                        -Self.pluckClamp), Self.pluckClamp)
        sheet.pin(node.i, node.j, to: h)
    }

    /// Releases the held node — its stored tension launches a wave.
    func release() {
        guard let node = heldNode else { return }
        sheet.unpin(node.i, node.j)
        heldNode = nil
    }

    // MARK: Resonance hunting

    /// The center-excitable mode whose frequency is nearest the current
    /// drive, and how far the drive is detuned from it (Hz).
    func nearestResonance() -> (mode: (m: Int, p: Int), frequency: Double, detune: Double) {
        var best = Self.drivableModes[0]
        var bestFreq = sheet.modeFrequency(m: best.m, p: best.p)
        var bestDetune = Double.infinity
        for mode in Self.drivableModes {
            let f = sheet.modeFrequency(m: mode.m, p: mode.p)
            let d = abs(f - driveFrequency)
            if d < bestDetune { bestDetune = d; best = mode; bestFreq = f }
        }
        return (best, bestFreq, driveFrequency - bestFreq)
    }

    /// The natural frequency of a mode on the current lattice.
    func frequency(ofMode m: Int, _ p: Int) -> Double {
        sheet.modeFrequency(m: m, p: p)
    }

    /// Snaps the drive exactly onto a mode's resonance.
    func seekMode(m: Int, p: Int) {
        driveOn = true
        driveFrequency = sheet.modeFrequency(m: m, p: p)
        insightText = "Driven right on the (\(m), \(p)) resonance. The mode blooms; grains settle onto its nodal lines, where the sheet barely moves."
    }

    // MARK: Presets

    func flatten() {
        sheet.flatten()
        responseRMS = 0
        insightText = "Silenced. Turn the shaker on and sweep for a resonance, or reach in and pull the sheet."
    }

    func centerPluck() {
        sheet.unpinAll()
        heldNode = nil
        let c = Self.gridCount / 2
        sheet.pluck(i: c, j: c, amplitude: 0.16, radius: 0.08)
        insightText = "Struck once at the center — circular waves race out at speed c and reflect off the clamped rim."
    }

    private func retuneInsight() {
        insightText = "Wave speed c = \(String(format: "%.1f", waveSpeed)) m/s. Stiffer medium, faster waves — every resonance climbs in frequency, so the modes you found shift up the sweep."
    }

    // MARK: Reset

    func reset() {
        var fresh = ElasticSheet(
            n: Self.gridCount, spacing: Self.spacing,
            waveSpeed: 1.2, damping: 0.14, boundary: .fixed)
        fresh.amplitudeLimit = Self.amplitudeCeiling
        fresh.driveAmplitude = Self.driveForce
        sheet = fresh
        waveSpeed = 1.2
        damping = 0.14
        boundaryFixed = true
        heldNode = nil
        responseRMS = 0
        isPaused = false
        driveOn = true
        driveFrequency = sheet.modeFrequency(m: 1, p: 1)
        sheet.driveNodes = [sheet.index(Self.driveCoord.i, Self.driveCoord.j)]
        sheet.setStandingMode(m: 1, p: 1, amplitude: 0.12)
        insightText = "Reset — the shaker rings the fundamental (1, 1) again. Sweep up to find the higher modes."
    }
}
