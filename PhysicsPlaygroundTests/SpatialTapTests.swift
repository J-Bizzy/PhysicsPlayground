//
//  SpatialTapTests.swift
//  PhysicsPlaygroundTests
//
//  The tap contract of `SpatialPicker`, which Projectiles' ball and arc
//  fans rely on: the handlers are called in a chain and the
//  tap is forwarded when the return is `false`. A handler that returned
//  `true` for something it did not own would eat a gesture meant for
//  the physics; one that returned `false` for its own plate would let
//  the tap hit the apparatus behind it.
//

import XCTest
import RealityKit
import RenderKit
@testable import PhysicsPlayground

@MainActor
final class SpatialTapTests: XCTestCase {

    /// Records what a control was asked to do.
    final class Log {
        var toggled: [String] = []
        var selected: [String] = []
        var state: [String: Bool] = [:]
    }

    // MARK: SpatialPicker

    private func makePicker(_ log: Log, staysOpen: Bool = true) -> SpatialPicker {
        let picker = SpatialPicker(
            accessibilityNoun: "World",
            choices: ["earth", "moon", "jupiter"].map {
                PickerChoice(id: $0, label: $0.capitalized)
            },
            staysOpen: staysOpen)
        picker.onSelect = { log.selected.append($0) }
        if !staysOpen { picker.open() }
        for _ in 0..<40 {
            picker.update(anchor: .zero, viewer: [0, 0, 1], dt: 1.0 / 90.0)
        }
        return picker
    }

    private func disc(_ picker: SpatialPicker, _ id: String) throws -> Entity {
        try XCTUnwrap(picker.root.children.first { $0.name == "picker-\(id)" },
                      "No disc was built for \(id).")
    }

    func testATapChoosesExactlyOneDisc() throws {
        let log = Log()
        let picker = makePicker(log)

        XCTAssertTrue(picker.handleTap(try disc(picker, "moon")))
        XCTAssertEqual(log.selected, ["moon"])
    }

    /// A choice's name is inside its own glass: one target, no hole.
    func testAChoiceIsOneTargetWithItsNameInside() throws {
        let log = Log()
        let picker = makePicker(log)
        let target = try disc(picker, "moon")
        XCTAssertTrue(target.children.isEmpty)
        XCTAssertTrue(picker.handleTap(target))
        XCTAssertEqual(log.selected, ["moon"])
    }

    func testThePickerRefusesTapsItDoesNotOwn() throws {
        let log = Log()
        let picker = makePicker(log)

        XCTAssertFalse(picker.handleTap(Entity()))
        XCTAssertFalse(picker.handleTap(picker.root))
        XCTAssertTrue(log.selected.isEmpty)
    }

    /// A momentary fan folds itself on choosing, so the caller does not
    /// have to remember to — which is the whole difference between the
    /// fan and the standing bank.
    func testAMomentaryFanFoldsItselfAndAStandingBankDoesNot() throws {
        let folding = makePicker(Log(), staysOpen: false)
        XCTAssertTrue(folding.isOpen)
        XCTAssertTrue(folding.handleTap(try disc(folding, "earth")))
        XCTAssertFalse(folding.isOpen, "A momentary fan must fold on choosing.")

        let standing = makePicker(Log(), staysOpen: true)
        XCTAssertTrue(standing.handleTap(try disc(standing, "earth")))
        XCTAssertTrue(standing.isOpen,
                      "A standing bank is a readout and must stay up.")
    }

    /// Closed means deaf, for the same reason a hidden bank is.
    func testAFoldedPickerIsDeaf() throws {
        let log = Log()
        let picker = makePicker(log, staysOpen: false)
        let target = try disc(picker, "moon")

        picker.close()
        for _ in 0..<40 {
            picker.update(anchor: .zero, viewer: [0, 0, 1], dt: 1.0 / 90.0)
        }

        XCTAssertFalse(picker.handleTap(target))
        XCTAssertTrue(log.selected.isEmpty)
    }
}
