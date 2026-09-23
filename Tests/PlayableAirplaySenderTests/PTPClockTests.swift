//
//  PTPClockTests.swift
//  The arithmetic the anchor rests on, and how it reaches the wire.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

import Foundation
import XCTest
@testable import PlayableAirplaySender

final class PTPClockTests: XCTestCase {

    /// A reading standing at a whole second, so a lead can be added to it exactly.
    private func reading(seconds: UInt64, nanoseconds: UInt32) -> PTPClock.Reading {
        PTPClock.Reading(identity: 0x542a1bfffe58d1f8,
                         seconds: seconds,
                         nanoseconds: nanoseconds,
                         heardAt: ProcessInfo.processInfo.systemUptime)
    }

    // MARK: - The fraction

    func testTheFractionFillsTheWholeSixtyFourBits() {
        // A quarter of a second is a quarter of the range, and a whole second
        // would be the whole of it, so the scale is 2^64 rather than 2^62.
        let quarter = PTPClock.now(from: reading(seconds: 100, nanoseconds: 250_000_000))

        XCTAssertEqual(quarter.seconds, 100)
        XCTAssertEqual(UInt64(bitPattern: quarter.fraction) >> 60, 4)
    }

    func testTheTopBitIsSetAboveHalfASecond() {
        // Which makes the value negative as an Int64, and that is the right bit
        // pattern rather than a mistake. Three quarters is 0xC000...
        let threeQuarters = PTPClock.now(from: reading(seconds: 100, nanoseconds: 750_000_000))

        XCTAssertLessThan(threeQuarters.fraction, 0)
        XCTAssertEqual(UInt64(bitPattern: threeQuarters.fraction) >> 60, 0xC)
    }

    func testAReadingUsedAtOnceHasBarelyAnyFraction() {
        // Not none: the reading is carried forward by however long it has been
        // held, which is the whole point of it. Immediately afterwards that is
        // a handful of microseconds, so the top nibble is still zero.
        let fraction = UInt64(bitPattern: PTPClock.now(from: reading(seconds: 7, nanoseconds: 0)).fraction)

        XCTAssertEqual(fraction >> 60, 0)
    }

    // MARK: - How it reaches the wire

    func testANegativeFractionIsWrittenAsTheSameEightBytesAsAPositiveOne() throws {
        // This is what makes the sign harmless. A binary property list writes an
        // eight byte integer as marker 0x13 and then the pattern, whichever way
        // the top bit points, so the receiver reads what was meant.
        let above = Int64(bitPattern: 0xC000_0000_0000_0000)
        let below = Int64(bitPattern: 0x4000_0000_0000_0000)

        let encodedAbove = try PropertyListSerialization.data(fromPropertyList: ["v": above],
                                                             format: .binary, options: 0)
        let encodedBelow = try PropertyListSerialization.data(fromPropertyList: ["v": below],
                                                             format: .binary, options: 0)

        XCTAssertEqual(encodedAbove.count, encodedBelow.count)
        XCTAssertTrue(encodedAbove.contains(Data([0x13, 0xC0, 0, 0, 0, 0, 0, 0, 0])))
        XCTAssertTrue(encodedBelow.contains(Data([0x13, 0x40, 0, 0, 0, 0, 0, 0, 0])))
    }

    // MARK: - The lead

    func testTheLeadIsAddedToTheReading() {
        let now = PTPClock.now(from: reading(seconds: 500, nanoseconds: 0))
        let ahead = PTPClock.now(from: reading(seconds: 500, nanoseconds: 0), ahead: 2)

        // Two seconds later, give or take the moment each was taken.
        XCTAssertEqual(ahead.seconds - now.seconds, 2)
    }

    func testTheSecondsAreTheClocksOwnAndNotAWallClock() {
        // A receiver counts from when it started, so a reading of 90787 stays
        // 90787 rather than becoming a date.
        XCTAssertEqual(PTPClock.now(from: reading(seconds: 90787, nanoseconds: 0)).seconds, 90787)
    }
}
