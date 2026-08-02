//
//  BloomPetalTests.swift
//  PhysicsPlaygroundTests
//
//  `Bloom` has been in the app since the rebuild and carries several
//  modules' per-object actions, but nothing has ever asserted the one
//  behaviour every caller silently depends on: **`retarget` rebuilds
//  only when the target id CHANGES.**
//
//  That guard exists for a good reason (a `@State` read from a render
//  closure came back stale, so the first version reconfigured itself
//  sixty times a second — the unfold animation reset to zero every frame
//  and two entities leaked per frame). But it has a consequence nobody
//  wrote down, and it is a trap:
//
//      A caller whose id is CONSTANT gets its petal list evaluated
//      exactly once, on the first frame, and never again.
//
//  Kinematics' launcher bloom is exactly that — its id is the literal
//  "launcher". So the obvious translation of the window panel's
//  `.disabled(flights.isEmpty)` — leave the Clear petal out when there
//  is nothing to clear — would compile, read correctly, and be evaluated
//  once at launch: the petal would be permanently present or permanently
//  absent depending on what the room looked like in frame one.
//
//  The launcher's Clear petal is unconditional because of this. These
//  tests pin the behaviour that reasoning rests on, so that changing
//  `retarget` breaks a test rather than silently un-disabling a control
//  in another file.
//

import XCTest
import RealityKit
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

    /// The launcher now carries three — Fire, Balls, Clear — which is
    /// the ceiling `Petal`'s own doc sets. Each must fire its own action
    /// and only its own: a layout that overlapped them, or a resolver
    /// that matched by index rather than by name, would show up here.
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

    /// The walk-up contract: a pinch lands on the glyph or the casing,
    /// not on the petal root, and must still resolve to the petal.
    func testATapOnAPetalsChildResolvesToThePetal() throws {
        let counter = Counter()
        let bloom = Bloom()
        bloom.retarget("launcher", petals: [petal("Clear", counter)], grip: nil)
        reveal(bloom)

        let petalEntity = try entity(bloom, named: "Clear")
        let child = try XCTUnwrap(petalEntity.children.first,
                                  "a petal should have a glyph to hit")

        XCTAssertTrue(bloom.handleTap(child))
        XCTAssertEqual(counter.fired, ["Clear"])
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
}
