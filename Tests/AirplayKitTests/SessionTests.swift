//
//  SessionTests.swift
//  What the session and the discovery do when they are handed nothing usable.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

import CAirplayKit
import Foundation
import XCTest

@testable import AirplayKit
@testable import AirplayKitSender

final class SessionTests: XCTestCase {
    func testRefusesAReceiverItCannotUse() {
        XCTAssertThrowsError(try AirPlaySession(host: "", port: 7000, senderName: "test")) { error in
            XCTAssertEqual(error as? AirPlayError, .invalidRequest)
        }

        XCTAssertThrowsError(try AirPlaySession(host: "somewhere.local", port: 0, senderName: "test")) { error in
            XCTAssertEqual(error as? AirPlayError, .invalidRequest)
        }
    }

    func testUnknownSessionHasNoVolume() {
        var level: Float = -1

        XCTAssertFalse(pa_session_get_volume(nil, &level))
        XCTAssertEqual(level, -1)
    }

    func testSwiftVolumeMemoryDefaultsToOptInAndCanToggle() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AirplayKit-public-volume-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("volumes.json")

        let swift = try AirPlayVolumeMemory(fileURL: file)
        XCTAssertFalse(swift.isEnabled)
        swift.isEnabled = true
        XCTAssertTrue(swift.isEnabled)

        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testAnAbsentGroupHasNoAudioToDiscard() {
        XCTAssertEqual(CAirplayKit.pa_group_discard_held_audio(nil), 0)
    }

    func testReceiverEventPreservesTheBodyAndNamesAPropertyListCommand() throws {
        let body = try PropertyListSerialization.data(fromPropertyList: ["type": "updateInfo", "value": ["x": 1]],
                                                      format: .binary, options: 0)
        let event = AirPlaySession.Event(EventChannel.Request(method: "POST", path: "/command", body: body))

        XCTAssertEqual(event.method, "POST")
        XCTAssertEqual(event.path, "/command")
        XCTAssertEqual(event.body, body)
        XCTAssertEqual(event.commandType, "updateInfo")
    }

    func testEveryFailureSaysWhatItMeans() {
        let all: [AirPlayError] = [.unreachable, .pairingRefused, .sessionEnded, .invalidRequest, .senderFailed]

        for failure in all {
            XCTAssertFalse(failure.description.isEmpty, "\(failure) says nothing")
            XCTAssertNotEqual(failure.description, "unknown", "\(failure) is not described")
        }
    }

    func testPairingRefusalSuggestsCheckingHomeSpeakerAccessConditionally() {
        let swiftMessage = AirPlayError.pairingRefused.description
        let cMessage = String(cString: pa_result_description(CResult.pairingRefused.rawValue)!)

        XCTAssertEqual(swiftMessage, cMessage)
        XCTAssertTrue(swiftMessage.contains("If this is a HomePod"))
        XCTAssertTrue(swiftMessage.contains("Home Settings > Speakers & TV"))
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

    // What the responder's numbers are read as. The numbers themselves are the
    // ones Apple's `dns_sd.h` declares, and -65563 is the one measured coming
    // out of a sandboxed application that was denied the network.

    func testTheCodeThatMeansDeniedAndTheCodeThatMeansAbsentReadTheSame() {
        XCTAssertEqual(pa_discovery_problem_for_error(-65563), PADiscoveryProblemNoResponder)
    }

    func testTheCodesThatSayDeniedAreReadAsARefusal() {
        for code in [Int32(-65570), -65571, -65555, -65553] {
            XCTAssertEqual(pa_discovery_problem_for_error(code), PADiscoveryProblemRefused,
                           "\(code) is not read as a refusal")
        }
    }

    func testAnythingElseIsAFailureThatCarriesItsNumber() {
        XCTAssertEqual(pa_discovery_problem_for_error(-65537), PADiscoveryProblemFailed)
        XCTAssertEqual(pa_discovery_problem_for_error(-1), PADiscoveryProblemFailed)
    }

    func testNoErrorIsNoProblem() {
        XCTAssertEqual(pa_discovery_problem_for_error(0), PADiscoveryProblemNone)
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
