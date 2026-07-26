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
    /// so you look straight at the pattern. It hangs back like a wall
    /// exhibit: behind the main window's default spot (≈ −1.3 m) so the
    /// controls never vanish behind it, and far from the nav orbs below.
    nonisolated static let center = SIMD3<Double>(0, 1.5, -1.7)
    nonisolated static let gridCount = 24
    nonisolated static let spacing = 0.044
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

    /// A center-excitable resonance: both mode numbers odd, so the mode
    /// has an antinode under the shaker and can actually be rung.
    struct Mode: Identifiable, Hashable, Sendable {
        let m: Int
        let p: Int
        /// Unique across the list — (1,3) and (3,3) share no id, which a
        /// bare `m` key would collide on in a ForEach.
        var id: Int { m * 100 + p }
        var label: String { "\(m),\(p)" }
    }

    /// The drivable resonances, in rising frequency.
    nonisolated static let drivableModes: [Mode] = [
        Mode(m: 1, p: 1), Mode(m: 1, p: 3), Mode(m: 3, p: 3),
        Mode(m: 3, p: 5), Mode(m: 5, p: 5),
    ]

    private(set) var sheet: ElasticSheet
    var isPaused = false

    // MARK: Medium parameters (pods)

    var waveSpeed: Double {
        didSet {
            sheet.waveSpeed = waveSpeed
            if waveSpeed != oldValue {
                rebuildModeCache()
                retuneInsight()
            }
        }
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

    /// The smoothed ring measure the RENDERER reads every frame (raw RMS
    /// m). Observation-ignored so the 60 Hz smoothing never invalidates
    /// SwiftUI — the pods watch the quantized `resonance` instead.
    @ObservationIgnored private(set) var responseRMS = 0.0
    /// How hard the sheet is ringing, 0…1, for the meter and readouts.
    /// Published only in 1 % steps, so the Shaker pod re-renders when the
    /// needle visibly moves — not sixty times a second.
    private(set) var resonance = 0.0

    /// The un-quantized ring measure for audio and bloom (no observation).
    var resonanceLive: Double { min(responseRMS / (Self.amplitudeCeiling * 0.42), 1) }

    /// The drivable modes' natural frequencies on the current medium,
    /// cached so views never have to touch the per-frame-mutating sheet.
    @ObservationIgnored private var cachedModeFrequencies: [(m: Int, p: Int, f: Double)] = []

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
        // Publish to the pods only when the meter visibly moves (1 %).
        let live = resonanceLive
        if abs(live - resonance) >= 0.01 || (live == 0 && resonance != 0) {
            resonance = live
        }
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

    /// Recomputes the drivable modes' natural frequencies. Called when
    /// the medium retunes — views read the cache, never the live sheet
    /// (which mutates every frame and would drag them into 60 Hz churn).
    private func rebuildModeCache() {
        cachedModeFrequencies = Self.drivableModes.map {
            ($0.m, $0.p, sheet.modeFrequency(m: $0.m, p: $0.p))
        }
    }

    /// The center-excitable mode whose frequency is nearest the current
    /// drive, and how far the drive is detuned from it (Hz).
    func nearestResonance() -> (mode: Mode, frequency: Double, detune: Double) {
        if cachedModeFrequencies.isEmpty { rebuildModeCache() }
        var best = cachedModeFrequencies[0]
        for entry in cachedModeFrequencies
        where abs(entry.f - driveFrequency) < abs(best.f - driveFrequency) {
            best = entry
        }
        return (Mode(m: best.m, p: best.p), best.f, driveFrequency - best.f)
    }

    /// The natural frequency of a drivable mode on the current medium.
    func frequency(of mode: Mode) -> Double {
        if cachedModeFrequencies.isEmpty { rebuildModeCache() }
        return cachedModeFrequencies.first { $0.m == mode.m && $0.p == mode.p }?.f
            ?? sheet.modeFrequency(m: mode.m, p: mode.p)
    }

    /// Snaps the drive exactly onto a mode's resonance.
    func seekMode(_ mode: Mode) {
        driveOn = true
        driveFrequency = frequency(of: mode)
        insightText = "Driven right on the (\(mode.m), \(mode.p)) resonance. The mode blooms; grains settle onto its nodal lines, where the sheet barely moves."
    }

    // MARK: Presets

    func flatten() {
        sheet.flatten()
        responseRMS = 0
        resonance = 0
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

    /// Opens RINGING, on (3,3), already at amplitude.
    ///
    /// It used to open on the fundamental (1,1) at a small amplitude
    /// with the drive still climbing, and (1,1) is exactly the mode that
    /// shows LEAST from the front: one central antinode, all of whose
    /// displacement points at the viewer, so a head-on look at the sheet
    /// saw a flat coloured square. (3,3) has interior nodal lines running
    /// both ways — structure that reads as structure from any angle, and
    /// the pattern the marker grains draw most legibly. Damping starts
    /// lower so the peak is sharp and the mode is unmistakably ringing.
    func reset() {
        var fresh = ElasticSheet(
            n: Self.gridCount, spacing: Self.spacing,
            waveSpeed: 1.2, damping: 0.09, boundary: .fixed)
        fresh.amplitudeLimit = Self.amplitudeCeiling
        fresh.driveAmplitude = Self.driveForce
        sheet = fresh
        waveSpeed = 1.2
        damping = 0.09
        boundaryFixed = true
        heldNode = nil
        responseRMS = 0
        resonance = 0
        isPaused = false
        driveOn = true
        let opening = Mode(m: 3, p: 3)
        driveFrequency = sheet.modeFrequency(m: opening.m, p: opening.p)
        sheet.driveNodes = [sheet.index(Self.driveCoord.i, Self.driveCoord.j)]
        // Seeded near the ceiling so the sheet is visibly in relief from
        // the first frame rather than ringing up over several seconds.
        sheet.setStandingMode(m: opening.m, p: opening.p, amplitude: 0.17)
        insightText = "Driven right on the (3, 3) resonance — the sheet is standing in nine cells, and the grains have gathered on the still lines between them. Sweep the drive off the peak and watch it die away."
    }
}
