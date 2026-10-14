//
//  AmbientScoreTests.swift
//  PhysicsPlaygroundTests
//
//  The house music is rendered on the device, once, and then lives in
//  Caches for good — so what a listener would notice has to be pinned
//  here: that it loops without a seam, that it is no louder than the pad
//  it replaced, that it is actually stereo, and that every device writes
//  the same file. Rendered at 8 kHz: the properties do not depend on the
//  rate, and the test stays quick.
//

import XCTest
@testable import PhysicsPlayground

final class AmbientScoreTests: XCTestCase {

    private static let rate = 8_000.0
    private static let score = AmbientScore.render(sampleRate: rate)

    func testItIsOneStereoPassOfTheLoop() {
        let (left, right) = Self.score
        XCTAssertEqual(left.count, Int(AmbientScore.loopSeconds * Self.rate))
        XCTAssertEqual(left.count, right.count)
        for sample in left + right {
            XCTAssertTrue(sample.isFinite)
            XCTAssertLessThanOrEqual(abs(sample), Float(AmbientScore.ceiling) + 0.001,
                                     "something got past the limiter")
        }
    }

    /// The jump from the last sample back to the first must be no bigger
    /// than an ordinary step inside the music — a seam would be a click
    /// every 64 seconds for as long as the app is open.
    func testTheLoopHasNoSeam() {
        let (left, right) = Self.score
        for channel in [left, right] {
            var steps: [Float] = []
            for i in 1..<channel.count { steps.append(abs(channel[i] - channel[i - 1])) }
            steps.sort()
            let typical = steps[Int(Double(steps.count) * 0.99)]
            let seam = abs(channel[0] - channel[channel.count - 1])
            XCTAssertLessThanOrEqual(seam, typical, """
                the loop jumps \(seam) at the seam, more than 99 % of the \
                steps inside it (\(typical)): that is a click
                """)
        }
    }

    /// The same loudness as the mono pad it replaced, in both ears.
    func testItIsAsLoudAsThePadItReplacedAndBalanced() {
        let (left, right) = Self.score
        func rmsDecibels(_ x: [Float]) -> Double {
            let mean = x.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(x.count)
            return 10 * log10(mean)
        }
        let target = 20 * log10(AmbientScore.targetRMS)
        XCTAssertEqual(rmsDecibels(left), target, accuracy: 0.5)
        XCTAssertEqual(rmsDecibels(right), target, accuracy: 0.5)
    }

    /// Stereo in name only would be two copies of one channel.
    func testItIsGenuinelyWide() {
        let (left, right) = Self.score
        var dot = 0.0, ll = 0.0, rr = 0.0
        for i in left.indices {
            dot += Double(left[i] * right[i])
            ll += Double(left[i] * left[i])
            rr += Double(right[i] * right[i])
        }
        XCTAssertLessThan(dot / sqrt(ll * rr), 0.9)
    }

    /// The cache is keyed by file name, so a score that differed between
    /// renders would differ between devices and never be rewritten.
    func testEveryRenderIsTheSame() {
        let again = AmbientScore.render(sampleRate: Self.rate)
        XCTAssertEqual(again.left, Self.score.left)
        XCTAssertEqual(again.right, Self.score.right)
    }

    /// The four chords hand over through shared tones: each shares at
    /// least one pitch class with the next, the last with the first.
    func testEachChordSharesAToneWithTheNext() {
        let chords = AmbientScore.progression
        for (index, chord) in chords.enumerated() {
            let next = chords[(index + 1) % chords.count]
            let here = Set(chord.notes.map { $0 % 12 })
            let there = Set(next.notes.map { $0 % 12 })
            XCTAssertFalse(here.isDisjoint(with: there),
                           "chord \(index) and the next share no tone")
        }
    }
}
