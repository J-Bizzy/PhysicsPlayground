//
//  LabMoreTests.swift
//  PhysicsPlaygroundTests
//
//  More is the fallback for everything that is not the apparatus. These
//  hold what it promises: every lab says something there, its numbers
//  read what the room is doing, nothing it offers is offered twice, every
//  item stands in one place by kind, a dependent shows exactly while its
//  switch is on (2026-11-04), and the room's own chrome — Move, Deep
//  space, dimming, Reset — is the same in every lab.
//

import XCTest
@testable import PhysicsPlayground

@MainActor
final class LabMoreTests: XCTestCase {

    /// Every lab has live numbers to show.
    func testEveryLabHasValues() {
        let appModel = AppModel()
        for module in ModuleCatalog.all(appModel: appModel) {
            XCTAssertFalse(module.readings().isEmpty, "\(module.id) has no values for More")
        }
    }

    /// A control offered twice is a control that can disagree with
    /// itself: ids are unique across a lab's More and its sliders.
    func testNothingInMoreIsOfferedTwice() {
        let appModel = AppModel()
        for module in ModuleCatalog.all(appModel: appModel) {
            let ids = module.more.everyItem.map(\.id) + module.adjustables.map(\.id)
            XCTAssertEqual(Set(ids).count, ids.count,
                           "\(module.id) offers something twice in More")
        }
    }

    /// A slider writes inside its range, whatever it is handed.
    func testEverySliderClampsToItsRange() {
        let appModel = AppModel()
        for module in ModuleCatalog.all(appModel: appModel) {
            let inMore = module.more.everyItem.compactMap { item -> PhysicsAdjustable? in
                if case .slider(let adjustable, _) = item { adjustable } else { nil }
            }
            for adjustable in module.adjustables + inMore {
                let before = adjustable.read()
                adjustable.write(adjustable.range.upperBound * 10 + 10)
                XCTAssertLessThanOrEqual(adjustable.read(), adjustable.range.upperBound + 1e-9,
                                         "\(module.id).\(adjustable.id) ran past its top")
                adjustable.write(before)
            }
        }
    }

    /// Electric Fields' numbers carry the test charge's own physics while
    /// one is in the room, and not before.
    func testFieldValuesCarryTheTestChargeWhileOneIsOut() {
        let appModel = AppModel()
        let module = ModuleCatalog.descriptor(id: "electrostatics", appModel: appModel)!
        XCTAssertFalse(module.readings().contains { $0.name == "E at charge" })
        appModel.electromagnetismModel.dropProbe()
        let rows = module.readings()
        for name in ["Test charge q", "E at charge", "Potential", "Electric force", "Speed"] {
            XCTAssertTrue(rows.contains { $0.name == name }, "missing \(name)")
        }
    }

    /// Circuit Workshop's values stay a list you can read: the bench and
    /// the selected part, not every part on the bench.
    func testCircuitsValuesStayReadable() {
        let appModel = AppModel()
        let module = ModuleCatalog.descriptor(id: "circuits", appModel: appModel)!
        XCTAssertLessThanOrEqual(module.readings().count, 2 + 2 * 3)
    }

    // MARK: Greyed, and why (2026-11-02)

    /// A gate's reason is there exactly while it greys its control.
    func testAGateSaysWhyExactlyWhileItGreys() {
        var open = true
        let gate = MoreItem.Availability.when({ open }, else: "Needs the compass")
        XCTAssertTrue(gate())
        XCTAssertNil(gate.reason())
        open = false
        XCTAssertFalse(gate())
        XCTAssertEqual(gate.reason(), "Needs the compass")
        XCTAssertNil(MoreItem.Availability.always.reason())
    }

    private func item(_ id: String, in module: String, _ appModel: AppModel) throws -> MoreItem {
        let descriptor = try XCTUnwrap(ModuleCatalog.descriptor(id: module, appModel: appModel))
        return try XCTUnwrap(descriptor.more.item(id), "\(module) has no \(id)")
    }

    /// What waits on the room, a ball or an empty bench is greyed and says
    /// why, and says nothing once it arrives.
    func testAGreyedControlNamesWhatItWaitsFor() throws {
        let appModel = AppModel()
        let kinematics = appModel.kinematicsModel
        kinematics.kind = .golfBall
        XCTAssertEqual(try item("customMass", in: "kinematics", appModel).unavailableReason,
                       "For the custom ball")
        kinematics.kind = .custom
        XCTAssertNil(try item("customMass", in: "kinematics", appModel).unavailableReason)

        let circuits = appModel.circuitsModel
        circuits.clearBench()
        XCTAssertEqual(try item("clear", in: "circuits", appModel).unavailableReason,
                       "The bench is empty")
    }

    // MARK: Hidden until on (2026-11-04)

    /// A control that only means something after a switch in More stands
    /// under that switch, is shown exactly while it is on, and is never
    /// greyed — the switch above it is the reason.
    func testADependentIsHiddenUntilItsSwitchIsOn() throws {
        let appModel = AppModel()
        let fields = appModel.electromagnetismModel
        let magnets = appModel.magnetismModel
        let kinematics = appModel.kinematicsModel
        let circuits = appModel.circuitsModel
        let cases: [(module: String, lead: String, dependents: [String], set: (Bool) -> Void)] = [
            ("electrostatics", "plates", ["plateVoltage", "deflect"], { fields.capacitorOn = $0 }),
            ("electrostatics", "bfield", ["uniformB"], { fields.magneticFieldOn = $0 }),
            ("magnetism", "handCompass", ["earth"], { magnets.compassOn = $0 }),
            ("kinematics", "air", ["wind"], { kinematics.airResistance = $0 }),
            ("circuits", "flow", ["truespeed"], { circuits.showElectronFlow = $0 }),
        ]
        for entry in cases {
            let descriptor = try XCTUnwrap(ModuleCatalog.descriptor(id: entry.module, appModel: appModel))
            let group = try XCTUnwrap(descriptor.more.first { $0.id == entry.lead },
                                      "\(entry.module) has no \(entry.lead) at the top level")
            guard case let .group(lead, reveals, items) = group else {
                XCTFail("\(entry.module).\(entry.lead) reveals nothing"); continue
            }
            guard case .toggle = lead else {
                XCTFail("\(entry.module).\(entry.lead) leads with something other than a switch"); continue
            }
            XCTAssertEqual(items.map(\.id), entry.dependents, "\(entry.module).\(entry.lead)")
            entry.set(false)
            XCTAssertFalse(reveals(), "\(entry.module).\(entry.lead) shows its controls while off")
            entry.set(true)
            XCTAssertTrue(reveals(), "\(entry.module).\(entry.lead) hides its controls while on")
            for item in items {
                XCTAssertNil(item.unavailableReason,
                             "\(entry.module).\(item.id) is greyed as well as hidden")
            }
        }
    }

    /// A coupled pair's spring is set under the verb that hangs it, once
    /// there is one.
    func testTheSpringStandsUnderTheCoupledPair() throws {
        let appModel = AppModel()
        let model = appModel.pendulumsModel
        let descriptor = try XCTUnwrap(ModuleCatalog.descriptor(id: "pendulums", appModel: appModel))
        guard case let .group(lead, reveals, items) = try XCTUnwrap(descriptor.more.first { $0.id == "coupledPair" }) else {
            return XCTFail("the coupled pair reveals nothing")
        }
        guard case .action = lead else { return XCTFail("Coupled pair is no longer a verb") }
        XCTAssertEqual(items.map(\.id), ["springStiffness"])
        XCTAssertFalse(reveals(), "the spring shows with no spring hung")
        model.addCoupledPair()
        XCTAssertTrue(reveals())
    }

    // MARK: Where things stand (2026-11-04)

    /// Every lab's More reads in the same order, by kind: choices, tiles,
    /// switches with what they reveal, sliders, verbs, and whatever throws
    /// work away at the foot beside Reset. Nothing is placed twice or lost.
    func testEveryItemStandsInExactlyOneBand() {
        let appModel = AppModel()
        for module in ModuleCatalog.all(appModel: appModel) {
            let layout = MoreLayout(module.more, adjustables: module.adjustables)
            let placed = layout.bands.flatMap { $0 }.map(\.id)
            XCTAssertEqual(placed.sorted(),
                           (module.more.map(\.id) + module.adjustables.map(\.id)).sorted(),
                           "\(module.id) loses or doubles an item in More's layout")
            for item in layout.foot {
                guard case let .action(_, _, _, confirms, destructive, _, _) = item else {
                    XCTFail("\(module.id).\(item.id) is at the foot but is not a verb"); continue
                }
                XCTAssertTrue(destructive && confirms,
                              "\(module.id).\(item.id) throws work away without arming")
            }
            for item in layout.tiles {
                guard case .toggle = item else {
                    XCTFail("\(module.id).\(item.id) is a tile but not a switch"); continue
                }
            }
        }
    }

    /// The menus replaced grids, not choices: every world and every
    /// authored circuit is still one choice away.
    func testTheMenusHoldEveryChoice() throws {
        let appModel = AppModel()
        let orbits = try XCTUnwrap(ModuleCatalog.descriptor(id: "gravitylab", appModel: appModel))
        guard case let .verbs(_, _, worlds, _, _, _) = try XCTUnwrap(orbits.more.item("worlds")) else {
            return XCTFail("Add a world is not a menu")
        }
        XCTAssertEqual(worlds.map(\.id), OrbitalMechanicsModel.Preset.allCases.map(\.id))

        let circuits = try XCTUnwrap(ModuleCatalog.descriptor(id: "circuits", appModel: appModel))
        guard case let .verbs(_, _, presets, note, _, run) = try XCTUnwrap(circuits.more.item("presets")) else {
            return XCTFail("Load a circuit is not a menu")
        }
        XCTAssertEqual(presets.map(\.id), CircuitsModel.Preset.allCases.map(\.rawValue))
        XCTAssertNotNil(note, "the menu that replaces the bench does not say so")
        let model = appModel.circuitsModel
        model.clearBench()
        run(CircuitsModel.Preset.allCases[0].rawValue)
        XCTAssertFalse(model.components.isEmpty, "choosing a circuit loaded nothing")
    }

    /// Twin suns names the one thing in its way: room in the system, then
    /// a single Sun to split.
    func testTwinSunsSaysWhichThingIsMissing() throws {
        let appModel = AppModel()
        let orbits = appModel.orbitalMechanicsModel
        XCTAssertNil(try item("binary", in: "gravitylab", appModel).unavailableReason)
        orbits.makeBinary()
        XCTAssertEqual(try item("binary", in: "gravitylab", appModel).unavailableReason,
                       "Needs a single Sun")
    }

    /// The room's dimming is one number, set by More's slider, clamped.
    func testTheDimmingSliderSetsTheRoom() {
        let appModel = AppModel()
        appModel.setDimming(0.7)
        XCTAssertEqual(appModel.roomDimming, 0.7, accuracy: 1e-12)
        appModel.setDimming(3)
        XCTAssertEqual(appModel.roomDimming, 1)
        appModel.setDimming(-1)
        XCTAssertEqual(appModel.roomDimming, 0)
    }
}
