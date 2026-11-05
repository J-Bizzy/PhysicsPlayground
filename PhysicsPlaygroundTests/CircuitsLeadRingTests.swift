//
//  CircuitsLeadRingTests.swift
//  PhysicsPlaygroundTests
//
//  A node's Cut ring (2026-11-03): tap a wired lead dot, or a joint's
//  junction, and one petal stands just over it. Cut takes that end's wires
//  and nothing else; a bare lead and a cable open nothing; once there is
//  nothing left to cut the ring folds. Driven through the same pure statics
//  and the same petal the view builds, because no automation can tap.
//

import XCTest
import RealityKit
import simd
@testable import PhysicsPlayground

@MainActor
final class CircuitsLeadRingTests: XCTestCase {

    /// battery —w1— bulb —w2— resistor —w3— battery.
    private func loop(_ model: CircuitsModel)
    -> (battery: UUID, bulb: UUID, resistor: UUID) {
        model.clearBench()
        let battery = model.add(.battery, at: CircuitsModel.buildCenter - SIMD3(0.35, 0, 0))!
        let bulb = model.add(.bulb, at: CircuitsModel.buildCenter)!
        let resistor = model.add(.resistor, at: CircuitsModel.buildCenter + SIMD3(0.35, 0, 0))!
        model.connectTerminals(.init(componentID: battery, end: 1), .init(componentID: bulb, end: 0))
        model.connectTerminals(.init(componentID: bulb, end: 1),
                               .init(componentID: resistor, end: 0))
        model.connectTerminals(.init(componentID: resistor, end: 1),
                               .init(componentID: battery, end: 0))
        model.step(dt: 1.0 / 90.0)
        return (battery, bulb, resistor)
    }

    func testAWiredLeadOffersCut() {
        let model = CircuitsModel()
        let (battery, _, _) = loop(model)
        let lead = CircuitsModel.Terminal(componentID: battery, end: 1)
        XCTAssertEqual(CircuitsSpaceView.leadRing(for: .lead(lead), on: model), .lead(lead))
        XCTAssertEqual(CircuitsSpaceView.partID(of: .lead(lead), on: model), battery)
    }

    /// Nothing to cut, so nothing opens: the tap only lights the net.
    func testABareLeadOffersNothing() {
        let model = CircuitsModel()
        _ = loop(model)
        let spare = model.add(.resistor, at: CircuitsModel.buildCenter + SIMD3(0, 0.3, 0))!
        XCTAssertNil(CircuitsSpaceView.leadRing(
            for: .lead(.init(componentID: spare, end: 0)), on: model))
    }

    /// A tap along a cable lights its net; a cable is not a node.
    func testACableIsNotANode() throws {
        let model = CircuitsModel()
        _ = loop(model)
        let cable = try XCTUnwrap(model.wires.first { !model.isJoint($0) })
        XCTAssertNil(CircuitsSpaceView.leadRing(for: .wire(cable.id), on: model))
    }

    /// Every wire on that end goes, and only those: the part's other end,
    /// and the rest of the circuit, keep theirs.
    func testCutTakesThatLeadsWiresAndNoOthers() {
        let model = CircuitsModel()
        let (battery, _, _) = loop(model)
        let spare = model.add(.resistor, at: CircuitsModel.buildCenter + SIMD3(0, 0.3, 0))!
        let lead = CircuitsModel.Terminal(componentID: battery, end: 1)
        model.connectTerminals(lead, .init(componentID: spare, end: 0))
        XCTAssertEqual(model.wires(at: lead).count, 2)
        let others = Set(model.wires.map(\.id)).subtracting(model.wires(at: lead).map(\.id))

        CircuitsSpaceView.cut(.lead(lead), on: model)

        XCTAssertTrue(model.wires(at: lead).isEmpty)
        XCTAssertEqual(Set(model.wires.map(\.id)), others)
        XCTAssertFalse(model.wires(at: .init(componentID: battery, end: 0)).isEmpty,
                       "the battery's other end keeps its wire")
        XCTAssertFalse(CircuitsSpaceView.isLive(.lead(lead), on: model),
                       "with nothing left to cut, the ring folds")
    }

    /// The lit net was the old circuit's; after a cut it would name the wrong one.
    func testCutClearsTheLitNet() {
        let model = CircuitsModel()
        let (battery, _, _) = loop(model)
        let lead = CircuitsModel.Terminal(componentID: battery, end: 1)
        model.highlightNet(containing: lead)
        XCTAssertNotNil(model.highlightedNet)
        CircuitsSpaceView.cut(.lead(lead), on: model)
        XCTAssertNil(model.highlightedNet)
    }

    /// Two leads seated nose to tail are one junction; its Cut parts them.
    func testCuttingAJointPartsItsLeads() throws {
        let model = CircuitsModel()
        model.clearBench()
        let gap = 2 * CircuitsModel.terminalOffset + 0.01
        let a = model.add(.resistor, at: CircuitsModel.buildCenter)!
        let b = model.add(.resistor, at: CircuitsModel.buildCenter + SIMD3(gap, 0, 0))!
        model.connectTerminals(.init(componentID: a, end: 1), .init(componentID: b, end: 0))
        let joint = try XCTUnwrap(model.wires.first)
        XCTAssertTrue(model.isJoint(joint), "the two leads should land as a joint")
        guard model.isJoint(joint) else { return }

        let ring = try XCTUnwrap(CircuitsSpaceView.leadRing(for: .wire(joint.id), on: model))
        XCTAssertEqual(ring, .joint(joint.id))
        XCTAssertEqual(CircuitsSpaceView.partID(of: ring, on: model), joint.from.componentID)

        CircuitsSpaceView.cut(ring, on: model)
        XCTAssertTrue(model.wires.isEmpty)
        XCTAssertFalse(CircuitsSpaceView.isLive(ring, on: model))
    }

    /// The petal the view builds, tapped the way the app taps it.
    func testTheRingsOwnPetalCuts() throws {
        let model = CircuitsModel()
        let (battery, _, _) = loop(model)
        let lead = CircuitsModel.Terminal(componentID: battery, end: 1)
        let bloom = Bloom()
        bloom.retarget(CircuitsSpaceView.LeadRing.lead(lead),
                       petals: [CircuitsSpaceView.cutPetal(for: .lead(lead), on: model)],
                       grip: nil, lift: Bloom.leadRingLift)
        reveal(bloom)
        let petal = try XCTUnwrap(bloom.root.children.first { $0.name == "bloom-Cut" })
        XCTAssertTrue(bloom.handleTap(petal))
        XCTAssertTrue(model.wires(at: lead).isEmpty)
    }

    /// Just over the dot, not 23 cm above it where a part's ring stands.
    func testALeadsPetalStandsJustOverTheDot() throws {
        let lead = Bloom()
        lead.retarget("lead", petals: [.init(name: "Cut", symbol: "scissors", tint: .white) {}],
                      grip: nil, lift: Bloom.leadRingLift)
        reveal(lead)
        let cut = try XCTUnwrap(lead.root.children.first { $0.name == "bloom-Cut" })
        XCTAssertEqual(cut.position.y, Bloom.leadRingLift, accuracy: Bloom.leadRingLift * 0.03)

        let part = Bloom()
        part.retarget("part", petals: [.init(name: "Delete", symbol: "trash", tint: .white) {}],
                      grip: nil)
        reveal(part)
        let delete = try XCTUnwrap(part.root.children.first { $0.name == "bloom-Delete" })
        XCTAssertGreaterThan(delete.position.y, 3 * Bloom.leadRingLift,
                             "a part's own ring keeps its height")
    }

    /// At one metre, so the ring's scale is 1, and long enough for the
    /// petals' eased unfold to settle.
    private func reveal(_ bloom: Bloom) {
        for _ in 0..<240 {
            bloom.update(anchor: .zero, viewer: [0, 0, 1], revealTarget: 1, dt: 1.0 / 90.0)
        }
    }
}
