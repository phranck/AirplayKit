//
//  SourceNameTests.swift
//  What a receiver shows as the source, where the caller named nothing.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

import XCTest
@testable import AirplayKitSender

/**
 The name that stands on the speaker.

 A caller passes its own, and both C entry points that open something accept a
 pointer that may be NULL or empty. What the receiver then shows is decided in
 one place, and this is the only thing that says so: nothing else in the suite
 reaches the C boundary, and the value is only ever seen on a physical speaker.
 */
final class SourceNameTests: XCTestCase {
    func testACallerThatNamesItselfIsShownUnderThatName() {
        "Podlive".withCString { name in
            XCTAssertEqual(sourceName(from: name), "Podlive")
        }
    }

    func testNothingAtAllIsShownAsTheLibrary() {
        XCTAssertEqual(sourceName(from: nil), "AirplayKit")
    }

    func testAnEmptyNameIsShownAsTheLibrary() {
        "".withCString { name in
            XCTAssertEqual(sourceName(from: name), "AirplayKit")
        }
    }
}
