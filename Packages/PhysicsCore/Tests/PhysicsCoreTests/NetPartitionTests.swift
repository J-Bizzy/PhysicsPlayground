//
//  NetPartitionTests.swift
//  Union-find over terminals: algebraic properties (reflexive, symmetric, transitive,
//  order-independent), since a wrong partition is usually wrong about an unwritten case.
//

import XCTest
@testable import PhysicsCore

final class NetPartitionTests: XCTestCase {

    func testUnionMakesOneNet() {
        var partition = NetPartition(slotCount: 4)
        XCTAssertEqual(partition.netCount, 4)
        XCTAssertFalse(partition.areConnected(0, 1))
        partition.union(0, 1)
        XCTAssertEqual(partition.netCount, 3)
        XCTAssertTrue(partition.areConnected(0, 1))
    }

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

    /// Connectivity is an equivalence relation; the app leans on all three parts.
    func testConnectivityIsSymmetricAndTransitive() {
        var partition = NetPartition(slotCount: 6)
        partition.union(0, 1)
        partition.union(1, 2)
        XCTAssertTrue(partition.areConnected(0, 0), "Reflexive.")
        XCTAssertTrue(partition.areConnected(2, 0), "Symmetric.")
        XCTAssertTrue(partition.areConnected(0, 2), "Transitive: 0–1 and 1–2 make 0–2.")
        XCTAssertEqual(partition.netCount, 4, "Six slots, two unions, four nets.")
    }

    func testRepeatedUnionIsIdempotent() {
        var partition = NetPartition(slotCount: 3)
        partition.union(0, 1)
        let after = partition.netCount
        for _ in 0..<10 { partition.union(0, 1) }
        XCTAssertEqual(partition.netCount, after)
    }

    /// Order independence: a restored bench replays wires in array order; a hand-built one does not.
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

    /// `CircuitSolver` grounds node 0, so the caller's chosen ground must land there.
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

    /// Numbering is compact 0..<nodeCount — the solver allocates a matrix of exactly that side.
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
        for a in 0..<8 {
            for b in 0..<8 {
                XCTAssertEqual(nodeOfSlot[a] == nodeOfSlot[b], partition.areConnected(a, b),
                               "Node numbering disagrees with the partition at \(a), \(b).")
            }
        }
    }

    /// Answers must not depend on path compression having happened —
    /// what makes the non-mutating `areConnected` safe.
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

    /// A deep chain is one net — the migration splices benches whose jumpers chain end to end.
    func testALongChainIsOneNet() {
        var partition = NetPartition(slotCount: 200)
        for slot in 1..<200 { partition.union(slot - 1, slot) }
        XCTAssertEqual(partition.netCount, 1)
        XCTAssertTrue(partition.areConnected(0, 199))
        let (nodeOfSlot, nodeCount) = partition.numbering(ground: 199)
        XCTAssertEqual(nodeCount, 1)
        XCTAssertEqual(Set(nodeOfSlot), [0])
    }

    /// An empty bench is a real state (Clear bench leaves one) and must not trap.
    func testAnEmptyPartitionIsSafe() {
        var partition = NetPartition(slotCount: 0)
        XCTAssertEqual(partition.netCount, 0)
        let (nodeOfSlot, nodeCount) = partition.numbering(ground: 0)
        XCTAssertTrue(nodeOfSlot.isEmpty)
        XCTAssertEqual(nodeCount, 0)
    }

    /// A floating terminal is its own net — `CircuitSolver`'s diagonal leak needs the node to exist.
    func testAFloatingSlotIsItsOwnNet() {
        var partition = NetPartition(slotCount: 3)
        partition.union(0, 1)
        let (nodeOfSlot, nodeCount) = partition.numbering(ground: 0)
        XCTAssertEqual(nodeCount, 2)
        XCTAssertNotEqual(nodeOfSlot[2], nodeOfSlot[0])
    }
}
