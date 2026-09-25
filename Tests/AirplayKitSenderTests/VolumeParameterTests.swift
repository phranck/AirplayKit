//
//  VolumeParameterTests.swift
//  Reading the level a receiver reports for an open AirPlay session.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

import Foundation
import XCTest
@testable import AirplayKitSender

final class VolumeParameterTests: XCTestCase {
    func testReadRequestNamesVolumeOnTheSession() {
        let request = VolumeParameter.readRequest(uri: "rtsp://127.0.0.1/42")

        XCTAssertEqual(request.method, "GET_PARAMETER")
        XCTAssertEqual(request.uri, "rtsp://127.0.0.1/42")
        XCTAssertEqual(request.headers.first?.name, "Content-Type")
        XCTAssertEqual(request.headers.first?.value, "text/parameters")
        XCTAssertEqual(request.body, Data("volume\r\n".utf8))
    }

    func testReportedAttenuationBecomesThePublicVolume() throws {
        XCTAssertEqual(try VolumeParameter.level(from: Data("volume: -12.0\r\n".utf8)), 0.6,
                       accuracy: 0.0001)
        XCTAssertEqual(try VolumeParameter.level(from: Data("volume: 0.0\r\n".utf8)), 1)
        XCTAssertEqual(try VolumeParameter.level(from: Data("volume: -144.0\r\n".utf8)), 0)
        XCTAssertEqual(try VolumeParameter.level(from: Data("volume: -100.0\r\n".utf8)), 0)
    }

    func testUnusableVolumeReplyIsRejected() {
        for body in ["", "progress: 10\r\n", "volume: NaN\r\n", "volume: 2\r\n",
                     "volume: -200\r\n", "volume: -12\r\nvolume: -20\r\n"] {
            XCTAssertThrowsError(try VolumeParameter.level(from: Data(body.utf8)), body)
        }
    }
}
