//
//  RotationTests.swift
//  PhysicsPlaygroundTests
//
//  WHAT THE AUDIT GOT WRONG, recorded here because the next person to
//  read P0-1 will otherwise go looking for a NaN that is not there.
//
//  `AUDIT_2026-08-07.md` P0-1 says of the Bloom grip's leader rod that
//  "either a NaN transform propagates into the leader subtree or the rod
//  lands at an arbitrary orientation". Measured on this platform,
//  neither happens:
//
//      simd_quatf(from: [0,1,0], to: [0,-1,0])  ->  π about [0,0,-1]
//      simd_quatf(from: [1,0,0], to: [ 1,0,0])  ->  identity
//
//  Apple's implementation resolves both degenerate ends deterministically
//  and correctly maps `a` to `b`. So there is no NaN anywhere in the
//  app today, and for the rotationally symmetric geometry at most of the
//  thirteen sites — a cylinder rod, an arrow shaft, a compass needle —
//  the arbitrary roll it picks is invisible.
//
//  Two things are nonetheless true and are what these tests pin:
//
//  1. The behaviour is UNSPECIFIED. `simd_quatf(from:to:)` documents no
//     answer for opposed vectors; the app is reading a value the library
//     does not promise, at thirteen sites, in every lab.
//  2. At one site the roll it picks is VISIBLE and wrong.
//     `CircuitsRenderer` aims a part along its model axis from a rest
//     axis of [1,0,0]. Drag a resistor end-for-end — axis [-1,0,0] — and
//     the library's choice is π about +Z, which lands the part UPSIDE
//     DOWN rather than turned around. `testAHorizontalFlipKeepsUpPointingUp`
//     is that case, and it fails against the bare library call.
//
//  So this is a robustness fix with one real visible defect inside it,
//  not the app-wide NaN the audit describes.
//

import XCTest
import RealityKit
import RenderKit
import simd
@testable import PhysicsPlayground

@MainActor
final class RotationTests: XCTestCase {

    // MARK: The criterion

    /// A sweep over the whole domain INCLUDING both degenerate poles,
    /// rather than a list of the pairs somebody thought of. The property
    /// is the definition: the returned rotation must take `a` to `b`,
    /// and must be a unit quaternion made of real numbers.
    func testRotationTakesAToBEverywhereOnTheSphere() {
        var directions: [SIMD3<Float>] = [
            [0, 1, 0], [0, -1, 0], [1, 0, 0], [-1, 0, 0], [0, 0, 1], [0, 0, -1],
        ]
        // Off-axis samples, so the poles are not the only thing covered.
        for i in 0..<7 {
            let theta = Float(i) * .pi / 6
            for j in 0..<7 {
                let phi = Float(j) * .pi / 3
                directions.append([sin(theta) * cos(phi), cos(theta), sin(theta) * sin(phi)])
            }
        }

        for a in directions {
            for b in directions {
                let ua = simd_normalize(a), ub = simd_normalize(b)
                let q = rotation(from: ua, to: ub)

                XCTAssertTrue(q.vector.x.isFinite && q.vector.y.isFinite
                              && q.vector.z.isFinite && q.vector.w.isFinite,
                              "rotation(from: \(ua), to: \(ub)) is not a number")
                XCTAssertEqual(simd_length(q.vector), 1, accuracy: 1e-3,
                               "rotation(from: \(ua), to: \(ub)) is not a unit quaternion")

                let landed = q.act(ua)
                XCTAssertEqual(simd_distance(landed, ub), 0, accuracy: 1e-3,
                               "rotation(from: \(ua), to: \(ub)) landed on \(landed)")
            }
        }
    }

    /// The one degenerate case whose ARBITRARY answer is visible in the
    /// app. A circuit part dragged end-for-end must turn around, not
    /// roll onto its back. `simd_quatf(from: [1,0,0], to: [-1,0,0])`
    /// returns π about +Z and fails this; `rotation` picks the axis that
    /// leaves world up alone.
    func testAHorizontalFlipKeepsUpPointingUp() {
        let flip = rotation(from: [1, 0, 0], to: [-1, 0, 0])
        XCTAssertEqual(simd_distance(flip.act([1, 0, 0]), [-1, 0, 0]), 0, accuracy: 1e-4,
                       "the flip did not turn the part around")
        XCTAssertEqual(simd_distance(flip.act([0, 1, 0]), [0, 1, 0]), 0, accuracy: 1e-4,
                       "the part came out upside down — this is CircuitsRenderer's "
                       + "part-axis aim, and it is what the bare library call does")
    }

    /// Degenerate INPUT, as opposed to a degenerate pair: a caller that
    /// forgets to guard a zero-length vector must get identity, not NaN.
    func testAZeroLengthVectorYieldsIdentityRatherThanNaN() {
        for q in [rotation(from: .zero, to: [0, 1, 0]),
                  rotation(from: [0, 1, 0], to: .zero),
                  rotation(from: .zero, to: .zero)] {
            XCTAssertTrue(q.vector.w.isFinite && simd_length(q.vector).isFinite)
            XCTAssertEqual(simd_distance(q.act([1, 2, 3]), [1, 2, 3]), 0, accuracy: 1e-4)
        }
    }

    /// `rotationFromYAxis` is now a name for one row of the table above;
    /// its historical antiparallel answer (π about X) must survive the
    /// promotion, because the arrows' own tests and screenshots rest on it.
    func testTheArrowHelperKeepsItsOldAntiparallelAnswer() {
        let q = VectorFieldArrows.rotationFromYAxis(to: [0, -1, 0])
        XCTAssertEqual(simd_distance(q.act([0, 1, 0]), [0, -1, 0]), 0, accuracy: 1e-4)
        XCTAssertEqual(simd_distance(q.act([1, 0, 0]), [1, 0, 0]), 0, accuracy: 1e-4,
                       "the flip should be about X, as it always was")
    }

    // MARK: Yaw

    /// The seven instruments that turn to face a reader solved a
    /// one-degree-of-freedom problem with a three-degree-of-freedom
    /// tool. `atan2` is exact; these are the four cardinal answers.
    func testYawFacesTheViewerFromEveryQuarter() {
        let origin = SIMD3<Float>(0.3, 1.1, -0.7)
        let cases: [(SIMD3<Float>, SIMD3<Float>)] = [
            ([0, 0, 1], [0, 0, 1]),      // reader on +Z: face stays +Z
            ([0, 0, -1], [0, 0, -1]),
            ([1, 0, 0], [1, 0, 0]),
            ([-1, 0, 0], [-1, 0, 0]),
        ]
        for (toward, expected) in cases {
            guard let q = yaw(facing: origin + toward, from: origin) else {
                return XCTFail("no yaw for a reader at \(toward)")
            }
            XCTAssertEqual(simd_distance(q.act([0, 0, 1]), expected), 0, accuracy: 1e-4)
            // Level: the instrument must never pitch or roll.
            XCTAssertEqual(simd_distance(q.act([0, 1, 0]), [0, 1, 0]), 0, accuracy: 1e-4,
                           "the instrument tipped — a bank that pitches shows its "
                           + "plates edge-on")
        }
    }

    /// Directly overhead carries no yaw. The old code silently kept the
    /// orientation it had; `nil` says so out loud, so a caller cannot
    /// snap an instrument to an arbitrary facing when the reader leans
    /// over it.
    func testAReaderDirectlyOverheadCarriesNoYaw() {
        XCTAssertNil(yaw(facing: [0, 2, 0], from: [0, 1, 0]))
        XCTAssertNotNil(yaw(facing: [0.001, 2, 0], from: [0, 1, 0]))
    }

    // MARK: The grip leader, end to end

    /// The site the audit named: every Bloom grip hangs its value
    /// callout straight down, so `Callout.rebuildLeader` aims a cylinder
    /// from [0,1,0] to exactly [0,-1,0].
    ///
    /// This passes today too — see the header — but it is the contract
    /// the promotion exists to hold, and nothing asserted it before.
    func testAGripLeaderHangingStraightDownIsFiniteAndPointsDown() {
        let callout = Callout(color: .white, textSize: 0.019,
                              offset: SIMD3(0, -0.046, 0))
        callout.setText("1.5 V")

        var rods: [Entity] = []
        func walk(_ entity: Entity) {
            XCTAssertTrue(entity.transform.matrix.columns.3.x.isFinite
                          && entity.transform.matrix.columns.3.y.isFinite
                          && entity.transform.matrix.columns.3.z.isFinite,
                          "\(entity.name) has a non-finite position")
            let v = entity.orientation.vector
            XCTAssertTrue(v.x.isFinite && v.y.isFinite && v.z.isFinite && v.w.isFinite,
                          "\(entity.name) has a non-finite orientation")
            // The rod is the leader's only child, and the only entity in
            // the callout sitting at half the offset.
            if simd_distance(entity.position, SIMD3(0, -0.023, 0)) < 1e-4 {
                rods.append(entity)
            }
            entity.children.forEach(walk)
        }
        walk(callout.root)

        guard let rod = rods.first else {
            return XCTFail("no leader rod — the callout stopped drawing its leader")
        }
        // generateCylinder runs along +Y; aimed down the offset it must
        // end up pointing at the anchor.
        XCTAssertEqual(simd_distance(rod.orientation.act([0, 1, 0]), [0, -1, 0]),
                       0, accuracy: 1e-4,
                       "the leader does not point down the offset it was given")
    }
}
