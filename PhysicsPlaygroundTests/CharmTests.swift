//
//  CharmTests.swift
//  PhysicsPlaygroundTests
//
//  The reactions the charm pass added, held to the physics that makes
//  them: Electric Fields' clack when two free charges first meet (once, not
//  every frame they touch, and not again after a scrub), its pop when the
//  test charge is captured, its whoosh only when a probe is actually
//  launched; and the three remarkable moments — each a gleam, each once a
//  session, each only when the physics truly arrives there: a coupled
//  swing passing wholly across, a coil's LED plainly lit, a laser beam
//  sent back into its own aperture.
//

import XCTest
import PhysicsCore
import simd
@testable import PhysicsPlayground

@MainActor
final class CharmTests: XCTestCase {

    private let dt = 1.0 / 90.0

    override func setUp() {
        super.setUp()
        Remark.forgetForTesting()
    }

    /// Steps `model` and collects every sound it emits along the way.
    private func sounds(_ frames: Int, step: () -> Void,
                        event: () -> SpatialSoundEvent?) -> [SoundPalette.Sound] {
        var heard: [SoundPalette.Sound] = []
        var last = event()?.id
        for _ in 0..<frames {
            step()
            if let now = event(), now.id != last {
                heard.append(now.kind)
                last = now.id
            }
        }
        return heard
    }

    // MARK: Electric Fields

    /// The opening dipole set free: the pair drifts together and meets
    /// once. One clack, as they touch — not one per frame they stay.
    func testFreeChargesClackOnceWhenTheyMeet() {
        let model = FieldModel()
        model.chargesRespond = true
        let heard = sounds(360, step: { model.step(dt: dt) }, event: { model.soundEvent })
        XCTAssertEqual(heard.filter { $0 == .clack }.count, 1, "\(heard)")
        XCTAssertEqual(model.touchingPairs.count, 1)
    }

    /// Restored to a moment the pair already touched, they do not clack
    /// again when the room runs on.
    func testAScrubDoesNotClackAPairThatAlreadyMet() {
        let model = FieldModel()
        model.chargesRespond = true
        _ = sounds(360, step: { model.step(dt: dt) }, event: { model.soundEvent })
        let snapshot = model.captureCapsuleSnapshot()
        model.restoreCapsuleSnapshot(snapshot)
        let heard = sounds(90, step: { model.step(dt: dt) }, event: { model.soundEvent })
        XCTAssertFalse(heard.contains(.clack))
    }

    /// Held charges never set free make no sound meeting: the clack is the
    /// free charges'.
    func testFixedChargesAreSilent() {
        let model = FieldModel()
        let heard = sounds(120, step: { model.step(dt: dt) }, event: { model.soundEvent })
        XCTAssertTrue(heard.isEmpty)
    }

    /// A positive test charge let go beside the negative charge falls in
    /// and is captured: a pop, once.
    func testACapturedTestChargePops() throws {
        let model = FieldModel()
        let negative = try XCTUnwrap(model.charges.first { $0.charge < 0 })
        model.probeIsPositive = true
        model.holdProbe(at: negative.position + SIMD3(0.09, 0, 0))
        model.releaseProbe()
        let heard = sounds(600, step: { model.step(dt: dt) }, event: { model.soundEvent })
        XCTAssertEqual(model.probeStatus, .captured)
        XCTAssertEqual(heard, [.pop])
    }

    /// A whoosh only when a probe actually leaves at speed: let go with B
    /// on (it is launched), never let go into a field without B (it starts
    /// at rest).
    func testAWhooshOnlyWhenTheProbeIsLaunched() {
        let model = FieldModel()
        let before = model.soundEvent?.id
        model.holdProbe(at: SIMD3(0, 1.6, -0.9))
        model.releaseProbe(flick: SIMD3(1.5, 0, 0))
        XCTAssertEqual(model.soundEvent?.id, before, "a probe let go at rest whooshed")

        model.magneticFieldOn = true
        model.holdProbe(at: SIMD3(0, 1.6, -0.9))
        model.releaseProbe(flick: SIMD3(1.5, 0, 0))
        XCTAssertEqual(model.soundEvent?.kind, .whoosh)
    }

    // MARK: Remarkable moments

    func testAMomentIsClaimedOnceASession() {
        XCTAssertTrue(Remark.claim(.firstLight))
        XCTAssertFalse(Remark.claim(.firstLight))
        XCTAssertTrue(Remark.isClaimed(.firstLight))
        XCTAssertTrue(Remark.claim(.beamHome), "one moment claimed another")
    }

    /// The coupled pair, alone: the swing passes wholly into the bob that
    /// started at rest (half a beat, about seven seconds) and gleams there.
    /// It passes back and across again; the session has heard it.
    func testASwingPassingWhollyAcrossGleamsOnce() throws {
        let model = PendulumsModel()
        for pendulum in model.pendulums { model.removePendulum(id: pendulum.id) }
        XCTAssertTrue(model.addCoupledPair())
        let heard = sounds(Int(30 / dt), step: { model.step(dt: dt) }, event: { model.soundEvent })
        XCTAssertEqual(heard.filter { $0 == .gleam }.count, 1, "\(heard)")
    }

    /// Too stiff a spring for one bob ever to hold the whole swing — or no
    /// spring at all — and there is nothing to remark.
    func testNoGleamWithoutAWholeTransfer() throws {
        let model = PendulumsModel()
        for pendulum in model.pendulums { model.removePendulum(id: pendulum.id) }
        XCTAssertTrue(model.addCoupledPair())
        let spring = try XCTUnwrap(model.springs.first)
        model.uncouple(id: spring.a)
        let heard = sounds(Int(20 / dt), step: { model.step(dt: dt) }, event: { model.soundEvent })
        XCTAssertFalse(heard.contains(.gleam))
    }

    /// A magnet carried briskly through a coil lights its LED: a gleam the
    /// first time only. A slow pass, below the LED's knee, never does.
    func testACoilsFirstLightGleamsOnce() throws {
        func pass(_ speed: Double, _ model: MagnetismModel, _ coil: MagnetismModel.Coil,
                  _ magnet: BarMagnet) -> [SoundPalette.Sound] {
            var offset = -0.6
            model.move(id: magnet.id, to: coil.position + coil.axis * offset)
            model.step(dt: dt)
            return sounds(Int(1.2 / speed / dt), step: {
                offset += speed * dt
                model.move(id: magnet.id, to: coil.position + coil.axis * offset)
                model.step(dt: dt)
            }, event: { model.soundEvent })
        }
        let model = MagnetismModel()
        model.dynamicsOn = false
        for extra in model.magnets.dropFirst() { model.removeMagnet(id: extra.id) }
        let coilID = try XCTUnwrap(model.addCoil(at: SIMD3(0, 1.3, -0.6)))
        let coil = try XCTUnwrap(model.coils.first { $0.id == coilID })
        let magnet = try XCTUnwrap(model.magnets.first)
        model.setStrength(id: magnet.id, MagnetismModel.defaultStrength, along: coil.axis)
        model.grab(id: magnet.id)

        XCTAssertFalse(pass(0.2, model, coil, magnet).contains(.gleam), "a slow pass lit it")
        XCTAssertEqual(pass(2, model, coil, magnet).filter { $0 == .gleam }.count, 1)
        XCTAssertFalse(pass(2, model, coil, magnet).contains(.gleam), "it gleamed twice")
    }

    /// A mirror set square to the laser sends the beam back into its
    /// aperture: a gleam from the laser. Turned three degrees, the beam
    /// comes back beside the laser, not into it, and there is nothing.
    func testTheBeamComingHomeGleams() throws {
        let model = OpticsModel()
        model.clearPieces()
        model.laser = .init(position: SIMD3(0, 1.2, -1), aim: SIMD3(1, 0, 0), isOn: true)
        let mirror = try XCTUnwrap(model.addPiece(.mirror, at: SIMD3(0.6, 1.2, -1)))
        let tilt = 3 * Double.pi / 180
        model.aim(id: mirror, toward: SIMD3(0.6 - cos(tilt), 1.2, -1 + sin(tilt)))
        model.traceIfNeeded()
        XCTAssertNotEqual(model.soundEvent?.kind, .gleam, "a beam beside the laser came home")
        XCTAssertFalse(Remark.isClaimed(.beamHome))

        model.aim(id: mirror, toward: SIMD3(0, 1.2, -1))
        model.traceIfNeeded()
        XCTAssertEqual(model.soundEvent?.kind, .gleam)
        XCTAssertTrue(Remark.isClaimed(.beamHome))
    }

    /// The geometry of "home", by itself: back the way the laser points,
    /// through the collar, with most of the power.
    func testWhatCountsAsHome() {
        let aperture = SIMD3<Double>(0, 1, 0), aim = SIMD3<Double>(1, 0, 0)
        func segment(from a: SIMD3<Double>, to b: SIMD3<Double>, power: Double = 0.9) -> LightTracer.Segment {
            .init(a: a, b: b, nanometers: 532, power: power, inside: nil)
        }
        let back = segment(from: SIMD3(0.5, 1.005, 0), to: SIMD3(-1, 1.005, 0))
        XCTAssertTrue(OpticsModel.beamComesHome([back], aperture: aperture, aim: aim))
        let beside = segment(from: SIMD3(0.5, 1.03, 0), to: SIMD3(-1, 1.03, 0))
        XCTAssertFalse(OpticsModel.beamComesHome([beside], aperture: aperture, aim: aim))
        let outgoing = segment(from: aperture, to: SIMD3(2, 1, 0))
        XCTAssertFalse(OpticsModel.beamComesHome([outgoing], aperture: aperture, aim: aim))
        let faint = segment(from: SIMD3(0.5, 1, 0), to: SIMD3(-1, 1, 0), power: 0.04)
        XCTAssertFalse(OpticsModel.beamComesHome([faint], aperture: aperture, aim: aim),
                       "a 4 % glint off glass is not the beam")
        let short = segment(from: SIMD3(0.5, 1, 0), to: SIMD3(0.2, 1, 0))
        XCTAssertFalse(OpticsModel.beamComesHome([short], aperture: aperture, aim: aim),
                       "stopped before it reached the laser")
    }
}
