//
//  ElasticSheetTests.swift
//  PhysicsCoreTests
//
//  Textbook membrane checks: standing modes, energy, symmetry, wave speed, edges.
//

import XCTest
@testable import PhysicsCore

final class ElasticSheetTests: XCTestCase {

    /// A struck mode stays proportional to its own shape (the definition of a
    /// normal mode) and oscillates through zero.
    func testStruckModeStaysAPureStandingWave() {
        var sheet = ElasticSheet(n: 21, spacing: 0.05, waveSpeed: 1.0,
                                 damping: 0, boundary: .fixed)
        sheet.setStandingMode(m: 1, p: 1, amplitude: 0.05)
        let shape = sheet.height   // the eigenvector

        let center = sheet.index(10, 10)
        var sawZeroCrossing = false
        var lastCenter = sheet.height[center]

        for _ in 0..<400 {
            sheet.step(dt: 1.0 / 240.0)
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

    /// The ceiling holds every frame even under a relentless driver.
    func testAmplitudeGovernorCapsADrivenSheet() {
        var sheet = ElasticSheet(n: 21, spacing: 0.05, waveSpeed: 1.2,
                                 damping: 0, boundary: .fixed)
        sheet.amplitudeLimit = 0.2
        for _ in 0..<600 {
            sheet.pluck(i: 10, j: 10, amplitude: 0.1, radius: 0.08)
            sheet.step(dt: 1.0 / 120.0)
            let peak = sheet.height.map { abs($0) }.max()!
            XCTAssertLessThanOrEqual(peak, 0.2 + 1e-9, "the ceiling holds every frame")
        }
    }

    /// Below the ceiling the governor is a no-op — no silent clipping.
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

    /// The integrator injects no energy even at the lattice's fastest modes
    /// (the CFL guard holds).
    func testBroadbandPluckStaysBounded() {
        var sheet = ElasticSheet(n: 19, spacing: 0.05, waveSpeed: 1.2,
                                 damping: 0, boundary: .fixed)
        sheet.pluck(i: 9, j: 9, amplitude: 0.05, radius: 0.06)
        let peak = sheet.height.map { abs($0) }.max()!
        for _ in 0..<1200 { sheet.step(dt: 1.0 / 120.0) }
        let laterPeak = sheet.height.map { abs($0) }.max()!
        XCTAssertLessThan(laterPeak, peak * 1.2, "no runaway growth")
    }

    func testDampingRemovesEnergy() {
        var sheet = ElasticSheet(n: 19, spacing: 0.05, waveSpeed: 1.2,
                                 damping: 1.5, boundary: .fixed)
        sheet.pluck(i: 9, j: 9, amplitude: 0.04, radius: 0.12)
        let initial = sheet.energy
        for _ in 0..<600 { sheet.step(dt: 1.0 / 120.0) }
        XCTAssertLessThan(sheet.energy, initial * 0.5, "ripples fade")
    }

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

    func testWavefrontTravelsAtWaveSpeed() {
        let c = 1.0, a = 0.05, n = 41
        var sheet = ElasticSheet(n: n, spacing: a, waveSpeed: c,
                                 damping: 0, boundary: .free)
        sheet.pluck(i: 5, j: 20, amplitude: 0.05, radius: 0.06)
        let farI = 34
        let distance = Double(farI - 5) * a
        let earliest = distance / c
        // Just before the front could arrive, the far node is still undisturbed.
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

    func testPinnedNodeHoldsWhileNeighboursMove() {
        var sheet = ElasticSheet(n: 21, spacing: 0.05, waveSpeed: 1.0,
                                 damping: 0, boundary: .fixed)
        sheet.pin(10, 10, to: 0.06)
        for _ in 0..<120 { sheet.step(dt: 1.0 / 120.0) }
        XCTAssertEqual(sheet.height[sheet.index(10, 10)], 0.06, accuracy: 1e-12)
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

    /// Mode frequencies climb with mode number and wave speed: ω = c·√λ for
    /// the discrete Laplacian.
    func testModeFrequenciesOrderAndScale() {
        let sheet = ElasticSheet(n: 21, spacing: 0.05, waveSpeed: 1.0,
                                 damping: 0, boundary: .fixed)
        let f11 = sheet.modeFrequency(m: 1, p: 1)
        let f21 = sheet.modeFrequency(m: 2, p: 1)
        let f22 = sheet.modeFrequency(m: 2, p: 2)
        XCTAssertGreaterThan(f11, 0)
        XCTAssertGreaterThan(f21, f11, "higher modes ring higher")
        XCTAssertGreaterThan(f22, f21)

        let fast = ElasticSheet(n: 21, spacing: 0.05, waveSpeed: 2.0,
                                damping: 0, boundary: .fixed)
        XCTAssertEqual(fast.modeFrequency(m: 1, p: 1), 2 * f11, accuracy: f11 * 1e-9)
    }

    /// Driven at (1,1)'s frequency the sheet rings up; well between modes it
    /// stays comparatively dead. That contrast IS resonance.
    func testDrivingAtAModeResonates() {
        func steadyRMS(driveHz: Double) -> Double {
            var sheet = ElasticSheet(n: 21, spacing: 0.05, waveSpeed: 1.0,
                                     damping: 0.4, boundary: .fixed)
            sheet.driveNodes = [sheet.index(10, 10)]
            sheet.driveAmplitude = 4.0
            sheet.driveFrequency = driveHz
            // Establish the steady state, then average RMS through the drive cycle.
            for _ in 0..<2400 { sheet.step(dt: 1.0 / 240.0) }
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

    /// Drive fields are inert until a node is actually driven.
    func testUndrivenSheetStaysFlat() {
        var sheet = ElasticSheet(n: 21, spacing: 0.05, waveSpeed: 1.2,
                                 damping: 0.1, boundary: .fixed)
        sheet.driveAmplitude = 5.0     // amplitude set, but no driveNodes
        sheet.driveFrequency = 1.0
        for _ in 0..<600 { sheet.step(dt: 1.0 / 120.0) }
        XCTAssertEqual(sheet.rms, 0, accuracy: 1e-12)
    }
}
