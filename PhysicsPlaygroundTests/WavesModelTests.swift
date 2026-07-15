//
//  WavesModelTests.swift
//  PhysicsPlaygroundTests
//
//  Tests for the ripple-tank app state: the opening scene, probe math on
//  known geometry, the inversion flip, silent-line counting, source
//  clamping, time control, and reset. Wave superposition itself is
//  covered in PhysicsCore's WaveFieldTests.
//

import XCTest
import PhysicsCore
import simd
@testable import PhysicsPlayground

@MainActor
final class WavesModelTests: XCTestCase {

    func testOpeningSceneIsTwoInPhaseSources() {
        let model = WavesModel()
        XCTAssertEqual(model.sources.count, 2)
        XCTAssertFalse(model.sources[0].wave.phaseInverted)
        XCTAssertFalse(model.sources[1].wave.phaseInverted)
        XCTAssertEqual(try! XCTUnwrap(model.sourceSeparation), 0.36, accuracy: 1e-9)
        XCTAssertEqual(model.wavelength, 0.5 / 1.5, accuracy: 1e-12)
    }

    /// The default probe sits on the midline: constructive, Δr = 0.
    func testDefaultProbeReadsMidlineConstructive() {
        let model = WavesModel()
        let readout = model.probeReadout
        XCTAssertEqual(readout.pathDifference ?? -1, 0, accuracy: 1e-9)
        XCTAssertEqual(readout.interference, .constructive)
        // Amplitude on the midline = 2 × single-source contribution.
        let r = simd_distance(model.probePosition, model.sources[0].wave.position)
        let single = WaveField.steadyAmplitude(
            at: model.probePosition, sources: [model.sources[0].wave],
            frequency: model.frequency, speed: model.waveSpeed)
        _ = r
        XCTAssertEqual(readout.amplitude, 2 * single, accuracy: single * 1e-9)
    }

    /// Inverting the selected source turns the midline silent.
    func testInvertingSelectedSourceSilencesMidline() {
        let model = WavesModel()
        model.selectedInverted = true
        XCTAssertTrue(model.sources.contains { $0.wave.phaseInverted })
        let readout = model.probeReadout
        XCTAssertEqual(readout.interference, .destructive)
        XCTAssertEqual(readout.amplitude, 0, accuracy: 1e-12)
    }

    /// Silent-line counts: λ = 0.2 m via f = 2.5 Hz, c = 0.5 m/s, d = 0.3 m.
    /// In phase: only Δr = λ/2 = 0.1 fits (0.3 > 0.1, 0.3 ≯ 0.3) → 2 lines.
    /// Inverted: midline + Δr = λ = 0.2 on both sides → 3 lines.
    func testSilentLineCounting() {
        let model = WavesModel()
        model.frequency = 2.5
        model.waveSpeed = 0.5
        model.moveSource(id: model.sources[0].id, to: SIMD2(-0.15, 0))
        model.moveSource(id: model.sources[1].id, to: SIMD2(0.15, 0))
        XCTAssertEqual(model.wavelength, 0.2, accuracy: 1e-12)

        XCTAssertEqual(model.silentLineCount, 2)

        model.select(id: model.sources[1].id)
        model.selectedInverted = true
        XCTAssertEqual(model.silentLineCount, 3)
    }

    func testSourcesClampToPool() {
        let model = WavesModel()
        model.moveSource(id: model.sources[0].id, to: SIMD2(5, -5))
        let position = model.sources[0].wave.position
        let limit = WavesModel.poolHalfExtent - 0.05
        XCTAssertEqual(position.x, limit, accuracy: 1e-9)
        XCTAssertEqual(position.y, -limit, accuracy: 1e-9)

        model.moveProbe(to: SIMD2(-9, 9))
        XCTAssertEqual(model.probePosition.x, -limit, accuracy: 1e-9)
    }

    func testTimeRespectsPauseAndScale() {
        let model = WavesModel()
        model.step(dt: 1.0 / 90.0)
        XCTAssertEqual(model.time, 1.0 / 90.0, accuracy: 1e-12)

        model.timeScale = 0.5
        model.step(dt: 1.0 / 90.0)
        XCTAssertEqual(model.time, 1.5 / 90.0, accuracy: 1e-12)

        model.isPaused = true
        model.step(dt: 1)
        XCTAssertEqual(model.time, 1.5 / 90.0, accuracy: 1e-12)
    }

    func testSourceBudgetAndMinimum() {
        let model = WavesModel()
        for _ in 0..<10 {
            model.addSource()
        }
        XCTAssertEqual(model.sources.count, WavesModel.sourceBudget)

        // Path-difference readouts only exist for exactly two sources.
        XCTAssertNil(model.probeReadout.pathDifference)
        XCTAssertNil(model.silentLineCount)

        while model.sources.count > 1 {
            model.removeSelectedSource()
        }
        model.removeSelectedSource()
        XCTAssertEqual(model.sources.count, 1, "the last source can't be removed")
    }

    func testResetRestoresOpeningScene() {
        let model = WavesModel()
        model.addSource()
        model.frequency = 2.8
        model.waveSpeed = 0.9
        model.showEnvelope = true
        model.isPaused = true
        model.timeScale = 0.2
        model.step(dt: 1)

        model.reset()

        XCTAssertEqual(model.sources.count, 2)
        XCTAssertEqual(model.frequency, 1.5)
        XCTAssertEqual(model.waveSpeed, 0.5)
        XCTAssertFalse(model.showEnvelope)
        XCTAssertFalse(model.isPaused)
        XCTAssertEqual(model.timeScale, 1.0)
        XCTAssertEqual(model.time, 0)
    }
}
