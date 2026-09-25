//
//  GroupVolumePlanTests.swift
//  A group fader retains member balance until a receiver reaches its limit.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

import XCTest
@testable import AirplayKitSender

final class GroupVolumePlanTests: XCTestCase {
    func testMovingAveragePreservesDifferenceWithoutClipping() {
        let levels = GroupVolumePlan.levels(for: [0.2, 0.6], average: 0.5)
        XCTAssertEqual(levels?[0] ?? -1, 0.3, accuracy: 0.0001)
        XCTAssertEqual(levels?[1] ?? -1, 0.7, accuracy: 0.0001)
    }

    func testClippedMemberDoesNotKeepAverageBelowRequestedLevel() {
        let levels = GroupVolumePlan.levels(for: [0.1, 0.9], average: 0.75)
        XCTAssertEqual(levels?[0] ?? -1, 0.5, accuracy: 0.0001)
        XCTAssertEqual(levels?[1] ?? -1, 1, accuracy: 0.0001)
    }

    func testUnknownOrNonFiniteInputCannotCreateAPlan() {
        XCTAssertNil(GroupVolumePlan.levels(for: [], average: 0.5))
        XCTAssertNil(GroupVolumePlan.levels(for: [0.3, .nan], average: 0.5))
        XCTAssertNil(GroupVolumePlan.levels(for: [0.3], average: .infinity))
    }
}
