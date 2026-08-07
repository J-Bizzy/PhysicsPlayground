//
//  TimeCapsule.swift
//  PhysicsCore — Math
//
//  A time-windowed ring buffer of simulation snapshots: the memory behind
//  the Time Capsule scrubber. A model records one snapshot per physics
//  step; scrubbing looks a recorded frame up by time and restores it.
//
//  Two properties are load-bearing and tested, not assumed:
//
//  - A lookup always lands ON a recorded frame, never between two. Most
//    of the simulations here advance by numerical integration through
//    discrete events (bounces, merges, component failures), so a state
//    interpolated between frames is a state that never happened. Scrub
//    resolution is therefore the recording cadence, by design.
//
//  - Memory is bounded twice over: frames older than `window` seconds are
//    evicted by time, and a fixed frame capacity is the hard guarantee if
//    the caller records faster than `expectedRate`.
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

    // Circular storage. `head` is the index of the oldest frame; frames
    // are ordered by strictly increasing time from there. Slots are
    // optionals only so the buffer can preallocate without demanding a
    // default Snapshot; every slot inside `count` is non-nil.
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

    /// Appends a frame. Time must grow; if it does not (a rewound or
    /// stalled clock), frames at or after `time` are dropped first so the
    /// buffer's ordering invariant survives a caller misbehaving.
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

    /// Discards every frame strictly after `time` — the resume path:
    /// un-pausing from a scrubbed instant truncates the rejected future.
    public mutating func truncate(after time: Double) {
        while let last = newest(), last.time > time {
            dropNewest()
        }
    }

    // MARK: Lookup

    /// The recorded frame nearest to and not after `time`. Queries before
    /// the span clamp to the oldest frame, after it to the newest —
    /// scrubbing never fabricates a state.
    public func frame(at time: Double) -> Frame? {
        guard count > 0 else { return nil }
        guard let i = index(atOrBefore: time) else { return frame(atIndex: 0) }
        return frame(atIndex: i)
    }

    /// The frame `frames` recorded ticks away from the frame at `time`
    /// (negative = earlier), clamped to the buffer's ends.
    public func frame(steppedFrom time: Double, by frames: Int) -> Frame? {
        guard count > 0 else { return nil }
        let base = index(atOrBefore: time) ?? 0
        let stepped = min(max(base + frames, 0), count - 1)
        return frame(atIndex: stepped)
    }

    /// Every recorded frame with time in `range`, taking each `stride`-th
    /// but always keeping both ends — a path drawn from these vertices
    /// starts and finishes where the recording does.
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

    /// Logical index → stored frame. Only valid for 0..<count.
    private func frame(atIndex logical: Int) -> Frame {
        storage[(head + logical) % capacity]!
    }

    /// Binary search: the greatest logical index whose time ≤ `time`,
    /// or nil if every frame is later.
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
