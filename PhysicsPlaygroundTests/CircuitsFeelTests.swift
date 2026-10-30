//
//  CircuitsFeelTests.swift
//  PhysicsPlaygroundTests
//
//  How Circuit Workshop answers a hand (2026-10-30, contract "Feel"): a
//  held part rides a little up and settles back when let go; carried
//  within a centimetre of a lead it can join, it leans in to seat; set
//  down there, its dots meet with a snap; a joint pulled at strains toward
//  the hand before it gives. Every one of them is drawn only — the model's
//  part is always where the hand put it. Reduce Motion is a system switch
//  these tests cannot flip, so the un-reduced path is what they assert.
//

import XCTest
import RealityKit
import RenderKit
import simd
@testable import PhysicsPlayground

@MainActor
final class CircuitsFeelTests: XCTestCase {

    private func tick(_ renderer: CircuitsRenderer, _ model: CircuitsModel, frames: Int = 1) {
        for _ in 0..<frames { renderer.tick(dt: 1 / 90, model: model) }
    }

    private func component(_ model: CircuitsModel, _ id: UUID) -> CircuitsModel.Component {
        model.components.first { $0.id == id }!
    }

    /// Taken up, a part rides `liftHeight` above where the model holds it;
    /// let go, it settles back onto the model's pose.
    func testAHeldPartRidesUpAndSettlesBack() throws {
        let model = CircuitsModel()
        let bulb = try XCTUnwrap(model.components.first { $0.kind == .bulb }).id
        let renderer = CircuitsRenderer()
        tick(renderer, model)
        let holder = try XCTUnwrap(renderer.root.findEntity(named: bulb.uuidString))

        renderer.flashPickup(id: bulb)
        tick(renderer, model, frames: 60)
        let held = component(model, bulb)
        XCTAssertEqual(holder.position.y - Float(held.position.y), CircuitsRenderer.liftHeight,
                       accuracy: 1e-4)
        XCTAssertEqual(holder.position.x, Float(held.position.x), accuracy: 1e-6, "only up")

        renderer.flashRelease()
        tick(renderer, model, frames: 60)
        XCTAssertLessThan(simd_distance(SIMD3<Double>(holder.position), component(model, bulb).position), 1e-6)
        XCTAssertEqual(renderer.displayPose(of: component(model, bulb)).position, component(model, bulb).position)
    }

    /// The lean is nothing beyond a centimetre, everything at contact, and
    /// grows steadily between.
    func testThePullInIsTheLastCentimetre() {
        XCTAssertEqual(CircuitsRenderer.pullInWeight(distance: 0.05), 0)
        XCTAssertEqual(CircuitsRenderer.pullInWeight(distance: CircuitsRenderer.pullInDistance), 0)
        XCTAssertEqual(CircuitsRenderer.pullInWeight(distance: 0), 1)
        var previous = 1.0
        for step in 0...100 {
            let weight = CircuitsRenderer.pullInWeight(distance: Double(step) * 0.0001)
            XCTAssertLessThanOrEqual(weight, previous + 1e-12)
            previous = weight
        }
    }

    /// A part carried 5 mm from a lead it can join is drawn leaning in
    /// toward where a release would seat it — while the model keeps it in
    /// the hand.
    func testACarriedPartLeansInToSeat() throws {
        let model = CircuitsModel()
        model.clearBench()
        let battery = try XCTUnwrap(model.add(.battery, at: CircuitsModel.buildCenter))
        let target = component(model, battery).terminalPosition(1)
        let bulb = try XCTUnwrap(model.add(.bulb, at: target + SIMD3(0.005 + CircuitsModel.terminalOffset,
                                                                      0.003, 0)))
        let renderer = CircuitsRenderer()
        tick(renderer, model)
        renderer.flashPickup(id: bulb)
        tick(renderer, model)

        let held = component(model, bulb)
        let seat = try XCTUnwrap(model.alignment(for: bulb))
        let drawn = renderer.displayPose(of: held).position
        let modelGap = simd_distance(held.position, seat.position)
        XCTAssertLessThan(simd_distance(drawn, seat.position) + 1e-5, modelGap,
                          "the drawn part should be nearer its seat than the held one")
        XCTAssertEqual(component(model, bulb).position, held.position, "the model's part did not move")

        // Carried away, the lean lets go.
        model.move(id: bulb, to: held.position + SIMD3(0.2, 0, 0))
        tick(renderer, model)
        let away = component(model, bulb)
        XCTAssertEqual(renderer.displayPose(of: away).position.x, away.position.x, accuracy: 1e-9)
    }

    /// Set down onto a neighbour's lead, the two dots meet with a seat; a
    /// release that lands nothing makes no seat.
    func testTwoDotsMeetingSeat() throws {
        let model = CircuitsModel()
        model.clearBench()
        let battery = try XCTUnwrap(model.add(.battery, at: CircuitsModel.buildCenter))
        let target = component(model, battery).terminalPosition(1)
        let bulb = try XCTUnwrap(model.add(.bulb, at: target + SIMD3(0.03 + CircuitsModel.terminalOffset,
                                                                      0.02, 0)))
        XCTAssertEqual(model.release(id: bulb), .joined)
        XCTAssertEqual(model.soundEvent?.kind, .seat)
    }

    /// Set down crooked beside a lead, a part is drawn gliding from where it
    /// was let go onto its seat, partway at any instant of the 0.12 s — and
    /// `-circSnapAt` holds that instant for a still.
    func testALandingGlidesOntoItsSeat() throws {
        let model = CircuitsModel()
        model.clearBench()
        let battery = try XCTUnwrap(model.add(.battery, at: CircuitsModel.buildCenter))
        let target = component(model, battery).terminalPosition(1)
        let bulb = try XCTUnwrap(model.add(.bulb, at: target + SIMD3(0.03 + CircuitsModel.terminalOffset,
                                                                      0.02, 0)))
        let before = component(model, bulb)
        XCTAssertEqual(model.release(id: bulb), .joined)
        let seated = component(model, bulb)
        let renderer = CircuitsRenderer()
        renderer.pinnedLandingTime = CircuitsRenderer.landingDuration / 2
        renderer.easeLanding(id: bulb, from: before.position, axis: before.axis)
        tick(renderer, model, frames: 30)

        let drawn = renderer.displayPose(of: seated).position
        let gap = simd_distance(before.position, seated.position)
        XCTAssertGreaterThan(simd_distance(drawn, seated.position), gap * 0.3, "not yet seated")
        XCTAssertGreaterThan(simd_distance(drawn, before.position), gap * 0.3, "well under way")

        renderer.pinnedLandingTime = nil
        tick(renderer, model, frames: 30)
        XCTAssertEqual(renderer.displayPose(of: seated).position, seated.position)
    }

    /// A joint pulled at stretches toward the hand before the press gives,
    /// keeping its volume, and is round again once the pull lets go.
    func testAJointStrainsTowardTheHand() throws {
        let model = CircuitsModel()
        model.clearBench()
        let battery = try XCTUnwrap(model.add(.battery, at: CircuitsModel.buildCenter))
        let target = component(model, battery).terminalPosition(1)
        let bulb = try XCTUnwrap(model.add(.bulb, at: target + SIMD3(0.03 + CircuitsModel.terminalOffset,
                                                                      0.02, 0)))
        XCTAssertEqual(model.release(id: bulb), .joined)
        let wire = try XCTUnwrap(model.wires.first).id
        let renderer = CircuitsRenderer()
        tick(renderer, model, frames: 2)
        let junction = try XCTUnwrap(renderer.root.findEntity(named: "w-\(wire.uuidString)")?
            .findEntity(named: "junction"))
        let rest = junction.scale

        renderer.jointStrain = (wire, [0, Float(PressLatch<Int>.tapTravel) * 0.9, 0])
        tick(renderer, model)
        XCTAssertGreaterThan(junction.scale.y, rest.y * 1.4, "it should stretch toward the hand")
        XCTAssertEqual(junction.scale.x * junction.scale.y * junction.scale.z,
                       rest.x * rest.y * rest.z, accuracy: 1e-4, "a pull, not a swelling")

        renderer.jointStrain = nil
        tick(renderer, model)
        XCTAssertLessThan(simd_distance(junction.scale, rest), 1e-6, "round again")
    }
}
