//
//  NetPartitionTests.swift
//  PhysicsCoreTests
//
//  The partition answers one question — "are these two terminals the
//  same electrical point?" — and everything above it trusts the
//  answer: the solver's node count, the app's refusal to build a
//  redundant wire, the meter's continuity check, and the migration
//  that splices a retired component out of a saved bench. So the
//  properties checked here are the algebraic ones (reflexive,
//  symmetric, transitive, order-independent) rather than a handful of
//  worked examples, because a partition that is wrong is usually
//  wrong about a case nobody wrote down.
//

import XCTest
@testable import PhysicsCore

final class NetPartitionTests: XCTestCase {

    /// Every slot starts alone, and joining two of them makes exactly
    /// one net out of two.
    func testUnionMakesOneNet() {
        var partition = NetPartition(slotCount: 4)
        XCTAssertEqual(partition.netCount, 4)
        XCTAssertFalse(partition.areConnected(0, 1))
        partition.union(0, 1)
        XCTAssertEqual(partition.netCount, 3)
        XCTAssertTrue(partition.areConnected(0, 1))
    }

    /// Unions do not leak: joining 0–1 says nothing about 2 and 3.
    func testDisjointSlotsStayApart() {
        var partition = NetPartition(slotCount: 4)
        partition.union(0, 1)
        partition.union(2, 3)
        XCTAssertTrue(partition.areConnected(0, 1))
        XCTAssertTrue(partition.areConnected(2, 3))
        XCTAssertFalse(partition.areConnected(0, 2))
        XCTAssertFalse(partition.areConnected(1, 3))
        XCTAssertEqual(partition.netCount, 2)
    }

    /// Being the same point is an equivalence relation, and the app
    /// leans on all three parts: reflexive (a terminal is itself),
    /// symmetric (wiring A to B is wiring B to A), transitive (a wire
    /// to a wire is one net, which is what makes a redundant third
    /// wire redundant).
    func testConnectivityIsSymmetricAndTransitive() {
        var partition = NetPartition(slotCount: 6)
        partition.union(0, 1)
        partition.union(1, 2)
        XCTAssertTrue(partition.areConnected(0, 0), "Reflexive.")
        XCTAssertTrue(partition.areConnected(2, 0), "Symmetric.")
        XCTAssertTrue(partition.areConnected(0, 2), "Transitive: 0–1 and 1–2 make 0–2.")
        XCTAssertEqual(partition.netCount, 4, "Six slots, two unions, four nets.")
    }

    /// Re-declaring a union that already holds changes nothing — the
    /// app calls this on every candidate pair it evaluates.
    func testRepeatedUnionIsIdempotent() {
        var partition = NetPartition(slotCount: 3)
        partition.union(0, 1)
        let after = partition.netCount
        for _ in 0..<10 { partition.union(0, 1) }
        XCTAssertEqual(partition.netCount, after)
    }

    /// The partition does not depend on the order the wires arrived
    /// in. A bench restored from disk replays its wires in array
    /// order; a bench built by hand does not.
    func testTheResultDoesNotDependOnUnionOrder() {
        let edges = [(0, 3), (1, 4), (3, 4), (2, 5)]
        var forward = NetPartition(slotCount: 6)
        for edge in edges { forward.union(edge.0, edge.1) }
        var backward = NetPartition(slotCount: 6)
        for edge in edges.reversed() { backward.union(edge.0, edge.1) }
        XCTAssertEqual(forward.netCount, backward.netCount)
        for a in 0..<6 {
            for b in 0..<6 {
                XCTAssertEqual(forward.areConnected(a, b), backward.areConnected(a, b),
                               "Slots \(a) and \(b) disagree between union orders.")
            }
        }
    }

    /// `CircuitSolver` grounds node 0 and eliminates its row, so the
    /// caller's chosen ground must land there — whichever slot it is.
    func testGroundIsAlwaysNodeZero() {
        var partition = NetPartition(slotCount: 6)
        partition.union(0, 1)
        partition.union(2, 3)
        for ground in 0..<6 {
            var copy = partition
            let (nodeOfSlot, _) = copy.numbering(ground: ground)
            XCTAssertEqual(nodeOfSlot[ground], 0,
                           "Slot \(ground) was named ground and did not get node 0.")
        }
    }

    /// Node numbers are 0..<nodeCount with nothing skipped — the
    /// solver allocates a matrix of exactly that side.
    func testNumberingIsCompactWithNoGaps() {
        var partition = NetPartition(slotCount: 8)
        partition.union(0, 1)
        partition.union(1, 6)
        partition.union(3, 4)
        let expectedNets = partition.netCount
        let (nodeOfSlot, nodeCount) = partition.numbering(ground: 0)
        XCTAssertEqual(nodeCount, expectedNets,
                       "One node per net: \(expectedNets) nets became \(nodeCount) nodes.")
        XCTAssertEqual(Set(nodeOfSlot), Set(0..<nodeCount), "Numbering has a gap or a duplicate.")
        // Slots on one net share a node; slots on different nets do not.
        for a in 0..<8 {
            for b in 0..<8 {
                XCTAssertEqual(nodeOfSlot[a] == nodeOfSlot[b], partition.areConnected(a, b),
                               "Node numbering disagrees with the partition at \(a), \(b).")
            }
        }
    }

    /// `find` rewrites the parent array as it walks. The answers must
    /// not depend on whether that has happened yet — this is the
    /// property that makes the non-mutating `areConnected` safe to
    /// ship alongside it.
    func testFindIsIdempotentUnderCompression() {
        var partition = NetPartition(slotCount: 5)
        partition.union(0, 1)
        partition.union(1, 2)
        partition.union(2, 3)
        let before = (0..<5).map { a in (0..<5).map { partition.areConnected(a, $0) } }
        for slot in 0..<5 { _ = partition.find(slot) }   // compress everything
        let after = (0..<5).map { a in (0..<5).map { partition.areConnected(a, $0) } }
        XCTAssertEqual(before, after, "Path compression changed an answer.")
        XCTAssertEqual(partition.netCount, 2, "Compression must not change the net count.")
    }

    /// A chain deep enough to matter still resolves to one net — the
    /// migration splices benches whose jumpers chain end to end.
    func testALongChainIsOneNet() {
        var partition = NetPartition(slotCount: 200)
        for slot in 1..<200 { partition.union(slot - 1, slot) }
        XCTAssertEqual(partition.netCount, 1)
        XCTAssertTrue(partition.areConnected(0, 199))
        let (nodeOfSlot, nodeCount) = partition.numbering(ground: 199)
        XCTAssertEqual(nodeCount, 1)
        XCTAssertEqual(Set(nodeOfSlot), [0])
    }

    /// An empty bench is a real state — Clear bench leaves one — and
    /// it must not trap on the way through.
    func testAnEmptyPartitionIsSafe() {
        var partition = NetPartition(slotCount: 0)
        XCTAssertEqual(partition.netCount, 0)
        let (nodeOfSlot, nodeCount) = partition.numbering(ground: 0)
        XCTAssertTrue(nodeOfSlot.isEmpty)
        XCTAssertEqual(nodeCount, 0)
    }

    /// One unwired terminal is its own net. `CircuitSolver`'s diagonal
    /// leak is what keeps such a node solvable, and it can only do
    /// that if the node exists.
    func testAFloatingSlotIsItsOwnNet() {
        var partition = NetPartition(slotCount: 3)
        partition.union(0, 1)
        let (nodeOfSlot, nodeCount) = partition.numbering(ground: 0)
        XCTAssertEqual(nodeCount, 2)
        XCTAssertNotEqual(nodeOfSlot[2], nodeOfSlot[0])
    }
}
