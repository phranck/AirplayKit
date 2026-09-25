//
//  PTPGrandmasterTests.swift
//  A clock reaches a peer and answers its delay request over real UDP sockets.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

import Foundation
import XCTest
@testable import PlayableAirplaySender

#if canImport(Glibc)
import Glibc
private let datagramSocket = Int32(SOCK_DGRAM.rawValue)
#else
import Darwin
private let datagramSocket = SOCK_DGRAM
#endif

final class PTPGrandmasterTests: XCTestCase {
    func testOneClockSendsToAPeerAndAnswersItsDelayRequest() throws {
        let eventReceiver = try UDPTestReceiver()
        let generalReceiver = try UDPTestReceiver()

        let clockID: UInt64 = 0x0200_0000_0001_0008
        let clock = try PTPGrandmaster(clockID: clockID,
                                      ports: .init(event: 0, general: 0,
                                                   peerEvent: eventReceiver.port,
                                                   peerGeneral: generalReceiver.port))
        defer { clock.close() }
        try clock.register("127.0.0.1")

        let sync = try XCTUnwrap(eventReceiver.receive(type: 0))
        XCTAssertEqual(sync.count, 44)
        XCTAssertEqual(Array(sync[20..<28]), [2, 0, 0, 0, 0, 1, 0, 8])
        XCTAssertNotNil(generalReceiver.receive(type: 11))

        var request = PTPWire.sync(clockID: 0x1122_3344_5566_7788, sequence: 0x1234)
        request[0] = 0x11
        request[6] = 0x04
        try eventReceiver.send(request, to: clock.eventPort)

        let reply = try XCTUnwrap(generalReceiver.receive(type: 9))
        XCTAssertEqual(Array(reply[30..<32]), [0x12, 0x34])
        XCTAssertEqual(Array(reply[44..<54]), [0x11, 0x22, 0x33, 0x44, 0x55,
                                              0x66, 0x77, 0x88, 0, 1])

        let incoming = PTPWire.announce(clockID: 0x1122_3344_5566_7788, sequence: 2)
        try generalReceiver.send(incoming, to: clock.generalPort)
        let deadline = Date().addingTimeInterval(2)
        while clock.observation(for: "127.0.0.1")?.grandmasterClockID == nil,
              Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        let observed = try XCTUnwrap(clock.observation(for: "127.0.0.1"))
        XCTAssertEqual(observed.grandmasterClockID, 0x1122_3344_5566_7788)
        XCTAssertEqual(observed.delayRequests, 1)
    }
}

private final class UDPTestReceiver {
    let handle: Int32
    let port: UInt16

    init() throws {
        let socketHandle = socket(AF_INET, datagramSocket, 0)
        guard socketHandle >= 0 else { throw TCPFailure.socketCouldNotBeOpened }

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socketHandle, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else {
            Self.close(socketHandle)
            throw TCPFailure.socketCouldNotBeOpened
        }

        var assigned = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let found = withUnsafeMutablePointer(to: &assigned) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(socketHandle, $0, &length)
            }
        }
        guard found == 0 else {
            Self.close(socketHandle)
            throw TCPFailure.socketCouldNotBeOpened
        }
        handle = socketHandle
        port = UInt16(bigEndian: assigned.sin_port)

        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(socketHandle, SOL_SOCKET, SO_RCVTIMEO,
                   &timeout, socklen_t(MemoryLayout<timeval>.size))
    }

    deinit { close() }

    private func close() { Self.close(handle) }

    func receive(type: UInt8) -> Data? {
        for _ in 0..<32 {
            var bytes = [UInt8](repeating: 0, count: 256)
            let count = recv(handle, &bytes, bytes.count, 0)
            guard count > 0 else { return nil }
            if bytes[0] & 0x0F == type { return Data(bytes[..<count]) }
        }
        return nil
    }

    func send(_ packet: Data, to port: UInt16) throws {
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let sent = packet.withUnsafeBytes { bytes in
            withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(handle, bytes.baseAddress, bytes.count, 0,
                           $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        XCTAssertEqual(sent, packet.count)
    }

    private static func close(_ handle: Int32) {
        #if canImport(Glibc)
        _ = Glibc.close(handle)
        #else
        _ = Darwin.close(handle)
        #endif
    }
}
