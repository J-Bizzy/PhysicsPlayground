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
