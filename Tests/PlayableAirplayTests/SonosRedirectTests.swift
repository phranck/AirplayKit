//
//  SonosRedirectTests.swift
//  Where a request to a speaker is allowed to end up.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

import Foundation
import XCTest
@testable import PlayableAirplayUPnP

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

#if canImport(Glibc)
import Glibc
private let streamSocketKind = Int32(SOCK_STREAM.rawValue)
#else
import Darwin
private let streamSocketKind = SOCK_STREAM
#endif

/// Why a speaker of this kind could not be stood up at all.
private enum SpeakerFailure: Error {
    case couldNotListen
}

/**
 A speaker that answers the first request with a redirect off itself.

 It listens on every address of this machine, so both loopback addresses below
 reach it, and it records the `Host` header of every request it answers. That
 header is what says which address a request was actually sent to, which is the
 whole question here.

 Anything but `/moved` is answered with `302` pointing at that path on the other
 address. `/moved` is answered with `200` and a body, so a client that followed
 the hop ends up with an answer rather than with an error, and the two outcomes
 cannot be confused.
 */
private final class RedirectingSpeaker {
    /// The port the system handed out.
    let port: UInt16

    /// The address a client is pointed at.
    static let addressed = "127.0.0.1"

    /// The address its redirect points at, which is the same machine under
    /// another name. Both are loopback, so a followed hop arrives here as well.
    static let elsewhere = "127.0.0.2"

    private let handle: Int32
    private let lock = NSLock()
    private var answered: [String] = []
    private var stopping = false

    /// The `Host` header of every request answered so far, in order.
    var requestedHosts: [String] {
        lock.lock()
        defer { lock.unlock() }

        return answered
    }

    init() throws {
        let opened = socket(AF_INET, streamSocketKind, 0)
        guard opened >= 0 else { throw SpeakerFailure.couldNotListen }

        var reuse: Int32 = 1
        setsockopt(opened, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        // Every address rather than one, because the redirect points at a second
        // loopback address and a listener bound to the first would not answer it.
        var wanted = sockaddr_in()
        wanted.sin_family = sa_family_t(AF_INET)
        wanted.sin_port = 0
        wanted.sin_addr.s_addr = in_addr_t(0)

        let bound = withUnsafePointer(to: &wanted) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(opened, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, listen(opened, 4) == 0 else {
            Self.closeSocket(opened)
            throw SpeakerFailure.couldNotListen
        }

        var chosen = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &chosen) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(opened, $0, &length)
            }
        }

        handle = opened
        port = UInt16(bigEndian: chosen.sin_port)

        let thread = Thread { [weak self] in
            while true {
                let taken = accept(opened, nil, nil)
                guard taken >= 0 else { return }

                self?.answer(on: taken)
                Self.closeSocket(taken)

                guard self?.isRunning == true else { return }
            }
        }
        thread.name = "PlayableAirplay.tests.speaker"
        thread.start()
    }

    /// Stops listening. The accepting thread leaves as soon as its socket goes.
    func close() {
        lock.lock()
        stopping = true
        lock.unlock()

        shutdown(handle, SHUT_RDWR)
        Self.closeSocket(handle)
    }

    private var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }

        return !stopping
    }

    /// Reads one request and answers it, either with the redirect or with the body.
    private func answer(on connection: Int32) {
        guard let request = Self.request(on: connection) else { return }

        lock.lock()
        answered.append(Self.host(in: request) ?? "")
        lock.unlock()

        let moved = "/moved"
        let response: String

        if Self.path(in: request) == moved {
            let body = "elsewhere"
            response = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n"
                + "Content-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n"
                + body
        } else {
            response = "HTTP/1.1 302 Found\r\n"
                + "Location: http://\(Self.elsewhere):\(port)\(moved)\r\n"
                + "Content-Length: 0\r\nConnection: close\r\n\r\n"
        }

        Self.reply(response, on: connection)
    }

    /// Everything up to the blank line that ends a request's headers.
    private static func request(on connection: Int32) -> String? {
        let terminator: [UInt8] = [13, 10, 13, 10]
        var received: [UInt8] = []
        var buffer = [UInt8](repeating: 0, count: 1024)

        while Array(received.suffix(terminator.count)) != terminator {
            #if canImport(Glibc)
            let taken = Glibc.read(connection, &buffer, buffer.count)
            #else
            let taken = Darwin.read(connection, &buffer, buffer.count)
            #endif
            guard taken > 0 else { break }

            received.append(contentsOf: buffer[0 ..< taken])
        }

        return String(bytes: received, encoding: .utf8)
    }

    /// The address the request was addressed to, as the client wrote it.
    private static func host(in request: String) -> String? {
        for line in request.split(separator: "\r\n") where line.lowercased().hasPrefix("host:") {
            return line.dropFirst("host:".count).trimmingCharacters(in: .whitespaces)
        }

        return nil
    }

    /// The path out of the request line, which says whether the hop was followed.
    private static func path(in request: String) -> String? {
        guard let line = request.split(separator: "\r\n").first else { return nil }

        let parts = line.split(separator: " ")
        guard parts.count >= 2 else { return nil }

        return String(parts[1])
    }

    private static func reply(_ response: String, on connection: Int32) {
        let bytes = Array(response.utf8)
        var sent = 0

        while sent < bytes.count {
            let written = bytes.withUnsafeBytes { raw -> Int in
                guard let start = raw.baseAddress else { return -1 }

                #if canImport(Glibc)
                return Glibc.write(connection, start.advanced(by: sent), bytes.count - sent)
                #else
                return Darwin.write(connection, start.advanced(by: sent), bytes.count - sent)
                #endif
            }
            guard written > 0 else { return }

            sent += written
        }
    }

    private static func closeSocket(_ handle: Int32) {
        #if canImport(Glibc)
        Glibc.close(handle)
        #else
        Darwin.close(handle)
        #endif
    }
}

/**
 A request stays on the speaker it was addressed to, whatever that speaker
 answers.

 `SonosClient` settles where a request goes before it makes it, and a redirect
 names the next destination afterwards, which is the moment this covers.
 */
final class SonosRedirectTests: XCTestCase {

    func testARedirectOffTheSpeakerIsNotFollowed() async throws {
        let speaker = try RedirectingSpeaker()
        defer { speaker.close() }

        let client = SonosClient(host: RedirectingSpeaker.addressed,
                                 port: Int(speaker.port),
                                 timeout: 2)

        do {
            let device = try await client.device()
            XCTFail("the redirect was followed and answered with \(device)")
        } catch {
            // The redirect itself comes back, rather than whatever it pointed
            // at, which is what refusing the hop leaves the client holding. A
            // client that followed it reports the far end instead: the answer
            // from the other address where that address is configured, and a
            // failure to reach it where it is not.
            XCTAssertEqual(error as? SonosError, .refused(status: 302))
        }

        // Where the request went, rather than what came back. This is the half
        // that catches a followed hop on a machine whose second loopback address
        // answers, and the assertion above is the half that catches it on one
        // where nothing does.
        XCTAssertEqual(speaker.requestedHosts.count, 1)
        XCTAssertEqual(speaker.requestedHosts.first,
                       "\(RedirectingSpeaker.addressed):\(speaker.port)")
    }
}
