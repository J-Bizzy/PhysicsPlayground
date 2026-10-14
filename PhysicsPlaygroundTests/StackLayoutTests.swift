//
//  StackLayoutTests.swift
//  PhysicsPlaygroundTests
//
//  Every module's display layers will hang off this, so the properties
//  worth pinning are the ones that would otherwise need a per-module
//  fudge: that the column stays centred on its anchor however many
//  switches it holds, that switches never overlap, and that a bank of one
//  or zero is still finite.
//

import XCTest
import simd
import RenderKit

final class StackLayoutTests: XCTestCase {

    /// The property that keeps callers honest: adding a switch grows the
    /// column in both directions, so the bank stays put beside the
    /// apparatus instead of creeping downward.
    func testColumnStaysCentredAsItGrows() {
        let stack = StackLayout()
        for count in 1...7 {
            let ys = (0..<count).map {
                stack.placement(index: $0, count: count, reveal: 1).offset.y
            }
            let mean = ys.reduce(0, +) / Double(count)
            XCTAssertEqual(mean, 0, accuracy: 1e-12,
                           "a bank of \(count) drifted off its anchor")
        }
    }

    /// Switches run top to bottom in index order — a bank that ran upward
    /// would put the first layer at the bottom of the list.
    func testSwitchesDescendInIndexOrder() {
        let stack = StackLayout()
        let ys = (0..<5).map {
            stack.placement(index: $0, count: 5, reveal: 1).offset.y
        }
        for (upper, lower) in zip(ys, ys.dropFirst()) {
            XCTAssertGreaterThan(upper, lower)
        }
    }

    /// Neighbours are exactly `pitch` apart, so a plate sized under the
    /// pitch can never overlap its neighbour.
    func testNeighboursAreExactlyOnePitchApart() {
        let stack = StackLayout(pitch: 0.05)
        for count in 2...7 {
            let ys = (0..<count).map {
                stack.placement(index: $0, count: count, reveal: 1).offset.y
            }
            for (a, b) in zip(ys, ys.dropFirst()) {
                XCTAssertEqual(a - b, 0.05, accuracy: 1e-12)
            }
        }
    }

    func testHeightMatchesTheSpanOfThePlacements() {
        let stack = StackLayout(pitch: 0.048)
        for count in 1...7 {
            let ys = (0..<count).map {
                stack.placement(index: $0, count: count, reveal: 1).offset.y
            }
            let span = (ys.max() ?? 0) - (ys.min() ?? 0)
            XCTAssertEqual(span, stack.height(count: count), accuracy: 1e-12)
        }
    }

    /// `lift` moves the whole bank without changing its internal spacing,
    /// which is what lets a module hang one beside an apparatus.
    func testLiftMovesTheWholeColumn() {
        let plain = StackLayout(lift: 0)
        let lifted = StackLayout(lift: 0.3)
        for index in 0..<4 {
            let a = plain.placement(index: index, count: 4, reveal: 1).offset.y
            let b = lifted.placement(index: index, count: 4, reveal: 1).offset.y
            XCTAssertEqual(b - a, 0.3, accuracy: 1e-12)
        }
    }

    // MARK: Reveal

    func testHiddenAtZeroRevealAndLandedAtOne() {
        let stack = StackLayout()
        XCTAssertFalse(stack.placement(index: 0, count: 3, reveal: 0).isVisible)
        let shown = stack.placement(index: 0, count: 3, reveal: 1)
        XCTAssertTrue(shown.isVisible)
        XCTAssertEqual(shown.scale, 1, accuracy: 1e-12)
        XCTAssertEqual(shown.offset.z, 0, accuracy: 1e-12, "fully slid in")
    }

    func testRevealIsClamped() {
        let stack = StackLayout()
        XCTAssertEqual(stack.placement(index: 0, count: 3, reveal: 9).scale,
                       1, accuracy: 1e-12)
        XCTAssertFalse(stack.placement(index: 0, count: 3, reveal: -4).isVisible)
    }

    // MARK: Degenerate counts

    /// A module with a single display layer still gets a legal bank, sat
    /// exactly on its anchor.
    func testSingleSwitchSitsOnTheAnchor() {
        let placement = StackLayout().placement(index: 0, count: 1, reveal: 1)
        XCTAssertEqual(placement.offset.y, 0, accuracy: 1e-12)
        XCTAssertTrue(placement.offset.y.isFinite)
    }

    func testZeroCountIsFiniteRatherThanCrashing() {
        let placement = StackLayout().placement(index: 0, count: 0, reveal: 1)
        XCTAssertTrue(placement.offset.y.isFinite)
        XCTAssertTrue(StackLayout().height(count: 0).isFinite)
    }
}
