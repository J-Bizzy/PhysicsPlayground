//
//  AppSettingsTests.swift
//  PhysicsPlaygroundTests
//
//  The settings model: every preference survives a relaunch (a fresh
//  AppSettings reads back what the last one wrote), the master volume
//  actually reaches the sound engine, and the two reset actions clear
//  exactly what they claim to.
//

import XCTest
@testable import PhysicsPlayground

@MainActor
final class AppSettingsTests: XCTestCase {

    // `settings.timeCapsule` was missing from this list until 2026-09-01,
    // so a preference left behind by a simulator session could leak into
    // "first launch" and neither test below ever touched the capsule.
    private static let keys = [
        "settings.masterVolume",
        "settings.ambientAudio", "settings.seenHints",
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
        XCTAssertTrue(settings.seenHints.isEmpty)
        // ON since 2026-09-01 (DECISIONS.md) — and the gate the models
        // read must agree with the preference, or a first launch would
        // record nothing until Settings was opened.
        XCTAssertTrue(settings.timeCapsule)
        XCTAssertTrue(TimeCapsuleSettings.isEnabled)
    }

    func testEveryPreferenceSurvivesRelaunch() {
        let settings = AppSettings()
        settings.masterVolume = 0.4
        settings.ambientAudio = false
        settings.timeCapsule = false
        settings.markHintSeen("circuits")
        settings.markHintSeen("waves")

        // A second instance is a relaunch: nothing but UserDefaults
        // connects the two.
        let relaunched = AppSettings()
        XCTAssertEqual(relaunched.masterVolume, 0.4)
        XCTAssertFalse(relaunched.ambientAudio)
        // OFF is the non-default now, so it is the direction that has to
        // persist — and reach the recording gate without Settings' help.
        XCTAssertFalse(relaunched.timeCapsule)
        XCTAssertFalse(TimeCapsuleSettings.isEnabled,
                       "the relaunch must hand the stored answer to the gate")
        XCTAssertTrue(relaunched.hasSeenHint("circuits"))
        XCTAssertTrue(relaunched.hasSeenHint("waves"))
        XCTAssertFalse(relaunched.hasSeenHint("pendulums"))
    }

    /// The criterion the ON default rests on: a first launch records
    /// without anyone visiting Settings. Built the way a launch builds
    /// it — settings first, then a model that steps — and asked the one
    /// question that matters, whether there is anything to scrub.
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

    func testResetOnboardingTipsShowsEveryHintAgain() {
        let settings = AppSettings()
        settings.markHintSeen("circuits")

        settings.resetOnboardingTips()

        XCTAssertFalse(settings.hasSeenHint("circuits"))
        let relaunched = AppSettings()
        XCTAssertTrue(relaunched.seenHints.isEmpty, "the reset persists")
    }

    // `testExperimentResetWipesProgressAndStreak` was deleted here on
    // 2026-08-09 along with `ExperimentProgress` itself. It covered
    // Settings → Reset experiment progress, which is also gone.
}
