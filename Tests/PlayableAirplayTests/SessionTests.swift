//
//  SessionTests.swift
//  What the session and the discovery do when they are handed nothing usable.
//
//  Copyright © 2026 cocoa:naut. All rights reserved.
//

import XCTest

@testable import PlayableAirplay

final class SessionTests: XCTestCase {
    func testRefusesAReceiverItCannotUse() {
        XCTAssertThrowsError(try AirPlaySession(host: "", port: 7000, senderName: "test")) { error in
            XCTAssertEqual(error as? AirPlayError, .invalidRequest)
        }

        XCTAssertThrowsError(try AirPlaySession(host: "somewhere.local", port: 0, senderName: "test")) { error in
            XCTAssertEqual(error as? AirPlayError, .invalidRequest)
        }
    }

    func testEveryFailureSaysWhatItMeans() {
        let all: [AirPlayError] = [.unreachable, .pairingRefused, .sessionEnded, .invalidRequest, .senderFailed]

        for failure in all {
            XCTAssertFalse(failure.description.isEmpty, "\(failure) says nothing")
            XCTAssertNotEqual(failure.description, "unknown", "\(failure) is not described")
        }
    }

    func testDiscoveryStartsAndStops() {
        // Whether anything is found depends on the network, which a test must
        // not, and whether browsing can start at all depends on an mDNS
        // responder. What is checked is that both paths come back.
        let discovery = AirPlayDiscovery { _ in }
        discovery.stop()
        discovery.stop()
    }
}
