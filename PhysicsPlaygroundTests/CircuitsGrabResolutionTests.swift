//
//  CircuitsGrabResolutionTests.swift
//  PhysicsPlaygroundTests
//
//  Which of six things claimed a pinch.
//
//  Nothing automated can touch a RealityKit entity, so until this was
//  a pure static the answer lived inside a gesture closure and could
//  only be checked by reading it. `FieldSpaceView.resolveCharge` made
//  the same move for the same reason.
//
//  The one rule worth stating: THERE IS NO DISTANCE FALLBACK. Electric
//  Fields has one — a pinch within 12 cm of a charge grabs that charge
//  — and it is right there, where the things being grabbed are far
//  apart and the room is mostly empty. On this bench one part's two
//  leads are 17 cm apart and its neighbours are closer than that, so a
//  fallback is not forgiveness, it is how you wire the wrong end.
//

import XCTest
import simd
@testable import PhysicsPlayground

@MainActor
final class CircuitsGrabResolutionTests: XCTestCase {

    private func bench() -> (model: CircuitsModel, battery: UUID, bulb: UUID, wire: UUID) {
        let model = CircuitsModel()
        model.clearBench()
        let battery = model.add(.battery, at: CircuitsModel.buildCenter - SIMD3(0.3, 0, 0))!
        let bulb = model.add(.bulb, at: CircuitsModel.buildCenter + SIMD3(0.3, 0, 0))!
        model.connectTerminals(.init(componentID: battery, end: 1),
                               .init(componentID: bulb, end: 0))
        return (model, battery, bulb, model.wires[0].id)
    }

    /// A copper lead resolves to a lead pull, at the right end.
    func testATerminalNameResolvesALead() {
        let (model, battery, _, _) = bench()
        XCTAssertEqual(
            CircuitsSpaceView.resolveGrab(names: ["t0-\(battery.uuidString)"], on: model),
            .lead(.init(componentID: battery, end: 0)))
        XCTAssertEqual(
            CircuitsSpaceView.resolveGrab(names: ["t1-\(battery.uuidString)"], on: model),
            .lead(.init(componentID: battery, end: 1)))
    }

    /// A bare UUID is the body: carry it.
    func testABodyNameResolvesACarry() {
        let (model, _, bulb, _) = bench()
        XCTAssertEqual(CircuitsSpaceView.resolveGrab(names: [bulb.uuidString], on: model),
                       .body(bulb))
    }

    /// A wire resolves to the wire, not to whatever it is strung
    /// between — grab the copper to make a wire, grab the cable to
    /// move one.
    func testAWireNameResolvesTheWire() {
        let (model, _, _, wire) = bench()
        XCTAssertEqual(CircuitsSpaceView.resolveGrab(names: ["w-\(wire.uuidString)"], on: model),
                       .wire(wire))
    }

    /// A switch lever is its own thing.
    func testALeverNameResolvesTheLever() {
        let model = CircuitsModel()
        let toggle = model.components.first { $0.kind == .switcher }!
        XCTAssertEqual(
            CircuitsSpaceView.resolveGrab(names: ["k-\(toggle.id.uuidString)"], on: model),
            .lever(toggle.id))
    }

    /// THE PRIORITY ORDER. A pinch lands on a child and the meaning
    /// can live on a parent, so the chain is walked nearest-first —
    /// and the nearest wins. A lead is a child of its holder, and the
    /// holder's name is a bare UUID; if the holder won, no lead on the
    /// bench could ever be pulled.
    func testTheNearestNameInTheChainWins() {
        let (model, battery, _, _) = bench()
        XCTAssertEqual(
            CircuitsSpaceView.resolveGrab(
                names: ["t1-\(battery.uuidString)", battery.uuidString], on: model),
            .lead(.init(componentID: battery, end: 1)),
            "The holder claimed a pinch that landed on a lead.")
    }

    /// An unnamed child falls through to its parent — this is why the
    /// chain exists at all.
    func testAnUnnamedChildFallsThroughToItsParent() {
        let (model, _, bulb, _) = bench()
        XCTAssertEqual(
            CircuitsSpaceView.resolveGrab(names: ["", "glow", bulb.uuidString], on: model),
            .body(bulb))
    }

    /// A name for something that is not on the bench resolves to
    /// nothing — it does not resolve to the nearest thing that IS.
    /// This is the no-fallback rule, stated as a test.
    func testAStaleNameResolvesNothingRatherThanTheNearestPart() {
        let (model, _, _, _) = bench()
        let ghost = UUID()
        XCTAssertEqual(CircuitsSpaceView.resolveGrab(names: [ghost.uuidString], on: model),
                       .none)
        XCTAssertEqual(
            CircuitsSpaceView.resolveGrab(names: ["t0-\(ghost.uuidString)"], on: model),
            .none)
        XCTAssertEqual(
            CircuitsSpaceView.resolveGrab(names: ["w-\(ghost.uuidString)"], on: model),
            .none)
    }

    /// An empty chain, and a chain of nothing recognisable, are both
    /// simply nothing.
    func testAnAnonymousHitResolvesNothing() {
        let (model, _, _, _) = bench()
        XCTAssertEqual(CircuitsSpaceView.resolveGrab(names: [], on: model), .none)
        XCTAssertEqual(
            CircuitsSpaceView.resolveGrab(names: ["skyline-tower", "jacket", ""], on: model),
            .none)
    }

    /// Malformed names do not trap or half-match. `"t0-"` with no
    /// UUID after it was a real shape once: the old resolver did
    /// `dropFirst(3)` and fed the remainder to `UUID(uuidString:)`
    /// without checking the part existed.
    func testMalformedNamesResolveNothing() {
        let (model, _, _, _) = bench()
        for name in ["t0-", "t1-not-a-uuid", "w-", "k-", "t2-\(UUID().uuidString)", "-"] {
            XCTAssertEqual(CircuitsSpaceView.resolveGrab(names: [name], on: model), .none,
                           "\"\(name)\" resolved to something.")
        }
    }

    /// The resolver reads the CURRENT bench: a deleted part's name
    /// stops resolving the moment it goes, which is what keeps a
    /// stale entity from acting on a component that is not there.
    func testADeletedPartsNameStopsResolving() {
        let (model, battery, _, _) = bench()
        XCTAssertNotEqual(CircuitsSpaceView.resolveGrab(names: [battery.uuidString], on: model),
                          .none)
        model.removeComponent(id: battery)
        XCTAssertEqual(CircuitsSpaceView.resolveGrab(names: [battery.uuidString], on: model),
                       .none)
        XCTAssertEqual(
            CircuitsSpaceView.resolveGrab(names: ["t0-\(battery.uuidString)"], on: model),
            .none, "A lead of a deleted part still resolved.")
    }

    /// A deleted wire's name likewise.
    func testADeletedWiresNameStopsResolving() {
        let (model, _, _, wire) = bench()
        model.deleteWire(id: wire)
        XCTAssertEqual(CircuitsSpaceView.resolveGrab(names: ["w-\(wire.uuidString)"], on: model),
                       .none)
    }
}
