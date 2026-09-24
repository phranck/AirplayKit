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

    func testTheFractionFillsTheWholeSixtyFourBits() throws {
        // A quarter of a second is a quarter of the range, and a whole second
        // would be the whole of it, so the scale is 2^64 rather than 2^62.
        let quarter = try XCTUnwrap(PTPClock.now(from: reading(seconds: 100, nanoseconds: 250_000_000)))

        XCTAssertEqual(quarter.seconds, 100)
        XCTAssertEqual(UInt64(bitPattern: quarter.fraction) >> 60, 4)
    }

    func testTheTopBitIsSetAboveHalfASecond() throws {
        // Which makes the value negative as an Int64, and that is the right bit
        // pattern rather than a mistake. Three quarters is 0xC000...
        let threeQuarters = try XCTUnwrap(PTPClock.now(from: reading(seconds: 100, nanoseconds: 750_000_000)))

        XCTAssertLessThan(threeQuarters.fraction, 0)
        XCTAssertEqual(UInt64(bitPattern: threeQuarters.fraction) >> 60, 0xC)
    }

    func testAReadingUsedAtOnceHasBarelyAnyFraction() throws {
        // Not none: the reading is carried forward by however long it has been
        // held, which is the whole point of it. Immediately afterwards that is
        // a handful of microseconds, so the top nibble is still zero.
        let now = try XCTUnwrap(PTPClock.now(from: reading(seconds: 7, nanoseconds: 0)))

        XCTAssertEqual(UInt64(bitPattern: now.fraction) >> 60, 0)
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

    func testTheLeadIsAddedToTheReading() throws {
        let now = try XCTUnwrap(PTPClock.now(from: reading(seconds: 500, nanoseconds: 0)))
        let ahead = try XCTUnwrap(PTPClock.now(from: reading(seconds: 500, nanoseconds: 0), ahead: 2))

        // Two seconds later, give or take the moment each was taken.
        XCTAssertEqual(ahead.seconds - now.seconds, 2)
    }

    func testTheSecondsAreTheClocksOwnAndNotAWallClock() throws {
        // A receiver counts from when it started, so a reading of 90787 stays
        // 90787 rather than becoming a date.
        let now = try XCTUnwrap(PTPClock.now(from: reading(seconds: 90787, nanoseconds: 0)))

        XCTAssertEqual(now.seconds, 90787)
    }

    // MARK: - A time that will not go on a timeline

    func testALeadThatIsNotANumberIsRefused() {
        // Converting it would end the process rather than fail, and this is a
        // public call whose lead is whatever the caller passed.
        XCTAssertNil(PTPClock.now(from: reading(seconds: 100, nanoseconds: 0), ahead: .nan))
    }

    func testALeadBeyondWhatAnAnchorCanCarryIsRefused() {
        XCTAssertNil(PTPClock.now(from: reading(seconds: 100, nanoseconds: 0), ahead: .infinity))
        XCTAssertNil(PTPClock.now(from: reading(seconds: 100, nanoseconds: 0), ahead: 1e19))
    }

    func testALeadThatWouldPutTheAnchorBeforeTheClockStartedIsRefused() {
        XCTAssertNil(PTPClock.now(from: reading(seconds: 10, nanoseconds: 0), ahead: -1000))
    }

    func testTheWholeRangeAClockCanAnnounceIsStillAccepted() throws {
        // The seconds arrive as the six bytes of a PTP timestamp, so the most a
        // receiver can say is 2^48 - 1, and that has to keep working.
        let largest = try XCTUnwrap(PTPClock.now(from: reading(seconds: (1 << 48) - 1, nanoseconds: 0),
                                                 ahead: 2))

        XCTAssertGreaterThan(largest.seconds, 0)
    }

    // MARK: - How long the clock waits

    func testAWaitLongerThanPollCanBeHandedIsClampedRatherThanConverted() {
        // `read(from:timeout:)` is public and carries a default, so this number
        // is the caller's. Anything past about twenty-five days does not fit the
        // milliseconds poll counts in, and converting it ends the process.
        let aYear = Date(timeIntervalSinceNow: 60 * 60 * 24 * 365)

        XCTAssertEqual(PTPClock.milliseconds(until: aYear), Int32.max)
    }

    func testADeadlineThatIsNotATimeWaitsForNothing() {
        XCTAssertEqual(PTPClock.milliseconds(until: Date(timeIntervalSinceNow: .nan)), 0)
    }

    func testADeadlineAlreadyPastWaitsForNothing() {
        XCTAssertEqual(PTPClock.milliseconds(until: Date(timeIntervalSinceNow: -5)), 0)
    }

    func testAnOrdinaryWaitIsCountedInMilliseconds() {
        let inTwoSeconds = PTPClock.milliseconds(until: Date(timeIntervalSinceNow: 2))

        XCTAssertGreaterThan(inTwoSeconds, 1900)
        XCTAssertLessThanOrEqual(inTwoSeconds, 2000)
    }
}
