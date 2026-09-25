//
//  FallingBehindTests.swift
//  What the sender does when it can no longer keep to the anchor it gave.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

import Foundation
import XCTest
@testable import AirplayKitSender

/**
 Slipping past the anchor, and saying so.

 The stream's timestamps advance by a packet per block whatever happens, and the
 anchor turned those timestamps into a promise about when each one sounds. Once
 the pump is later than that promise by more than the lead it was given, the
 receiver discards audio that is already late and the session plays silence
 whilst looking healthy. Only a fresh anchor gets out of that.

 Sending it needs a receiver, so what is checked here is the decision to send
 one and the instrument that reports it.
 */
final class FallingBehindTests: XCTestCase {

    // MARK: - The decision

    func testAPumpOnScheduleHasNotFallenBehind() {
        XCTAssertFalse(AirPlaySender.hasFallenBehindTheAnchor(due: 1000, now: 1000))
    }

    func testAPumpAheadOfItsScheduleHasNotFallenBehind() {
        // Ordinary: the pump sleeps out the difference and nothing is wrong.
        XCTAssertFalse(AirPlaySender.hasFallenBehindTheAnchor(due: 1000.5, now: 1000))
    }

    func testBeingLateByLessThanTheLeadIsAbsorbed() {
        // The lead is what the anchor bought to be spent on exactly this, so
        // being inside it is not yet a fault worth an anchor.
        let almost = AirPlaySender.anchorLead - 0.01

        XCTAssertFalse(AirPlaySender.hasFallenBehindTheAnchor(due: 1000, now: 1000 + almost))
    }

    func testBeingLateByMoreThanTheLeadHasFallenBehind() {
        let past = AirPlaySender.anchorLead + 0.01

        XCTAssertTrue(AirPlaySender.hasFallenBehindTheAnchor(due: 1000, now: 1000 + past))
    }

    func testTheLeadItselfIsStillInsideWhatCanBeAbsorbed() {
        // The boundary, which is where the comparison would sit the wrong way
        // round without anything saying so.
        let lead = AirPlaySender.anchorLead

        XCTAssertFalse(AirPlaySender.hasFallenBehindTheAnchor(due: 1000, now: 1000 + lead))
    }

    // MARK: - The instrument

    func testAClosedSessionReportsNothingSlipped() {
        XCTAssertEqual(AirPlaySender.Underruns.none.fellBehind, 0)
    }

    func testSlippingIsCountedApartFromPaddingAndWaiting() {
        // A padded packet is a hole in the audio and this is the whole stream
        // having gone past its moment, so one reading cannot stand for both.
        let tally = AirPlaySender.Underruns(packets: 3, waited: 0.5, fellBehind: 2)

        XCTAssertEqual(tally.packets, 3)
        XCTAssertEqual(tally.fellBehind, 2)
        XCTAssertNotEqual(tally, .none)
    }
}
