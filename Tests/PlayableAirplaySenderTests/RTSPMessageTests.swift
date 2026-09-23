//
//  RTSPMessageTests.swift
//  What goes on the wire, and what comes back off it.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

import XCTest
@testable import PlayableAirplaySender

final class RTSPMessageTests: XCTestCase {

    // MARK: - Writing a request

    func testARequestCarriesItsMethodUriAndSequence() {
        let request = RTSPRequest(method: "OPTIONS", uri: "*")

        let text = String(data: request.encoded(sequence: 1), encoding: .utf8)

        XCTAssertEqual(text, "OPTIONS * RTSP/1.0\r\nCSeq: 1\r\n\r\n")
    }

    func testABodyBringsItsOwnContentLength() {
        // Written here rather than by the caller, because a length that
        // disagrees with the body is a fault no receiver recovers from.
        let request = RTSPRequest(method: "POST",
                                  uri: "/pair-setup",
                                  headers: [("Content-Type", "application/octet-stream")],
                                  body: Data([0x01, 0x02, 0x03]))

        let encoded = request.encoded(sequence: 4)
        let text = String(data: encoded, encoding: .utf8)

        XCTAssertTrue(text?.contains("Content-Length: 3\r\n") == true)
        XCTAssertEqual(encoded.suffix(3), Data([0x01, 0x02, 0x03]))
    }

    func testARequestWithoutABodyDeclaresNoLength() {
        let text = String(data: RTSPRequest(method: "RECORD", uri: "rtsp://host/1").encoded(sequence: 2),
                          encoding: .utf8)

        XCTAssertFalse(text?.contains("Content-Length") == true)
    }

    func testHeadersKeepTheOrderTheyWereGivenIn() {
        let request = RTSPRequest(method: "POST",
                                  uri: "/pair-setup",
                                  headers: [("X-Apple-HKP", "4"), ("User-Agent", "AirPlay/550.10")])

        let text = String(data: request.encoded(sequence: 3), encoding: .utf8) ?? ""

        XCTAssertLessThan(text.range(of: "X-Apple-HKP")!.lowerBound,
                          text.range(of: "User-Agent")!.lowerBound)
    }

    // MARK: - Reading an answer

    func testAnAnswerIsReadIntoItsParts() throws {
        let bytes = Data("RTSP/1.0 200 OK\r\nCSeq: 1\r\nServer: AirTunes/550.10\r\n\r\n".utf8)

        let read = try RTSPResponse.read(from: bytes)

        XCTAssertEqual(read?.response.status, 200)
        XCTAssertEqual(read?.response.reason, "OK")
        XCTAssertEqual(read?.response.header("Server"), "AirTunes/550.10")
        XCTAssertEqual(read?.consumed, bytes.count)
    }

    func testAHeaderIsFoundHoweverItWasCapitalised() throws {
        let bytes = Data("RTSP/1.0 200 OK\r\ncontent-length: 0\r\n\r\n".utf8)

        let read = try RTSPResponse.read(from: bytes)

        XCTAssertEqual(read?.response.header("Content-Length"), "0")
    }

    func testABodyIsTakenAtTheLengthDeclared() throws {
        let bytes = Data("RTSP/1.0 200 OK\r\nContent-Length: 4\r\n\r\n".utf8) + Data([1, 2, 3, 4])

        let read = try RTSPResponse.read(from: bytes)

        XCTAssertEqual(read?.response.body, Data([1, 2, 3, 4]))
        XCTAssertEqual(read?.consumed, bytes.count)
    }

    func testWhatFollowsAnAnswerIsLeftAlone() throws {
        let one = Data("RTSP/1.0 200 OK\r\nContent-Length: 2\r\n\r\n".utf8) + Data([0xAA, 0xBB])
        let buffer = one + Data("RTSP/1.0 200 OK\r\n\r\n".utf8)

        let read = try RTSPResponse.read(from: buffer)

        XCTAssertEqual(read?.consumed, one.count)
    }

    func testAnAnswerThatHasNotAllArrivedIsNotReadYet() throws {
        // Headers complete, body short by one byte.
        let partial = Data("RTSP/1.0 200 OK\r\nContent-Length: 4\r\n\r\n".utf8) + Data([1, 2, 3])

        XCTAssertNil(try RTSPResponse.read(from: partial))
        XCTAssertNil(try RTSPResponse.read(from: Data("RTSP/1.0 200 OK\r\n".utf8)))
        XCTAssertNil(try RTSPResponse.read(from: Data()))
    }

    func testAnHttpAnswerIsReadTheSameWay() throws {
        // A receiver answers a plain GET /info in HTTP on the same connection,
        // and the status line is the only thing that differs.
        let bytes = Data("HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n".utf8)

        XCTAssertEqual(try RTSPResponse.read(from: bytes)?.response.status, 200)
    }

    func testAFailureStatusIsReadRatherThanRefused() throws {
        // A 403 is an answer and the sender has to see it, so reading it is not
        // an error even though acting on it will be.
        let bytes = Data("RTSP/1.0 403 Forbidden\r\n\r\n".utf8)

        let read = try RTSPResponse.read(from: bytes)

        XCTAssertEqual(read?.response.status, 403)
        XCTAssertEqual(read?.response.reason, "Forbidden")
    }

    func testAStatusLineWithNoNumberIsRefused() {
        let bytes = Data("this is not a status line\r\n\r\n".utf8)

        XCTAssertThrowsError(try RTSPResponse.read(from: bytes)) { error in
            XCTAssertEqual(error as? RTSPFailure, .answerIsNotReadable)
        }
    }
}
