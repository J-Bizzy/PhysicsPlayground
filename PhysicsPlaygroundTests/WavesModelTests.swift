//
//  WavesModelTests.swift
//  PhysicsPlaygroundTests
//
//  Tests for the 3D interference-field app state: the opening scene,
//  probe math on known geometry, the inversion flip, silence-surface
//  counting, region clamping, time control, and reset. Wave
//  superposition itself is covered in PhysicsCore's WaveFieldTests.
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
        XCTAssertEqual(try! XCTUnwrap(model.sourceSeparation), 0.8, accuracy: 1e-9)
        XCTAssertEqual(model.wavelength, 0.5 / 1.5, accuracy: 1e-12)
    }

    /// The default probe sits on the midplane: constructive, Δr = 0, and
    /// exactly twice a single source's contribution.
    func testDefaultProbeReadsMidplaneConstructive() {
        let model = WavesModel()
        let readout = model.probeReadout
        XCTAssertEqual(readout.pathDifference ?? -1, 0, accuracy: 1e-9)
        XCTAssertEqual(readout.interference, .constructive)
        let single = WaveField.steadyAmplitude(
            at: model.probePosition, sources: [model.sources[0].wave],
            frequency: model.frequency, speed: model.waveSpeed)
        XCTAssertEqual(readout.amplitude, 2 * single, accuracy: single * 1e-9)
    }

    /// Inverting the selected source turns the midplane silent.
    func testInvertingSelectedSourceSilencesMidplane() {
        let model = WavesModel()
        model.selectedInverted = true
        XCTAssertTrue(model.sources.contains { $0.wave.phaseInverted })
        let readout = model.probeReadout
        XCTAssertEqual(readout.interference, .destructive)
        XCTAssertEqual(readout.amplitude, 0, accuracy: 1e-12)
    }

    /// Silence-surface counts: λ = 0.2 m via f = 2.5 Hz, c = 0.5 m/s,
    /// d = 0.3 m. In phase: only Δr = λ/2 = 0.1 fits → 2 surfaces.
    /// Inverted: midplane + Δr = λ = 0.2 on both sides → 3.
    func testSilenceSurfaceCounting() {
        let model = WavesModel()
        model.frequency = 2.5
        model.waveSpeed = 0.5
        let center = WavesModel.regionCenter
        model.moveSource(id: model.sources[0].id, to: center + SIMD3(-0.15, 0, 0))
        model.moveSource(id: model.sources[1].id, to: center + SIMD3(0.15, 0, 0))
        XCTAssertEqual(model.wavelength, 0.2, accuracy: 1e-12)

        XCTAssertEqual(model.silentSurfaceCount, 2)

        model.select(id: model.sources[1].id)
        model.selectedInverted = true
        XCTAssertEqual(model.silentSurfaceCount, 3)
    }

    /// Sources and the probe stay inside the region cube — and above the
    /// floor margin.
    func testSourcesClampToRegion() {
        let model = WavesModel()
        model.moveSource(id: model.sources[0].id, to: SIMD3(5, -5, 5))
        let position = model.sources[0].wave.position
        let center = WavesModel.regionCenter
        let half = WavesModel.regionHalfExtent
        XCTAssertEqual(position.x, center.x + half, accuracy: 1e-9)
        XCTAssertEqual(position.y, max(center.y - half, WavesModel.regionFloor), accuracy: 1e-9)
        XCTAssertEqual(position.z, center.z + half, accuracy: 1e-9)

        model.moveProbe(to: SIMD3(0, -9, 0))
        XCTAssertGreaterThanOrEqual(model.probePosition.y, WavesModel.regionFloor - 1e-9)
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
        XCTAssertNil(model.silentSurfaceCount)

        while model.sources.count > 1 {
            model.removeSelectedSource()
        }
        model.removeSelectedSource()
        XCTAssertEqual(model.sources.count, 1, "the last source can't be removed")
    }

    /// A source held still carries no Doppler velocity; swept across the
    /// field it gains one (pointing the way it was dragged), and once it
    /// stops the field relaxes exactly back to rest.
    func testDraggingASourceProducesThenReleasesDopplerVelocity() {
        let model = WavesModel()
        let id = model.sources[0].id
        let center = WavesModel.regionCenter
        var x = -0.2
        for _ in 0..<10 {
            x += 0.03
            model.moveSource(id: id, to: center + SIMD3(x, 0, 0))
            model.step(dt: 1.0 / 90.0)
        }
        let moving = model.sources[0].wave.velocity
        XCTAssertGreaterThan(simd_length(moving), 0.05, "a swept source moves through the medium")
        XCTAssertGreaterThan(moving.x, 0, "the way it was dragged")

        for _ in 0..<80 { model.step(dt: 1.0 / 90.0) }
        XCTAssertEqual(simd_length(model.sources[0].wave.velocity), 0, accuracy: 1e-9,
                       "a source at rest relaxes the field back to the static pattern")
    }

    /// The Doppler flyby cruises the selected source across the field —
    /// giving it a real velocity — and never leaves the region (it
    /// bounces off the walls); switching it off parks it.
    func testDopplerFlybyMovesBouncesAndStops() {
        let model = WavesModel()
        model.select(id: model.sources[1].id)
        model.selectedIsFlying = true
        let start = model.selectedSource!.wave.position
        let center = WavesModel.regionCenter
        let half = WavesModel.regionHalfExtent

        var travelled = 0.0
        for _ in 0..<600 {
            model.step(dt: 1.0 / 90.0)
            let p = model.selectedSource!.wave.position
            travelled = max(travelled, abs(p.x - start.x))
            XCTAssertLessThanOrEqual(p.x, center.x + half + 1e-9)
            XCTAssertGreaterThanOrEqual(p.x, center.x - half - 1e-9)
        }
        XCTAssertGreaterThan(travelled, 0.1, "the flyby actually travels")
        XCTAssertGreaterThan(simd_length(model.selectedSource!.wave.velocity), 0.05,
                             "carrying a Doppler velocity")

        model.selectedIsFlying = false
        for _ in 0..<80 { model.step(dt: 1.0 / 90.0) }
        XCTAssertEqual(simd_length(model.selectedSource!.wave.velocity), 0, accuracy: 1e-9)
    }

    func testResetRestoresOpeningScene() {
        let model = WavesModel()
        model.addSource()
        model.frequency = 2.8
        model.waveSpeed = 0.9
        model.showSilenceSurfaces = false
        model.isPaused = true
        model.timeScale = 0.2
        model.step(dt: 1)

        model.reset()

        XCTAssertEqual(model.sources.count, 2)
        XCTAssertEqual(model.frequency, 1.5)
        XCTAssertEqual(model.waveSpeed, 0.5)
        XCTAssertTrue(model.showSilenceSurfaces)
        XCTAssertFalse(model.isPaused)
        XCTAssertEqual(model.timeScale, 1.0)
        XCTAssertEqual(model.time, 0)
    }
}
