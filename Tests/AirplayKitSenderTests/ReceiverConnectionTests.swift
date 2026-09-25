//
//  ReceiverConnectionTests.swift
//  What one control connection does when two threads reach it at once.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

import Foundation
import XCTest
@testable import AirplayKitSender

#if canImport(Glibc)
import Glibc
#else
import Darwin
#endif

// Glibc types the socket kinds as an enumeration and Darwin as a plain number,
// which is the one place the two headers differ here.
#if canImport(Glibc)
private let streamSocketKind = Int32(SOCK_STREAM.rawValue)
private let sendFlags = Int32(MSG_NOSIGNAL)
#else
private let streamSocketKind = SOCK_STREAM
private let sendFlags: Int32 = 0
#endif

/**
 A receiver that answers everything with 200 and remembers the `CSeq` each
 request carried.

 On the loopback address and on whichever port the system hands out, so several
 of these can run at once and none of them needs anything to be free.
 */
private final class AnsweringReceiver {
    /// The port it ended up listening on.
    let port: UInt16

    private let listener: Int32
    private let lock = NSLock()
    private var seen: [Int] = []
    private var requests: [String] = []
    private let volumeReply: Data?

    /// Every `CSeq` that arrived, in the order it arrived in.
    var sequencesSeen: [Int] {
        lock.lock()
        defer { lock.unlock() }

        return seen
    }

    var requestsSeen: [String] {
        lock.lock()
        defer { lock.unlock() }

        return requests
    }

    init(volumeReply: String? = nil) throws {
        self.volumeReply = volumeReply.map { Data($0.utf8) }
        // On a local handle throughout, because the stored one cannot be read
        // from a closure until every member has a value.
        let handle = socket(AF_INET, streamSocketKind, 0)
        guard handle >= 0 else { throw TCPFailure.socketCouldNotBeOpened }

        var reuse: Int32 = 1
        setsockopt(handle, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var wanted = sockaddr_in()
        wanted.sin_family = sa_family_t(AF_INET)
        wanted.sin_port = 0
        wanted.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bound = withUnsafePointer(to: &wanted) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(handle, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, listen(handle, 4) == 0 else {
            Self.closeSocket(handle)
            throw TCPFailure.socketCouldNotBeOpened
        }

        var chosen = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &chosen) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(handle, $0, &length)
            }
        }

        listener = handle
        port = UInt16(bigEndian: chosen.sin_port)

        let thread = Thread { [weak self] in
            let accepted = accept(handle, nil, nil)
            guard accepted >= 0 else { return }

            self?.answerEverything(on: accepted)
            Self.closeSocket(accepted)
        }
        thread.name = "AirplayKit.tests.receiver"
        thread.start()
    }

    /// Stops listening, which ends the serving thread with the connection.
    func close() {
        shutdown(listener, Int32(SHUT_RDWR))
        Self.closeSocket(listener)
    }

    private func answerEverything(on handle: Int32) {
        var pending = Data()
        var arrived = [UInt8](repeating: 0, count: 4096)
        let separator = Data("\r\n\r\n".utf8)

        while true {
            let count = recv(handle, &arrived, arrived.count, 0)
            guard count > 0 else { return }

            pending += Data(arrived[0..<count])

            while let range = pending.range(of: separator) {
                let head = String(decoding: pending[pending.startIndex..<range.lowerBound], as: UTF8.self)
                let length = Self.contentLength(in: head)
                guard pending.distance(from: range.upperBound, to: pending.endIndex) >= length else { break }

                let bodyEnd = pending.index(range.upperBound, offsetBy: length)
                let body = Data(pending[range.upperBound..<bodyEnd])
                pending = Data(pending[bodyEnd...])

                let sequence = Self.sequence(in: head)
                lock.lock()
                seen.append(sequence)
                requests.append(head + "\r\n\r\n" + String(decoding: body, as: UTF8.self))
                lock.unlock()

                let responseBody = head.hasPrefix("GET_PARAMETER ") ? volumeReply ?? Data() : Data()
                let reply = Data("RTSP/1.0 200 OK\r\nCSeq: \(sequence)\r\nContent-Length: \(responseBody.count)\r\n\r\n".utf8)
                    + responseBody
                reply.withUnsafeBytes { bytes in
                    _ = send(handle, bytes.baseAddress, reply.count, sendFlags)
                }
            }
        }
    }

    /// The `CSeq` a request carried, or nought where it carried none.
    private static func sequence(in head: String) -> Int {
        for line in head.components(separatedBy: "\r\n") where line.lowercased().hasPrefix("cseq:") {
            return Int(line.dropFirst("cseq:".count).trimmingCharacters(in: .whitespaces)) ?? 0
        }

        return 0
    }

    private static func contentLength(in head: String) -> Int {
        for line in head.components(separatedBy: "\r\n") where line.lowercased().hasPrefix("content-length:") {
            return Int(line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)) ?? 0
        }

        return 0
    }

    private static func closeSocket(_ handle: Int32) {
        #if canImport(Glibc)
        Glibc.close(handle)
        #else
        Darwin.close(handle)
        #endif
    }
}

final class ReceiverConnectionTests: XCTestCase {

    /// How many requests each thread sends, which is enough for a race to show every time.
    private let requestsPerThread = 200

    func testTwoThreadsSendingAtOnceNeverShareASequenceNumber() throws {
        // The sequence number, the frame counter and the two buffers are one
        // state, and a request moves all of them. Two requests interleaved put
        // the receiver's counter permanently behind this side's, after which
        // nothing on the connection opens again and the session dies quietly.
        let receiver = try AnsweringReceiver()
        defer { receiver.close() }

        let connection = try ReceiverConnection(host: "127.0.0.1",
                                                port: receiver.port,
                                                senderName: "AirplayKit tests",
                                                timeout: 2)
        let expected = requestsPerThread * 2
        let counting = NSLock()
        var refused = 0

        DispatchQueue.concurrentPerform(iterations: 2) { _ in
            for _ in 0..<self.requestsPerThread {
                do { _ = try connection.send(RTSPRequest(method: "GET", uri: "/info")) }
                catch {
                    // Two threads reading one socket take each other's answers,
                    // so a request that went out is left waiting for one that
                    // has already been read by somebody else.
                    counting.lock()
                    refused += 1
                    counting.unlock()
                }
            }
        }

        let seen = receiver.sequencesSeen

        XCTAssertEqual(refused, 0, "a request on a shared connection did not get its own answer")
        XCTAssertEqual(seen.count, expected)
        XCTAssertEqual(Set(seen).count, seen.count, "two requests carried the same CSeq")
        XCTAssertEqual(seen.sorted(), Array(1...expected))
    }

    func testOneThreadStillNumbersItsRequestsFromOne() throws {
        let receiver = try AnsweringReceiver()
        defer { receiver.close() }

        let connection = try ReceiverConnection(host: "127.0.0.1",
                                                port: receiver.port,
                                                senderName: "AirplayKit tests",
                                                timeout: 2)

        for _ in 0..<3 {
            XCTAssertEqual(try connection.send(RTSPRequest(method: "GET", uri: "/info")).status, 200)
        }

        XCTAssertEqual(receiver.sequencesSeen, [1, 2, 3])
    }

    func testSessionReadsVolumeFromTheReceiver() throws {
        let receiver = try AnsweringReceiver(volumeReply: "volume: -12.0\r\n")
        defer { receiver.close() }

        let connection = try ReceiverConnection(host: "127.0.0.1",
                                                port: receiver.port,
                                                senderName: "AirplayKit tests",
                                                timeout: 2)
        let session = Session(connection: connection)

        XCTAssertEqual(try session.readVolume(), 0.6, accuracy: 0.0001)
        XCTAssertEqual(receiver.requestsSeen.count, 1)
        XCTAssertTrue(receiver.requestsSeen[0].hasPrefix("GET_PARAMETER rtsp://"))
        XCTAssertTrue(receiver.requestsSeen[0].hasSuffix("\r\n\r\nvolume\r\n"))
    }
}
