//
//  SessionTimingTests.swift
//  Group members keep separate sessions but advertise one timing identity.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

import Foundation
import XCTest
@testable import PlayableAirplaySender

final class SessionTimingTests: XCTestCase {
    func testTwoGroupMembersAdvertiseOneClockAndDistinctSessions() throws {
        let identity = Session.Timing(groupUUID: "GROUP-UUID",
                                      clockIdentifier: Int64(bitPattern: 0x0200_0000_0001_0008),
                                      peerID: "TIMING-PEER",
                                      deviceIdentifier: "02:00:00:00:00:01",
                                      isGroup: true)
        let office = Session.setupProperties(senderName: "PlayableAirplay",
                                             sessionUUID: "OFFICE-SESSION",
                                             localAddress: "10.0.0.193",
                                             timing: identity)
        let dining = Session.setupProperties(senderName: "PlayableAirplay",
                                             sessionUUID: "DINING-SESSION",
                                             localAddress: "10.0.0.193",
                                             timing: identity)

        XCTAssertEqual(office["sessionUUID"] as? String, "OFFICE-SESSION")
        XCTAssertEqual(dining["sessionUUID"] as? String, "DINING-SESSION")
        XCTAssertEqual(office["groupUUID"] as? String, "GROUP-UUID")
        XCTAssertEqual(dining["groupUUID"] as? String, "GROUP-UUID")
        XCTAssertEqual(office["isMultiSelectAirPlay"] as? Bool, true)
        XCTAssertEqual(dining["isMultiSelectAirPlay"] as? Bool, true)

        for body in [office, dining] {
            let peer = try XCTUnwrap(body["timingPeerInfo"] as? [String: Any])
            XCTAssertEqual(peer["ClockID"] as? Int64, identity.clockIdentifier)
            XCTAssertEqual(peer["ID"] as? String, "TIMING-PEER")
            XCTAssertEqual(peer["Addresses"] as? [String], ["10.0.0.193"])
            XCTAssertEqual(body["deviceID"] as? String, "02:00:00:00:00:01")
        }
    }
}
