//
//  OpticsModelTests.swift
//  PhysicsPlaygroundTests
//
//  Light & Optics as built: the scene it opens on really does what it is
//  staged to do (white light leaves the prism straight ahead at least
//  deviation and fans by colour onto the wall; the laser is trapped in the
//  bar by total internal reflection), a hand's aim turns a piece the way
//  the tracer turns it, a held laser points where the hand points, and
//  the light is traced again only when something moves.
//

import XCTest
import PhysicsCore
import RenderKit
import simd
@testable import PhysicsPlayground

@MainActor
final class OpticsModelTests: XCTestCase {

    /// A wall across the room at depth `z`, facing the wearer.
    private func wall(at z: Double) -> RoomWalls.Wall {
        RoomWalls.Wall(center: SIMD3(0, 1.5, z), normal: SIMD3(0, 0, 1),
                       uAxis: SIMD3(1, 0, 0), vAxis: SIMD3(0, 1, 0), halfU: 3, halfV: 1.5)
    }

    private func strongest(_ landings: [LightTracer.Landing], nanometers: Double)
        -> LightTracer.Landing? {
        landings.filter { $0.nanometers == nanometers }.max { $0.power < $1.power }
    }

    func testTheOpeningPrismFansWhiteLightStraightAheadOntoTheWall() throws {
        let model = OpticsModel()
        model.laser.isOn = false
        model.room = LightTracer.Room(walls: [wall(at: -3)], floorY: 0, maxSegment: 6)
        let trace = model.traceIfNeeded()

        // Green leaves along −z: the prism stands at least deviation for it.
        let green = try XCTUnwrap(strongest(trace.landings, nanometers: 550))
        XCTAssertEqual(green.surface, .wall(0))
        XCTAssertLessThan(green.direction.z, -0.999, "the spectrum does not leave straight ahead")

        // Violet is bent further than red, toward the prism's base — and in
        // flint the fan is a spectrum a hand's width across, not a line.
        let violet = try XCTUnwrap(strongest(trace.landings, nanometers: 400))
        let red = try XCTUnwrap(strongest(trace.landings, nanometers: 700))
        let base = -OpticsModel.level(try XCTUnwrap(model.pieces.first { $0.kind == .prism }).aim)
        XCTAssertGreaterThan(simd_dot(violet.point - red.point, base), 0)
        let spread = simd_distance(violet.point, red.point)
        XCTAssertGreaterThan(spread, 0.05)
        XCTAssertLessThan(spread, 0.4)
    }

    func testTheOpeningLaserIsTrappedInTheBarByTotalInternalReflection() throws {
        let model = OpticsModel()
        model.torch.isOn = false
        model.room = LightTracer.Room(walls: [wall(at: -3)], floorY: 0, maxSegment: 6)
        let trace = model.traceIfNeeded()
        let bar = try XCTUnwrap(model.pieces.first { $0.kind == .block })
        let events = trace.events.filter { $0.element == bar.id }
        XCTAssertTrue(events.contains { $0.kind == .enter }, "the beam never reached the bar")
        XCTAssertGreaterThanOrEqual(events.filter { $0.kind == .totalInternalReflection }.count, 1)
        // Every side bounce is past the critical angle — that is the trap.
        let critical = asin(1 / model.glass.index(nanometers: model.laserNanometers))
        for bounce in events where bounce.kind == .totalInternalReflection {
            XCTAssertGreaterThan(bounce.incidence, critical)
        }
        // And most of the light gets through to the wall.
        XCTAssertGreaterThan(trace.landed, 0.6)
    }

    /// The bead turns a piece to face it, and the tracer sees the piece the
    /// way it is drawn: a mirror faces its aim; a prism stays upright and
    /// turns only about the vertical.
    func testAimingTurnsAPieceAndAPrismStaysUpright() throws {
        let model = OpticsModel()
        let mirror = try XCTUnwrap(model.addPiece(.mirror, at: SIMD3(0, 1.2, -1)))
        model.aim(id: mirror, toward: SIMD3(1, 1.7, -1))
        let aimed = try XCTUnwrap(model.pieces.first { $0.id == mirror })
        let face = OpticsModel.orientation(kind: .mirror, aim: aimed.aim).act(SIMD3<Double>(0, 0, 1))
        XCTAssertEqual(simd_dot(face, simd_normalize(SIMD3(1, 0.5, 0))), 1, accuracy: 1e-12)

        let prism = try XCTUnwrap(model.addPiece(.prism, at: SIMD3(0.4, 1.2, -1)))
        model.aim(id: prism, toward: SIMD3(0.4, 2.2, -1.5))
        let turned = try XCTUnwrap(model.pieces.first { $0.id == prism })
        XCTAssertEqual(turned.aim.y, 0, accuracy: 1e-12)
        let up = OpticsModel.orientation(kind: .prism, aim: turned.aim).act(SIMD3<Double>(0, 0, 1))
        XCTAssertEqual(up.y, 1, accuracy: 1e-12)
    }

    /// Carried, the laser points from the eyes through the hand.
    func testAHeldLaserPointsWhereTheHandPoints() {
        let model = OpticsModel()
        let eyes = SIMD3<Double>(0, 1.6, 0)
        model.grab(id: OpticsModel.laserID)
        model.move(id: OpticsModel.laserID, to: SIMD3(0.3, 1.4, -0.5), viewer: eyes)
        let expected = simd_normalize(SIMD3(0.3, 1.4, -0.5) - eyes)
        XCTAssertEqual(simd_distance(model.laser.aim, expected), 0, accuracy: 1e-12)
    }

    func testTheWellRefusesPastTheBudgetAndClearKeepsTheLights() {
        let model = OpticsModel()
        while model.pieces.count < OpticsModel.pieceBudget {
            XCTAssertNotNil(model.addPiece(.lens, at: SIMD3(0, 1, -1)))
        }
        XCTAssertNil(model.addPiece(.lens, at: SIMD3(0, 1, -1)))
        model.clearPieces()
        XCTAssertTrue(model.pieces.isEmpty)
        XCTAssertTrue(model.laser.isOn)
        XCTAssertTrue(model.torch.isOn)
    }

    /// Nothing moved, nothing re-traced; one thing moved, one trace.
    func testTheLightIsTracedAgainOnlyWhenSomethingMoves() throws {
        let model = OpticsModel()
        model.traceIfNeeded()
        let version = model.traceVersion
        model.traceIfNeeded()
        model.traceIfNeeded()
        XCTAssertEqual(model.traceVersion, version)
        let prism = try XCTUnwrap(model.pieces.first { $0.kind == .prism })
        model.move(id: prism.id, to: prism.position + SIMD3(0.01, 0, 0))
        model.traceIfNeeded()
        XCTAssertEqual(model.traceVersion, version + 1)
    }

    /// Where every colour shares one line, one white beam is drawn; where
    /// the prism has pulled them apart, a stroke per colour.
    func testTheSpectrumIsOneWhiteBeamUntilThePrismFansIt() throws {
        let model = OpticsModel()
        model.laser.isOn = false
        let strokes = OpticsBeamLayout.strokes(model.traceIfNeeded())
        let first = try XCTUnwrap(strokes.first)
        XCTAssertGreaterThan(first.color.min(), 0.6, "the torch's beam is not white")
        let coloured = strokes.filter { $0.color.min() < 0.3 }
        XCTAssertGreaterThanOrEqual(coloured.count, LightTracer.visibleSpectrum.count - 1)
    }

    /// With no wall ahead, the fanned spectrum meets nothing: its strokes
    /// are marked to fade out rather than end in a cut. Light that lands
    /// is never marked (2026-11-02).
    func testLightThatMeetsNothingFadesOut() {
        let model = OpticsModel()
        model.laser.isOn = false
        let open = OpticsBeamLayout.strokes(model.traceIfNeeded())
        XCTAssertTrue(open.contains { $0.fadesOut }, "nothing ran out in an unscanned room")
        XCTAssertFalse(open.contains { $0.fadesOut && $0.inGlass }, "light faded inside glass")

        model.room = LightTracer.Room(
            walls: [RoomWalls.Wall(center: SIMD3(0, 1.5, -3), normal: SIMD3(0, 0, 1),
                                   uAxis: SIMD3(1, 0, 0), vAxis: SIMD3(0, 1, 0),
                                   halfU: 6, halfV: 3)],
            floorY: OpticsModel.floorY, maxSegment: 6)
        let walled = model.traceIfNeeded()
        let landed = OpticsBeamLayout.strokes(walled).filter { stroke in
            walled.landings.contains { simd_distance(SIMD3<Float>($0.point), stroke.b) < 1e-3 }
        }
        XCTAssertFalse(landed.isEmpty, "the wall caught nothing")
        XCTAssertFalse(landed.contains { $0.fadesOut }, "light that landed was faded out")
    }

    func testResetReturnsTheOpeningScene() {
        let model = OpticsModel()
        model.clearPieces()
        model.showsAngles = true
        model.showsWeakReflections = true
        model.laser.isOn = false
        model.glass = .nbk7
        model.reset()
        XCTAssertEqual(model.pieces.map(\.kind), [.prism, .mirror, .block])
        XCTAssertFalse(model.showsAngles)
        XCTAssertFalse(model.showsWeakReflections)
        XCTAssertTrue(model.laser.isOn)
        XCTAssertEqual(model.glass, .sf11)
    }
}
