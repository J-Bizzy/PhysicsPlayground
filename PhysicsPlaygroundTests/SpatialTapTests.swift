//
//  SpatialTapTests.swift
//  PhysicsPlaygroundTests
//
//  The two shared controls whose `handleTap` nothing had ever called.
//
//  THIS FILE EXISTS BECAUSE OF A NAME THAT DIDN'T. `CLAUDE.md`,
//  `docs/ON_DEVICE_TESTS.md` and `DECISIONS.md` all cited a
//  `StationTapTests` as the thing that replaced the XCUITest reach the
//  no-panels decision gave up — "`handleTap` called directly against
//  real entities" — and no such file was ever in the repository. The
//  name is from the merged-worlds era (stations), which was undone on
//  2026-07-30; the pattern survived the undo and the name did not.
//
//  The pattern is real and is carried by `SpatialActionBankTests`,
//  `BloomPetalTests` and `MultimeterTests`. But going looking turned up
//  the part that was actually missing: of the four shared types that
//  expose `handleTap(_:) -> Bool`, two had no direct tap test at all —
//  and one of them, `SpatialLayerBank`, is used by ALL SIX MODULES and
//  is the most-tapped object in the app.
//
//  So the docs were wrong about the file and right about the principle,
//  and the honest repair is this file plus a correction to the three
//  documents. See DECISIONS.md, 2026-08-02.
//
//  What is pinned here is the tap CONTRACT the modules rely on, which is
//  identical in both types and is load-bearing in a specific way: every
//  SpaceView calls these in a chain — bank first, then bloom — and
//  forwards the tap onward when the return is `false`. A handler that
//  returned `true` for something it did not own would silently eat a
//  gesture meant for the physics; one that returned `false` for its own
//  plate would let the tap fall through and hit the apparatus behind it.
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

    // MARK: SpatialLayerBank

    /// A three-plate bank, revealed. `handleTap` refuses while `root` is
    /// disabled and reveal eases in over time, so every test has to run
    /// the bank forward first, exactly as the render loop would.
    private func makeBank(_ log: Log) -> SpatialLayerBank {
        log.state = ["lines": true, "grid": false, "field": false]
        let bank = SpatialLayerBank(
            accent: .white,
            layers: ["lines", "grid", "field"].map { id in
                LayerSwitch(id: id, label: id.capitalized,
                            isOn: { log.state[id] ?? false },
                            toggle: {
                                log.toggled.append(id)
                                log.state[id] = !(log.state[id] ?? false)
                            })
            })
        for _ in 0..<40 {
            bank.update(anchor: .zero, viewer: [0, 0, 1], dt: 1.0 / 90.0)
        }
        return bank
    }

    private func plate(_ bank: SpatialLayerBank, _ id: String) throws -> Entity {
        try XCTUnwrap(bank.root.children.first { $0.name == "layer-\(id)" },
                      "No plate was built for \(id).")
    }

    /// One press, one toggle. A duplicated handler or a chain that failed
    /// to stop at the first match would flip the layer twice and leave it
    /// exactly where it started — the failure mode that looks like a dead
    /// control rather than a broken one.
    func testATapFlipsExactlyOneLayerOnce() throws {
        let log = Log()
        let bank = makeBank(log)

        XCTAssertTrue(bank.handleTap(try plate(bank, "grid")))

        XCTAssertEqual(log.toggled, ["grid"])
        XCTAssertEqual(log.state["grid"], true)
        XCTAssertEqual(log.state["lines"], true, "A tap must not disturb its neighbours.")
        XCTAssertEqual(log.state["field"], false)
    }

    /// The plate carries a label as a child entity, and a pinch ray can
    /// land on the label rather than the plate. The walk up the parent
    /// chain is what makes the whole plate tappable rather than just the
    /// slab underneath its text.
    func testATapOnAPlatesLabelStillFlipsThePlate() throws {
        let log = Log()
        let bank = makeBank(log)
        let target = try plate(bank, "lines")
        let child = try XCTUnwrap(target.children.first,
                                  "A plate should carry its label as a child.")

        XCTAssertTrue(bank.handleTap(child))
        XCTAssertEqual(log.toggled, ["lines"])
    }

    /// **The forwarding contract.** Every SpaceView reads this return
    /// value to decide whether to keep routing the gesture. Claiming a
    /// tap it does not own is how a switch bank eats a pinch aimed at the
    /// apparatus standing behind it.
    func testTheBankRefusesTapsItDoesNotOwn() throws {
        let log = Log()
        let bank = makeBank(log)

        XCTAssertFalse(bank.handleTap(Entity()),
                       "An unrelated entity must fall through.")
        XCTAssertFalse(bank.handleTap(bank.root),
                       "The root is not a plate; the walk must stop there.")
        XCTAssertTrue(log.toggled.isEmpty)
    }

    /// A bank that has not been revealed yet must not answer. This is the
    /// `SpatialTrackControl.isEnabled` lesson in the other shape: a
    /// control that is not on screen must not still be writing to the
    /// model.
    ///
    /// **THE PLATES HAVE TO STILL BE THERE FOR THIS TO TEST ANYTHING.**
    /// The first version of this test called `setLayers([])` to hide the
    /// bank, which also removes every plate — so the walk found no match
    /// and returned `false` for the wrong reason. Deleting
    /// `guard root.isEnabled` from the primitive left it passing. It is
    /// written against a bank that is fully built and simply has not been
    /// revealed yet, which is the real state: `init` disables `root`, and
    /// only `update` brings it up.
    func testABankThatHasNotBeenRevealedIsDeaf() throws {
        let log = Log()
        log.state = ["grid": false]
        let bank = SpatialLayerBank(
            accent: .white,
            layers: [LayerSwitch(id: "grid", label: "Grid",
                                 isOn: { log.state["grid"] ?? false },
                                 toggle: { log.toggled.append("grid") })])
        // Deliberately NO update() — the bank is built but unrevealed.
        XCTAssertFalse(bank.root.isEnabled, "Precondition: the bank starts hidden.")

        let target = try plate(bank, "grid")
        XCTAssertFalse(bank.handleTap(target),
                       "An unrevealed bank must not claim the tap.")
        XCTAssertTrue(log.toggled.isEmpty,
                      "An unrevealed bank must not write to the model.")
    }

    /// The plate is a READOUT as much as a control: it reads `isOn` every
    /// frame rather than remembering the last tap, so a model change from
    /// anywhere — a reset, a launch argument, another control — has to
    /// show up on the lamp. This is the property the six reset defects
    /// were all violations of, pinned at the primitive.
    func testThePlateFollowsTheModelRatherThanTheLastTap() throws {
        let log = Log()
        let bank = makeBank(log)

        XCTAssertTrue(bank.handleTap(try plate(bank, "grid")))
        XCTAssertEqual(log.state["grid"], true)

        // Something other than a tap moves the model — a reset would.
        log.state["grid"] = false
        bank.update(anchor: .zero, viewer: [0, 0, 1], dt: 1.0 / 90.0)

        // The next tap must act on the model's value, not a cached one:
        // if the bank had remembered "on", this would turn it off.
        XCTAssertTrue(bank.handleTap(try plate(bank, "grid")))
        XCTAssertEqual(log.state["grid"], true,
                       "The plate must toggle from what the model says now.")
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

    /// Same parent-chain walk as the bank: a disc carries its label and
    /// its icon as children, and both are in front of the disc itself.
    func testATapOnADiscsLabelStillChoosesIt() throws {
        let log = Log()
        let picker = makePicker(log)
        let target = try disc(picker, "jupiter")
        let child = try XCTUnwrap(target.children.first,
                                  "A disc should carry its label as a child.")

        XCTAssertTrue(picker.handleTap(child))
        XCTAssertEqual(log.selected, ["jupiter"])
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
