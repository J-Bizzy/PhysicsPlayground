//
//  NetPartition.swift
//  PhysicsCore — Circuits
//
//  Which terminals are electrically the same point. A disjoint-set
//  forest over SLOTS — small integers the caller assigns — with union
//  by size and path compression, so a bench of a few dozen terminals
//  partitions in effectively linear time.
//
//  This is the half of the circuit that `CircuitSolver` assumes has
//  already happened: the solver takes `nodeA`/`nodeB` as given and
//  never asks how two components came to share a node. Until now that
//  question was answered by a union–find built from scratch inside the
//  app's solve, every frame, and thrown away — so nothing above it
//  could ever ask "are these two terminals already the same point?"
//  without walking the wire list again. It is here, in PhysicsCore,
//  because it is pure index arithmetic with real invariants, and it
//  belongs in the fast `swift test` loop rather than behind a
//  simulator.
//
//  SLOT NUMBERING IS THE CALLER'S CONTRACT, and it is load-bearing.
//  Circuit Workshop uses `slot = 2 * componentIndex + end`, which is
//  what lets its stamping loop stay index-parallel with its component
//  array — element i is component i — without a lookup table between
//  them.
//
//  Ground is not a property of the graph. `numbering(ground:)` takes
//  the slot the caller wants at node 0, because which point of a
//  circuit is "zero volts" is a modelling choice, not a fact about the
//  wires.
//

import Foundation

/// A partition of terminal slots into electrically-common nets.
public struct NetPartition: Sendable, Equatable {
    /// Parent pointers; a root is its own parent.
    private var parent: [Int]
    /// Tree sizes, for union by size. Meaningful at roots only.
    private var size: [Int]
    /// How many disjoint sets remain — every slot starts alone, and
    /// each union that joins two distinct roots removes one.
    public private(set) var netCount: Int

    public var slotCount: Int { parent.count }

    public init(slotCount: Int) {
        precondition(slotCount >= 0, "A partition cannot have negative slots.")
        parent = Array(0..<slotCount)
        size = Array(repeating: 1, count: slotCount)
        netCount = slotCount
    }

    /// The root of `slot`'s set, compressing the path it walked.
    ///
    /// Mutating is not an implementation detail leaking out: path
    /// compression is what keeps this near-constant, and a
    /// non-mutating variant that skipped it would quietly be the slow
    /// one. `areConnected` exists for callers holding a `let`.
    public mutating func find(_ slot: Int) -> Int {
        precondition(parent.indices.contains(slot), "Slot \(slot) is outside the partition.")
        var root = slot
        while parent[root] != root { root = parent[root] }
        var current = slot
        while parent[current] != root {
            let next = parent[current]
            parent[current] = root
            current = next
        }
        return root
    }

    /// Declare two slots to be the same electrical point. Idempotent,
    /// and order-independent: the partition after a set of unions does
    /// not depend on the order they arrived in.
    public mutating func union(_ a: Int, _ b: Int) {
        let rootA = find(a), rootB = find(b)
        guard rootA != rootB else { return }
        // Union by size: the smaller tree hangs off the larger, which
        // is what bounds the depth path compression then flattens.
        let (big, small) = size[rootA] >= size[rootB] ? (rootA, rootB) : (rootB, rootA)
        parent[small] = big
        size[big] += size[small]
        netCount -= 1
    }

    /// Whether two slots are the same electrical point — without
    /// mutating, so a caller holding an immutable partition can ask.
    /// Answers identically to `find(a) == find(b)`; it just walks the
    /// full path instead of compressing it.
    public func areConnected(_ a: Int, _ b: Int) -> Bool {
        precondition(parent.indices.contains(a) && parent.indices.contains(b),
                     "Slot outside the partition.")
        return root(of: a) == root(of: b)
    }

    private func root(of slot: Int) -> Int {
        var root = slot
        while parent[root] != root { root = parent[root] }
        return root
    }

    /// Compact node numbers for the solver: 0..<nodeCount with no gaps,
    /// `ground`'s net forced to 0 because `CircuitSolver` grounds node
    /// 0 and eliminates its row.
    ///
    /// Returns an ARRAY indexed by slot, not a dictionary — this is
    /// read twice per component on every frame of every circuit, and a
    /// dictionary here is a hash per terminal per frame for a lookup
    /// the caller already has an integer for.
    ///
    /// Numbering is deterministic: after ground, nets are numbered in
    /// order of their lowest-numbered slot, so the same bench always
    /// produces the same node ids and a snapshot restored twice is the
    /// same circuit twice.
    public mutating func numbering(ground: Int) -> (nodeOfSlot: [Int], nodeCount: Int) {
        guard !parent.isEmpty else { return ([], 0) }
        precondition(parent.indices.contains(ground), "Ground slot \(ground) is outside the partition.")
        var nodeOfRoot = [Int: Int](minimumCapacity: netCount)
        nodeOfRoot[find(ground)] = 0
        var nodeCount = 1
        var nodeOfSlot = [Int](repeating: 0, count: parent.count)
        for slot in parent.indices {
            let root = find(slot)
            if let node = nodeOfRoot[root] {
                nodeOfSlot[slot] = node
            } else {
                nodeOfRoot[root] = nodeCount
                nodeOfSlot[slot] = nodeCount
                nodeCount += 1
            }
        }
        return (nodeOfSlot, nodeCount)
    }
}
