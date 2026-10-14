//
//  RackScrollTests.swift
//  PhysicsPlaygroundTests
//
//  The shelf's scroll arithmetic: a strip that follows the hand, settles
//  on whole slots, projects a flick and pushes back at its ends.
//

import XCTest
import RenderKit
@testable import PhysicsPlayground

final class RackScrollTests: XCTestCase {

    private let pitch: Float = 0.105

    private func rack(count: Int = 11, visible: Int = 6) -> RackScroll {
        RackScroll(pitch: pitch, count: count, visible: visible)
    }

    /// Runs the settle to rest, a frame at a time.
    private func settle(_ scroll: inout RackScroll, frames: Int = 400) {
        for _ in 0..<frames where scroll.isMoving {
            scroll.step(dt: 1 / 90)
        }
    }

    func testTheWindowStartsAtTheFirstSlot() {
        let scroll = rack()
        XCTAssertEqual(scroll.offset, 0)
        XCTAssertEqual(scroll.index, 0)
        XCTAssertEqual(scroll.maxOffset, 5 * pitch, accuracy: 1e-6)
        XCTAssertTrue(scroll.canScroll)
    }

    func testAShortRackNeverMoves() {
        var scroll = rack(count: 4, visible: 6)
        XCTAssertFalse(scroll.canScroll)
        scroll.beginDrag()
        scroll.drag(travel: 0.3)
        scroll.endDrag()
        settle(&scroll)
        XCTAssertEqual(scroll.offset, 0)
        scroll.jump(toIndex: 3)
        XCTAssertEqual(scroll.offset, 0)
    }

    /// Direct manipulation: the strip goes where the hand goes.
    func testTheStripFollowsTheHandOneToOne() {
        var scroll = rack()
        scroll.beginDrag()
        scroll.drag(travel: 0.2)
        XCTAssertEqual(scroll.offset, 0.2, accuracy: 1e-6)
        scroll.drag(travel: 0.05)
        XCTAssertEqual(scroll.offset, 0.05, accuracy: 1e-6)
    }

    func testAReleaseSettlesOnTheNearestWholeSlot() {
        var scroll = rack()
        scroll.beginDrag()
        scroll.drag(travel: 1.4 * pitch)
        for _ in 0..<30 { scroll.step(dt: 1 / 90) }   // the hand comes to rest
        scroll.endDrag()
        settle(&scroll)
        XCTAssertEqual(scroll.offset, pitch, accuracy: 1e-5)
        XCTAssertEqual(scroll.index, 1)
        XCTAssertFalse(scroll.isMoving)
    }

    /// A slow drag that stops moving has no flick in it: the release
    /// lands on the slot under the hand, not one further on.
    func testAStillHandHasNoFlick() {
        var scroll = rack()
        scroll.beginDrag()
        scroll.drag(travel: 2.2 * pitch)
        for _ in 0..<30 { scroll.step(dt: 1 / 90) }
        XCTAssertEqual(scroll.velocity, 0, accuracy: 1e-4)
        scroll.endDrag()
        settle(&scroll)
        XCTAssertEqual(scroll.index, 2)
    }

    /// A moving hand at release projects the strip past where it let go.
    func testAFlickCarriesPastTheHand() {
        var scroll = rack()
        scroll.beginDrag()
        var travel: Float = 0
        for _ in 0..<6 {
            travel += 0.012                 // 1.08 m/s
            scroll.drag(travel: travel)
            scroll.step(dt: 1 / 90)
        }
        XCTAssertGreaterThan(scroll.velocity, 0.5)
        scroll.endDrag()
        settle(&scroll)
        XCTAssertGreaterThan(scroll.index, 1,
                             "a fast release landed on the slot under the hand")
        XCTAssertEqual(scroll.offset, Float(scroll.index) * pitch, accuracy: 1e-5,
                       "the flick did not land on a whole slot")
    }

    func testAFlickNeverPassesTheLastSlot() {
        var scroll = rack()
        scroll.beginDrag()
        var travel: Float = 0
        for _ in 0..<20 {
            travel += 0.03
            scroll.drag(travel: travel)
            scroll.step(dt: 1 / 90)
        }
        scroll.endDrag()
        settle(&scroll)
        XCTAssertEqual(scroll.offset, scroll.maxOffset, accuracy: 1e-5)
        XCTAssertEqual(scroll.index, 5)
    }

    /// Past an end the strip resists rather than stops, and springs back.
    func testTheEndsPushBack() {
        var scroll = rack()
        scroll.beginDrag()
        scroll.drag(travel: -0.10)
        XCTAssertLessThan(scroll.offset, 0, "the strip did not give at all")
        XCTAssertGreaterThan(scroll.offset, -0.10, "the strip did not resist")
        XCTAssertGreaterThan(scroll.offset, -RackScroll.overscroll * pitch,
                             "the strip went past its rubber band")
        scroll.endDrag()
        settle(&scroll)
        XCTAssertEqual(scroll.offset, 0, accuracy: 1e-5)

        scroll.beginDrag()
        scroll.drag(travel: scroll.maxOffset + 0.5)
        XCTAssertGreaterThan(scroll.offset, scroll.maxOffset)
        XCTAssertLessThan(scroll.offset, scroll.maxOffset + RackScroll.overscroll * pitch)
        scroll.endDrag()
        settle(&scroll)
        XCTAssertEqual(scroll.offset, scroll.maxOffset, accuracy: 1e-5)
    }

    func testTheRubberBandIsMonotonicAndBounded() {
        let band: Float = 0.06
        var last: Float = 0
        for over in stride(from: Float(0), through: 2, by: 0.05) {
            let shown = RackScroll.rubberBanded(-over, limit: 0.5, band: band)
            XCTAssertLessThanOrEqual(shown, last + 1e-7, "not monotonic at \(over)")
            XCTAssertGreaterThan(shown, -band)
            last = shown
        }
        XCTAssertEqual(RackScroll.rubberBanded(0.3, limit: 0.5, band: band), 0.3)
    }

    func testReduceMotionLandsAtOnce() {
        var scroll = rack()
        scroll.beginDrag()
        scroll.drag(travel: 1.6 * pitch)
        scroll.endDrag(reduceMotion: true)
        XCTAssertFalse(scroll.isMoving)
        XCTAssertEqual(scroll.offset, 2 * pitch, accuracy: 1e-5)
    }

    func testAJumpIsInstantAndClamped() {
        var scroll = rack()
        scroll.jump(toIndex: 3)
        XCTAssertEqual(scroll.offset, 3 * pitch, accuracy: 1e-6)
        XCTAssertFalse(scroll.isMoving)
        scroll.jump(toIndex: 99)
        XCTAssertEqual(scroll.index, 5)
        scroll.jump(toIndex: -4)
        XCTAssertEqual(scroll.index, 0)
    }

    // MARK: The arrival

    /// An arrival puts the strip below its slot and closes on it.
    func testACoastLandsOnTheNearestSlot() {
        var scroll = rack()
        scroll.coast(from: -0.4 * pitch, rate: 4)
        XCTAssertTrue(scroll.isMoving)
        XCTAssertLessThan(scroll.offset, 0)
        XCTAssertGreaterThanOrEqual(scroll.offset, -RackScroll.overscroll * pitch)
        settle(&scroll)
        XCTAssertEqual(scroll.offset, 0, accuracy: 1e-6)
        XCTAssertFalse(scroll.isMoving)
    }

    /// A coast starts no further out than a hand could push, and lands
    /// on the slot it was nearest, so a scrolled window is kept.
    func testACoastIsClampedToTheRubberBandAndKeepsItsSlot() {
        var scroll = rack()
        scroll.jump(toIndex: 5)
        scroll.coast(from: scroll.offset + 3 * pitch)
        XCTAssertLessThanOrEqual(scroll.offset,
                                 scroll.maxOffset + RackScroll.overscroll * pitch + 1e-6)
        settle(&scroll)
        XCTAssertEqual(scroll.offset, scroll.maxOffset, accuracy: 1e-6)
        XCTAssertEqual(scroll.index, 5)
    }

    /// The rate is the coast's own: a gentle arrival is slower than the
    /// house settle, and the next hand's settle is back at the house rate.
    func testACoastClosesAtItsOwnRateAndAHandsSettleAtTheHouses() {
        var gentle = rack()
        gentle.coast(from: -0.4 * pitch, rate: 3.5)
        var brisk = rack()
        brisk.coast(from: -0.4 * pitch)
        for _ in 0..<30 {
            gentle.step(dt: 1 / 90)
            brisk.step(dt: 1 / 90)
        }
        XCTAssertLessThan(abs(brisk.offset), abs(gentle.offset),
                          "the arrival is closing as fast as a hand's settle")

        gentle.beginDrag()
        gentle.drag(travel: 0.3 * pitch + 0.4 * pitch)
        gentle.endDrag()
        for _ in 0..<60 where gentle.isMoving { gentle.step(dt: 1 / 90) }
        XCTAssertFalse(gentle.isMoving,
                       "a hand's settle after a coast kept the coast's slow rate")
    }

    func testReduceMotionLandsACoastAtOnce() {
        var scroll = rack()
        scroll.coast(from: -0.4 * pitch, rate: 1)
        scroll.step(dt: 1 / 90, reduceMotion: true)
        XCTAssertEqual(scroll.offset, 0)
        XCTAssertFalse(scroll.isMoving)
    }

    func testAShortRackDoesNotCoast() {
        var scroll = rack(count: 4, visible: 6)
        scroll.coast(from: -0.4 * pitch)
        XCTAssertEqual(scroll.offset, 0)
        XCTAssertFalse(scroll.isMoving)
    }
}
