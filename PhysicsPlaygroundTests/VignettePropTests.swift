//
//  VignettePropTests.swift
//  Physics Playground — app tests
//
//  The five props `Tools/vignetteprops.py` authors for the hub
//  miniatures, and the one thing about them that cannot be checked by
//  looking at either side on its own: which way round they come out.
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
                                   + "Tools/vignetteprops.py")
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
        for name in ["BarMagnet", "PendulumGantry", "GyroGimbalOuter",
                     "GyroGimbalInner", "GyroRotor",
                     "CircuitBattery", "CircuitBulb", "LauncherBarrel"] {
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

    /// The gantry is wider than it is tall, and stands up Y. It hangs
    /// three pendulums off a crossbeam; on its side it hangs them off
    /// nothing.
    func testTheGantryStandsUp() throws {
        let box = try extents(of: "PendulumGantry")
        XCTAssertGreaterThan(box.x, box.y,
                             "the gantry should be wider than it is tall")
        XCTAssertGreaterThan(box.y, box.z,
                             "the gantry is deeper than it is tall — it has "
                             + "probably arrived lying on its back")
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
