//
//  PlateStyle.swift
//  Physics Playground — DesignSystem
//
//  The one switch plate, measured once.
//
//  The two banks deliberately differ in MATERIAL — frosted glass for a
//  state, machined stock for a verb, "a verb and a state must not be
//  the same object in two colours" — and deliberately matched their
//  corner radius. But their depths had drifted (0.007 vs 0.009 thick,
//  0.006 vs 0.008 edge), because each file typed its own numbers on a
//  different day. Family resemblance is carried by the SILHOUETTE, and
//  two plates of different thickness hanging in the same room read as
//  two design systems.
//
//  The action bank's chunkier stock won: a plate is a physical control,
//  and the thicker edge catches the hairline better. A test asserts the
//  two banks actually build from these numbers, so the drift cannot
//  quietly reopen.
//

import Foundation

/// Shared geometry for a bank's switch plate, whichever bank hangs it.
enum PlateStyle {
    static let width: Float = 0.086
    static let height: Float = 0.050
    /// 0.020 of a 0.050-tall plate — 80 % of the way to a full lozenge,
    /// which is where visionOS's own panels sit (the layer bank's
    /// original derivation).
    static let corner: Float = 0.020
    static let depth: Float = 0.009
    /// The edge hairline pane behind the plate.
    static let edgeDepth: Float = 0.008
    /// How far a lamp or icon stands proud of the plate's centre.
    static let faceLift: Float = 0.006
    static let labelSize: CGFloat = 0.0104
    static let labelGap: Float = 0.008
}
