//
//  RoomTeachTests.swift
//  PhysicsPlaygroundTests
//
//  The first sentence of a lab moved out of the flat window and into the
//  room on 2026-08-08, because the apparatus stood through it there.
//
//  What is worth testing is not that a card exists — a card that shows
//  the wrong thing, or never goes away, or cannot be dismissed by a
//  wearer who does not pinch, all "exist". Four claims:
//
//  1. It says what the module authored, and it stops saying it once the
//     receipt is written.
//  2. It is DISMISSED BY TOUCHING ANYWHERE ON IT, and dismissing twice
//     writes one receipt.
//  3. It is operable without a pinch, through the same `handleTap` a
//     finger takes — not straight at the callback.
//  4. It stands nearer to the reader than the apparatus, which is the
//     entire reason it moved. That one is asserted against the labs'
//     actual anchors rather than against a number typed twice.
//

import XCTest
import RealityKit
import RenderKit
@testable import PhysicsPlayground

@MainActor
final class RoomTeachTests: XCTestCase {

    private let sentence = "Five steel balls, touching, with one drawn back "
        + "— let it go and watch which of them move."

    private func settled(_ card: RoomTeachCard, frames: Int = 120) {
        for _ in 0..<frames { card.update(viewer: [0, 1.5, 0], dt: 1 / 90) }
    }

    // MARK: What it says

    func testAnEmptyTeachShowsNothing() {
        let card = RoomTeachCard()
        settled(card)
        XCTAssertFalse(card.root.isEnabled)
        XCTAssertFalse(card.isShowing)
    }

    func testItShowsTheSentenceItWasGiven() throws {
        let card = RoomTeachCard()
        card.setText(sentence)
        settled(card)
        XCTAssertTrue(card.isShowing)
        XCTAssertFalse(card.root.children.isEmpty)

        // …and the words are the module's, not a placeholder.
        let labels = Self.accessibilityLabels(of: card.root)
        XCTAssertTrue(labels.contains { $0.contains("Five steel balls") },
                      "the card is up but does not carry the hint: \(labels)")
    }

    // MARK: Dismissal

    func testTappingAnywhereOnTheCardDismissesIt() throws {
        let card = RoomTeachCard()
        var receipts = 0
        card.onDismiss = { receipts += 1 }
        card.setText(sentence)
        settled(card)

        // A DEEP CHILD, not the target itself: a pinch lands on whatever
        // glyph mesh is under the finger, and the card has to walk up to
        // find itself. Aiming the test at the target entity would pass
        // while every real tap missed.
        let deep = try XCTUnwrap(Self.deepestChild(of: card.root))
        XCTAssertTrue(card.handleTap(deep), "a tap on the card did nothing")
        XCTAssertEqual(receipts, 1)

        settled(card)
        XCTAssertFalse(card.isShowing, "the card stayed up after dismissal")
        XCTAssertFalse(card.root.isEnabled)
    }

    /// ONE RECEIPT PER READ. The card is still tappable for the few
    /// frames it spends fading, and Settings counts dismissals.
    func testDismissingTwiceWritesOneReceipt() throws {
        let card = RoomTeachCard()
        var receipts = 0
        card.onDismiss = { receipts += 1 }
        card.setText(sentence)
        settled(card)

        let deep = try XCTUnwrap(Self.deepestChild(of: card.root))
        _ = card.handleTap(deep)
        _ = card.handleTap(deep)
        card.dismiss()
        XCTAssertEqual(receipts, 1)
    }

    func testATapSomewhereElseIsNotADismissal() {
        let card = RoomTeachCard()
        var receipts = 0
        card.onDismiss = { receipts += 1 }
        card.setText(sentence)
        settled(card)

        XCTAssertFalse(card.handleTap(Entity()))
        XCTAssertEqual(receipts, 0)
        XCTAssertTrue(card.isShowing)
    }

    // MARK: Reachable without hands

    /// The card is pinchable, so it must be operable. Driven through the
    /// published action rather than by calling `dismiss()`, which is the
    /// distinction `SpatialActionCriterionTests` exists to enforce.
    func testVoiceOverCanDismissIt() throws {
        let card = RoomTeachCard()
        var receipts = 0
        card.onDismiss = { receipts += 1 }
        card.setText(sentence)
        settled(card)

        let targets = Self.entities(of: card.root) {
            $0.components[InputTargetComponent.self] != nil
        }
        XCTAssertFalse(targets.isEmpty, "nothing on the card can be aimed at")
        for entity in targets {
            XCTAssertNotNil(entity.components[SpatialActionComponent.self], """
                a pinchable part of the teach card publishes no action, so \
                VoiceOver can find it and not use it.
                """)
        }
        let action = try XCTUnwrap(
            targets.compactMap { $0.components[SpatialActionComponent.self] }.first)
        action.activate?()
        XCTAssertEqual(receipts, 1, "activating the card did not dismiss it")
    }

    // MARK: Where it stands

    /// NEARER THAN THE PHYSICS. This is the whole reason it left the
    /// window, so it is asserted against the labs' own anchors — if a
    /// module moves its apparatus forward, this goes red rather than
    /// quietly going back to being occluded.
    func testItStandsNearerThanEveryLabsApparatus() {
        // The z each lab puts its apparatus at, read from the scenes.
        let apparatus: [(String, Float)] = [
            ("Pendulums rig", -0.95),
            ("Gravity Lab system", -1.00),
            ("Circuits bench", -0.90),
            ("Experiment checker", -0.90),
        ]
        for (name, z) in apparatus {
            XCTAssertGreaterThan(RoomTeachCard.standoff.z, z, """
                the teach card sits at z \(RoomTeachCard.standoff.z), behind \
                the \(name) at \(z). It moved out of the window precisely to \
                stop standing behind things.
                """)
        }
    }

    /// …and within reach, because you dismiss it by touching it.
    func testItIsWithinArmsReach() {
        let fromViewer = length(RoomTeachCard.standoff - SIMD3<Float>(0, 1.5, 0))
        XCTAssertLessThan(Double(fromViewer), InstrumentClearance.maximumReach, """
            the teach card is \(fromViewer) m from a standing viewer, past \
            the \(InstrumentClearance.maximumReach) m reach limit — and it is \
            dismissed by touching it.
            """)
    }

    // MARK: Helpers

    private static func entities(of root: Entity,
                                 where predicate: (Entity) -> Bool) -> [Entity] {
        var found: [Entity] = []
        func walk(_ entity: Entity) {
            if predicate(entity) { found.append(entity) }
            entity.children.forEach(walk)
        }
        walk(root)
        return found
    }

    private static func accessibilityLabels(of root: Entity) -> [String] {
        entities(of: root) { $0.components[AccessibilityComponent.self] != nil }
            .compactMap { $0.components[AccessibilityComponent.self]?.label }
            .map { String(localized: $0) }
    }

    private static func deepestChild(of root: Entity) -> Entity? {
        var best: Entity?
        var bestDepth = -1
        func walk(_ entity: Entity, _ depth: Int) {
            if depth > bestDepth { best = entity; bestDepth = depth }
            entity.children.forEach { walk($0, depth + 1) }
        }
        walk(root, 0)
        return best
    }
}
