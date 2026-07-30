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

    // MARK: The world is registered as one module

    func testTheCatalogListsOneEMWorldAndNotItsTwoBenches() {
        let ids = ModuleCatalog.all(appModel: AppModel()).map(\.id)
        XCTAssertTrue(ids.contains(EMWorldModule.id))
        XCTAssertFalse(ids.contains("circuits"),
                       "the bench is a station of the world, not an entry")
        XCTAssertFalse(ids.contains("magnetism"),
                       "the field is a station of the world, not an entry")
    }

    /// Both benches' experiments, plus the ones that need both.
    func testTheWorldCarriesBothBenchesExperimentsPlusTheLink() {
        let appModel = AppModel()
        let ids = ExperimentCatalog
            .experiments(for: EMWorldModule.id, appModel: appModel)
            .map(\.experiment.id)
        XCTAssertTrue(ids.contains("circuits.charged"), "bench experiments survive")
        XCTAssertTrue(ids.contains("magnetism.snap"), "field experiments survive")
        XCTAssertTrue(ids.contains("em.reach"), "and the link gets its own")
    }

    /// Pause is a freeze-EVERYTHING orb: it must not leave one bench
    /// running while the other is stopped.
    func testPauseFreezesBothBenches() {
        let appModel = AppModel()
        guard let world = ModuleCatalog.all(appModel: appModel)
            .first(where: { $0.id == EMWorldModule.id }) else {
            return XCTFail("the E&M world should be in the catalog")
        }
        appModel.circuitsModel.isPaused = false
        appModel.magnetismModel.isPaused = false
        XCTAssertFalse(world.isPaused())

        world.togglePause()
        XCTAssertTrue(appModel.circuitsModel.isPaused)
        XCTAssertTrue(appModel.magnetismModel.isPaused)
        XCTAssertTrue(world.isPaused())

        world.togglePause()
        XCTAssertFalse(appModel.circuitsModel.isPaused)
        XCTAssertFalse(appModel.magnetismModel.isPaused)
    }
}
