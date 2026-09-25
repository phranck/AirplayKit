//
//  ReceiverEventDiffTests.swift
//  Device events report observed changes without inventing group membership.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

import XCTest
@testable import PlayableAirplay

final class ReceiverEventDiffTests: XCTestCase {
    func testNameAndAvailabilityChangesAreTyped() {
        let before = receiver(id: "A", name: "Office", hasSender: false)
        let after = receiver(id: "A", name: "Study", hasSender: true)
        let changes = ReceiverEventDiff.changes(from: [before], to: [after])
        XCTAssertEqual(changes.count, 2)
        guard case .receiverNameChanged(id: "A", name: "Study") = changes[0] else {
            return XCTFail("name change was missing")
        }
        guard case .receiverStateChanged(id: "A", hasSender: true, isPlaying: false) = changes[1] else {
            return XCTFail("state change was missing")
        }
    }

    func testAdvertisedGroupIDDoesNotAssertPlaybackMembership() {
        let before = receiver(id: "A", name: "Office", groupID: "A")
        let after = receiver(id: "A", name: "Office", groupID: "A+B")
        XCTAssertTrue(ReceiverEventDiff.changes(from: [before], to: [after]).isEmpty)
    }

    private func receiver(id: String, name: String, groupID: String = "",
                          hasSender: Bool = false) -> AirPlayReceiver {
        AirPlayReceiver(id: id, name: name, host: "host.local.", port: 7000,
                        model: "One", manufacturer: "Sonos", groupID: groupID,
                        supportsAirPlay2: true, isFullyDescribed: true,
                        hasSender: hasSender, isPlaying: false)
    }
}
