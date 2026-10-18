//
//  WireCurrentsTests.swift
//  PhysicsCoreTests
//
//  How a node's current divides among the wires that make it up — the
//  question the nodal solve, which collapses wires into nodes, never asks.
//  On a tree Kirchhoff's current law answers it exactly; in a loop the
//  wires' own conductances do.
//

import XCTest
@testable import PhysicsCore

final class WireCurrentsTests: XCTestCase {

    private func solve(_ slots: Int, _ edges: [(Int, Int)], _ injections: [Double],
                       conductances: [Double]? = nil) -> [Double] {
        WireCurrents.solve(
            slotCount: slots,
            edges: edges.map { WireCurrents.Edge(a: $0.0, b: $0.1) },
            conductances: conductances ?? Array(repeating: 1, count: edges.count),
            injections: injections)
    }

    func testAChainCarriesTheSameCurrentThroughEveryWire() {
        let currents = solve(3, [(0, 1), (1, 2)], [1.5, 0, -1.5])
        XCTAssertEqual(currents[0], 1.5, accuracy: 1e-12)
        XCTAssertEqual(currents[1], 1.5, accuracy: 1e-12)
    }

    func testAStarSplitsTheWayItsLegsDraw() {
        let currents = solve(4, [(0, 1), (0, 2), (0, 3)], [0, 1, -0.4, -0.6])
        XCTAssertEqual(currents[0], -1, accuracy: 1e-12, "the current comes in from slot 1")
        XCTAssertEqual(currents[1], 0.4, accuracy: 1e-12)
        XCTAssertEqual(currents[2], 0.6, accuracy: 1e-12)
    }

    /// A battery terminal wired to one bulb and that bulb's terminal wired on
    /// to a second: the first wire carries both bulbs' current, the second
    /// only the far bulb's. Splitting each terminal's current evenly over its
    /// wires — what Circuit Workshop's electron dots did until 2026-10-18 —
    /// gets both wrong.
    func testTwoBulbsChainedOffOneTerminal() {
        let near = 0.25, far = 0.10
        let currents = solve(3, [(0, 1), (1, 2)], [near + far, -near, -far],
                             conductances: [1 / 0.3, 1 / 0.2])
        XCTAssertEqual(currents[0], near + far, accuracy: 1e-12)
        XCTAssertEqual(currents[1], far, accuracy: 1e-12)
    }

    /// Kirchhoff at every terminal of a tree, whatever the wires are made of:
    /// what leaves through the wires is what the component pushed in.
    func testCurrentBalancesAtEveryTerminalOfATree() {
        let edges = [(0, 1), (1, 2), (1, 3), (3, 4), (3, 5), (0, 6)]
        let injections = [0.7, -0.2, 0.1, 0.3, -0.5, -0.6, 0.2]
        XCTAssertEqual(injections.reduce(0, +), 0, accuracy: 1e-12)
        for conductances in [Array(repeating: 1.0, count: 6), [3, 0.2, 7, 1, 0.5, 40]] {
            let currents = solve(7, edges, injections, conductances: conductances)
            for slot in 0..<7 {
                var leaving = 0.0
                for (index, edge) in edges.enumerated() {
                    if edge.0 == slot { leaving += currents[index] }
                    if edge.1 == slot { leaving -= currents[index] }
                }
                XCTAssertEqual(leaving, injections[slot], accuracy: 1e-12, "slot \(slot)")
            }
        }
    }

    /// Two wires between the same two points: a loop. Ideal wires leave it
    /// undetermined; copper divides it inversely to length.
    func testALoopDividesByConductance() {
        let currents = solve(2, [(0, 1), (0, 1)], [1, -1], conductances: [1 / 1.0, 1 / 3.0])
        XCTAssertEqual(currents[0], 0.75, accuracy: 1e-12)
        XCTAssertEqual(currents[1], 0.25, accuracy: 1e-12)
    }

    /// A snapped joint is a zero-length wire; the caller floors its length at
    /// a millimetre, and the current through it is still the chain's.
    func testAZeroLengthJointCarriesItsShare() {
        let currents = solve(3, [(0, 1), (1, 2)], [2, 0, -2],
                             conductances: [1 / 1e-3, 1 / 0.4])
        XCTAssertEqual(currents[0], 2, accuracy: 1e-9)
        XCTAssertEqual(currents[1], 2, accuracy: 1e-9)
    }

    func testIsolatedTerminalsAndNoWiresCarryNothing() {
        XCTAssertEqual(solve(4, [], [0, 0, 0, 0]), [])
        let currents = solve(5, [(0, 1)], [0.5, -0.5, 9, -9, 0])
        XCTAssertEqual(currents[0], 0.5, accuracy: 1e-12)
    }

    /// The circuit solver leaks a nanoamp at every node; a group whose
    /// injections do not quite sum to zero still solves, finitely.
    func testAnUnbalancedGroupStaysFinite() {
        let currents = solve(3, [(0, 1), (1, 2)], [1, 0, -1 + 1e-9])
        XCTAssertTrue(currents.allSatisfy(\.isFinite))
        XCTAssertEqual(currents[1], 1, accuracy: 1e-6)
    }
}
