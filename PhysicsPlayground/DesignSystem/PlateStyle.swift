//
//  PlateStyle.swift
//  Physics Playground — DesignSystem
//
//  The one switch plate geometry both banks build from — the banks differ
//  in material, never silhouette; a test asserts they use these numbers.
//

import Foundation

/// Shared geometry for a bank's switch plate, whichever bank hangs it.
enum PlateStyle {
    static let width: Float = 0.086
    static let height: Float = 0.050
    /// 80 % of the way to a full lozenge — where visionOS's own panels sit.
    static let corner: Float = 0.020
    static let depth: Float = 0.009
    /// The edge hairline pane behind the plate.
    static let edgeDepth: Float = 0.008
    /// How far a lamp or icon stands proud of the plate's centre.
    static let faceLift: Float = 0.006
    // MARK: The two nameplate sizes
    // Two sizes because two reading distances: arm's length vs across the
    // room. Not drift — do not merge them.

    /// A nameplate on something you can touch: bank plates, wells,
    /// picker discs, rail beads, folding tabs, the multimeter.
    static let labelSize: CGFloat = 0.0104
    /// A nameplate read from across the room: gallery exhibits, the
    /// bodies in an orrery, the voltage skyline's towers.
    static let exhibitLabelSize: CGFloat = 0.030
    static let labelGap: Float = 0.008
}
