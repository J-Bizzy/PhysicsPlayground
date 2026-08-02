//
//  SpatialActionBankTests.swift
//  PhysicsPlaygroundTests
//
//  Written BEFORE the primitive's first caller, deliberately.
//
//  `SpatialTrackControl` sat in the tree for days with no shipping call
//  site, and the day it got one it turned out to be carrying three real
//  defects — a 29 cm collider on a 1 cm rail, no enabled state, and no
//  accessibility value. An unused primitive is not a working primitive,
//  and the cost of finding out is paid by whoever adopts it first. This
//  file is that cost, paid up front.
//
//  It builds real `Entity` objects and calls `handleTap` directly, which
//  is the only kind of interaction testing available in this project —
//  no automation can synthesise a pinch, and XCUITest has no API for a
//  RealityKit entity at all (`docs/ON_DEVICE_TESTS.md`).
//

import XCTest
import RealityKit
import RenderKit
@testable import PhysicsPlayground

@MainActor
final class SpatialActionBankTests: XCTestCase {

    /// Counts how many times an action actually fired.
    final class Counter {
        var count = 0
        var available = true
    }

    /// A bank, revealed. `handleTap` refuses while `root` is disabled, and
    /// reveal eases in over time — so every test has to open the bank
    /// first, exactly as a frame of the render loop would.
    private func makeBank(confirms: Bool = false,
                          counter: Counter = Counter())
    -> (SpatialActionBank, Counter) {
        let bank = SpatialActionBank(
            accent: .white,
            actions: [
                .init(id: "clear", label: "Clear", symbol: "trash.slash",
                      isAvailable: { counter.available },
                      confirms: confirms,
                      fire: { counter.count += 1 }),
            ])
        open(bank)
        return (bank, counter)
    }

    /// Run the bank forward until it is fully revealed.
    private func open(_ bank: SpatialActionBank) {
        for _ in 0..<20 {
            bank.update(anchor: .zero, viewer: [0, 0, 1], dt: 1.0 / 90.0)
        }
    }

    private func plate(_ bank: SpatialActionBank, _ id: String) throws -> Entity {
        try XCTUnwrap(bank.root.children.first { $0.name == "action-\(id)" },
                      "No plate was built for \(id).")
    }

    // MARK: Firing

    /// The whole point of the control, and the thing a duplicated tap
    /// handler would break: one press, one firing.
    func testATapFiresTheActionExactlyOnce() throws {
        let (bank, counter) = makeBank()

        XCTAssertTrue(bank.handleTap(try plate(bank, "clear")),
                      "The plate did not claim its own tap.")
        XCTAssertEqual(counter.count, 1)
    }

    /// The walk-up contract every station in this app keeps: a pinch ray
    /// lands on whatever child geometry it hit — a lamp, an icon, a
    /// nameplate — and must resolve to the plate that owns it.
    func testATapOnAChildResolvesToItsPlate() throws {
        let (bank, counter) = makeBank()
        let plate = try plate(bank, "clear")
        let child = try XCTUnwrap(plate.children.first,
                                  "The plate should have a lamp to hit.")

        XCTAssertTrue(bank.handleTap(child))
        XCTAssertEqual(counter.count, 1, "A tap on the lamp did not fire the plate.")
    }

    /// A bank must not eat taps meant for the apparatus standing beside it.
    func testATapOnAForeignEntityFiresNothing() throws {
        let (bank, counter) = makeBank()

        XCTAssertFalse(bank.handleTap(Entity()))
        XCTAssertEqual(counter.count, 0)
    }

    /// A folded bank has no plates on screen, so it has no taps to claim.
    /// The case this guards: a tap arriving in the same frame the bank
    /// was switched off.
    func testAFoldedBankClaimsNothing() throws {
        let (bank, counter) = makeBank()
        let plate = try plate(bank, "clear")
        bank.setActions([])

        XCTAssertFalse(bank.handleTap(plate))
        XCTAssertEqual(counter.count, 0)
    }

    // MARK: Availability

    /// The replacement for the panel button's `.disabled`. An unavailable
    /// plate must also NOT consume the tap — a dim plate that swallowed
    /// pinches would be worse than one that isn't there, because the
    /// thing behind it would stop responding for no visible reason.
    func testAnUnavailableActionNeitherFiresNorConsumes() throws {
        let (bank, counter) = makeBank()
        counter.available = false

        XCTAssertFalse(bank.handleTap(try plate(bank, "clear")),
                       "A dim plate consumed a tap it could not act on.")
        XCTAssertEqual(counter.count, 0)
    }

    // MARK: Confirmation

    /// The guard that replaces the window's `confirmationDialog`. Circuit
    /// Workshop's bench survives launches; one stray pinch must not wipe it.
    func testAConfirmingActionArmsFirstAndFiresSecond() throws {
        let (bank, counter) = makeBank(confirms: true)
        let plate = try plate(bank, "clear")

        XCTAssertTrue(bank.handleTap(plate), "Arming must consume the tap.")
        XCTAssertEqual(counter.count, 0, "The first tap fired a destructive action.")
        XCTAssertTrue(bank.isArmed("clear"))

        XCTAssertTrue(bank.handleTap(plate))
        XCTAssertEqual(counter.count, 1, "The second tap did not fire.")
        XCTAssertFalse(bank.isArmed("clear"), "Firing must leave the plate disarmed.")
    }

    /// Arming that outlived the moment would be a trap: a plate armed and
    /// forgotten, then brushed an hour later, is exactly the accident the
    /// confirmation exists to prevent.
    func testAnArmedActionDisarmsItselfAfterTheWindow() throws {
        let (bank, counter) = makeBank(confirms: true)
        let plate = try plate(bank, "clear")

        bank.handleTap(plate)
        XCTAssertTrue(bank.isArmed("clear"))

        // Past the window, a frame at a time, as the render loop does it.
        for _ in 0..<Int(SpatialActionBank.armWindow * 90) + 10 {
            bank.update(anchor: .zero, viewer: [0, 0, 1], dt: 1.0 / 90.0)
        }
        XCTAssertFalse(bank.isArmed("clear"), "The arm window never expired.")

        // And the next tap re-arms rather than firing.
        bank.handleTap(plate)
        XCTAssertEqual(counter.count, 0,
                       "A tap after the window expired fired without confirmation.")
    }

    /// `reset()`'s obligation, and the reason `disarm()` is public.
    ///
    /// Four modules have now shipped a flag that drifted out of `reset()`
    /// and stayed wrong because nothing in the room contradicted it. The
    /// arm timer is this class's only state and it is the same hazard in
    /// a new costume: a Clear plate left armed across a reset is one
    /// stray pinch from wiping the thing the reset just rebuilt.
    func testResettingDisarms() throws {
        let (bank, counter) = makeBank(confirms: true)
        let plate = try plate(bank, "clear")

        bank.handleTap(plate)
        XCTAssertTrue(bank.isArmed("clear"))

        bank.disarm()                    // what a module's reset() must call

        XCTAssertFalse(bank.isArmed("clear"))
        bank.handleTap(plate)
        XCTAssertEqual(counter.count, 0,
                       "After a reset the plate fired on a single tap.")
    }

    /// Rebuilding the bank must not carry an armed plate across.
    func testSettingNewActionsDisarms() throws {
        let (bank, _) = makeBank(confirms: true)
        bank.handleTap(try plate(bank, "clear"))
        XCTAssertTrue(bank.isArmed("clear"))

        bank.setActions([])
        XCTAssertFalse(bank.isArmed("clear"))
    }

    // MARK: The collider — the defect class that has broken modules here

    /// The rule from the `SpatialScaleHandle` ban (DECISIONS, 2026-07-29):
    /// an input-targetable collider must be no larger than the thing it
    /// represents. These plates hang beside apparatus, and one oversized
    /// box would shield whatever it stands next to from every pinch.
    func testTheColliderIsNoBiggerThanThePlate() throws {
        let (bank, _) = makeBank()
        let plate = try plate(bank, "clear")
        let collision = try XCTUnwrap(plate.components[CollisionComponent.self],
                                      "The plate must be pressable.")
        let extents = collision.shapes[0].bounds.extents

        XCTAssertLessThan(extents.x, 0.10, "Wider than the plate it represents.")
        XCTAssertLessThan(extents.y, 0.07, "Taller than the plate it represents.")
        XCTAssertLessThan(extents.z, 0.03,
                          "Deep enough to sit between a hand and the apparatus behind it.")
    }

    // MARK: Accessibility

    /// A plate replaces a `Button`, and a button already speaks its name.
    /// The ARMED state has to speak too: a plate one tap from wiping a
    /// bench and a plate two taps from it must not read the same to
    /// someone who cannot see it light up.
    func testVoiceOverIsToldTheArmedState() throws {
        let (bank, _) = makeBank(confirms: true)
        let plate = try plate(bank, "clear")

        let resting = try XCTUnwrap(plate.components[AccessibilityComponent.self])
        XCTAssertNotNil(resting.label, "The plate has no name.")

        bank.handleTap(plate)
        open(bank)                       // repaint runs in update, as in the app

        let armed = try XCTUnwrap(plate.components[AccessibilityComponent.self])
        XCTAssertNotEqual(String(localized: try XCTUnwrap(armed.value)),
                          String(localized: try XCTUnwrap(resting.value)),
                          "Arming a destructive plate said nothing to VoiceOver.")
    }
}
