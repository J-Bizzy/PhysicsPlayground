//
//  TimeCapsule.swift
//  PhysicsCore — Math: time-windowed ring buffer of simulation snapshots.
//  Lookups land ON a recorded frame, never between two (an interpolated
//  state never happened); memory bounded by `window` AND a hard `capacity`.
//

public struct TimeCapsule<Snapshot> {

    public struct Frame {
        public let time: Double
        public let snapshot: Snapshot

        public init(time: Double, snapshot: Snapshot) {
            self.time = time
            self.snapshot = snapshot
        }
    }

    /// Seconds of history the buffer keeps.
    public let window: Double

    /// The hard frame cap: window × expectedRate, rounded up.
    public let capacity: Int

    // Circular: `head` = oldest, strictly increasing time from there; slots
    // are optional only to preallocate — every slot inside `count` is non-nil.
    private var storage: [Frame?]
    private var head = 0
    public private(set) var count = 0

    public init(window: Double = 30, expectedRate: Double = 90) {
        precondition(window > 0 && expectedRate > 0)
        self.window = window
        self.capacity = Int((window * expectedRate).rounded(.up))
        self.storage = Array(repeating: nil, count: capacity)
    }

    public var isEmpty: Bool { count == 0 }

    /// Oldest…newest recorded time, or nil while empty.
    public var span: ClosedRange<Double>? {
        guard count > 0 else { return nil }
        return frame(atIndex: 0).time...frame(atIndex: count - 1).time
    }

    public func newest() -> Frame? {
        count > 0 ? frame(atIndex: count - 1) : nil
    }

    // MARK: Recording

    /// Appends. Time must grow; a rewound/stalled clock drops frames at or
    /// after `time` first, so the ordering invariant survives a bad caller.
    public mutating func record(_ snapshot: Snapshot, at time: Double) {
        while let last = newest(), last.time >= time {
            dropNewest()
        }
        if count == capacity {
            dropOldest()
        }
        storage[(head + count) % capacity] = Frame(time: time, snapshot: snapshot)
        count += 1
        evict(before: time - window)
    }

    public mutating func removeAll() {
        for i in storage.indices { storage[i] = nil }
        head = 0
        count = 0
    }

    /// Discards frames strictly after `time` — un-pausing from a scrub truncates the rejected future.
    public mutating func truncate(after time: Double) {
        while let last = newest(), last.time > time {
            dropNewest()
        }
    }

    // MARK: Lookup

    /// Nearest recorded frame not after `time`, clamped to the span's ends — never fabricates a state.
    public func frame(at time: Double) -> Frame? {
        guard count > 0 else { return nil }
        guard let i = index(atOrBefore: time) else { return frame(atIndex: 0) }
        return frame(atIndex: i)
    }

    /// The frame `frames` recorded ticks away (negative = earlier), clamped to the ends.
    public func frame(steppedFrom time: Double, by frames: Int) -> Frame? {
        guard count > 0 else { return nil }
        let base = index(atOrBefore: time) ?? 0
        let stepped = min(max(base + frames, 0), count - 1)
        return frame(atIndex: stepped)
    }

    /// Every `stride`-th recorded frame in `range`, but ALWAYS keeping both ends.
    public func frames(in range: ClosedRange<Double>, stride: Int = 1) -> [Frame] {
        guard count > 0, stride > 0 else { return [] }
        var first: Int?
        var last: Int?
        for i in 0..<count {
            let t = frame(atIndex: i).time
            if range.contains(t) {
                if first == nil { first = i }
                last = i
            } else if t > range.upperBound {
                break
            }
        }
        guard let lo = first, let hi = last else { return [] }
        var result: [Frame] = []
        result.reserveCapacity((hi - lo) / stride + 2)
        var i = lo
        while i <= hi {
            result.append(frame(atIndex: i))
            i += stride
        }
        if let tail = result.last, tail.time != frame(atIndex: hi).time {
            result.append(frame(atIndex: hi))
        }
        return result
    }

    // MARK: Internals

    private func frame(atIndex logical: Int) -> Frame {
        storage[(head + logical) % capacity]!
    }

    /// Binary search: greatest logical index with time ≤ `time`; nil if all later.
    private func index(atOrBefore time: Double) -> Int? {
        guard count > 0, frame(atIndex: 0).time <= time else { return nil }
        var lo = 0
        var hi = count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if frame(atIndex: mid).time <= time {
                lo = mid
            } else {
                hi = mid - 1
            }
        }
        return lo
    }

    private mutating func dropOldest() {
        guard count > 0 else { return }
        storage[head] = nil
        head = (head + 1) % capacity
        count -= 1
    }

    private mutating func dropNewest() {
        guard count > 0 else { return }
        storage[(head + count - 1) % capacity] = nil
        count -= 1
    }

    private mutating func evict(before cutoff: Double) {
        while count > 0, frame(atIndex: 0).time < cutoff {
            dropOldest()
        }
    }
}

extension TimeCapsule: Sendable where Snapshot: Sendable {}
extension TimeCapsule.Frame: Sendable where Snapshot: Sendable {}
extension TimeCapsule.Frame: Equatable where Snapshot: Equatable {}
