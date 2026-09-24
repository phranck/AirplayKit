//
//  ProtocolConstantsTests.swift
//  The facts about the wire format that are written down twice.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

import CPlayableAirplay
import XCTest
@testable import PlayableAirplay
@testable import PlayableAirplaySender

/**
 The sample rate and the channel count, which the C header and the Swift sender
 each declare.

 A C header cannot read a Swift constant, so the two cannot be reduced to one.
 They are one fact all the same: a caller sizes its buffers from the header and
 the stream is built from the Swift side, and nothing in either would report a
 difference. What it would produce is audio at the wrong rate or with the
 channels interleaved wrongly, which is heard rather than reported.

 So they are compared here. This is the last resort of the three, and it is the
 right one only because neither can be derived from the other.
 */
final class ProtocolConstantsTests: XCTestCase {

    func testTheHeaderAndTheSenderAgreeOnTheSampleRate() {
        XCTAssertEqual(Int(PA_SAMPLE_RATE), ALACFrame.sampleRate)
    }

    func testTheHeaderAndTheSenderAgreeOnTheChannelCount() {
        XCTAssertEqual(Int(PA_CHANNELS), ALACFrame.channelCount)
    }

    func testWhatASessionTellsACallerIsWhatGoesOnTheWire() {
        // The public surface used to take these from the header whilst the
        // stream took them from the sender, so a caller could be told one thing
        // and have another sent.
        XCTAssertEqual(AirPlaySession.sampleRate, ALACFrame.sampleRate)
        XCTAssertEqual(AirPlaySession.channelCount, ALACFrame.channelCount)
    }
}
