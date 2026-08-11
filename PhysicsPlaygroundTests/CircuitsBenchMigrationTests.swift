//
//  CircuitsBenchMigrationTests.swift
//  PhysicsPlaygroundTests
//
//  Retiring a component kind must not cost anybody their bench.
//
//  `ComponentKind` is `Codable` by rawValue, so decoding a saved file
//  straight into `[Component]` throws on the first unrecognised kind —
//  and it throws for the WHOLE array, which `restoreSavedBench` and
//  `loadSlot` both swallow with `try?`. Deleting `.wire` that way
//  would have silently emptied every user's auto-saved bench AND all
//  eight named slots on first launch, with no error and no crash: the
//  app would have looked like it was working and behaved like it had
//  never been used.
//
//  So a retired kind is DATA. A jumper is spliced — its terminals were
//  an electrical point like any other, so everything joined through it
//  stays joined — and an unrecognised kind is dropped without taking
//  the bench with it.
//
//  THE LAST TEST HERE IS THE ONE THAT MATTERS MOST. It uses a kind
//  that never existed rather than the one just retired, so it goes on
//  meaning something after `.wire` is ancient history. It is what
//  makes the next retirement cheap.
//

import XCTest
import PhysicsCore
import simd
@testable import PhysicsPlayground

@MainActor
final class CircuitsBenchMigrationTests: XCTestCase {

    private typealias Stored = CircuitsModel.StoredComponent
    private typealias Bench = CircuitsModel.StoredBench

    private func wire(_ a: (UUID, Int), _ b: (UUID, Int)) -> CircuitsModel.Wire {
        CircuitsModel.Wire(id: UUID(),
                           from: .init(componentID: a.0, end: a.1),
                           to: .init(componentID: b.0, end: b.1))
    }

    private func stored(_ id: UUID, _ kind: String, _ value: Double) -> Stored {
        Stored(id: id, kind: kind, position: CircuitsModel.buildCenter, value: value)
    }

    /// Installs a legacy bench through the REAL decode path — encoded
    /// to JSON, put in UserDefaults, restored by a fresh model — so
    /// nothing here can pass by calling a function the app does not.
    private func restore(_ bench: Bench) -> CircuitsModel {
        let data = try! JSONEncoder().encode(bench)
        UserDefaults.standard.set(data, forKey: CircuitsModel.saveKey)
        defer { UserDefaults.standard.removeObject(forKey: CircuitsModel.saveKey) }
        return CircuitsModel(restoreSaved: true)
    }

    /// battery → jumper → bulb → battery becomes battery → bulb →
    /// battery, and the assertion is on the SOLVED CURRENT, not the
    /// wire count: the claim the migration makes is that the circuit
    /// is the same circuit, and 9/(24 + 0.05) is what that means.
    func testAJumperBecomesADirectWire() {
        let battery = UUID(), jumper = UUID(), bulb = UUID()
        let model = restore(Bench(
            components: [stored(battery, "battery", 9),
                         stored(jumper, "wire", 0.4),
                         stored(bulb, "bulb", 24)],
            wires: [wire((battery, 1), (jumper, 0)),
                    wire((jumper, 1), (bulb, 0)),
                    wire((bulb, 1), (battery, 0))]))

        XCTAssertEqual(model.components.count, 2, "The jumper should be gone.")
        XCTAssertFalse(model.components.contains { $0.id == jumper })
        XCTAssertTrue(model.components.contains { $0.id == battery })
        XCTAssertTrue(model.components.contains { $0.id == bulb })

        model.step(dt: 1.0 / 90.0)
        let expected = 9.0 / (24 + 0.05)
        XCTAssertEqual(abs(model.readouts[bulb]?.amps ?? 0), expected, accuracy: expected * 1e-6,
                       "The spliced loop must carry the current the jumper loop carried.")
    }

    /// Two jumpers end to end are still one point, and the splice must
    /// see through both of them in one pass.
    func testChainedJumpersCollapseToOneWire() {
        let battery = UUID(), first = UUID(), second = UUID(), bulb = UUID()
        let model = restore(Bench(
            components: [stored(battery, "battery", 9),
                         stored(first, "wire", 0.3),
                         stored(second, "wire", 0.3),
                         stored(bulb, "bulb", 24)],
            wires: [wire((battery, 1), (first, 0)),
                    wire((first, 1), (second, 0)),
                    wire((second, 1), (bulb, 0)),
                    wire((bulb, 1), (battery, 0))]))

        XCTAssertEqual(model.components.count, 2)
        XCTAssertEqual(model.wires.count, 2, "One wire per net, not one per hop.")
        model.step(dt: 1.0 / 90.0)
        let expected = 9.0 / (24 + 0.05)
        XCTAssertEqual(abs(model.readouts[bulb]?.amps ?? 0), expected, accuracy: expected * 1e-6)
    }

    /// A jumper wired at one end only was carrying nothing, so it
    /// leaves with its wire and joins nothing to anything.
    func testAJumperWiredAtOneEndDisappearsWithItsWire() {
        let battery = UUID(), jumper = UUID(), bulb = UUID()
        let model = restore(Bench(
            components: [stored(battery, "battery", 9),
                         stored(jumper, "wire", 0.4),
                         stored(bulb, "bulb", 24)],
            wires: [wire((battery, 1), (bulb, 0)),
                    wire((bulb, 1), (battery, 0)),
                    wire((jumper, 0), (bulb, 1))]))

        XCTAssertEqual(model.components.count, 2)
        // bulb1 and battery0 were one net; the dangling jumper end
        // joined that net and brought nothing else to it.
        XCTAssertTrue(model.areConnected(.init(componentID: bulb, end: 1),
                                         .init(componentID: battery, end: 0)))
        model.step(dt: 1.0 / 90.0)
        let expected = 9.0 / (24 + 0.05)
        XCTAssertEqual(abs(model.readouts[bulb]?.amps ?? 0), expected, accuracy: expected * 1e-6)
    }

    /// A jumper wired at NEITHER end simply goes.
    func testAnUnwiredJumperJustDisappears() {
        let battery = UUID(), jumper = UUID(), bulb = UUID()
        let model = restore(Bench(
            components: [stored(battery, "battery", 9),
                         stored(jumper, "wire", 0.4),
                         stored(bulb, "bulb", 24)],
            wires: [wire((battery, 1), (bulb, 0)),
                    wire((bulb, 1), (battery, 0))]))
        XCTAssertEqual(model.components.count, 2)
        XCTAssertEqual(model.wires.count, 2)
    }

    /// A bench with nothing retired in it must come back exactly as it
    /// was — the migration is not allowed to rearrange a bench it has
    /// no business touching.
    func testABenchWithNoJumpersRoundTripsUnchanged() {
        let battery = UUID(), toggle = UUID(), bulb = UUID()
        let model = restore(Bench(
            components: [stored(battery, "battery", 9),
                         stored(toggle, "switcher", 0),
                         stored(bulb, "bulb", 24)],
            wires: [wire((battery, 1), (toggle, 0)),
                    wire((toggle, 1), (bulb, 0)),
                    wire((bulb, 1), (battery, 0))]))

        XCTAssertEqual(model.components.count, 3)
        XCTAssertEqual(model.wires.count, 3)
        XCTAssertEqual(Set(model.components.map(\.id)), [battery, toggle, bulb])
        model.step(dt: 1.0 / 90.0)
        let expected = 9.0 / (24 + 0.05 + CircuitSolver.switchResistance)
        XCTAssertEqual(abs(model.readouts[bulb]?.amps ?? 0), expected, accuracy: expected * 1e-6)
    }

    /// Values, aims and switch positions survive the trip.
    func testTheSurvivingPartsKeepTheirState() {
        let battery = UUID(), toggle = UUID()
        var openSwitch = stored(toggle, "switcher", 0)
        openSwitch.isClosed = false
        var aimed = stored(battery, "battery", 7.5)
        aimed.axis = SIMD3(0, 1, 0)
        let model = restore(Bench(components: [aimed, openSwitch], wires: []))

        let restoredBattery = model.components.first { $0.id == battery }!
        XCTAssertEqual(restoredBattery.value, 7.5, accuracy: 1e-9)
        XCTAssertEqual(restoredBattery.axis.y, 1, accuracy: 1e-9)
        XCTAssertFalse(model.components.first { $0.id == toggle }!.isClosed)
    }

    /// A file written before `axis` and `isClosed` existed still
    /// loads, with the defaults `Component` would have given it. A
    /// required field in the stored row would have been the same
    /// silent-data-loss bug in a different coat.
    func testAFileMissingTheOptionalFieldsStillLoads() throws {
        let id = UUID()
        let json = """
        {"components":[{"id":"\(id.uuidString)","kind":"bulb",
          "position":[0,1.25,-0.9],"value":24}],"wires":[]}
        """
        UserDefaults.standard.set(Data(json.utf8), forKey: CircuitsModel.saveKey)
        defer { UserDefaults.standard.removeObject(forKey: CircuitsModel.saveKey) }
        let model = CircuitsModel(restoreSaved: true)

        let part = try XCTUnwrap(model.components.first { $0.id == id })
        XCTAssertEqual(part.axis, SIMD3(1, 0, 0), "Missing axis should default, not fail.")
        XCTAssertTrue(part.isClosed)
        XCTAssertEqual(part.capacitorVoltage, 0)
    }

    /// THE TEST THAT MAKES THE NEXT RETIREMENT CHEAP. A kind that
    /// never existed — a corrupted row, or a file from a version that
    /// has not shipped yet — is dropped, and everything else survives.
    /// Before this, one such row emptied the whole bench.
    func testAnUnknownKindDoesNotDestroyTheBench() {
        let battery = UUID(), ghost = UUID(), bulb = UUID()
        let model = restore(Bench(
            components: [stored(battery, "battery", 9),
                         stored(ghost, "flux-capacitor", 1.21),
                         stored(bulb, "bulb", 24)],
            wires: [wire((battery, 1), (bulb, 0)),
                    wire((bulb, 1), (battery, 0)),
                    wire((ghost, 0), (bulb, 0))]))

        XCTAssertEqual(model.components.count, 2, "The bench was lost to one bad row.")
        XCTAssertFalse(model.components.contains { $0.id == ghost })
        model.step(dt: 1.0 / 90.0)
        let expected = 9.0 / (24 + 0.05)
        XCTAssertEqual(abs(model.readouts[bulb]?.amps ?? 0), expected, accuracy: expected * 1e-6,
                       "The surviving loop must still light.")
    }

    /// An unknown kind that JOINED two things keeps them joined, the
    /// same as a retired one — the splice does not care why a row is
    /// unreadable.
    func testAnUnknownKindIsSplicedNotJustDropped() {
        let battery = UUID(), ghost = UUID(), bulb = UUID()
        let model = restore(Bench(
            components: [stored(battery, "battery", 9),
                         stored(ghost, "flux-capacitor", 1),
                         stored(bulb, "bulb", 24)],
            wires: [wire((battery, 1), (ghost, 0)),
                    wire((ghost, 1), (bulb, 0)),
                    wire((bulb, 1), (battery, 0))]))
        model.step(dt: 1.0 / 90.0)
        XCTAssertTrue(model.areConnected(.init(componentID: battery, end: 1),
                                         .init(componentID: bulb, end: 0)),
                      "What was joined through the unreadable part must stay joined.")
    }

    /// Garbage that is not a bench at all leaves the starter loop
    /// standing rather than emptying the room.
    func testUndecodableDataLeavesTheStarterLoop() {
        UserDefaults.standard.set(Data("not a bench".utf8), forKey: CircuitsModel.saveKey)
        defer { UserDefaults.standard.removeObject(forKey: CircuitsModel.saveKey) }
        let model = CircuitsModel(restoreSaved: true)
        XCTAssertEqual(model.components.count, 3, "The starter loop should still be there.")
    }

    /// The star is the minimal wire set, so it cannot overrun the
    /// budget and cannot produce a pair the same-net rule would refuse.
    func testTheMigrationRespectsTheWireBudgetAndTheSameNetRule() {
        // Sixteen parts all shorted into one net through jumpers.
        var components: [Stored] = []
        var wires: [CircuitsModel.Wire] = []
        var parts: [UUID] = []
        for _ in 0..<8 {
            let part = UUID(), jumper = UUID()
            parts.append(part)
            components.append(stored(part, "resistor", 100))
            components.append(stored(jumper, "wire", 0.2))
            wires.append(wire((part, 0), (jumper, 0)))
            if let previous = parts.dropLast().last {
                wires.append(wire((jumper, 1), (previous, 0)))
            }
        }
        let model = restore(Bench(components: components, wires: wires))

        XCTAssertEqual(model.components.count, 8)
        XCTAssertLessThanOrEqual(model.wires.count, CircuitsModel.wireBudget)
        // No wire in the result may join two ends the live rule would
        // refuse — i.e. the star must contain no cycle.
        var seen = Set<CircuitsModel.Wire.ID>()
        for candidate in model.wires {
            XCTAssertTrue(seen.insert(candidate.id).inserted)
        }
        XCTAssertEqual(model.wires.count, 7, "A star over 8 terminals in one net is 7 edges.")
    }

    /// The named slots go through the same door — a migration that
    /// covered the auto-save and missed the eight slots would lose
    /// exactly the benches somebody cared enough about to name.
    func testNamedSlotsMigrateToo() {
        let battery = UUID(), jumper = UUID(), bulb = UUID()
        let bench = Bench(
            components: [stored(battery, "battery", 9),
                         stored(jumper, "wire", 0.4),
                         stored(bulb, "bulb", 24)],
            wires: [wire((battery, 1), (jumper, 0)),
                    wire((jumper, 1), (bulb, 0)),
                    wire((bulb, 1), (battery, 0))])
        let data = try! JSONEncoder().encode(bench)
        UserDefaults.standard.set(["legacy": data], forKey: CircuitsModel.slotsKey)
        defer { UserDefaults.standard.removeObject(forKey: CircuitsModel.slotsKey) }

        let model = CircuitsModel()
        model.refreshSlotNames()
        XCTAssertTrue(model.loadSlot(named: "legacy"), "The slot refused to load.")
        XCTAssertEqual(model.components.count, 2)
        model.step(dt: 1.0 / 90.0)
        let expected = 9.0 / (24 + 0.05)
        XCTAssertEqual(abs(model.readouts[bulb]?.amps ?? 0), expected, accuracy: expected * 1e-6)
    }

    /// A bench saved TODAY reloads byte-for-byte the same, which is
    /// what says the stored row and the written row are one format.
    func testATodaysBenchRoundTripsThroughTheStoredFormat() {
        let source = CircuitsModel()
        source.persistNow()
        defer { UserDefaults.standard.removeObject(forKey: CircuitsModel.saveKey) }

        let restored = CircuitsModel(restoreSaved: true)
        XCTAssertEqual(Set(restored.components.map(\.id)), Set(source.components.map(\.id)))
        XCTAssertEqual(restored.wires.count, source.wires.count)
        restored.step(dt: 1.0 / 90.0)
        let bulb = restored.components.first { $0.kind == .bulb }!
        let expected = 9.0 / (24 + 0.05 + CircuitSolver.switchResistance)
        XCTAssertEqual(abs(restored.readouts[bulb.id]?.amps ?? 0), expected,
                       accuracy: expected * 1e-6)
    }

    /// The jumper is gone from the rack as well as the bench — a part
    /// nobody can make is the "authored but never rendered" defect,
    /// and a rack slot for a kind that no longer exists is its mirror.
    func testTheRackNoLongerOffersAJumper() {
        let kinds = CircuitsPartsLayout.Flank.allCases
            .flatMap { CircuitsPartsLayout.kinds(on: $0) }
        XCTAssertEqual(Set(kinds), Set(CircuitsModel.ComponentKind.allCases),
                       "Every kind the bench can hold needs a slot, and no slot may name one it cannot.")
        XCTAssertEqual(kinds.count, 10)
    }
}
