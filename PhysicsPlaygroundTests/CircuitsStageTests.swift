//
//  CircuitsStageTests.swift
//  PhysicsPlaygroundTests
//
//  The turntable under the floating circuit (2026-10-18, the owner's
//  choice of a designed container): a slim disc that keeps a set clearance
//  under the circuit's lowest point, sits inside the zoom with the bench,
//  fades out as a two-hand zoom dives in, and stands clear of the parts
//  shelf and the meter.
//

import XCTest
import PhysicsCore
import RealityKit
import simd
@testable import PhysicsPlayground

@MainActor
final class CircuitsStageTests: XCTestCase {

    private func lowestPoint(_ model: CircuitsModel) -> Double {
        model.components.flatMap {
            [$0.position.y, $0.terminalPosition(0).y, $0.terminalPosition(1).y]
        }.min() ?? 0
    }

    func testTheStageSitsItsClearanceUnderTheCircuit() {
        let model = CircuitsModel()
        model.reset()
        XCTAssertEqual(model.stage.top, lowestPoint(model) - CircuitsModel.stageClearance,
                       accuracy: 1e-9)
        for preset in CircuitsModel.Preset.allCases {
            model.loadPreset(preset)
            XCTAssertEqual(model.stage.top,
                           max(CircuitsModel.stageFloor,
                               lowestPoint(model) - CircuitsModel.stageClearance),
                           accuracy: 1e-9, "\(preset)")
        }
    }

    func testTheStageFollowsAPartReleasedLowerButNeverBelowItsFloor() throws {
        let model = CircuitsModel()
        model.reset()
        let part = try XCTUnwrap(model.components.first?.id)
        model.drag(id: part, toward: SIMD3(0.5, 0.4, -0.9))
        model.release(id: part)
        XCTAssertEqual(model.stage.top, CircuitsModel.stageFloor, accuracy: 1e-9)
    }

    /// The renderer stands it where the model says, inside the zoom.
    func testTheRendererStandsTheStageWhereTheModelSays() throws {
        let model = CircuitsModel()
        model.reset()
        let renderer = CircuitsRenderer()
        renderer.tick(dt: 1.0 / 90.0, model: model)
        let stage = try XCTUnwrap(renderer.root.findEntity(named: "circuit-stage"))
        let world = stage.position(relativeTo: renderer.root)
        XCTAssertEqual(world.y, Float(model.stage.top), accuracy: 1e-4)
        XCTAssertEqual(world.x, Float(model.stage.center.x), accuracy: 1e-4)
        XCTAssertEqual(world.z, Float(model.stage.center.y), accuracy: 1e-4)
        XCTAssertNotNil(renderer.root.findEntity(named: "circuit-stage-deck"), "no deck asset")
        XCTAssertNotNil(renderer.root.findEntity(named: "circuit-stage-rim"), "no rim asset")
    }

    func testTheStageFadesAsTheZoomDivesIn() {
        XCTAssertEqual(CircuitsRenderer.stageOpacity(atZoom: 1), 1)
        XCTAssertEqual(CircuitsRenderer.stageOpacity(atZoom: 1.25), 1, accuracy: 1e-6)
        XCTAssertEqual(CircuitsRenderer.stageOpacity(atZoom: 2), 0)
        XCTAssertEqual(CircuitsRenderer.stageOpacity(atZoom: 8), 0)
        XCTAssertGreaterThan(CircuitsRenderer.stageOpacity(atZoom: 1.6), 0)
    }

    /// Clear of the parts shelf, under its lowest slot, and in reach.
    func testTheStageClearsTheShelfAndIsWithinReach() {
        let model = CircuitsModel()
        model.reset()
        let radius = CircuitsModel.stageRadius
        let center = model.stage.center
        XCTAssertLessThan(center.x + radius, Double(CircuitsPartsLayout.rightColumnX) - 0.06,
                          "the stage runs into the parts shelf")
        let viewer = SIMD3<Double>(CircuitsPartsLayout.viewer)
        let nearRim = SIMD3(center.x, model.stage.top, center.y + radius)
        XCTAssertLessThan(simd_distance(nearRim, viewer), Double(CircuitsPartsLayout.maximumReach))
        XCTAssertGreaterThanOrEqual(lowestPoint(model) - model.stage.top, 0.25)
    }

    // MARK: Turning and carrying the circuit (B1b)

    private func distances(_ model: CircuitsModel) -> [Double] {
        let points = model.components.flatMap { [$0.terminalPosition(0), $0.terminalPosition(1)] }
        var result: [Double] = []
        for i in points.indices { for j in points.indices where j > i {
            result.append(simd_distance(points[i], points[j]))
        } }
        return result
    }

    /// A turn is rigid about the stage's axis: every distance, every height
    /// and every wire's length the same, the topology untouched, and the
    /// stage's yaw the angle turned.
    func testATurnIsRigidAboutTheStagesAxis() {
        let model = CircuitsModel()
        model.loadPreset(.rcCharger)
        model.step(dt: 1 / 90)
        let before = distances(model)
        let heights = model.components.map(\.position.y)
        let lengths = model.wires.map(model.wireLength)
        #if DEBUG
        let rebuilds = model.netRebuildCount
        #endif
        XCTAssertTrue(model.spinCircuit(by: 1.1))
        for (a, b) in zip(distances(model), before) { XCTAssertEqual(a, b, accuracy: 1e-9) }
        for (a, b) in zip(model.components.map(\.position.y), heights) {
            XCTAssertEqual(a, b, accuracy: 1e-12)
        }
        for (a, b) in zip(model.wires.map(model.wireLength), lengths) { XCTAssertEqual(a, b, accuracy: 1e-9) }
        XCTAssertEqual(model.stage.yaw, 1.1, accuracy: 1e-12)
        model.step(dt: 1 / 90)
        #if DEBUG
        XCTAssertEqual(model.netRebuildCount, rebuilds, "a turn is geometry, not topology")
        #endif
    }

    /// The rim turns with the hand one to one about the axis, and a flick
    /// let go coasts on, dying away over `stageCoastTime`; a hand that had
    /// stopped lets go without a coast.
    func testTheRimTurnsWithTheHandAndCoasts() {
        let model = CircuitsModel()
        let centre = SIMD3(model.stage.center.x, 1.0, model.stage.center.y)
        func hand(_ angle: Double) -> SIMD3<Double> {
            centre + SIMD3(cos(angle), 0, -sin(angle)) * CircuitsModel.stageRadius
        }
        XCTAssertTrue(model.beginSpin(hand: hand(0), at: 0))
        for frame in 1...9 {
            model.updateSpin(hand: hand(0.04 * Double(frame)), at: Double(frame) / 90)
        }
        XCTAssertEqual(model.stage.yaw, 0.36, accuracy: 1e-9, "one to one with the hand")
        model.endSpin(coasts: true, at: 9.0 / 90)
        // Smoothed over ~80 ms, so it has risen most of the way to the
        // hand's 3.6 rad/s.
        let rate = model.stageSpinRate
        XCTAssertGreaterThan(rate, 2)
        XCTAssertLessThanOrEqual(rate, 0.04 * 90 + 1e-9)
        model.step(dt: 0.1)
        XCTAssertEqual(model.stageSpinRate, rate * exp(-0.1 / CircuitsModel.stageCoastTime),
                       accuracy: 1e-9)
        for _ in 0..<300 { model.step(dt: 1 / 90) }
        XCTAssertEqual(model.stageSpinRate, 0, "a coast stops")

        // Held still before letting go: no coast.
        model.beginSpin(hand: hand(model.stage.yaw), at: 10)
        model.updateSpin(hand: hand(model.stage.yaw + 0.1), at: 10.01)
        model.endSpin(coasts: true, at: 10.5)
        XCTAssertEqual(model.stageSpinRate, 0)
        // And under Reduce Motion, none either.
        model.beginSpin(hand: hand(model.stage.yaw), at: 11)
        model.updateSpin(hand: hand(model.stage.yaw + 0.1), at: 11.01)
        model.endSpin(coasts: false, at: 11.02)
        XCTAssertEqual(model.stageSpinRate, 0)
    }

    /// No coast while paused; a hand on a part stops one; nothing turns in
    /// the past or with a lead in the hand.
    func testACoastStopsForAPauseAHandAndThePast() throws {
        let model = CircuitsModel()
        #if DEBUG
        model.setStageCoast(rate: 2)
        model.isPaused = true
        model.step(dt: 1 / 90)
        XCTAssertEqual(model.stageSpinRate, 0)
        model.isPaused = false
        model.setStageCoast(rate: 2)
        model.stopStageCoast()
        XCTAssertEqual(model.stageSpinRate, 0)
        #endif
        let wire = try XCTUnwrap(model.wires.first)
        model.beginLeadPull(from: wire.from, hand: model.components[0].position)
        XCTAssertFalse(model.spinCircuit(by: 0.5))
        model.cancelLeadPull()
        model.scrubTime = 0.2
        XCTAssertFalse(model.spinCircuit(by: 0.5))
        XCTAssertFalse(model.beginSpin(hand: .zero, at: 0))
        XCTAssertFalse(model.beginStageCarry(hand: .zero))
        XCTAssertEqual(model.moveCircuit(by: SIMD3(0.1, 0, 0)), .zero)
    }

    /// Carried by its deck, the circuit follows the hand — and slides along
    /// a limit rather than refusing: the stage never sinks below its floor.
    func testTheDeckCarriesTheCircuitAndStopsAtTheFloor() {
        let model = CircuitsModel()
        let start = model.components.map(\.position)
        XCTAssertTrue(model.beginStageCarry(hand: SIMD3(0, 1, -0.5)))
        model.updateStageCarry(hand: SIMD3(0.2, 1, -0.6))
        for (part, before) in zip(model.components, start) {
            XCTAssertEqual(simd_distance(part.position, before + SIMD3(0.2, 0, -0.1)), 0, accuracy: 1e-9)
        }
        XCTAssertEqual(model.stage.center.x, CircuitsModel.homeStage.center.x + 0.2, accuracy: 1e-9)
        // Down hard: the stage stops at its floor, the circuit with it.
        model.updateStageCarry(hand: SIMD3(0.2, -3, -0.6))
        XCTAssertEqual(model.stage.top, CircuitsModel.stageFloor, accuracy: 1e-9)
        XCTAssertEqual(lowestPoint(model) - model.stage.top, CircuitsModel.stageClearance, accuracy: 1e-9)
        // ...and follows straight back up the moment the hand turns.
        model.updateStageCarry(hand: SIMD3(0.2, -2.9, -0.6))
        XCTAssertEqual(model.stage.top, CircuitsModel.stageFloor + 0.1, accuracy: 1e-9)
        model.endStageCarry()
    }

    /// A preset and a fresh part from the shelf's fallback land over the
    /// stage where it stands; a reset brings the stage home.
    func testPresetsLandOnTheStageWhereItStands() {
        let model = CircuitsModel()
        model.moveCircuit(by: SIMD3(-0.4, 0, 0.3))
        model.spinCircuit(by: 0.8)
        let centre = model.stage.center
        model.loadPreset(.parallel)
        let xs = model.components.map(\.position.x), zs = model.components.map(\.position.z)
        let middle = SIMD2((xs.min()! + xs.max()!) / 2, (zs.min()! + zs.max()!) / 2)
        XCTAssertLessThan(simd_distance(middle, centre), 0.25, "the preset should stand over the stage")
        XCTAssertEqual(model.stage.yaw, 0, "a preset faces the wearer")
        let added = model.add(.resistor)!
        let part = model.components.first { $0.id == added }!
        XCTAssertLessThan(simd_distance(SIMD2(part.position.x, part.position.z), centre), 0.5)
        model.reset()
        XCTAssertEqual(model.stage.center, CircuitsModel.homeStage.center)
        XCTAssertEqual(model.stage.yaw, 0)
    }

    /// Clearing the bench sends the stage home: the next parts come from
    /// the shelf, and a stage left a metre away would stand under nothing.
    func testClearingTheBenchSendsTheStageHome() {
        let model = CircuitsModel()
        model.moveCircuit(by: SIMD3(0.5, 0, -0.4))
        model.spinCircuit(by: 1)
        model.clearBench()
        XCTAssertEqual(model.stage.center, CircuitsModel.homeStage.center)
        XCTAssertEqual(model.stage.yaw, 0)
        XCTAssertEqual(model.stageSpinRate, 0)
    }

    /// The stage is saved with the bench, and a bench saved before it could
    /// move gets one centred under its parts.
    func testTheStageIsSavedAndAnOldBenchDerivesOne() throws {
        let model = CircuitsModel()
        model.moveCircuit(by: SIMD3(0.3, 0, -0.2))
        model.spinCircuit(by: 0.5)
        model.persistNow()
        let data = try XCTUnwrap(UserDefaults.standard.data(forKey: CircuitsModel.saveKey))
        let saved = try JSONDecoder().decode(CircuitsModel.SavedBench.self, from: data)
        XCTAssertEqual(saved.stage, model.stage)

        let old = CircuitsModel.SavedBench(components: model.components, wires: model.wires)
        let derived = CircuitsModel.derivedStage(for: old.components)
        XCTAssertEqual(derived.yaw, 0)
        let xs = model.components.map(\.position.x)
        XCTAssertEqual(derived.center.x, (xs.min()! + xs.max()!) / 2, accuracy: 1e-9)
    }

    /// The renderer's rim and deck targets resolve to the stage holds, at
    /// the lowest priority, and a tap there is a tap on empty space.
    func testTheRimAndDeckAreTheStagesHandles() {
        let model = CircuitsModel()
        XCTAssertEqual(CircuitsSpaceView.resolveGrab(names: [CircuitsRenderer.stageRimName], on: model),
                       .stageRim)
        XCTAssertEqual(CircuitsSpaceView.resolveGrab(names: [CircuitsRenderer.stageDeckName], on: model),
                       .stageDeck)
        let part = model.components[0].id
        XCTAssertEqual(CircuitsSpaceView.resolveGrab(
            names: [part.uuidString, CircuitsRenderer.stageDeckName], on: model), .body(part),
            "a part outranks the stage under it")
        XCTAssertEqual(CircuitsSpaceView.carryDispatch(
            leadPullActive: false, partDragActive: false, stageHeld: true, rackDragging: true), .stage)
        XCTAssertEqual(CircuitsSpaceView.carryDispatch(
            leadPullActive: false, partDragActive: true, stageHeld: true, rackDragging: false), .carry)
    }

    /// The deck takes a hand only on its band: none of its targets reaches
    /// in under the parts.
    func testTheDecksMiddleTakesNoHand() throws {
        let renderer = CircuitsRenderer()
        let deck = try XCTUnwrap(renderer.root.findEntity(named: CircuitsRenderer.stageDeckName))
        let shapes = try XCTUnwrap(deck.components[CollisionComponent.self]?.shapes)
        XCTAssertEqual(shapes.count, CircuitsRenderer.deckBandSegments)
        for shape in shapes {
            let centre = shape.bounds.center
            XCTAssertGreaterThan(simd_length(SIMD2(centre.x, centre.z)),
                                 CircuitsRenderer.deckBand.lowerBound)
        }
        let rim = try XCTUnwrap(renderer.root.findEntity(named: CircuitsRenderer.stageRimName))
        XCTAssertEqual(rim.components[CollisionComponent.self]?.shapes.count,
                       CircuitsRenderer.rimGrabSegments)
    }

    /// The zoom grows about the stage where it stands.
    func testTheZoomPivotRidesTheStage() {
        XCTAssertEqual(CircuitsRenderer.zoomPivot(for: CircuitsModel.homeStage), CircuitsRenderer.benchPivot)
        var moved = CircuitsModel.homeStage
        moved.center += SIMD2(0.5, -0.2)
        moved.top += 0.1
        let pivot = CircuitsRenderer.zoomPivot(for: moved)
        XCTAssertEqual(pivot.x, CircuitsRenderer.benchPivot.x + 0.5, accuracy: 1e-6)
        XCTAssertEqual(pivot.y, CircuitsRenderer.benchPivot.y + 0.1, accuracy: 1e-6)
        XCTAssertEqual(pivot.z, CircuitsRenderer.benchPivot.z - 0.2, accuracy: 1e-6)
    }
}
