//
//  CushionTests.swift
//  How much the sender gathers before it sends anything.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

import XCTest
@testable import AirplayKitSender

/**
 The cushion between a live source and the speaker.

 Measured on 2026-09-24 against a Sonos: without one, the ring sat 0.07 seconds
 from empty for a whole session, because the pump began draining the moment the
 first packet landed and from then on consumed at exactly the rate the source
 produced. Every hiccup in the source therefore reached the speaker as a hole,
 which is heard as crackle.

 The one thing in here that can be quietly wrong is the unit. The ring counts
 samples and the cushion is named in frames, so a comparison that mixes them is
 out by the channel count. Too small a cushion sounds exactly like the fault it
 was meant to cure, and too large a one is latency nobody asked for.
 */
final class CushionTests: XCTestCase {

    func testTheCushionIsHalfASecondOfAudio() {
        XCTAssertEqual(Double(AirPlaySender.primeFrames) / Double(ALACFrame.sampleRate), 0.5)
    }

    func testAnEmptyRingHasNoCushion() {
        XCTAssertFalse(AirPlaySender.hasCushion(samplesHeld: 0))
    }

    func testTheCushionIsCountedInSamplesRatherThanFrames() {
        // Half a second of stereo is 22050 frames, which is 44100 samples. A
        // comparison against the frame count alone would call the first of
        // these enough, and it is half of what was asked for.
        let frames = AirPlaySender.primeFrames

        XCTAssertFalse(AirPlaySender.hasCushion(samplesHeld: frames))
        XCTAssertTrue(AirPlaySender.hasCushion(samplesHeld: frames * ALACFrame.channelCount))
    }

    func testOneSampleShortIsStillShort() {
        let needed = AirPlaySender.primeFrames * ALACFrame.channelCount

        XCTAssertFalse(AirPlaySender.hasCushion(samplesHeld: needed - 1))
        XCTAssertTrue(AirPlaySender.hasCushion(samplesHeld: needed))
    }

    func testTheCushionFitsInsideTheLeadTheAnchorBought() {
        // It is paid for with silence at the start, which costs the listener
        // nothing only whilst it fits inside the lead. A cushion larger than
        // that would delay the first sound by the difference.
        let cushion = Double(AirPlaySender.primeFrames) / Double(ALACFrame.sampleRate)

        XCTAssertLessThan(cushion, AirPlaySender.anchorLead)
    }

    func testTheRingHoldsSeveralCushionsSoASourceRunningAheadIsNotRefused() {
        // The cushion is a standing distance from empty, not the capacity. A
        // ring only as large as the cushion would refuse a source that ran
        // briefly ahead, and refusing a live source drops audio.
        let cushion = AirPlaySender.primeFrames * ALACFrame.channelCount
        let capacity = AirPlaySender.ringFrames * ALACFrame.channelCount

        XCTAssertGreaterThanOrEqual(capacity, cushion * 4)
    }
}
