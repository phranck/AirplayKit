//
//  CBufferWritingTests.swift
//  Handing a name to a caller whose buffer may be too small for it.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

import XCTest
@testable import AirplayKitDevices

/**
 Writing a name into a C buffer.

 The failure this guards is quiet. An empty buffer means "this device published
 no name", and writing nothing when the name did not fit said the same thing
 with a different meaning, so a caller with a short buffer read a named device
 as nameless.

 The helper is exercised directly rather than through `pa_product_name`, because
 a Swift target that imports both this module and the C header cannot call an
 `@_cdecl` function: the symbol is declared twice with differently spelled
 pointers, and the toolchain CI uses aborts on it.
 */
final class CBufferWritingTests: XCTestCase {

    /// Writes into a buffer of a given size and hands back what a C caller would read.
    private func written(_ text: String, capacity: Int) -> (string: String, needed: Int) {
        // Filled with something other than nought, so a terminator that was
        // never written shows up as a longer string rather than as an empty one.
        var buffer = [CChar](repeating: 0x7F, count: max(capacity, 1) + 8)

        let needed = buffer.withUnsafeMutableBufferPointer { out in
            writeCString(text, into: out.baseAddress, capacity: capacity)
        }

        return (String(cString: buffer), needed)
    }

    // MARK: - When it fits

    func testANameThatFitsIsWrittenWhole() {
        let result = written("Sonos One", capacity: 10)

        XCTAssertEqual(result.string, "Sonos One")
        XCTAssertEqual(result.needed, 9)
    }

    func testANameThatFitsExactlyIsWrittenWhole() {
        // Nine bytes and a terminator, which is the smallest buffer that holds
        // the whole of it and the boundary a cut would be one byte away from.
        XCTAssertEqual(written("Sonos One", capacity: 10).string, "Sonos One")
    }

    // MARK: - When it does not

    func testANameThatDoesNotFitIsCutShortRatherThanDropped() {
        // The failure: this used to give an empty buffer, which is what a
        // device that published nothing gives.
        let result = written("Sonos One", capacity: 6)

        XCTAssertEqual(result.string, "Sonos")
        XCTAssertFalse(result.string.isEmpty)
    }

    func testTheLengthTheWholeNameNeedsComesBackEvenWhenItIsCutShort() {
        // What lets a caller make room and ask again, which is the C library's
        // own convention and is why this returns anything at all.
        let result = written("Sonos One", capacity: 6)

        XCTAssertEqual(result.needed, 9)
        XCTAssertEqual(written("Sonos One", capacity: result.needed + 1).string, "Sonos One")
    }

    func testABufferWithRoomForNothingButATerminatorGivesAnEmptyName() {
        let result = written("Sonos One", capacity: 1)

        XCTAssertEqual(result.string, "")
        XCTAssertEqual(result.needed, 9)
    }

    // MARK: - Cutting between characters

    func testACutNeverLandsInsideACharacter() {
        // Half a character is not a shorter name, it is bytes no reader can
        // decode. "Küche" is six bytes and its second character is two of them,
        // so a buffer with room for two bytes has to stop after the first.
        let result = written("Küche", capacity: 3)

        XCTAssertEqual(result.string, "K")
        XCTAssertEqual(result.needed, 6)
    }

    func testAWholeMultiByteCharacterIsKeptWhereThereIsRoomForIt() {
        let result = written("Küche", capacity: 4)

        XCTAssertEqual(result.string, "Kü")
        XCTAssertEqual(result.needed, 6)
    }

    func testANameOfNothingButMultiByteCharactersCutsToNothingRatherThanToHalf() {
        let result = written("ü", capacity: 2)

        XCTAssertEqual(result.string, "")
        XCTAssertEqual(result.needed, 2)
    }

    // MARK: - Nowhere to write

    func testAskingWithNoBufferStillSaysHowMuchRoomItWouldNeed() {
        XCTAssertEqual(writeCString("Sonos One", into: nil, capacity: 0), 9)
        XCTAssertEqual(writeCString("Küche", into: nil, capacity: 100), 6)
    }

    func testABufferOfNoCapacityIsNotWrittenTo() {
        var buffer = [CChar](repeating: 0x7F, count: 4)

        let needed = buffer.withUnsafeMutableBufferPointer { out in
            writeCString("Sonos One", into: out.baseAddress, capacity: 0)
        }

        XCTAssertEqual(needed, 9)
        XCTAssertEqual(buffer, [0x7F, 0x7F, 0x7F, 0x7F])
    }
}
