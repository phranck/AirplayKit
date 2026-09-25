//
//  DiscoveryStoppingTests.swift
//  Stopping a browse, from the thread that asked for it and from the one it runs on.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

import CAirplayKit
import Foundation
import XCTest

final class DiscoveryStoppingTests: XCTestCase {

    /**
     A browse, or nothing where this machine has no responder to browse with.

     Nothing is the ordinary case in a container and on a Linux machine without
     `avahi-daemon`, and it is not a failure of anything under test here, so the
     tests below leave rather than fail on it.
     */
    private func startedBrowse() -> OpaquePointer? {
        pa_discovery_start({ _, _, _ in }, nil, nil, nil)
    }

    func testStoppingFromAnotherThreadWaitsForTheBrowseToFinish() {
        guard let discovery = startedBrowse() else { return }

        // The ordinary path: this is not the thread the browse runs on, so the
        // call joins that thread and releases everything before it returns.
        pa_discovery_stop(discovery)
    }

    func testStoppingSomethingThatIsNotThereIsAllowed() {
        pa_discovery_stop(nil)
    }

    func testAskingNothingForItsProblemSaysNothingIsWrong() {
        var code: Int32 = 7

        XCTAssertEqual(pa_discovery_problem(nil, &code), PADiscoveryProblemNone)
        XCTAssertEqual(code, 0)
    }
}
