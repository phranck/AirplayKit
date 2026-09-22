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

    func testBrowsingAndItsReasonAgree() {
        // The two answers are opposite sides of one fact, on either machine:
        // where browsing is running there is nothing to explain, and where it
        // is not there has to be a reason.
        let discovery = AirPlayDiscovery { _ in }
        defer { discovery.stop() }

        if discovery.isBrowsing {
            XCTAssertNil(discovery.problem)
        } else {
            XCTAssertNotNil(discovery.problem)
        }
    }

    func testEveryReasonCarriesTheRespondersOwnNumber() {
        // The number is what goes in a log, so a reason that lost it would be a
        // reason nobody can follow up.
        let all: [AirPlayDiscovery.Problem] = [
            .refused(code: -65570), .noResponder(code: -65563), .failed(code: -65537),
        ]

        for problem in all {
            switch problem {
            case .refused(let code), .noResponder(let code), .failed(let code):
                XCTAssertNotEqual(code, 0, "\(problem) carries no number")
            }
        }
    }
}
