//
//  LaunchTrace.swift
//  Physics Playground — Shell
//
//  Launch progress in the console, debug builds only: when the props are
//  warm, when the space is ready, when the gallery stands. A launch that
//  shows nothing for seconds needs to say what it is doing.
//

#if DEBUG
import Foundation

@MainActor
enum LaunchTrace {
    private static var start: TimeInterval?

    /// Call once, as early as the app runs.
    static func begin() {
        if start == nil { start = ProcessInfo.processInfo.systemUptime }
    }

    /// One console line, stamped with seconds since `begin`.
    static func mark(_ what: String) {
        let origin = start ?? ProcessInfo.processInfo.systemUptime
        let elapsed = ProcessInfo.processInfo.systemUptime - origin
        print("[launch] +" + String(format: "%.2f", elapsed) + " s  " + what)
    }
}
#endif
