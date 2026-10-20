//
//  FrameLog.swift
//  Physics Playground — Shell
//
//  Frame pacing in the console, debug builds only, under `-frameLog 1`:
//  every few seconds, how many frames the scene ran, the median and
//  99th-percentile frame and the worst, and how many ran long — measured
//  on the wall clock between RealityKit's updates, so a frame the main
//  thread held up shows as the gap it left. A main-thread sample says how
//  busy a scene is; this says whether it ever stutters, which is what a
//  wearer sees. Each line names what was on screen.
//

#if DEBUG
import QuartzCore
import RealityKit
import SwiftUI

struct FrameLogView: View {
    /// What the lines are labelled with: the lab, or the home.
    let scene: () -> String
    @State private var log = FrameLog()

    var body: some View {
        RealityView { content in
            log.subscription = content.subscribe(to: SceneEvents.Update.self) { [weak log] _ in
                log?.tick(scene: scene())
            }
        }
        .onDisappear {
            log.subscription?.cancel()
            log.subscription = nil
        }
    }
}

@MainActor
final class FrameLog {
    var subscription: EventSubscription?
    private var last: CFTimeInterval?
    private var intervals: [Double] = []
    private var windowStart: CFTimeInterval?
    private var label = ""

    /// How long a window runs before it is reported, seconds.
    static let window = 5.0
    /// A long frame: half again a 90 Hz frame.
    static let long = 1.5 / 90.0

    func tick(scene: String) {
        let now = CACurrentMediaTime()
        if scene != label {
            report(until: now)
            label = scene
            last = nil
        }
        if let last {
            let interval = now - last
            intervals.append(interval)
            // A frame twice the budget is named on its own, with when.
            if interval > 2 / 90.0 {
                LaunchTrace.mark("[frames] \(label) dropped: "
                                 + String(format: "%.1f", interval * 1000) + " ms")
            }
        }
        last = now
        if windowStart == nil { windowStart = now }
        if let windowStart, now - windowStart >= Self.window { report(until: now) }
    }

    private func report(until now: CFTimeInterval) {
        defer {
            intervals.removeAll(keepingCapacity: true)
            windowStart = now
        }
        guard intervals.count > 10 else { return }
        let sorted = intervals.sorted()
        let ms = { (value: Double) in String(format: "%.1f", value * 1000) }
        let median = sorted[sorted.count / 2]
        let p99 = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.99))]
        let long = sorted.filter { $0 > Self.long }.count
        print("[frames] \(label): \(sorted.count) frames, median \(ms(median)) ms, "
              + "99th \(ms(p99)) ms, worst \(ms(sorted.last ?? 0)) ms, \(long) long")
    }
}
#endif
