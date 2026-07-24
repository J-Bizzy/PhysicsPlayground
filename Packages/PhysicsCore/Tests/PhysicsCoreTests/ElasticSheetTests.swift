//
//  ElasticSheetTests.swift
//  PhysicsCoreTests
//
//  The membrane pinned to the textbook: a struck (m,p) mode stays a
//  PURE standing wave (an exact eigenvector of the discrete Laplacian)
//  and oscillates; a lossless clamped drumhead conserves energy; a
//  symmetric pluck stays symmetric; a pulse crosses the sheet at the
//  wave speed; and free vs fixed edges reflect differently.
//

import XCTest
@testable import PhysicsCore

final class ElasticSheetTests: XCTestCase {

    /// A (1,1) mode stays proportional to its own shape at every
    /// instant — the definition of a normal mode — and the amplitude
    /// oscillates through zero.
    func testStruckModeStaysAPureStandingWave() {
        var sheet = ElasticSheet(n: 21, spacing: 0.05, waveSpeed: 1.0,
                                 damping: 0, boundary: .fixed)
        sheet.setStandingMode(m: 1, p: 1, amplitude: 0.05)
        let shape = sheet.height   // the eigenvector

        // The reference antinode (center) ratio defines the amplitude.
        let center = sheet.index(10, 10)
        var sawZeroCrossing = false
        var lastCenter = sheet.height[center]

        for _ in 0..<400 {
            sheet.step(dt: 1.0 / 240.0)
            // Every node tracks the SAME scalar multiple of the shape.
            let ratio = sheet.height[center] / shape[center]
            for k in 0..<shape.count where abs(shape[k]) > 1e-3 {
                XCTAssertEqual(sheet.height[k] / shape[k], ratio, accuracy: 2e-3,
                               "node \(k) left the mode")
            }
            if sheet.height[center] * lastCenter < 0 { sawZeroCrossing = true }
            lastCenter = sheet.height[center]
        }
        XCTAssertTrue(sawZeroCrossing, "the mode should oscillate through flat")
    }

    /// Lossless, clamped: a pure standing mode holds its energy as it
    /// trades kinetic for potential and back over many oscillations.
    func testEnergyConservedWithoutDamping() {
        var sheet = ElasticSheet(n: 21, spacing: 0.05, waveSpeed: 1.0,
                                 damping: 0, boundary: .fixed)
        sheet.setStandingMode(m: 2, p: 1, amplitude: 0.04)
        let initial = sheet.energy
        XCTAssertGreaterThan(initial, 0)
        var low = initial, high = initial
        for _ in 0..<1200 {
            sheet.step(dt: 1.0 / 240.0)
            low = min(low, sheet.energy)
            high = max(high, sheet.energy)
        }
        XCTAssertEqual(high, initial, accuracy: initial * 0.02,
                       "a lossless drumhead never gains energy")
        XCTAssertEqual(low, initial, accuracy: initial * 0.02,
                       "and never loses it")
    }

    /// The amplitude governor caps a DRIVEN sheet: pump energy in by
    /// re-plucking every step and the free field still never passes the
    /// ceiling — no runaway, no glitch.
    func testAmplitudeGovernorCapsADrivenSheet() {
        var sheet = ElasticSheet(n: 21, spacing: 0.05, waveSpeed: 1.2,
                                 damping: 0, boundary: .fixed)
        sheet.amplitudeLimit = 0.2
        for _ in 0..<600 {
            // A relentless driver — far more energy than any hand.
            sheet.pluck(i: 10, j: 10, amplitude: 0.1, radius: 0.08)
            sheet.step(dt: 1.0 / 120.0)
            let peak = sheet.height.map { abs($0) }.max()!
            XCTAssertLessThanOrEqual(peak, 0.2 + 1e-9, "the ceiling holds every frame")
        }
    }

    /// Below the ceiling the governor does nothing — a gentle pluck
    /// keeps its full amplitude and its energy (no silent clipping).
    func testGovernorLeavesSmallWavesUntouched() {
        var withLimit = ElasticSheet(n: 21, spacing: 0.05, waveSpeed: 1.0,
                                     damping: 0, boundary: .fixed)
        withLimit.amplitudeLimit = 0.3
        withLimit.pluck(i: 10, j: 10, amplitude: 0.05, radius: 0.1)
        var without = ElasticSheet(n: 21, spacing: 0.05, waveSpeed: 1.0,
                                   damping: 0, boundary: .fixed)
        without.pluck(i: 10, j: 10, amplitude: 0.05, radius: 0.1)
        for _ in 0..<300 {
            withLimit.step(dt: 1.0 / 120.0)
            without.step(dt: 1.0 / 120.0)
        }
        for k in 0..<withLimit.height.count {
            XCTAssertEqual(withLimit.height[k], without.height[k], accuracy: 1e-12)
        }
    }

    /// A sharp broadband pluck stays BOUNDED — the integrator injects
    /// no energy even when the spectrum reaches the lattice's fastest
    /// modes (the CFL guard holds).
    func testBroadbandPluckStaysBounded() {
        var sheet = ElasticSheet(n: 19, spacing: 0.05, waveSpeed: 1.2,
                                 damping: 0, boundary: .fixed)
        sheet.pluck(i: 9, j: 9, amplitude: 0.05, radius: 0.06)
        let peak = sheet.height.map { abs($0) }.max()!
        for _ in 0..<1200 { sheet.step(dt: 1.0 / 120.0) }
        let laterPeak = sheet.height.map { abs($0) }.max()!
        XCTAssertLessThan(laterPeak, peak * 1.2, "no runaway growth")
    }

    /// Damping drains it.
    func testDampingRemovesEnergy() {
        var sheet = ElasticSheet(n: 19, spacing: 0.05, waveSpeed: 1.2,
                                 damping: 1.5, boundary: .fixed)
        sheet.pluck(i: 9, j: 9, amplitude: 0.04, radius: 0.12)
        let initial = sheet.energy
        for _ in 0..<600 { sheet.step(dt: 1.0 / 120.0) }
        XCTAssertLessThan(sheet.energy, initial * 0.5, "ripples fade")
    }

    /// A center pluck keeps the sheet's four-fold symmetry forever.
    func testSymmetricPluckStaysSymmetric() {
        var sheet = ElasticSheet(n: 21, spacing: 0.05, waveSpeed: 1.0,
                                 damping: 0, boundary: .fixed)
        sheet.pluck(i: 10, j: 10, amplitude: 0.05, radius: 0.1)
        for _ in 0..<300 { sheet.step(dt: 1.0 / 120.0) }
        for j in 0..<21 {
            for i in 0..<21 {
                let mirrored = sheet.height[sheet.index(20 - i, 20 - j)]
                XCTAssertEqual(sheet.height[sheet.index(i, j)], mirrored, accuracy: 1e-9)
            }
        }
    }

    /// A pulse struck at one edge reaches the far side no sooner than
    /// the wave speed allows — signal travels at c, not instantly.
    func testWavefrontTravelsAtWaveSpeed() {
        let c = 1.0, a = 0.05, n = 41
        var sheet = ElasticSheet(n: n, spacing: a, waveSpeed: c,
                                 damping: 0, boundary: .free)
        sheet.pluck(i: 5, j: 20, amplitude: 0.05, radius: 0.06)
        // Distance from the pluck to a far column.
        let farI = 34
        let distance = Double(farI - 5) * a
        let earliest = distance / c
        // Step to just BEFORE the front could arrive; the far node must
        // still be essentially undisturbed.
        var t = 0.0
        let dt = 1.0 / 480.0
        while t < earliest * 0.7 {
            sheet.step(dt: dt); t += dt
        }
        XCTAssertLessThan(abs(sheet.height[sheet.index(farI, 20)]), 1e-3,
                          "nothing outruns the wave speed")
        // Well after arrival it has moved.
        while t < earliest * 2.0 {
            sheet.step(dt: dt); t += dt
        }
        XCTAssertGreaterThan(abs(sheet.height[sheet.index(farI, 20)]), 1e-4,
                             "the front arrives on time")
    }

    /// A pinned node holds its height while the medium moves around it.
    func testPinnedNodeHoldsWhileNeighboursMove() {
        var sheet = ElasticSheet(n: 21, spacing: 0.05, waveSpeed: 1.0,
                                 damping: 0, boundary: .fixed)
        sheet.pin(10, 10, to: 0.06)
        for _ in 0..<120 { sheet.step(dt: 1.0 / 120.0) }
        XCTAssertEqual(sheet.height[sheet.index(10, 10)], 0.06, accuracy: 1e-12)
        // A neighbour has been pulled up off the flat rest state.
        XCTAssertGreaterThan(sheet.height[sheet.index(9, 10)], 1e-4)
    }

    /// Fixed edges stay clamped at zero; free edges do not.
    func testBoundaryClamping() {
        var fixed = ElasticSheet(n: 21, spacing: 0.05, waveSpeed: 1.0,
                                 damping: 0, boundary: .fixed)
        fixed.pluck(i: 10, j: 10, amplitude: 0.05, radius: 0.2)
        for _ in 0..<200 { fixed.step(dt: 1.0 / 120.0) }
        XCTAssertEqual(fixed.height[fixed.index(0, 10)], 0, accuracy: 1e-12)

        var free = ElasticSheet(n: 21, spacing: 0.05, waveSpeed: 1.0,
                                damping: 0, boundary: .free)
        free.pluck(i: 10, j: 10, amplitude: 0.05, radius: 0.2)
        for _ in 0..<200 { free.step(dt: 1.0 / 120.0) }
        XCTAssertGreaterThan(abs(free.height[free.index(0, 10)]), 1e-4,
                             "an open edge is free to move")
    }

    // MARK: The shaker & resonance

    /// The lattice mode frequencies climb with the mode numbers and with
    /// the wave speed, and match ω = c·√λ for the discrete Laplacian.
    func testModeFrequenciesOrderAndScale() {
        let sheet = ElasticSheet(n: 21, spacing: 0.05, waveSpeed: 1.0,
                                 damping: 0, boundary: .fixed)
        let f11 = sheet.modeFrequency(m: 1, p: 1)
        let f21 = sheet.modeFrequency(m: 2, p: 1)
        let f22 = sheet.modeFrequency(m: 2, p: 2)
        XCTAssertGreaterThan(f11, 0)
        XCTAssertGreaterThan(f21, f11, "higher modes ring higher")
        XCTAssertGreaterThan(f22, f21)

        // Doubling the wave speed doubles every mode frequency.
        let fast = ElasticSheet(n: 21, spacing: 0.05, waveSpeed: 2.0,
                                damping: 0, boundary: .fixed)
        XCTAssertEqual(fast.modeFrequency(m: 1, p: 1), 2 * f11, accuracy: f11 * 1e-9)
    }

    /// Drive the center node at mode (1,1)'s natural frequency and the
    /// sheet rings up to a large amplitude; drive it at a frequency well
    /// between modes and it stays comparatively dead. That contrast IS
    /// resonance.
    func testDrivingAtAModeResonates() {
        func steadyRMS(driveHz: Double) -> Double {
            var sheet = ElasticSheet(n: 21, spacing: 0.05, waveSpeed: 1.0,
                                     damping: 0.4, boundary: .fixed)
            sheet.driveNodes = [sheet.index(10, 10)]
            sheet.driveAmplitude = 4.0
            sheet.driveFrequency = driveHz
            // Let the driven steady state establish.
            for _ in 0..<2400 { sheet.step(dt: 1.0 / 240.0) }
            // Average RMS over a further stretch (through the drive cycle).
            var acc = 0.0
            for _ in 0..<240 { sheet.step(dt: 1.0 / 240.0); acc += sheet.rms }
            return acc / 240
        }

        let f11 = ElasticSheet(n: 21, spacing: 0.05, waveSpeed: 1.0,
                               damping: 0.4, boundary: .fixed).modeFrequency(m: 1, p: 1)
        let onResonance = steadyRMS(driveHz: f11)
        let offResonance = steadyRMS(driveHz: f11 * 0.45)   // between DC and mode 1
        XCTAssertGreaterThan(onResonance, offResonance * 3,
                             "driving on a mode should ring far louder than off it")
    }

    /// With no shaker attached, a sheet that starts flat stays flat — the
    /// drive fields are inert until a node is actually driven.
    func testUndrivenSheetStaysFlat() {
        var sheet = ElasticSheet(n: 21, spacing: 0.05, waveSpeed: 1.2,
                                 damping: 0.1, boundary: .fixed)
        sheet.driveAmplitude = 5.0     // amplitude set, but no driveNodes
        sheet.driveFrequency = 1.0
        for _ in 0..<600 { sheet.step(dt: 1.0 / 120.0) }
        XCTAssertEqual(sheet.rms, 0, accuracy: 1e-12)
    }
}
