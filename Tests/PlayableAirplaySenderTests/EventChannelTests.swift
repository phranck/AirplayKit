//
//  EventChannelTests.swift
//  Answering what a receiver pushes, and what a reply that did not go means.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

import Foundation
import XCTest
@testable import PlayableAirplaySender

final class EventChannelTests: XCTestCase {

    /// One key for both directions here, since what is under test is the framing rather than the keys.
    private let key = Data(repeating: 0x2B, count: 32)

    /// One pushed request, as a receiver writes it: a request line, a `CSeq`, and nothing under it.
    private func request(sequence: Int) -> Data {
        Data("OPTIONS * RTSP/1.0\r\nCSeq: \(sequence)\r\n\r\n".utf8)
    }

    // MARK: - A reply that did not go

    func testAReplyThatCouldNotBeWrittenIsReported() {
        // Swallowed, this is the worst failure this channel has: the counter has
        // moved and the receiver's has not, so nothing opens there again and the
        // session dies half a minute later for no visible reason.
        var sealing = EncryptedChannel(key: key)
        var plaintext = request(sequence: 1)

        XCTAssertThrowsError(try EventChannel.answerRequests(in: &plaintext,
                                                            sealedWith: &sealing,
                                                            sendingThrough: { _ in
            throw TCPFailure.connectionClosed
        }))
    }

    func testNothingIsAnsweredAfterAReplyThatDidNotGo() {
        // Sealing the next one would move the counter again, against a receiver
        // that is already a frame behind and will never catch up.
        var sealing = EncryptedChannel(key: key)
        var plaintext = request(sequence: 1) + request(sequence: 2)
        var attempts = 0

        XCTAssertThrowsError(try EventChannel.answerRequests(in: &plaintext,
                                                            sealedWith: &sealing,
                                                            sendingThrough: { _ in
            attempts += 1
            throw TCPFailure.connectionClosed
        }))

        XCTAssertEqual(attempts, 1)
    }

    // MARK: - Answering

    func testEveryWholeRequestIsAnsweredInOrder() throws {
        var sealing = EncryptedChannel(key: key)
        var reading = EncryptedChannel(key: key)
        var plaintext = request(sequence: 4) + request(sequence: 5)
        var written = Data()

        try EventChannel.answerRequests(in: &plaintext,
                                        sealedWith: &sealing,
                                        sendingThrough: { written += $0 })

        XCTAssertTrue(plaintext.isEmpty)

        var answers: [String] = []
        while let frame = try reading.open(written) {
            answers.append(String(decoding: frame.message, as: UTF8.self))
            written = Data(written.dropFirst(frame.consumed))
        }

        XCTAssertEqual(answers, ["RTSP/1.0 200 OK\r\nServer: AirTunes/550.10\r\nCSeq: 4\r\n\r\n",
                                 "RTSP/1.0 200 OK\r\nServer: AirTunes/550.10\r\nCSeq: 5\r\n\r\n"])
    }

    func testHalfARequestIsLeftForTheNextRead() throws {
        // TCP delivers what it likes when it likes, so part of a request in the
        // buffer is ordinary and waits for the rest of it.
        let partial = Data("OPTIONS * RTSP/1.0\r\nCSeq: 9\r\n".utf8)
        var sealing = EncryptedChannel(key: key)
        var plaintext = partial
        var replies = 0

        try EventChannel.answerRequests(in: &plaintext,
                                        sealedWith: &sealing,
                                        sendingThrough: { _ in replies += 1 })

        XCTAssertEqual(replies, 0)
        XCTAssertEqual(plaintext, partial)
    }

    // MARK: - What a reply carries

    func testTheReplyCarriesNothingBeyondTheStatusLineAndTheSequence() {
        // A `Content-Length` or an `Audio-Latency` in here corrupts the
        // receiver's timeline, and the session then stays connected and renders
        // silence, which is the most expensive way this protocol goes wrong.
        let answer = String(decoding: EventChannel.reply(echoing: "3"), as: UTF8.self)

        XCTAssertEqual(answer, "RTSP/1.0 200 OK\r\nServer: AirTunes/550.10\r\nCSeq: 3\r\n\r\n")
    }

    func testARequestCarryingNoSequenceIsAnsweredWithoutOne() {
        let answer = String(decoding: EventChannel.reply(echoing: nil), as: UTF8.self)

        XCTAssertEqual(answer, "RTSP/1.0 200 OK\r\nServer: AirTunes/550.10\r\n\r\n")
    }
}
