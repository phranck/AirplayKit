//
//  PTPWireTests.swift
//  Sender clock packets checked against the IEEE 802.1AS wire tables.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

import Foundation
import XCTest
@testable import PlayableAirplaySender

final class PTPWireTests: XCTestCase {
    private let clockID: UInt64 = 0x0200_0000_0001_0008

    func testTwoStepSyncNamesTheGroupClockAndItsSequence() {
        let packet = PTPWire.sync(clockID: clockID, sequence: 0x1234)

        XCTAssertEqual(packet.count, 44)
        XCTAssertEqual(Array(packet.prefix(8)), [0x10, 0x12, 0, 44, 0, 0, 0x06, 0x08])
        XCTAssertEqual(Array(packet[20..<30]), [2, 0, 0, 0, 0, 1, 0, 8, 0, 1])
        XCTAssertEqual(Array(packet[30..<34]), [0x12, 0x34, 0, 0xFD])
        XCTAssertEqual(Array(packet[34..<44]), Array(repeating: 0, count: 10))
    }

    func testFollowUpCarriesTheSameSequenceAndThePreciseOriginTime() {
        let stamp = PTPWire.Timestamp(seconds: 0x0102_0304_0506, nanoseconds: 0x1122_3344)
        let packet = PTPWire.followUp(clockID: clockID, sequence: 0x1234, timestamp: stamp)

        XCTAssertEqual(packet.count, 76)
        XCTAssertEqual(Array(packet.prefix(4)), [0x18, 0x12, 0, 76])
        XCTAssertEqual(Array(packet[30..<34]), [0x12, 0x34, 2, 0xFD])
        XCTAssertEqual(Array(packet[34..<44]), [1, 2, 3, 4, 5, 6, 0x11, 0x22, 0x33, 0x44])
        XCTAssertEqual(Array(packet[44..<54]), [0, 3, 0, 28, 0, 0x80, 0xC2, 0, 0, 1])
    }

    func testAnnounceAdvertisesOneGrandmasterAndItsPath() {
        let packet = PTPWire.announce(clockID: clockID, sequence: 7)

        XCTAssertEqual(packet.count, 76)
        XCTAssertEqual(Array(packet.prefix(4)), [0x1B, 0x12, 0, 76])
        XCTAssertEqual(Array(packet[30..<34]), [0, 7, 5, 0])
        XCTAssertEqual(Array(packet[47..<61]), [128, 6, 0x21, 0x43, 0x6A, 128, 2, 0, 0, 0, 0, 1, 0, 8])
        XCTAssertEqual(Array(packet[64..<76]), [0, 8, 0, 8, 2, 0, 0, 0, 0, 1, 0, 8])
    }

    func testDelayRequestIsParsedWithoutTrustingAnIncompleteDatagram() throws {
        var request = PTPWire.sync(clockID: 0x1122_3344_5566_7788, sequence: 0x2345)
        request[0] = 0x11
        request[6] = 0x04

        let parsed = try XCTUnwrap(PTPWire.request(request))
        XCTAssertEqual(parsed.kind, .delay)
        XCTAssertEqual(parsed.clockID, 0x1122_3344_5566_7788)
        XCTAssertEqual(parsed.portNumber, 1)
        XCTAssertEqual(parsed.sequence, 0x2345)

        request.removeLast()
        XCTAssertNil(PTPWire.request(request))
    }

    func testDelayResponseReturnsReceiveTimeAndRequestingPort() throws {
        let stamp = PTPWire.Timestamp(seconds: 0x0102_0304_0506, nanoseconds: 0x1122_3344)
        let response = PTPWire.delayResponse(clockID: clockID,
                                             sequence: 0x2345,
                                             receivedAt: stamp,
                                             requesterClockID: 0x1122_3344_5566_7788,
                                             requesterPort: 0x4567)

        XCTAssertEqual(response.count, 54)
        XCTAssertEqual(Array(response.prefix(4)), [0x19, 0x12, 0, 54])
        XCTAssertEqual(Array(response[30..<34]), [0x23, 0x45, 3, 0x7F])
        XCTAssertEqual(Array(response[34..<44]), [1, 2, 3, 4, 5, 6, 0x11, 0x22, 0x33, 0x44])
        XCTAssertEqual(Array(response[44..<54]), [0x11, 0x22, 0x33, 0x44, 0x55,
                                                 0x66, 0x77, 0x88, 0x45, 0x67])
    }

    func testPeerDelayResponsePairsTheReceiveAndSendTimes() throws {
        let received = PTPWire.Timestamp(seconds: 50, nanoseconds: 100)
        let sent = PTPWire.Timestamp(seconds: 50, nanoseconds: 700)
        let requestID: UInt64 = 0x1122_3344_5566_7788
        let event = PTPWire.peerDelayResponse(clockID: clockID, sequence: 9,
                                              receivedAt: received,
                                              requesterClockID: requestID, requesterPort: 2)
        let followUp = PTPWire.peerDelayFollowUp(clockID: clockID, sequence: 9,
                                                 sentAt: sent,
                                                 requesterClockID: requestID, requesterPort: 2)

        XCTAssertEqual(event.count, 54)
        XCTAssertEqual(followUp.count, 54)
        XCTAssertEqual(Array(event.prefix(4)), [0x13, 0x12, 0, 54])
        XCTAssertEqual(Array(followUp.prefix(4)), [0x1A, 0x12, 0, 54])
        XCTAssertEqual(event[6], 0x06)
        XCTAssertEqual(Array(event[34..<44]), [0, 0, 0, 0, 0, 50, 0, 0, 0, 100])
        XCTAssertEqual(Array(followUp[34..<44]), [0, 0, 0, 0, 0, 50, 0, 0, 2, 188])
        XCTAssertEqual(Array(event[44..<54]), Array(followUp[44..<54]))
    }

    func testAnnouncementReportsTheGrandmasterAndRejectsTruncation() throws {
        var announcement = PTPWire.announce(clockID: 0x1122_3344_5566_7788, sequence: 3)
        announcement.replaceSubrange(53..<61, with: [2, 0, 0, 0, 0, 1, 0, 8])

        let parsed = try XCTUnwrap(PTPWire.announcement(announcement))
        XCTAssertEqual(parsed.sourceClockID, 0x1122_3344_5566_7788)
        XCTAssertEqual(parsed.grandmasterClockID, 0x0200_0000_0001_0008)

        announcement.removeLast()
        XCTAssertNil(PTPWire.announcement(announcement))
    }
}
