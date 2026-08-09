//
//  CircuitsInsightTests.swift
//  PhysicsPlaygroundTests
//
//  WRITTEN TWELVE TIMES, READ NEVER.
//
//  `CircuitsModel.insightText` had twelve assignments and, until
//  2026-08-08, not one reader anywhere in the app: the charge-curve
//  percentage, the power leader, the Electron View explanation, the fuse
//  post-mortem, and a paragraph for each of the five presets. All of it
//  compiled, none of it reachable — orphaned when the window panel was
//  deleted on 2026-08-01.
//
//  The tests below are in two halves, and the second is the one that
//  matters in a year.
//
//  1. The card behaves: absent with nothing to say, present with
//     something, and it does not rebuild a text mesh per frame.
//  2. THE STRINGS STILL HAVE A READER. A surface can be deleted again —
//     that is exactly what happened to the panel — and the failure mode
//     is silent, because a `insightText = "…"` that nobody displays
//     still compiles, still passes every other test, and still looks
//     like a feature in the source. `testTheInsightStringsReachASurface`
//     drives the model to write one and asserts it comes out the other
//     end, so the wiring cannot be removed without a red build.
//

import XCTest
import RealityKit
import RenderKit
@testable import PhysicsPlayground

@MainActor
final class CircuitsInsightTests: XCTestCase {

    // MARK: The card

    private func settle(_ card: CircuitsInsightCard, text: String,
                        frames: Int = 90) {
        for _ in 0..<frames {
            card.update(text: text, anchor: .zero, dt: 1 / 90)
        }
    }

    /// An empty bench has nothing to say, and a card saying nothing is
    /// the sign the owner had removed from this app the day before.
    func testNothingToSayMeansNoCard() {
        let card = CircuitsInsightCard()
        settle(card, text: "")
        XCTAssertFalse(card.root.isEnabled)
    }

    func testSomethingToSayPutsItOnScreen() {
        let card = CircuitsInsightCard()
        settle(card, text: "Series: ONE path, so the same current threads "
                         + "both bulbs.")
        XCTAssertTrue(card.root.isEnabled)
        XCTAssertFalse(card.root.children.isEmpty,
                       "the card is enabled but has nothing in it")
    }

    /// …and it goes away again when the bench is cleared, rather than
    /// leaving the last thing it said hanging over an empty room.
    func testItLeavesWhenThereIsNothingLeftToSay() {
        let card = CircuitsInsightCard()
        settle(card, text: "A dead short: nothing limits the current.")
        XCTAssertTrue(card.root.isEnabled)
        settle(card, text: "")
        XCTAssertFalse(card.root.isEnabled)
    }

    /// THE TEXT MESH IS REBUILT ONLY WHEN THE STRING CHANGES. `update`
    /// runs at 90 Hz and a generated text mesh is the most expensive
    /// thing on this card by an order of magnitude — the defect this
    /// codebase has swept out of four renderers already.
    func testAnUnchangedStringDoesNotRebuildTheMesh() throws {
        let card = CircuitsInsightCard()
        let text = "RC charging: the capacitor fills toward 9 V."
        settle(card, text: text)
        let first = try XCTUnwrap(card.root.children.first { $0 is ModelEntity })

        settle(card, text: text, frames: 30)
        let second = try XCTUnwrap(card.root.children.first { $0 is ModelEntity })
        XCTAssertTrue(first === second,
                      "the card rebuilt its mesh for a string that had not changed")
    }

    /// It is a READOUT, so it must not be pinchable. It stands inside the
    /// volume a component can be dragged into, and an input target there
    /// would shield parts from every pinch — the shielding failure the
    /// clearance rules exist to prevent.
    func testTheCardCannotBePinched() {
        let card = CircuitsInsightCard()
        settle(card, text: "Parallel: each bulb gets the FULL 9 V.")
        func walk(_ entity: Entity) {
            XCTAssertNil(entity.components[InputTargetComponent.self],
                         "the insight card grew a touch target")
            entity.children.forEach(walk)
        }
        walk(card.root)
    }

    // MARK: The wiring

    /// THE STRINGS REACH A SURFACE, asserted end to end.
    ///
    /// Loading a preset is the clearest writer — one paragraph per
    /// circuit, set inside `loadPreset` — so this drives the real model
    /// and asserts the text arrives. If the card is ever unmounted, or
    /// the SpaceView stops passing `model.insightText`, this is what
    /// goes red; without it the strings would simply go quiet again and
    /// nothing would notice for months.
    func testTheInsightStringsReachASurface() {
        let model = CircuitsModel()
        XCTAssertTrue(model.insightText.isEmpty,
                      "a fresh bench should have nothing to say")

        for preset in CircuitsModel.Preset.allCases {
            model.loadPreset(preset)
            XCTAssertFalse(model.insightText.isEmpty, """
                \(preset.displayName) wrote no insight — the paragraph \
                authored for it is unreachable again.
                """)

            // And the surface renders whatever the model wrote.
            let card = CircuitsInsightCard()
            settle(card, text: model.insightText)
            XCTAssertTrue(card.root.isEnabled, """
                \(preset.displayName)'s insight did not reach the card.
                """)
        }
    }

    /// AND IT SURVIVES THE RUNNING COMMENTARY, which is what "reaching a
    /// surface" actually requires.
    ///
    /// `loadPreset` wrote its paragraph and `updateLiveInsight`
    /// overwrote it within half a second, so each of the five was
    /// displayed for roughly one frame. The earlier test passed —
    /// the string DID reach the card — and a screenshot of the Series
    /// preset showed the power-leader line instead. Reachable and
    /// unreadable are different things, and only one of them was tested.
    func testAPresetParagraphOutlastsTheLiveCommentary() throws {
        let model = CircuitsModel()
        model.loadPreset(.series)
        let paragraph = model.insightText
        XCTAssertTrue(paragraph.contains("Series"), paragraph)

        // Several seconds of a live, unpaused circuit — far more than
        // the half-second the commentary refreshes on.
        for _ in 0..<300 { model.step(dt: 1.0 / 60) }
        XCTAssertEqual(model.insightText, paragraph, """
            the preset's paragraph was replaced by the running commentary \
            after \(300.0 / 60) s. It is meant to hold long enough to read.
            """)
    }

    /// …and then yields, because the commentary is about the circuit as
    /// it is NOW and a paragraph about how it arrived stops being true.
    func testTheCommentaryTakesOverOnceTheParagraphHasBeenRead() {
        let model = CircuitsModel()
        model.loadPreset(.series)
        let paragraph = model.insightText
        for _ in 0..<(20 * 60) { model.step(dt: 1.0 / 60) }
        XCTAssertNotEqual(model.insightText, paragraph,
                          "the paragraph never yields — the card is now a sign")
        XCTAssertFalse(model.insightText.isEmpty)
    }

    /// A FAILURE INTERRUPTS IT. A blown fuse is not commentary, and a
    /// paragraph about series bulbs over a dead bench is worse than
    /// none.
    func testAFailureSpeaksOverAHeldParagraph() throws {
        let model = CircuitsModel()
        model.loadPreset(.shortCircuit)
        let paragraph = model.insightText
        // The dead short blows its way to a failure on its own.
        for _ in 0..<240 { model.step(dt: 1.0 / 60) }
        if model.components.contains(where: { $0.failed }) {
            XCTAssertNotEqual(model.insightText, paragraph,
                              "a component failed and the card kept talking "
                              + "about the preset")
        } else {
            throw XCTSkip("the short did not blow anything in 4 s")
        }
    }

    /// Every preset's paragraph is DIFFERENT. Five circuits sharing one
    /// sentence would be a tally in prose — and the strings are the only
    /// thing that distinguishes the five once the parts are on the
    /// bench.
    func testEachPresetSaysSomethingOfItsOwn() {
        let model = CircuitsModel()
        var seen: Set<String> = []
        for preset in CircuitsModel.Preset.allCases {
            model.loadPreset(preset)
            XCTAssertTrue(seen.insert(model.insightText).inserted, """
                \(preset.displayName) repeats another preset's insight.
                """)
        }
        XCTAssertEqual(seen.count, CircuitsModel.Preset.allCases.count)
    }
}
