//
//  AppSettingsTests.swift
//  PhysicsPlaygroundTests
//
//  The settings model: every preference survives a relaunch, the master
//  volume reaches the sound engine, and a first launch records without
//  a visit to Settings.
//

import XCTest
@testable import PhysicsPlayground

@MainActor
final class AppSettingsTests: XCTestCase {

    private static let keys = [
        "settings.masterVolume",
        "settings.ambientAudio",
        "settings.timeCapsule",
    ]

    private func clearKeys() {
        for key in Self.keys { UserDefaults.standard.removeObject(forKey: key) }
    }

    override func setUp() {
        super.setUp()
        clearKeys()
    }

    override func tearDown() {
        clearKeys()
        SoundPalette.masterVolume = 1
        // The shipped default, restored for whatever runs next.
        TimeCapsuleSettings.isEnabled = true
        super.tearDown()
    }

    func testDefaultsOnFirstLaunch() {
        let settings = AppSettings()
        XCTAssertEqual(settings.masterVolume, 1.0)
        XCTAssertTrue(settings.ambientAudio)
        // On by default, and the gate the models read must agree with the
        // preference.
        XCTAssertTrue(settings.timeCapsule)
        XCTAssertTrue(TimeCapsuleSettings.isEnabled)
    }

    func testEveryPreferenceSurvivesRelaunch() {
        let settings = AppSettings()
        settings.masterVolume = 0.4
        settings.ambientAudio = false
        settings.timeCapsule = false

        // A second instance is a relaunch: nothing but UserDefaults
        // connects the two.
        let relaunched = AppSettings()
        XCTAssertEqual(relaunched.masterVolume, 0.4)
        XCTAssertFalse(relaunched.ambientAudio)
        // Off is the non-default now, so it is the direction that has to
        // persist — and reach the recording gate without Settings' help.
        XCTAssertFalse(relaunched.timeCapsule)
        XCTAssertFalse(TimeCapsuleSettings.isEnabled,
                       "the relaunch must hand the stored answer to the gate")
    }

    /// A first launch records without anyone visiting Settings, built the
    /// way a launch builds it.
    func testAFirstLaunchRecordsWithoutVisitingSettings() {
        _ = AppSettings()

        let model = KinematicsModel()
        model.roomWalls = []
        model.clearFlights()
        model.fire()
        for _ in 0..<30 { model.step(dt: 1.0 / 90.0) }

        XCTAssertNotNil(model.capsuleSpan,
                        "a fresh install must have a past to scrub the first time it pauses")
    }

    func testMasterVolumeReachesTheSoundEngine() {
        let settings = AppSettings()
        settings.masterVolume = 0.3
        XCTAssertEqual(SoundPalette.masterVolume, 0.3,
                       "the slider must reach the engine live, not on next hub visit")

        // And a relaunch restores it without any surface's help.
        SoundPalette.masterVolume = 1
        _ = AppSettings()
        XCTAssertEqual(SoundPalette.masterVolume, 0.3)
    }

}
