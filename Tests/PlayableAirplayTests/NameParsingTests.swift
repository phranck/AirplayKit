//
//  NameParsingTests.swift
//  What can be checked without a receiver on the network.
//
//  Copyright © 2026 cocoa:naut. All rights reserved.
//

import CPlayableAirplay
import XCTest

@testable import PlayableAirplay

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
        let (identifier, name) = split("AABBCC@Emma@Home")

        XCTAssertEqual(identifier, "AABBCC")
        XCTAssertEqual(name, "Emma@Home")
    }

    func testTerminatesABufferTooShortToHoldTheWhole() {
        var identifier = [CChar](repeating: 1, count: 4)
        var name = [CChar](repeating: 1, count: 4)

        pa_split_instance_name("48A6B8F7CA56@DiningRoom", &identifier, identifier.count, &name, name.count)

        XCTAssertEqual(identifier.last, 0)
        XCTAssertEqual(name.last, 0)
    }
}
