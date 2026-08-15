//
//  VignettePropTests.swift
//  Physics Playground — app tests
//
//  The props the hub miniatures load — `Tools/moduleprops.py` for the
//  six modules' apparatus, `Tools/vignetteprops.py` for the labs emblem
//  — and the one thing about them that cannot be checked by looking at
//  either side on its own: which way round they come out.
//
//  Blender is Z-up and RealityKit is Y-up, and the exporter is told to
//  convert with forward −Z and up +Y, which lands on
//
//      Blender (x, y, z)  ->  RealityKit (x, z, -y)
//
//  Every prop below is authored against that mapping and then placed by
//  Swift code that assumes the result. Nothing catches a mistake in
//  between: a ring authored in the wrong plane still loads, still
//  renders, and simply faces the wall. The multimeter has a comment
//  about exactly this — its first version stood its dial and both jacks
//  on edge, "one render, immediately obvious; unreadable from the source
//  alone."
//
//  These tests are that render, in a form that runs on every build.
//

import XCTest
import RealityKit
import simd
@testable import PhysicsPlayground

@MainActor
final class VignettePropTests: XCTestCase {

    private func extents(of name: String) throws -> SIMD3<Float> {
        let loaded = try XCTUnwrap(try? Entity.load(named: name),
                                   "\(name).usdz is not in the bundle — run "
                                   + "Tools/moduleprops.py / vignetteprops.py")
        let box = loaded.visualBounds(relativeTo: nil).extents
        XCTAssertGreaterThan(min(box.x, min(box.y, box.z)), 0,
                             "\(name) has no thickness on some axis")
        return box
    }

    /// Everything the miniatures load, loads. A miniature falls back to
    /// primitives when an asset is missing, which is the right behaviour
    /// and also completely silent — so the only way a dropped file gets
    /// noticed is here.
    func testEveryPropTheMiniaturesAskForExists() throws {
        for name in ["BarMagnet", "PendulumStand", "PendulumBob",
                     "CompassBody", "CompassNeedle",
                     "LauncherCarriage", "QuadrantPointer", "TargetStand",
                     "CometNucleus", "ChargePlus", "ChargeMinus",
                     "GyroGimbalOuter", "GyroGimbalInner", "GyroRotor",
                     "CircuitBattery", "CircuitBulb", "CircuitSwitch",
                     "LauncherBarrel"] {
            _ = try extents(of: name)
        }
    }

    /// The bar magnet lies along X, which is the axis
    /// `HubVignettes.magnetism()` separates the pair along. Authored up
    /// Blender's Z instead, it would arrive standing on end and the two
    /// bars would approach each other sideways.
    func testTheBarMagnetLiesAlongX() throws {
        let box = try extents(of: "BarMagnet")
        XCTAssertGreaterThan(box.x, box.y * 2, "the magnet is not a BAR")
        XCTAssertEqual(box.y, box.z, accuracy: box.y * 0.35,
                       "the magnet's section should be near square")
    }

    /// The stand is wider than it is tall and taller than it is deep —
    /// beam along X, standing up Y. On its back, the pendulums would
    /// hang out of the exhibit toward the reader.
    func testTheStandStandsUp() throws {
        let box = try extents(of: "PendulumStand")
        XCTAssertGreaterThan(box.x, box.y,
                             "the stand should be wider than it is tall")
        XCTAssertGreaterThan(box.y, box.z,
                             "the stand is deeper than it is tall — it has "
                             + "probably arrived lying on its back")
    }

    /// The bob hangs up Y: sphere below, stem and eye above. Its height
    /// is its longest span, which is also what the importer normalises
    /// on — `hang` computes the eye's position from exactly that ratio.
    func testTheBobHangsUpY() throws {
        let box = try extents(of: "PendulumBob")
        XCTAssertGreaterThan(box.y, box.x,
                             "the bob's stem and eye should make Y its "
                             + "longest axis")
        XCTAssertEqual(box.x, box.z, accuracy: box.x * 0.1,
                       "the bob is not round in plan")
    }

    /// The compass is a dish lying dial-up: thin on Y, round in XZ. On
    /// edge, the needle would sweep through the bowl.
    func testTheCompassLiesDialUp() throws {
        let box = try extents(of: "CompassBody")
        XCTAssertLessThan(box.y, min(box.x, box.z) * 0.5,
                          "the compass bowl is on edge — its axis is not Y")
        XCTAssertEqual(box.x, box.z, accuracy: box.x * 0.08,
                       "the bowl is not round")
    }

    /// The needle lies along X — north at +X, the handedness
    /// `magnetism()` steers by — and is symmetric about its pivot, which
    /// is the property that lets the importer's box-centring BE the
    /// pivot.
    func testTheNeedleLiesAlongX() throws {
        let box = try extents(of: "CompassNeedle")
        XCTAssertGreaterThan(box.x, box.z * 3, "the needle is not a needle")
        XCTAssertGreaterThan(box.x, box.y * 3,
                             "the needle stands on end")
    }

    /// The pointer is a long X spike too: its authored origin is its
    /// hinge, and `projectile()` un-centres it after import on the
    /// assumption that the long axis arrives along X.
    func testThePointerLiesAlongX() throws {
        let box = try extents(of: "QuadrantPointer")
        XCTAssertGreaterThan(box.x, box.y * 3, "the pointer is not a spike")
        XCTAssertGreaterThan(box.x, box.z * 3,
                             "the pointer is fatter than it is long in Z")
    }

    /// The target's ring is HORIZONTAL — the ball falls through it — so
    /// the stand's width (mast plus ring reach) beats its height, and
    /// its height beats its depth.
    func testTheTargetRingIsHorizontal() throws {
        let box = try extents(of: "TargetStand")
        XCTAssertGreaterThan(box.x, box.y,
                             "the ring should reach sideways off the mast")
        XCTAssertGreaterThan(box.y, box.z * 0.9,
                             "the stand has fallen over")
    }

    /// The comet is bilobed ALONG X: two overlapping lobes, so X is the
    /// long axis and neither of the others comes close. A sphere here
    /// would mean the displacement or the second lobe went missing.
    func testTheCometIsBilobedAlongX() throws {
        let box = try extents(of: "CometNucleus")
        XCTAssertGreaterThan(box.x, box.y * 1.25,
                             "the nucleus is round — the second lobe is missing")
        XCTAssertGreaterThan(box.x, box.z * 1.25,
                             "the nucleus is round — the second lobe is missing")
    }

    /// Each charge is a round conductor whose moulded sign stands proud
    /// on +Z, the reader's side. The sign is sub-millimetre proud, but
    /// it is the only thing that breaks the sphere's symmetry — so Z
    /// strictly beats both other axes, and equality here means the sign
    /// is buried or facing the wall.
    func testTheChargeSignsFaceTheReader() throws {
        for name in ["ChargePlus", "ChargeMinus"] {
            let box = try extents(of: name)
            XCTAssertEqual(box.x, box.y, accuracy: box.x * 0.03,
                           "\(name) is not round")
            XCTAssertGreaterThan(box.z, box.x * 1.005,
                                 "\(name)'s sign does not stand proud toward "
                                 + "the reader")
            XCTAssertLessThan(box.z, box.x * 1.1,
                              "\(name)'s Z span is far beyond a moulded sign "
                              + "— something else is sticking out")
        }
    }

    /// Both gimbal rings and the rotor FACE the reader: their axis is Z,
    /// so Z is the thin one. This is the assertion that catches the
    /// Blender-Y trick going wrong, and it is the whole reason the
    /// emblem is authored with a 90° rotation it would not otherwise
    /// need.
    func testTheGyroscopePartsFaceTheReader() throws {
        for name in ["GyroGimbalOuter", "GyroGimbalInner"] {
            let box = try extents(of: name)
            XCTAssertLessThan(box.z, min(box.x, box.y) * 0.5,
                              "\(name) is edge-on — its axis is not Z")
            // Near-round, not exactly round: each ring carries two pivot
            // bosses, and they stand proud on the axis that ring turns
            // about — which is 90° apart between the two of them, and is
            // the entire difference between a gimbal and a pair of
            // hoops. A ring that measured perfectly round here would
            // mean the bearings had gone missing.
            XCTAssertEqual(box.x, box.y, accuracy: min(box.x, box.y) * 0.15,
                           "\(name) is not round in the XY plane")
            XCTAssertNotEqual(box.x, box.y, accuracy: min(box.x, box.y) * 0.02,
                              "\(name) has no pivot bosses standing proud")
        }
    }

    /// The rotor's longest dimension is its AXLE, along the spin axis.
    /// `HubVignettes` normalises on the longest dimension, so this ratio
    /// is what actually decides how big the disc looks inside the rings
    /// — changing the axle length in the script silently resizes the
    /// wheel in the app.
    func testTheRotorIsAxleDominant() throws {
        let box = try extents(of: "GyroRotor")
        XCTAssertGreaterThan(box.z, box.x,
                             "the rotor's axle should be its longest span")
        XCTAssertEqual(box.x, box.y, accuracy: box.x * 0.08,
                       "the rotor disc is not round")
    }

    /// The launcher barrel points up +Y, which is the contract
    /// `KinematicsRenderer` already relies on ("0.30 m base-to-muzzle
    /// along +Y") and which the miniature now shares — it slides the
    /// barrel up half its own length to put the breech on the origin.
    func testTheLauncherBarrelPointsUp() throws {
        let box = try extents(of: "LauncherBarrel")
        XCTAssertGreaterThan(box.y, box.x * 2,
                             "the barrel is not aligned with +Y")
    }
}
