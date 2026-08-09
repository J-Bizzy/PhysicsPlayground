//
//  ScrollGesture.swift
//  RenderKit
//
//  TELLING A SCROLL FROM A PULL, WITHOUT A MODE SWITCH.
//
//  A shelf of objects you can both browse and take from has two drags
//  starting with the same pinch: slide the shelf to see more, or pull one
//  object out. The obvious fix is a scroll bar beside the shelf, which is
//  a control next to a control — the exact clutter a compact shelf exists
//  to remove.
//
//  So they are told apart by which way the hand actually goes, and that
//  rule lives here rather than inside a gesture closure. `simctl` has no
//  tap verb and XCUITest has no entity API, so a rule buried in a closure
//  is one verified by hand, in a headset, forever. This is arithmetic:
//  every interesting case is a unit test and none of them need a hand.
//
//  THE BIAS IS DELIBERATELY NOT 50/50. A hand arcing out of a shelf
//  drifts along it as it goes — wrists rotate — so a pull that only just
//  beats its own sideways component is more likely a scroll that curved.
//  The two mistakes are not equally cheap: a spurious scroll moves the
//  shelf somewhere you can see and undo, while a spurious pull drops an
//  unwanted object into a workspace that may persist across launches.
//
//  (Written for Circuit Workshop's parts drawer on 2026-08-08, deleted
//  with it hours later when the owner rejected the cabinet, and restored
//  the same day when the request came back as "a more general scrolling
//  feature" for the shelf that replaced it. The classifier was never the
//  part that was wrong.)
//

import Foundation
import simd

/// Which of a shelf's two drags this is.
public enum ScrollGesture: Equatable, Sendable {
    case undecided
    case scroll
    case pull

    /// The axis a shelf scrolls along, in its own frame.
    public enum Axis: Sendable {
        case horizontal   // x
        case vertical     // y

        func component(_ travel: SIMD3<Float>) -> Float {
            switch self {
            case .horizontal: travel.x
            case .vertical: travel.y
            }
        }
    }

    /// How much further OUT than along the shelf a hand must travel
    /// before it counts as taking something.
    public static let pullBias: Float = 1.6

    /// Below this the hand has not committed to anything. Deciding
    /// earlier is how a 2 mm tremor becomes a spawned object — the
    /// classifier runs every frame of a drag, and the first frame after
    /// the pinch lands is noise.
    public static let deadZone: Float = 0.012

    /// `travel` is the hand's movement in the shelf's own frame; +z is
    /// out toward the reader.
    public static func classify(travel: SIMD3<Float>,
                                axis: Axis = .horizontal) -> ScrollGesture {
        let along = abs(axis.component(travel))
        // Pushing INTO the shelf is not a pull. Taking the magnitude
        // here would make shoving the shelf backwards hand you an object.
        let out = max(travel.z, 0)
        guard max(along, out) > deadZone else { return .undecided }
        return out > along * pullBias ? .pull : .scroll
    }
}
