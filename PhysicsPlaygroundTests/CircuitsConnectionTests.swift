//
//  CircuitsConnectionTests.swift
//  PhysicsPlaygroundTests
//
//  Wiring made smooth (2026-10-18), the gesture unchanged: a wire's grab
//  volume never overlaps a lead's; two leads snapped together are one
//  joint, drawn as one junction dot that is the one thing to grab there; a pull
//  lifts the end the hand means; a "these are already connected" refusal
//  lights the connection it found; and a part snapped onto a neighbour
//  glides there instead of jumping.
//

import XCTest
import RealityKit
import RenderKit
import simd
@testable import PhysicsPlayground

@MainActor
final class CircuitsConnectionTests: XCTestCase {

    private func lead(_ model: CircuitsModel, _ id: UUID, _ end: Int) -> SIMD3<Double> {
        model.components.first { $0.id == id }!.terminalPosition(end)
    }

    /// A battery–bulb loop, both wires long.
    private func loop(_ model: CircuitsModel) -> (battery: UUID, bulb: UUID) {
        model.clearBench()
        let battery = model.add(.battery, at: CircuitsModel.buildCenter - SIMD3(0.35, 0, 0))!
        let bulb = model.add(.bulb, at: CircuitsModel.buildCenter + SIMD3(0.35, 0, 0))!
        model.connectTerminals(.init(componentID: battery, end: 1), .init(componentID: bulb, end: 0))
        model.connectTerminals(.init(componentID: bulb, end: 1), .init(componentID: battery, end: 0))
        return (battery, bulb)
    }

    /// A bulb set down a few centimetres off a battery's + lead and
    /// released: it snaps nose-to-tail, and the wire between is a joint.
    private func joint(_ model: CircuitsModel)
    -> (battery: UUID, bulb: UUID, wire: UUID, before: CircuitsModel.Component) {
        model.clearBench()
        let battery = model.add(.battery, at: CircuitsModel.buildCenter)!
        let landing = lead(model, battery, 1) + SIMD3(0.03 + CircuitsModel.terminalOffset, 0.02, 0)
        let bulb = model.add(.bulb, at: landing)!
        let before = model.components.first { $0.id == bulb }!
        XCTAssertEqual(model.release(id: bulb), .joined)
        let wire = model.wires.first!
        XCTAssertTrue(model.isJoint(wire))
        return (battery, bulb, wire.id, before)
    }

    private func tick(_ renderer: CircuitsRenderer, _ model: CircuitsModel,
                      frames: Int = 1, dt: Double = 1 / 90) {
        for _ in 0..<frames { renderer.tick(dt: dt, model: model) }
    }

    // MARK: Grab volumes that never overlap

    /// However long a cable, its capsule stops short of both leads' own
    /// targets; below the joint length it is a joint's sphere instead.
    func testACablesTargetStopsShortOfBothLeads() {
        let lead = CircuitsRenderer.terminalTargetRadius
        var length: Float = 0
        while length < 1.2 {
            switch CircuitsRenderer.wireGrabShape(length: length) {
            case .joint(let radius):
                XCTAssertLessThan(length, Float(CircuitsModel.jointLength))
                XCTAssertEqual(radius, CircuitsRenderer.jointGrabRadius)
            case .cable(let height, let radius):
                XCTAssertLessThanOrEqual(radius, height / 2 + 1e-6)
                // The capsule's nearest point to a lead's centre is its tip.
                XCTAssertGreaterThan(length / 2 - height / 2, lead, "length \(length)")
                XCTAssertLessThanOrEqual(radius, CircuitsRenderer.wireGrabRadius)
            case .none:
                XCTAssertGreaterThanOrEqual(length, Float(CircuitsModel.jointLength))
                XCTAssertLessThan(length, 0.07, "a wire this long should be grabbable")
            }
            length += 0.0025
        }
    }

    /// On a real bench every cable's target is clear of its leads', and at
    /// a joint the two coincident leads give their targets — and their dots —
    /// to the one junction dot.
    func testAJointsLeadsGiveTheirTargetsToItsJunction() throws {
        let model = CircuitsModel()
        let (battery, bulb, wire, _) = joint(model)
        let renderer = CircuitsRenderer()
        tick(renderer, model, frames: 3)

        let batteryLead = try XCTUnwrap(renderer.root.findEntity(named: "t1-\(battery.uuidString)"))
        let bulbLead = try XCTUnwrap(renderer.root.findEntity(named: "t0-\(bulb.uuidString)"))
        XCTAssertNil(batteryLead.components[CollisionComponent.self])
        XCTAssertNil(bulbLead.components[CollisionComponent.self])
        // The leads not in the joint keep theirs.
        let free = try XCTUnwrap(renderer.root.findEntity(named: "t0-\(battery.uuidString)"))
        XCTAssertNotNil(free.components[CollisionComponent.self])

        let cable = try XCTUnwrap(renderer.root.findEntity(named: "w-\(wire.uuidString)"))
        let shape = try XCTUnwrap(cable.components[CollisionComponent.self]?.shapes.first)
        XCTAssertEqual(shape.bounds.extents.x, 2 * CircuitsRenderer.jointGrabRadius, accuracy: 1e-3)
        let junction = try XCTUnwrap(cable.findEntity(named: "junction"))
        XCTAssertTrue(junction.isEnabled)
        XCTAssertTrue(batteryLead.children.allSatisfy { !$0.isEnabled }, "its dot gives way to the junction")
        XCTAssertTrue(bulbLead.children.allSatisfy { !$0.isEnabled })
        XCTAssertEqual(CircuitsSpaceView.resolveGrab(names: ["w-\(wire.uuidString)"], on: model),
                       .wire(wire))

        // Carry the bulb away: the joint opens and the leads take their
        // targets back.
        model.move(id: bulb, to: lead(model, battery, 1) + SIMD3(0.4, 0.1, 0))
        tick(renderer, model)
        XCTAssertNotNil(batteryLead.components[CollisionComponent.self])
        XCTAssertNotNil(bulbLead.components[CollisionComponent.self])
        XCTAssertFalse(junction.isEnabled)
        XCTAssertTrue(batteryLead.children.allSatisfy(\.isEnabled), "its dot is back")
    }

    // MARK: Which end a pull lifts

    /// Along a cable, the end nearer the hand once it has moved: the end
    /// pressed near, or from the middle the end the hand moved toward.
    func testACablePullLiftsTheEndTheHandMeans() throws {
        let model = CircuitsModel()
        let (battery, bulb) = loop(model)
        let wire = try XCTUnwrap(model.wires.first { $0.from.componentID == battery })
        let a = lead(model, battery, 1), b = lead(model, bulb, 0)
        let nearA = a + (b - a) * 0.15
        XCTAssertEqual(model.endToLift(of: wire.id, pressedAt: nearA, hand: nearA + [0, 0.02, 0]), 0)
        let middle = (a + b) / 2
        let towardB = simd_normalize(b - a) * 0.02
        XCTAssertEqual(model.endToLift(of: wire.id, pressedAt: middle, hand: middle + towardB), 1)
        XCTAssertEqual(model.endToLift(of: wire.id, pressedAt: middle, hand: middle - towardB), 0)
    }

    /// At a joint the side the hand pulls away from keeps the wire: pull
    /// toward the bulb's side and the lead is drawn out of the battery,
    /// the bulb's contact coming free — and the other way about.
    func testAJointPullKeepsTheSidePulledAwayFrom() throws {
        let model = CircuitsModel()
        let (battery, bulb, wireID, _) = joint(model)
        let wire = try XCTUnwrap(model.wires.first { $0.id == wireID })
        let point = lead(model, battery, 1)
        let towardBulb = simd_normalize(model.components.first { $0.id == bulb }!.position - point)

        let end = try XCTUnwrap(model.endToLift(of: wireID, pressedAt: point,
                                                hand: point + towardBulb * 0.02))
        let anchor = end == 0 ? wire.to : wire.from
        XCTAssertEqual(anchor.componentID, battery, "pulling toward the bulb keeps the battery's side")

        let back = try XCTUnwrap(model.endToLift(of: wireID, pressedAt: point,
                                                 hand: point - towardBulb * 0.02))
        XCTAssertNotEqual(back, end)

        // And the pull itself: the lead comes out of the battery's contact.
        model.beginRewire(wire: wireID, grabbing: end, hand: point + towardBulb * 0.02)
        XCTAssertEqual(model.leadPull?.source, .init(componentID: battery, end: 1))
        XCTAssertFalse(model.wires.contains { $0.id == wireID }, "the joint is open in your hand")
    }

    // MARK: "Already connected" lights the connection

    /// A lead held over a terminal already on its net lights that net, and
    /// a release there keeps it lit for `refusalLinger`.
    func testASameNetRefusalLightsTheNetThatJoinsThem() {
        let model = CircuitsModel()
        let (battery, bulb) = loop(model)
        model.clearNetHighlight()
        let renderer = CircuitsRenderer()
        tick(renderer, model)
        XCTAssertTrue(renderer.litTerminals.isEmpty)

        // Battery + is already wired to the bulb's lead 0.
        let source = CircuitsModel.Terminal(componentID: battery, end: 1)
        let target = CircuitsModel.Terminal(componentID: bulb, end: 0)
        model.beginLeadPull(from: source, hand: lead(model, bulb, 0))
        XCTAssertEqual(model.leadPull?.refusal, .sameNet)
        tick(renderer, model)
        XCTAssertTrue(renderer.litTerminals.isSuperset(of: [source, target]))
        XCTAssertFalse(renderer.litTerminals.contains(.init(componentID: battery, end: 0)),
                       "only the net that joins them lights")

        model.endLeadPull()
        let dt = 0.1
        tick(renderer, model, frames: 7, dt: dt)
        XCTAssertTrue(renderer.litTerminals.contains(target), "the net stays lit a moment")
        tick(renderer, model, frames: 3, dt: dt)
        XCTAssertTrue(renderer.litTerminals.isEmpty, "and then goes out")
    }

    /// A lead over a terminal it may join lights nothing: the light is the
    /// refusal's, not the preview's.
    func testAJoinableTargetLightsNothing() {
        let model = CircuitsModel()
        let (battery, bulb) = loop(model)
        let closing = model.wires.first { $0.from == .init(componentID: bulb, end: 1) }!
        model.deleteWire(id: closing.id)
        model.clearNetHighlight()
        let renderer = CircuitsRenderer()
        model.beginLeadPull(from: .init(componentID: battery, end: 0), hand: lead(model, bulb, 1))
        XCTAssertNil(model.leadPull?.refusal)
        tick(renderer, model)
        XCTAssertTrue(renderer.litTerminals.isEmpty)
    }

    // MARK: The landing glides

    /// A released part snapped onto a neighbour's lead is drawn gliding
    /// from where it was let go to where it lands, over `landingDuration`,
    /// and its joint's junction dot follows it in.
    func testASnappedPartGlidesIntoPlace() throws {
        let model = CircuitsModel()
        let (_, bulb, _, before) = joint(model)
        let landed = try XCTUnwrap(model.components.first { $0.id == bulb })
        XCTAssertGreaterThan(simd_distance(before.position, landed.position), 0.01)

        let renderer = CircuitsRenderer()
        tick(renderer, model)
        renderer.easeLanding(id: bulb, from: before.position, axis: before.axis)
        let holder = try XCTUnwrap(renderer.root.findEntity(named: bulb.uuidString))
        let dt = CircuitsRenderer.landingDuration / 4
        tick(renderer, model, dt: dt)
        let midway = SIMD3<Double>(holder.position)
        let fromStart = simd_distance(midway, before.position)
        let toEnd = simd_distance(midway, landed.position)
        XCTAssertGreaterThan(fromStart, 1e-4, "it should have left where it was let go")
        XCTAssertGreaterThan(toEnd, 1e-4, "it should not have jumped to the landing")

        tick(renderer, model, frames: 4, dt: dt)
        XCTAssertLessThan(simd_distance(SIMD3<Double>(holder.position), landed.position), 1e-5)
        XCTAssertEqual(renderer.displayPose(of: landed).position, landed.position)
    }

    /// Picking the part up again mid-glide stops the glide: the hand owns it.
    func testAPickupStopsTheGlide() throws {
        let model = CircuitsModel()
        let (_, bulb, _, before) = joint(model)
        let renderer = CircuitsRenderer()
        tick(renderer, model)
        renderer.easeLanding(id: bulb, from: before.position, axis: before.axis)
        renderer.flashPickup(id: bulb)
        let landed = try XCTUnwrap(model.components.first { $0.id == bulb })
        XCTAssertEqual(renderer.displayPose(of: landed).position, landed.position)
    }
}
