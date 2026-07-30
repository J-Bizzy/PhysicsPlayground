//
//  EMWorldLinkTests.swift
//  PhysicsPlaygroundTests
//
//  The one claim the merged E&M world makes that neither bench could
//  make alone: the current in a circuit you built is the current in a
//  coil across the room, and that coil is a magnet.
//
//  The dipole and induction math itself is held to closed forms in
//  PhysicsCore. This guards the JOIN — that the number really travels
//  from one bench's solver into the other's field, that it is this
//  frame's number and not last frame's, and that opening the switch
//  takes the magnetism away with the current.
//

import XCTest
import PhysicsCore
import simd
@testable import PhysicsPlayground

@MainActor
final class EMWorldLinkTests: XCTestCase {

    /// A battery, a switch, and an inductor in one loop.
    private func makeDrivenLoop() -> CircuitsModel {
        let circuits = CircuitsModel()
        circuits.clearBench()
        circuits.add(.battery)
        circuits.add(.switcher)
        circuits.add(.inductor)
        let battery = circuits.components[0]
        let switcher = circuits.components[1]
        let inductor = circuits.components[2]
        circuits.tapTerminal(.init(componentID: battery.id, end: 1))
        circuits.tapTerminal(.init(componentID: switcher.id, end: 0))
        circuits.tapTerminal(.init(componentID: switcher.id, end: 1))
        circuits.tapTerminal(.init(componentID: inductor.id, end: 0))
        circuits.tapTerminal(.init(componentID: inductor.id, end: 1))
        circuits.tapTerminal(.init(componentID: battery.id, end: 0))
        return circuits
    }

    private func settle(_ circuits: CircuitsModel, frames: Int = 240) {
        for _ in 0..<frames { circuits.step(dt: 1.0 / 60) }
    }

    // MARK: The current crosses the room

    func testTheBenchCurrentBecomesTheCoilsMagneticMoment() {
        let circuits = makeDrivenLoop()
        settle(circuits)
        let current = circuits.inductorCurrent
        XCTAssertGreaterThan(abs(current), 1e-3,
                             "a battery across an inductor must settle to a current")

        let magnetism = MagnetismModel()
        magnetism.electromagnetOn = true
        magnetism.setCoilCurrent(current)

        // m = N·I·A, with the coil's own turns and radius.
        let expected = Double(MagnetismModel.coilTurns) * current
            * CurrentLoop.area(radius: MagnetismModel.coilRadius)
        XCTAssertEqual(magnetism.electromagnetMoment, expected, accuracy: 1e-9,
                       "the coil's moment is N·I·A on the BENCH's current")
        XCTAssertNotNil(magnetism.electromagnet,
                        "a coil carrying current is a magnet")
    }

    /// The point of the whole merge: the coil's field reaches the bar
    /// magnets and pushes them. A force, not a proximity check.
    func testThePoweredCoilExertsAForceOnABarMagnet() {
        let circuits = makeDrivenLoop()
        settle(circuits)

        let magnetism = MagnetismModel()
        magnetism.electromagnetOn = true
        magnetism.dynamicsOn = false
        magnetism.setCoilCurrent(circuits.inductorCurrent)
        guard let coil = magnetism.electromagnet,
              let magnet = magnetism.magnets.first else {
            return XCTFail("a powered coil and the cold-open magnet should both exist")
        }

        // Put the magnet a hand's width off the coil, along its axis.
        magnetism.move(id: magnet.id,
                       to: magnetism.electromagnetPosition
                           + magnetism.electromagnetAxis * 0.12)
        guard let moved = magnetism.magnets.first else { return XCTFail("magnet vanished") }

        let force = MagneticField.netForce(on: moved, from: [coil])
        XCTAssertGreaterThan(simd_length(force), 1e-4,
                             "the circuit's current must move the magnet, not just glow")
    }

    // MARK: Opening the switch takes it all away

    func testOpeningTheSwitchKillsTheCoil() {
        let circuits = makeDrivenLoop()
        settle(circuits)

        let magnetism = MagnetismModel()
        magnetism.electromagnetOn = true
        magnetism.setCoilCurrent(circuits.inductorCurrent)
        XCTAssertNotNil(magnetism.electromagnet, "coil should start alive")

        let switcher = circuits.components[1]
        circuits.toggleSwitch(id: switcher.id)
        settle(circuits)

        magnetism.setCoilCurrent(circuits.inductorCurrent)
        XCTAssertLessThan(abs(circuits.inductorCurrent), 1e-6,
                          "an open switch carries no current")
        XCTAssertNil(magnetism.electromagnet,
                     "and a coil carrying no current is not a magnet")
    }

    /// With no inductor on the bench there is nothing to feed the coil
    /// — the same condition under which the world draws no cable.
    func testABenchWithNoInductorFeedsNothing() {
        let circuits = CircuitsModel()
        circuits.reset()          // battery, switch, bulb: no inductor
        settle(circuits, frames: 60)
        XCTAssertFalse(circuits.components.contains { $0.kind == .inductor })
        XCTAssertEqual(circuits.inductorCurrent, 0, accuracy: 1e-12)
    }

    // MARK: The catalog — six experiences behind two doors

    /// The catalog is the six experiences; the merged worlds are gone.
    /// They were undone for GEOMETRY (see DECISIONS.md 2026-07-30):
    /// three benches in one room pushed everything a step out of reach,
    /// and the orrery proved impossible outright.
    func testTheCatalogListsTheSixExperiencesAndNoWorlds() {
        let ids = ModuleCatalog.all(appModel: AppModel()).map(\.id)
        for id in ["electrostatics", "circuits", "magnetism",
                   "kinematics", "pendulums", "gravitylab"] {
            XCTAssertTrue(ids.contains(id), "\(id) should be an entry")
        }
        XCTAssertFalse(ids.contains("em"), "the merged E&M world was undone")
        XCTAssertFalse(ids.contains("mechanics"),
                       "the merged Mechanics world was undone")
    }

    /// Every experience sits behind one of the two doors, and each door
    /// leads somewhere — the Home Screen's whole promise.
    func testEveryExperienceHasADoorAndEveryDoorHasExperiences() {
        let ids = ModuleCatalog.all(appModel: AppModel()).map(\.id)
        XCTAssertEqual(Set(HubDomain.arcOrder), Set(ids),
                       "the doors and the catalog have drifted apart")
        for domain in HubDomain.allCases {
            XCTAssertFalse(domain.moduleIDs.isEmpty,
                           "\(domain) is a door onto nothing")
        }
    }

    /// The link experiments live with Circuit Workshop, which is the
    /// experience that BRINGS the coil (the one wired pair — the cable
    /// demonstration cannot exist with a single bench). Magnetism alone
    /// keeps only its own.
    func testTheLinkExperimentsBelongToCircuitWorkshop() {
        let appModel = AppModel()
        let circuits = ExperimentCatalog
            .experiments(for: "circuits", appModel: appModel)
            .map(\.experiment.id)
        XCTAssertTrue(circuits.contains("circuits.charged"))
        XCTAssertTrue(circuits.contains("em.reach"),
                      "the cable's experiments ride with the bench that powers it")

        let magnetism = ExperimentCatalog
            .experiments(for: "magnetism", appModel: appModel)
            .map(\.experiment.id)
        XCTAssertTrue(magnetism.contains("magnetism.snap"))
        XCTAssertFalse(magnetism.contains("em.reach"),
                       "alone, the field has no cable to earn these with")
    }
}
