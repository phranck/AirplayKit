//
//  NameParsingTests.swift
//  What can be checked without a receiver on the network.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

import CAirplayKit
import XCTest

@testable import AirplayKit

final class NameParsingTests: XCTestCase {
    /// Splits a Bonjour instance name the way discovery does, and hands back both halves.
    private func split(_ instance: String) -> (identifier: String, name: String) {
        var identifier = [CChar](repeating: 0, count: Int(PA_MAX_ID))
        var name = [CChar](repeating: 0, count: Int(PA_MAX_NAME))

        pa_split_instance_name(instance, &identifier, identifier.count, &name, name.count)

        return (String(cString: identifier), String(cString: name))
    }

    func testTakesTheAddressFromBeforeTheSeparator() {
        let (identifier, name) = split("48A6B8F7CA56@DiningRoom")

        XCTAssertEqual(identifier, "48A6B8F7CA56")
        XCTAssertEqual(name, "DiningRoom")
    }

    func testKeepsAnInstanceThatCarriesNoAddress() {
        let (identifier, name) = split("LivingRoom")

        XCTAssertEqual(identifier, "LivingRoom")
        XCTAssertEqual(name, "LivingRoom")
    }

    func testDividesOnTheFirstSeparatorOnly() {
        let (identifier, name) = split("AABBCC@the HomePod mini@Home")

        XCTAssertEqual(identifier, "AABBCC")
        XCTAssertEqual(name, "the HomePod mini@Home")
    }

    func testTerminatesABufferTooShortToHoldTheWhole() {
        var identifier = [CChar](repeating: 1, count: 4)
        var name = [CChar](repeating: 1, count: 4)

        pa_split_instance_name("48A6B8F7CA56@DiningRoom", &identifier, identifier.count, &name, name.count)

        XCTAssertEqual(identifier.last, 0)
        XCTAssertEqual(name.last, 0)
    }

    // The two services name one receiver differently, so a receiver seen on both
    // is only recognised as one receiver if these two spellings meet.

    /// Reads a `deviceid` field the way discovery does.
    private func identity(from deviceID: String) -> String {
        var identifier = [CChar](repeating: 0, count: Int(PA_MAX_ID))
        pa_identity_from_device_id(deviceID, &identifier, identifier.count)

        return String(cString: identifier)
    }

    func testADeviceIdBecomesTheIdentifierTheOtherServiceCarries() {
        let instance = split("48A6B8F7CA56@DiningRoom").identifier

        XCTAssertEqual(identity(from: "48:A6:B8:F7:CA:56"), instance)
    }

    func testTheCaseOfTheDeviceIdDoesNotMatter() {
        XCTAssertEqual(identity(from: "38:42:0b:4c:8b:ec"), "38420B4C8BEC")
    }

    func testAnySeparatorIsDropped() {
        XCTAssertEqual(identity(from: "38-42-0B-4C-8B-EC"), "38420B4C8BEC")
        XCTAssertEqual(identity(from: "38420B4C8BEC"), "38420B4C8BEC")
    }

    /// A receiver that announced nothing usable leaves the value empty, and
    /// discovery drops that sighting rather than inventing an identity for it.
    func testAFieldWithNothingUsableAnswersEmpty() {
        XCTAssertEqual(identity(from: ""), "")
        XCTAssertEqual(identity(from: "::::::"), "")
    }

    func testTerminatesAnIdentityBufferTooShortToHoldTheWhole() {
        var identifier = [CChar](repeating: 1, count: 4)
        pa_identity_from_device_id("38:42:0B:4C:8B:EC", &identifier, identifier.count)

        XCTAssertEqual(String(cString: identifier), "384")
        XCTAssertEqual(identifier.last, 0)
    }

    // A resolve answers with the name in its wire form, so what a person sees is
    // whatever comes out of here.

    /// Unescapes a service name the way discovery does.
    private func unescape(_ escaped: String) -> String {
        var plain = [CChar](repeating: 0, count: Int(PA_MAX_NAME))
        pa_unescape_instance_name(escaped, &plain, plain.count)

        return String(cString: plain)
    }

    func testASpaceArrivesAsItsByteValue() {
        XCTAssertEqual(unescape("Dining\\032Room"), "Dining Room")
    }

    func testADotInsideANameIsEscapedWithABackslash() {
        XCTAssertEqual(unescape("Bob\\.s\\032Speaker"), "Bob.s Speaker")
    }

    func testABackslashStandsForItself() {
        XCTAssertEqual(unescape("one\\\\two"), "one\\two")
    }

    func testANameWithNothingToUndoIsUnchanged() {
        XCTAssertEqual(unescape("Kitchen"), "Kitchen")
    }

    /// Two digits are not an escape, so they stay as they are rather than
    /// swallowing the character after them.
    func testOnlyThreeDigitsAreReadAsAByte() {
        XCTAssertEqual(unescape("a\\12b"), "a12b")
    }

    func testATrailingBackslashIsDropped() {
        XCTAssertEqual(unescape("Kitchen\\"), "Kitchen")
    }
}
