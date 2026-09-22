//
//  ReceiverStateTests.swift
//  The four states a receiver was measured reporting, held against the reading of them.
//
//  Copyright © 2026 cocoa:naut. All rights reserved.
//

import CPlayableAirplay
import XCTest

@testable import PlayableAirplay

final class ReceiverStateTests: XCTestCase {
    /// Reads a status field the way discovery does, and hands back both answers.
    private func read(_ flags: String) -> (hasSender: Bool, isPlaying: Bool) {
        var hasSender = false
        var isPlaying = false

        var bytes = Array(flags.utf8)
        bytes.withUnsafeMutableBytes { buffer in
            pa_read_receiver_state(buffer.baseAddress, buffer.count, &hasSender, &isPlaying)
        }

        return (hasSender, isPlaying)
    }

    // The four values below were read off a HomePod mini on 2026-09-22, from its
    // Bonjour record and from its own /info at the same four moments, and they
    // agreed every time. They are the whole of what this reading rests on, so a
    // change to the bit masks has to fail here.

    func testARestingReceiverReportsNeither() {
        let state = read("0x80404")

        XCTAssertFalse(state.hasSender)
        XCTAssertFalse(state.isPlaying)
    }

    func testAReceiverPlayingReportsBoth() {
        let state = read("0x1a0c04")

        XCTAssertTrue(state.hasSender)
        XCTAssertTrue(state.isPlaying)
    }

    func testAReceiverStoppedButStillHeldReportsOnlyTheSender() {
        let state = read("0xa0c04")

        XCTAssertTrue(state.hasSender)
        XCTAssertFalse(state.isPlaying)
    }

    func testAReceiverThatWasDisconnectedGoesBackToNeither() {
        let state = read("0x80404")

        XCTAssertFalse(state.hasSender)
        XCTAssertFalse(state.isPlaying)
    }

    /// Every Sonos on that network advertised this, whatever it was doing.
    func testAReceiverThatDoesNotReportItsStateAnswersFalse() {
        let state = read("0x4")

        XCTAssertFalse(state.hasSender)
        XCTAssertFalse(state.isPlaying)
    }

    func testAFieldWithoutItsPrefixIsStillRead() {
        let state = read("1a0c04")

        XCTAssertTrue(state.hasSender)
        XCTAssertTrue(state.isPlaying)
    }

    /// A receiver that publishes nothing, and one that publishes nonsense, are
    /// both a receiver not saying it is busy rather than one saying it is free.
    func testAnUnreadableFieldAnswersFalse() {
        XCTAssertFalse(read("").hasSender)
        XCTAssertFalse(read("not a number").hasSender)
        XCTAssertFalse(read("not a number").isPlaying)
    }

    /// The value is counted rather than terminated where it arrives, so a reader
    /// that trusted a terminator would run past the end of it.
    func testOnlyTheCountedBytesAreRead() {
        var hasSender = false
        var isPlaying = false

        var bytes = Array("0x1a0c04 and whatever follows it".utf8)
        bytes.withUnsafeMutableBytes { buffer in
            pa_read_receiver_state(buffer.baseAddress, 8, &hasSender, &isPlaying)
        }

        XCTAssertTrue(hasSender)
        XCTAssertTrue(isPlaying)
    }
}
