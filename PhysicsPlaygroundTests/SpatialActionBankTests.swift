//
//  SpatialActionBankTests.swift
//  PhysicsPlaygroundTests
//
//  Written before the primitive's first caller: an unused primitive is
//  not a working primitive. Builds real entities and calls `handleTap`
//  directly, the only interaction testing available without a headset.
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

    // MARK: Reset disarms it

    /// A reset disarms an armed plate: a module's reset reaches its model,
    /// and the armed plate lives in the SpaceView, so an armed "Clear bench"
    /// once survived Reset one pinch from wiping a restored bench. Wired
    /// through `AppModel.resetNonce`; asserted as behaviour, not mechanism.
    func testAResetDisarmsAnArmedPlate() throws {
        let (bank, counter) = makeBank(confirms: true)
        let target = try plate(bank, "clear")

        XCTAssertTrue(bank.handleTap(target))
        XCTAssertTrue(bank.isArmed("clear"), "Precondition: the plate is armed.")

        // One frame at a new reset nonce — what a Reset produces.
        bank.update(anchor: .zero, viewer: [0, 0, 1], dt: 1.0 / 90.0, resetNonce: 1)

        XCTAssertFalse(bank.isArmed("clear"),
                       "Reset must leave nothing armed.")
        XCTAssertEqual(counter.count, 0,
                       "Disarming is not firing — a reset must never run the verb.")

        // And the plate still works afterwards: disarming must not wedge it.
        XCTAssertTrue(bank.handleTap(target))
        XCTAssertTrue(bank.isArmed("clear"))
    }

    /// The nonce must only act on a change, or a bank ticked at a constant
    /// nonce would disarm before the second tap could land.
    func testAnUnchangedNonceLeavesTheArmedPlateAlone() throws {
        let (bank, _) = makeBank(confirms: true)
        let target = try plate(bank, "clear")

        // Let the bank adopt the nonce before arming, or the tick is a genuine
        // change.
        bank.update(anchor: .zero, viewer: [0, 0, 1], dt: 1.0 / 90.0, resetNonce: 7)

        XCTAssertTrue(bank.handleTap(target))
        for _ in 0..<30 {
            bank.update(anchor: .zero, viewer: [0, 0, 1],
                        dt: 1.0 / 90.0, resetNonce: 7)
        }
        XCTAssertTrue(bank.isArmed("clear"),
                      "A steady nonce must not disarm; only a change may. "
                      + "A bank that disarmed every frame would make the "
                      + "second tap of a confirmation impossible to land.")
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

    /// A plate is one target, with no child for a pinch to land on instead.
    func testAPlateIsOneTarget() throws {
        let (bank, counter) = makeBank()
        let plate = try plate(bank, "clear")
        XCTAssertTrue(plate.children.isEmpty)
        XCTAssertTrue(bank.handleTap(plate))
        XCTAssertEqual(counter.count, 1)
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

    /// An unavailable plate must not consume the tap either: a dim plate
    /// that swallowed pinches would stop the thing behind it responding.
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

    /// `reset()`'s obligation: a Clear plate left armed across a reset is
    /// one stray pinch from wiping what the reset just rebuilt.
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

    /// The plate carries no collider of its own: its glass is the target,
    /// so nothing invisible can stand between a hand and the apparatus the
    /// bank hangs beside.
    func testThePlateCarriesNoColliderOfItsOwn() throws {
        let (bank, _) = makeBank()
        let plate = try plate(bank, "clear")
        XCTAssertNil(plate.components[CollisionComponent.self])
        XCTAssertNil(plate.components[InputTargetComponent.self])
        XCTAssertTrue(ControlAttachment.isControl(plate))
    }

    // MARK: Accessibility

    /// The armed state has to show (and speak — the family's button reads
    /// "armed — tap again to confirm"): one tap from wiping a bench and two
    /// taps from it must not look the same.
    func testTheArmedStateReachesTheGlass() throws {
        let (bank, _) = makeBank(confirms: true)
        let plate = try plate(bank, "clear")
        XCTAssertEqual(bank.control(for: "clear")?.isArmed, false)

        bank.handleTap(plate)
        open(bank)                       // the state is written in update, as in the app

        XCTAssertEqual(bank.control(for: "clear")?.isArmed, true,
                       "Arming a destructive plate changed nothing on it.")
    }
}
