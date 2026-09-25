//
//  GroupTimelineTests.swift
//  A joining stream maps its first frame onto the existing group's time.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

import XCTest
@testable import PlayableAirplaySender

final class GroupTimelineTests: XCTestCase {
    func testLaterStreamHasEquivalentMediaToClockMapping() throws {
        let timeline = GroupTimeline(baseSeconds: 1000.25, sampleRate: 44_100)
        let first = try XCTUnwrap(timeline.anchor(forFrame: 0))
        let later = try XCTUnwrap(timeline.anchor(forFrame: 44_100 * 17))

        XCTAssertEqual(first.rtpTime, 0)
        XCTAssertEqual(first.seconds, 1000)
        XCTAssertEqual(later.rtpTime, 44_100 * 17)
        XCTAssertEqual(later.seconds, 1017)
        XCTAssertEqual(first.fraction, later.fraction)
    }

    func testRTPWrapKeepsTheClockMovingForward() throws {
        let timeline = GroupTimeline(baseSeconds: 1000, sampleRate: 44_100)
        let beyondWrap = try XCTUnwrap(timeline.anchor(forFrame: UInt64(UInt32.max) + 352))
        XCTAssertEqual(beyondWrap.rtpTime, 351)
        XCTAssertGreaterThan(beyondWrap.seconds, 1000)
    }
}
