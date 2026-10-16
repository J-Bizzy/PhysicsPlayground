//
//  LabMoreTests.swift
//  PhysicsPlaygroundTests
//
//  More is the fallback for everything that is not the apparatus. These
//  hold what it promises: every lab says something there, its numbers
//  read what the room is doing, nothing it offers is offered twice, and
//  the room's own chrome — Move, Studio, dimming, Reset — is the same in
//  every lab.
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
            let ids = module.more.map(\.id) + module.adjustables.map(\.id)
            XCTAssertEqual(Set(ids).count, ids.count,
                           "\(module.id) offers something twice in More")
        }
    }

    /// A slider writes inside its range, whatever it is handed.
    func testEverySliderClampsToItsRange() {
        let appModel = AppModel()
        for module in ModuleCatalog.all(appModel: appModel) {
            let inMore = module.more.compactMap { item -> PhysicsAdjustable? in
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
