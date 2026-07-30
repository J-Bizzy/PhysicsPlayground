//
//  StationDebug.swift
//  Physics Playground
//
//  Launch-argument plumbing for modules that hold more than one
//  apparatus.
//
//  `-viewScale 2.5` was written when a station WAS a module: one
//  apparatus read the key, one apparatus zoomed, and the CLI got the
//  screenshot it asked for. In a world the same key is read by every
//  station that owns a scale rig, so the circuit bench and the magnetic
//  field both jump to 2.5x together and the screenshot shows a scale
//  nobody chose. Five stations will read it before this is done.
//
//  So inside a world the key is ADDRESSED — `-viewScale.bench 2.5` —
//  and a bare `-viewScale` is refused loudly rather than obeyed twice.
//  Modules that still hold a single apparatus keep reading the bare key
//  directly; there is nothing ambiguous to fix there yet.
//

import Foundation

#if DEBUG
enum StationDebug {
    /// A committed zoom for one named station, or nil if none was asked
    /// for. `double(forKey:)` coerces the string the launch-argument
    /// domain actually stores; `object as? Double` does not.
    static func forcedScale(_ station: String) -> Float? {
        let value = UserDefaults.standard.double(forKey: "viewScale.\(station)")
        guard value > 0 else {
            warnIfBareKeyUsed()
            return nil
        }
        return Float(value)
    }

    /// A bare `-viewScale` inside a multi-station world is almost
    /// certainly someone reaching for the old single-apparatus spelling.
    /// Obeying it would zoom every station at once, which is the bug
    /// this addressing exists to prevent — so say so instead, in the
    /// same spirit as `AppModel`'s unknown-module-id message.
    private static func warnIfBareKeyUsed() {
        guard UserDefaults.standard.double(forKey: "viewScale") > 0,
              !hasWarned else { return }
        hasWarned = true
        print("""
            [debug] -viewScale is ignored inside a multi-station world: \
            it would zoom every station at once. Address it instead — \
            -viewScale.bench, -viewScale.field.
            """)
    }

    private nonisolated(unsafe) static var hasWarned = false
}
#endif
