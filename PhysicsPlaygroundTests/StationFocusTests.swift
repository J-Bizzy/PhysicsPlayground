//
//  StationFocusTests.swift
//  Physics Playground — app tests
//
//  Focus is the mechanic that lets a world hold three apparatus without
//  becoming the picker that killed the last two mergers. The difference
//  between the two is not a claim, it is these assertions.
//

import XCTest
@testable import PhysicsPlayground

@MainActor
final class StationFocusTests: XCTestCase {

    // MARK: The anti-picker floor

    /// PROPERTY 4 of the focus contract, and the one that is a single
    /// number: an unfocused station is dimmer, never absent.
    ///
    /// From DECISIONS.md — "a merger is only a merger if both halves are
    /// simultaneously present, live and reachable. Focus changes which
    /// half is emphasised; a picker changes which half exists." If this
    /// floor ever reaches zero, the unfocused station is invisible, and
    /// an invisible station is one nobody finds. That is precisely how
    /// Fields and Oscillators died.
    func testTheDimFloorIsNeverZero() {
        XCTAssertGreaterThan(
            StationEmphasis.dimFloor, 0,
            "an unfocused station must stay visible — at zero this stops "
            + "being emphasis and becomes a picker")
        XCTAssertLessThan(StationEmphasis.dimFloor, 1,
                          "at 1 the mechanic does nothing at all")
    }

    /// The floor is enforced by the type, not by its callers, so no
    /// future caller can dim a station out of existence by accident.
    func testEmphasisNeverFallsBelowTheFloorHoweverLongItEases() {
        let focus = StationFocus(initial: EMStation.bench)
        focus.register(.field)
        // Far more easing than any real session will ever apply.
        for _ in 0..<10_000 { focus.tick(dt: 1.0 / 90.0) }
        XCTAssertGreaterThanOrEqual(focus.emphasis(for: .field),
                                    StationEmphasis.dimFloor)
    }

    // MARK: Traces fade further than the apparatus

    /// A field line leaves its station legitimately — a field really is
    /// everywhere — so an unattended charges bench would otherwise fill
    /// the whole view. Traces therefore fade past the apparatus floor.
    /// The floor itself is NOT relaxed: it guards the thing you grab,
    /// and nobody grabs a field line.
    func testTracesFadeFurtherThanTheApparatusTheyBelongTo() {
        let focus = StationFocus(initial: EMStation.bench)
        focus.register(.charges)
        focus.snap()
        XCTAssertLessThan(focus.traceEmphasis(for: .charges),
                          focus.emphasis(for: .charges),
                          "an unattended bench's traces must recede further "
                          + "than the bench")
        XCTAssertEqual(focus.traceEmphasis(for: .charges),
                       StationEmphasis.traceFloor, accuracy: 1e-6)
    }

    /// Both curves ride the same eased progress, so they can never
    /// disagree about which bench is being attended to — a lit bench
    /// with faded lines, or the reverse, would read as a glitch.
    func testTheApparatusAndItsTracesArriveTogether() {
        let focus = StationFocus(initial: EMStation.bench)
        focus.register(.charges)
        focus.snap()
        XCTAssertEqual(focus.traceEmphasis(for: .bench), 1, accuracy: 1e-6,
                       "the attended bench's traces must be fully lit")

        focus.focus(.charges)
        for _ in 0..<400 {
            focus.tick(dt: 1.0 / 90.0)
            // Whichever way each is heading, the traces are never
            // brighter than the apparatus they hang inside.
            XCTAssertLessThanOrEqual(focus.traceEmphasis(for: .bench),
                                     focus.emphasis(for: .bench) + 1e-6)
            XCTAssertLessThanOrEqual(focus.traceEmphasis(for: .charges),
                                     focus.emphasis(for: .charges) + 1e-6)
        }
        XCTAssertEqual(focus.traceEmphasis(for: .charges), 1, accuracy: 0.01)
        XCTAssertEqual(focus.traceEmphasis(for: .bench),
                       StationEmphasis.traceFloor, accuracy: 0.01)
    }

    // MARK: Easing

    /// Exponential approach: monotone toward the target, never
    /// overshooting past it.
    func testEmphasisMovesMonotonicallyTowardTheTarget() {
        let focus = StationFocus(initial: EMStation.bench)
        focus.register(.field)
        focus.snap()

        focus.focus(.field)
        var previousRising = focus.emphasis(for: .field)
        var previousFalling = focus.emphasis(for: .bench)
        for _ in 0..<200 {
            focus.tick(dt: 1.0 / 90.0)
            let rising = focus.emphasis(for: .field)
            let falling = focus.emphasis(for: .bench)
            XCTAssertGreaterThanOrEqual(rising, previousRising - 1e-6,
                                        "the focused station dipped")
            XCTAssertLessThanOrEqual(falling, previousFalling + 1e-6,
                                     "the unfocused station brightened")
            XCTAssertLessThanOrEqual(rising, 1.0 + 1e-6, "overshot full")
            previousRising = rising
            previousFalling = falling
        }
        XCTAssertEqual(focus.emphasis(for: .field), 1, accuracy: 0.01)
        XCTAssertEqual(focus.emphasis(for: .bench),
                       StationEmphasis.dimFloor, accuracy: 0.01)
    }

    /// Frame-rate independence: the same elapsed time reaches the same
    /// place whether it arrives in a few long frames or many short ones.
    /// Without this a dropped frame would visibly jump the fade.
    func testEasingIsFrameRateIndependent() {
        let coarse = StationFocus(initial: EMStation.bench)
        coarse.register(.field)
        coarse.snap()
        coarse.focus(.field)

        let fine = StationFocus(initial: EMStation.bench)
        fine.register(.field)
        fine.snap()
        fine.focus(.field)

        for _ in 0..<30 { coarse.tick(dt: 1.0 / 30.0) }
        for _ in 0..<90 { fine.tick(dt: 1.0 / 90.0) }

        XCTAssertEqual(coarse.emphasis(for: .field),
                       fine.emphasis(for: .field), accuracy: 0.02)
    }

    /// A drag sends a focus request every frame. Re-focusing the station
    /// already focused must not restart the fade, or the emphasis would
    /// never arrive while a hand is moving.
    func testRefocusingTheFocusedStationIsIdempotent() {
        let focus = StationFocus(initial: EMStation.bench)
        focus.register(.field)
        focus.focus(.field)
        for _ in 0..<40 { focus.tick(dt: 1.0 / 90.0) }
        let partway = focus.emphasis(for: .field)

        focus.focus(.field)
        XCTAssertEqual(focus.emphasis(for: .field), partway, accuracy: 1e-9,
                       "re-focusing restarted the fade")
        focus.tick(dt: 1.0 / 90.0)
        XCTAssertGreaterThan(focus.emphasis(for: .field), partway)
    }

    // MARK: Snap — the screenshot path

    /// `-focusStation` uses this. The simulator has no hands, so without
    /// an exact landing a CLI screenshot catches a mid-fade frame and
    /// shows a scale nobody chose.
    func testSnapLandsExactlyOnTheSettledValues() {
        let focus = StationFocus(initial: EMStation.bench)
        focus.register(.field)
        focus.focus(.field)
        focus.snap()
        XCTAssertEqual(focus.emphasis(for: .field), 1, accuracy: 1e-9)
        XCTAssertEqual(focus.emphasis(for: .bench),
                       StationEmphasis.dimFloor, accuracy: 1e-9)
    }

    /// A station nobody has registered still answers with its settled
    /// emphasis rather than zero — the reserved third seat asks this
    /// before it is ever installed.
    func testUnregisteredStationsReportTheirSettledEmphasis() {
        let focus = StationFocus(initial: EMStation.bench)
        XCTAssertEqual(focus.emphasis(for: .bench), 1, accuracy: 1e-9)
        XCTAssertEqual(focus.emphasis(for: .charges),
                       StationEmphasis.dimFloor, accuracy: 1e-9)
    }

    func testFocusStartsWhereItWasInitialised() {
        XCTAssertEqual(StationFocus(initial: EMStation.field).focused, .field)
    }
}
