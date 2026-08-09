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

    private static let keys = [
        "settings.masterVolume",
        "settings.ambientAudio", "settings.seenHints",
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
        super.tearDown()
    }

    func testDefaultsOnFirstLaunch() {
        let settings = AppSettings()
        XCTAssertEqual(settings.masterVolume, 1.0)
        XCTAssertTrue(settings.ambientAudio)
        XCTAssertTrue(settings.seenHints.isEmpty)
    }

    func testEveryPreferenceSurvivesRelaunch() {
        let settings = AppSettings()
        settings.masterVolume = 0.4
        settings.ambientAudio = false
        settings.markHintSeen("circuits")
        settings.markHintSeen("waves")

        // A second instance is a relaunch: nothing but UserDefaults
        // connects the two.
        let relaunched = AppSettings()
        XCTAssertEqual(relaunched.masterVolume, 0.4)
        XCTAssertFalse(relaunched.ambientAudio)
        XCTAssertTrue(relaunched.hasSeenHint("circuits"))
        XCTAssertTrue(relaunched.hasSeenHint("waves"))
        XCTAssertFalse(relaunched.hasSeenHint("pendulums"))
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
