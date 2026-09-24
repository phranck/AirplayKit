//
//  TCPConnectionFailureTests.swift
//  Telling a hangup, a timeout and a deliberate stop apart.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

import Foundation
import XCTest
@testable import PlayableAirplaySender

#if canImport(Glibc)
import Glibc
#else
import Darwin
#endif

#if canImport(Glibc)
private let listeningSocketKind = Int32(SOCK_STREAM.rawValue)
#else
private let listeningSocketKind = SOCK_STREAM
#endif

/**
 A listener that accepts one connection and then does whatever it was told.

 Deliberately not a receiver: what is under test is the socket underneath, so
 this answers nothing and exists only to be connected to, ignored, or hung up
 on.
 */
private final class Listener {
    /// The port the system handed out.
    let port: UInt16

    private let handle: Int32
    private var accepted: Int32 = -1
    private let ready = DispatchSemaphore(value: 0)
    private let asked = DispatchSemaphore(value: 0)
    private let done = DispatchSemaphore(value: 0)

    /// What the far end does once it has accepted.
    enum Behaviour {
        /// Accept and never read, so the sender's buffers fill and it waits.
        case goQuiet

        /// Accept, wait to be asked, then hang up with no lingering, which sends a reset.
        ///
        /// Asked rather than immediate, because a listener that resets the
        /// moment it accepts can do so before the connection at the other end
        /// has finished being made, and then it is `connect` that fails rather
        /// than the write under test. That was measured on a CI runner and not
        /// on this machine, which is what a race of this shape looks like.
        case hangUp
    }

    init(_ behaviour: Behaviour) throws {
        let opened = socket(AF_INET, listeningSocketKind, 0)
        guard opened >= 0 else { throw TCPFailure.socketCouldNotBeOpened }

        var reuse: Int32 = 1
        setsockopt(opened, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var wanted = sockaddr_in()
        wanted.sin_family = sa_family_t(AF_INET)
        wanted.sin_port = 0
        wanted.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bound = withUnsafePointer(to: &wanted) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(opened, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, listen(opened, 4) == 0 else {
            Self.closeSocket(opened)
            throw TCPFailure.socketCouldNotBeOpened
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
            let taken = accept(opened, nil, nil)
            guard taken >= 0 else { return }

            switch behaviour {
            case .goQuiet:
                // Held open and never read from, so the sender fills every
                // buffer between here and there and then waits on the socket.
                self?.accepted = taken
                self?.ready.signal()

            case .hangUp:
                self?.accepted = taken
                self?.ready.signal()
                _ = self?.asked.wait(timeout: .now() + 10)

                // A reset rather than an orderly close, so the next write to it
                // fails rather than being quietly accepted.
                var immediate = linger(l_onoff: 1, l_linger: 0)
                setsockopt(taken, SOL_SOCKET, SO_LINGER,
                           &immediate, socklen_t(MemoryLayout<linger>.size))
                Self.closeSocket(taken)
                self?.accepted = -1
                self?.done.signal()
            }
        }
        thread.name = "PlayableAirplay.tests.listener"
        thread.start()
    }

    /// Waits until the far end has accepted, so a test is not racing the connection.
    func waitUntilReady() {
        _ = ready.wait(timeout: .now() + 5)
    }

    /// Hangs up, and comes back once it has, so what follows meets a reset connection.
    func hangUpNow() {
        asked.signal()
        _ = done.wait(timeout: .now() + 5)
    }

    func close() {
        if accepted >= 0 { Self.closeSocket(accepted) }
        Self.closeSocket(handle)
    }

    private static func closeSocket(_ handle: Int32) {
        #if canImport(Glibc)
        Glibc.close(handle)
        #else
        Darwin.close(handle)
        #endif
    }
}

final class TCPConnectionFailureTests: XCTestCase {

    /// More than every buffer between here and the far end, so a quiet peer makes this wait.
    private let moreThanAnyBufferHolds = Data(repeating: 0xAB, count: 8 * 1024 * 1024)

    /// What ended a write, whether or not part of the message had already gone.
    private func cause(of failure: TCPFailure) -> TCPFailure {
        guard case .messageWasPartlySent(_, _, let because) = failure else { return failure }

        return because
    }

    // MARK: - The three, told apart

    func testStoppingIsNotAHangup() throws {
        // The one that could not be read off the error number: a shutdown here
        // and a hangup there leave the same one.
        let listener = try Listener(.goQuiet)
        defer { listener.close() }

        let connection = try TCPConnection(host: "127.0.0.1", port: listener.port, timeout: 2)
        listener.waitUntilReady()

        connection.stop()

        XCTAssertThrowsError(try connection.write(Data([0x01]))) { error in
            XCTAssertEqual(error as? TCPFailure, .connectionWasStopped)
        }
    }

    func testAQuietPeerIsATimeoutRatherThanAHangup() throws {
        // The far end is alive and simply not reading, which is the ordinary
        // state of a receiver whose buffer is full. Calling that a closed
        // connection is what sent anybody diagnosing this in the wrong
        // direction.
        let listener = try Listener(.goQuiet)
        defer { listener.close() }

        let connection = try TCPConnection(host: "127.0.0.1", port: listener.port, timeout: 1)
        listener.waitUntilReady()

        XCTAssertThrowsError(try connection.write(moreThanAnyBufferHolds)) { error in
            let failure = try? XCTUnwrap(error as? TCPFailure)
            XCTAssertEqual(failure.map(cause), .timedOut)
        }
    }

    func testAPeerThatHungUpIsAHangup() throws {
        let listener = try Listener(.hangUp)
        defer { listener.close() }

        // Connected and accepted before the reset is asked for, so what fails
        // is the write rather than the connection being made.
        let connection = try TCPConnection(host: "127.0.0.1", port: listener.port, timeout: 2)
        listener.waitUntilReady()
        listener.hangUpNow()

        // Writing enough that the reset cannot be missed, however much the
        // kernel was willing to take before it arrived.
        XCTAssertThrowsError(try connection.write(moreThanAnyBufferHolds)) { error in
            let failure = try? XCTUnwrap(error as? TCPFailure)
            XCTAssertEqual(failure.map(cause), .connectionClosed)
        }
    }

    // MARK: - Half a message on the wire

    func testAWriteThatGotPartWayThroughSaysSoAndSaysWhy() throws {
        let listener = try Listener(.goQuiet)
        defer { listener.close() }

        let connection = try TCPConnection(host: "127.0.0.1", port: listener.port, timeout: 1)
        listener.waitUntilReady()

        XCTAssertThrowsError(try connection.write(moreThanAnyBufferHolds)) { error in
            guard case .messageWasPartlySent(let bytes, let total, let because) =
                    (error as? TCPFailure) ?? .timedOut
            else {
                return XCTFail("a write that filled every buffer reported \(error)")
            }

            XCTAssertGreaterThan(bytes, 0)
            XCTAssertLessThan(bytes, total)
            XCTAssertEqual(total, self.moreThanAnyBufferHolds.count)
            XCTAssertEqual(because, .timedOut)
        }
    }

    func testNothingElseIsAllowedOnAConnectionWithHalfAMessageOnIt() throws {
        // The half that cannot be repaired. The bytes that went are on the
        // wire, the counter has moved past them, and a retry would send good
        // bytes after bad ones.
        let listener = try Listener(.goQuiet)
        defer { listener.close() }

        let connection = try TCPConnection(host: "127.0.0.1", port: listener.port, timeout: 1)
        listener.waitUntilReady()

        var first: TCPFailure?
        XCTAssertThrowsError(try connection.write(moreThanAnyBufferHolds)) { error in
            first = error as? TCPFailure
        }

        XCTAssertThrowsError(try connection.write(Data([0x01]))) { error in
            XCTAssertEqual(error as? TCPFailure, first)
        }

        XCTAssertThrowsError(try connection.read()) { error in
            XCTAssertEqual(error as? TCPFailure, first)
        }
    }

    // MARK: - What a caller is told

    func testEveryWayAnOpenConnectionEndsIsTheSessionEnding() {
        // Told apart at the socket so a log says which happened, and the same
        // thing to a caller. A new case falling through to senderFailed would
        // report a dropped session as something the caller cannot act on.
        let ended: [TCPFailure] = [
            .connectionClosed,
            .connectionWasStopped,
            .messageWasPartlySent(bytes: 10, of: 100, because: .timedOut),
            .messageWasPartlySent(bytes: 10, of: 100, because: .connectionClosed),
        ]

        for failure in ended {
            XCTAssertEqual(SenderFailureKind(failure), .sessionEnded, "\(failure)")
        }
    }

    func testReachingTheReceiverAtAllIsStillToldApartFromLosingIt() {
        XCTAssertEqual(SenderFailureKind(TCPFailure.hostCouldNotBeResolved("x")), .unreachable)
        XCTAssertEqual(SenderFailureKind(TCPFailure.socketCouldNotBeOpened), .unreachable)
        XCTAssertEqual(SenderFailureKind(TCPFailure.timedOut), .unreachable)
    }
}
