//
//  NetPartition.swift
//  Disjoint-set forest over caller-assigned terminal slots (union by size + path compression) — which terminals are electrically one point.
//  Slot numbering is the caller's contract (Circuit Workshop: slot = 2·componentIndex + end, keeping stamping index-parallel); ground is a numbering choice, not a graph property.
//

import Foundation

/// A partition of terminal slots into electrically-common nets.
public struct NetPartition: Sendable, Equatable {
    /// Parent pointers; a root is its own parent.
    private var parent: [Int]
    /// Tree sizes, for union by size. Meaningful at roots only.
    private var size: [Int]
    /// Disjoint sets remaining — each root-joining union removes one.
    public private(set) var netCount: Int

    public var slotCount: Int { parent.count }

    public init(slotCount: Int) {
        precondition(slotCount >= 0, "A partition cannot have negative slots.")
        parent = Array(0..<slotCount)
        size = Array(repeating: 1, count: slotCount)
        netCount = slotCount
    }

    /// Root of `slot`'s set, compressing the path — mutating on purpose (compression is the speed);
    /// `areConnected` serves callers holding a `let`.
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

    /// Declare two slots the same electrical point. Idempotent and order-independent.
    public mutating func union(_ a: Int, _ b: Int) {
        let rootA = find(a), rootB = find(b)
        guard rootA != rootB else { return }
        // Union by size bounds the depth that compression then flattens.
        let (big, small) = size[rootA] >= size[rootB] ? (rootA, rootB) : (rootB, rootA)
        parent[small] = big
        size[big] += size[small]
        netCount -= 1
    }

    /// Non-mutating `find(a) == find(b)` — walks the full path instead of compressing.
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

    /// Compact gapless node numbers with `ground`'s net forced to 0 (CircuitSolver grounds node 0).
    /// Returns a slot-indexed array (read twice per component per frame), and numbering is deterministic — nets ordered by lowest slot, so a restored bench gets identical node ids.
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
