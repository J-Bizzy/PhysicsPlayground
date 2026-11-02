//
//  BloomPetalTests.swift
//  PhysicsPlaygroundTests
//
//  `Bloom.retarget` rebuilds only when the target id changes, so a
//  caller with a constant id gets its petal list evaluated once;
//  `Petal.isAvailable` is a closure for exactly that reason, and
//  `Petal.confirms` guards the destructive verb.
//

import XCTest
import RealityKit
import RenderKit
@testable import PhysicsPlayground

@MainActor
final class BloomPetalTests: XCTestCase {

    final class Counter {
        var fired: [String] = []
    }

    private func petal(_ name: String, _ counter: Counter) -> Bloom.Petal {
        .init(name: name, symbol: "circle", tint: .white) {
            counter.fired.append(name)
        }
    }

    /// Bloom builds one entity per petal directly under `root`, named
    /// `bloom-<petal name>` — the prefix is the contract `handleTap`
    /// resolves through, so these tests read it the same way the app does.
    private func entity(_ bloom: Bloom, named name: String) throws -> Entity {
        try XCTUnwrap(bloom.root.children.first { $0.name == "bloom-\(name)" },
                      "no petal entity named bloom-\(name); children were "
                      + "\(bloom.root.children.map(\.name))")
    }

    private func hasPetal(_ bloom: Bloom, named name: String) -> Bool {
        bloom.root.children.contains { $0.name == "bloom-\(name)" }
    }

    /// Reveal the bloom — `handleTap` refuses while the root is disabled.
    private func reveal(_ bloom: Bloom) {
        for _ in 0..<40 {
            bloom.update(anchor: .zero, viewer: [0, 0, 1],
                         revealTarget: 1, dt: 1.0 / 90.0)
        }
    }

    // MARK: The trap

    /// The claim the launcher's comment depends on: same id, no rebuild,
    /// so the petal closure is never consulted again.
    func testRetargetIgnoresANewPetalListWhenTheIDIsUnchanged() throws {
        let counter = Counter()
        let bloom = Bloom()

        bloom.retarget("launcher",
                       petals: [petal("Fire", counter)],
                       grip: nil)
        XCTAssertNoThrow(try entity(bloom, named: "Fire"))

        // The same id, a different list — as a per-frame `syncBloom`
        // that computed its petals conditionally would produce.
        bloom.retarget("launcher",
                       petals: [petal("Fire", counter), petal("Clear", counter)],
                       grip: nil)

        XCTAssertFalse(hasPetal(bloom, named: "Clear"),
                     """
                     `retarget` rebuilt on an unchanged id. That is a \
                     BEHAVIOUR CHANGE, not a bug fix — read this file's \
                     header. Kinematics' launcher petals are \
                     unconditional precisely because this could not \
                     happen; if it can now, that comment is wrong and \
                     the Clear petal should go back to tracking \
                     `flights.isEmpty`.
                     """)
    }

    /// …and the other half: a genuinely new target does rebuild.
    func testRetargetRebuildsWhenTheIDChanges() throws {
        let counter = Counter()
        let bloom = Bloom()

        bloom.retarget("launcher", petals: [petal("Fire", counter)], grip: nil)
        bloom.retarget("other", petals: [petal("Delete", counter)], grip: nil)

        XCTAssertNoThrow(try entity(bloom, named: "Delete"))
        XCTAssertFalse(hasPetal(bloom, named: "Fire"),
                       "the previous target's petals survived a retarget")
    }

    // MARK: Three petals resolve independently

    /// Three petals, each firing only its own action.
    func testEachOfThreePetalsFiresOnlyItsOwnAction() throws {
        let counter = Counter()
        let bloom = Bloom()
        bloom.retarget("launcher",
                       petals: [petal("Fire", counter),
                                petal("Balls", counter),
                                petal("Clear", counter)],
                       grip: nil)
        reveal(bloom)

        for name in ["Clear", "Fire", "Balls"] {
            XCTAssertTrue(bloom.handleTap(try entity(bloom, named: name)),
                          "\(name) did not claim its own tap")
        }
        XCTAssertEqual(counter.fired, ["Clear", "Fire", "Balls"],
                       "petals fired the wrong actions, or fired extra ones")
    }

    /// A petal is one target: the family's glass button, with no glyph or
    /// casing beneath it for a pinch to land on instead.
    func testAPetalIsOneTargetWithNothingBeneathToMiss() throws {
        let counter = Counter()
        let bloom = Bloom()
        bloom.retarget("launcher", petals: [petal("Clear", counter)], grip: nil)
        reveal(bloom)

        let petalEntity = try entity(bloom, named: "Clear")
        XCTAssertTrue(petalEntity.children.isEmpty,
                      "a petal grew a child a pinch could land on")
        XCTAssertTrue(ControlAttachment.isControl(petalEntity))
        XCTAssertTrue(bloom.handleTap(petalEntity))
        XCTAssertEqual(counter.fired, ["Clear"])
    }

    /// The acknowledge-swell keeps the petal's own orientation; a target
    /// transform built without one tumbled every petal 90°.
    func testTheSwellTargetPreservesThePetalsOrientation() throws {
        let counter = Counter()
        let bloom = Bloom()
        bloom.retarget("launcher", petals: [petal("Fire", counter)], grip: nil)
        reveal(bloom)

        let petalEntity = try entity(bloom, named: "Fire")
        let target = Bloom.swellTarget(for: petalEntity)

        let dot = abs(simd_dot(target.rotation.vector,
                               petalEntity.orientation.vector))
        XCTAssertEqual(dot, 1, accuracy: 1e-5,
                       "the swell's target rotation differs from the "
                       + "petal's built orientation — the tap animation "
                       + "will visibly tumble the petal")
        XCTAssertGreaterThan(target.scale.x, petalEntity.scale.x,
                             "the swell should still grow the petal")
    }

    /// A folded bloom is not on screen and must claim nothing.
    func testAFoldedBloomFiresNothing() throws {
        let counter = Counter()
        let bloom = Bloom()
        bloom.retarget("launcher", petals: [petal("Clear", counter)], grip: nil)
        let petalEntity = try entity(bloom, named: "Clear")

        XCTAssertFalse(bloom.handleTap(petalEntity))
        XCTAssertEqual(counter.fired, [])
    }

    // MARK: Availability — the escape from the trap

    /// The whole point of `isAvailable` being a closure: read every frame,
    /// not captured once.
    func testAnAvailabilityClosureIsReadEveryFrameNotOnce() throws {
        let counter = Counter()
        var hasFlights = false
        let bloom = Bloom()
        bloom.retarget("launcher", petals: [
            .init(name: "Clear", symbol: "trash.slash", tint: .white,
                  isAvailable: { hasFlights }) { counter.fired.append("Clear") },
        ], grip: nil)
        reveal(bloom)
        let petalEntity = try entity(bloom, named: "Clear")

        // Unavailable: refuses, and does not consume — a dim petal must
        // not be a hole that swallows a gesture aimed past it.
        XCTAssertFalse(bloom.handleTap(petalEntity))
        XCTAssertEqual(counter.fired, [])

        // The room changes. Nothing calls `retarget` — the id is constant.
        hasFlights = true
        reveal(bloom)

        XCTAssertTrue(bloom.handleTap(petalEntity),
                      "The closure must be re-read, not remembered.")
        XCTAssertEqual(counter.fired, ["Clear"])
    }

    /// Dim, never absent. Removing a petal would shift its neighbours —
    /// the ring's angles come from the count — out from under a finger
    /// already reaching for one.
    func testAnUnavailablePetalDimsRatherThanDisappearing() throws {
        let bloom = Bloom()
        bloom.retarget("launcher", petals: [
            .init(name: "Clear", symbol: "trash.slash", tint: .white,
                  isAvailable: { false }) { },
        ], grip: nil)
        reveal(bloom)

        XCTAssertTrue(hasPetal(bloom, named: "Clear"),
                      "An unavailable petal must still be in the ring.")
        let petalEntity = try entity(bloom, named: "Clear")
        XCTAssertTrue(petalEntity.isEnabled)
        XCTAssertEqual(bloom.control(named: "Clear")?.isEnabled, false,
                       "It must read as unavailable.")
    }

    // MARK: Confirmation

    /// Two taps, one firing — the same contract `SpatialActionBank`
    /// gives a standing verb plate.
    func testAConfirmingPetalArmsFirstAndFiresSecond() throws {
        let counter = Counter()
        let bloom = Bloom()
        bloom.retarget("launcher", petals: [
            .init(name: "Clear", symbol: "trash.slash", tint: .white,
                  confirms: true) { counter.fired.append("Clear") },
        ], grip: nil)
        reveal(bloom)
        let petalEntity = try entity(bloom, named: "Clear")

        XCTAssertTrue(bloom.handleTap(petalEntity),
                      "Arming is a real response and must consume the tap.")
        XCTAssertEqual(counter.fired, [], "The first tap must not fire.")

        XCTAssertTrue(bloom.handleTap(petalEntity))
        XCTAssertEqual(counter.fired, ["Clear"])
    }

    /// An armed petal walked away from disarms itself, so coming back to
    /// an open ring minutes later is not one pinch from a wipe.
    func testAnArmedPetalDisarmsItselfAfterTheWindow() throws {
        let counter = Counter()
        let bloom = Bloom()
        bloom.retarget("launcher", petals: [
            .init(name: "Clear", symbol: "trash.slash", tint: .white,
                  confirms: true) { counter.fired.append("Clear") },
        ], grip: nil)
        reveal(bloom)
        let petalEntity = try entity(bloom, named: "Clear")

        XCTAssertTrue(bloom.handleTap(petalEntity))
        for _ in 0..<Int(Bloom.armWindow * 90) + 10 {
            bloom.update(anchor: .zero, viewer: [0, 0, 1],
                         revealTarget: 1, dt: 1.0 / 90.0)
        }

        // The next tap arms again rather than firing.
        XCTAssertTrue(bloom.handleTap(petalEntity))
        XCTAssertEqual(counter.fired, [],
                       "A disarmed petal must need arming again, not fire.")
    }

    /// A petal without `confirms` still fires on the first tap. The
    /// guard is opt-in — pause, polarity and mass are not destructive
    /// and must not grow a second tap.
    func testAnOrdinaryPetalStillFiresOnTheFirstTap() throws {
        let counter = Counter()
        let bloom = Bloom()
        bloom.retarget("launcher", petals: [petal("Fire", counter)], grip: nil)
        reveal(bloom)

        XCTAssertTrue(bloom.handleTap(try entity(bloom, named: "Fire")))
        XCTAssertEqual(counter.fired, ["Fire"])
    }

    /// A petal that changes a state says what the state is now: its
    /// announcement is read after the action, so it speaks the new state,
    /// not the one the tap left behind.
    func testAStatePetalAnnouncesTheStateItLeft() throws {
        var mass = 0.5
        var heard: [String] = []
        let bloom = Bloom()
        bloom.configure(petals: [
            .init(name: "Mass", symbol: "scalemass", tint: .white,
                  announce: {
                      let said = "Mass \(mass)"
                      heard.append(said)
                      return said
                  }) { mass = 1.5 },
        ], grip: nil)
        reveal(bloom)
        XCTAssertTrue(bloom.handleTap(try entity(bloom, named: "Mass")))
        XCTAssertEqual(heard, ["Mass 1.5"])
    }
}
