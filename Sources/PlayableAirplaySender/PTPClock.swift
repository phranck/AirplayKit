//
//  PTPClock.swift
//  Reading the clock a receiver keeps, so the anchor can be expressed on it.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

import Foundation

#if canImport(Glibc)
import Glibc
#else
import Darwin
#endif

/**
 What a receiver's own PTP clock says.

 A receiver on the buffered path will not take an anchor on a timeline it cannot
 read, and it names that timeline by a clock identity. These receivers keep the
 clock themselves and announce it: they send Announce, Sync and Follow_Up to the
 addresses `SETPEERS` gave them, and expect the sender to follow rather than to
 lead.

 So this listens rather than speaks. It takes the grandmaster's identity out of
 an Announce and its time out of a Follow_Up, and from then on it can say what
 that clock reads at any later instant.

 The estimate carries the one-way delay of the network as an error, because
 nothing here sends a Delay_Req to measure it. For placing the start of a stream
 a few hundred microseconds out, that is immaterial; for holding two speakers in
 step it would not be, and that is the multi-room work rather than this.
 */
public final class PTPClock {
    /// The ports PTP uses: the event messages on one and everything else on the other.
    static let eventPort: UInt16 = 319
    static let generalPort: UInt16 = 320

    /// What a receiver's clock said, and when this machine heard it.
    public struct Reading {
        /// The grandmaster's clock identity, which the anchor names as its timeline.
        public let identity: UInt64

        /// The clock's seconds at the moment it was read.
        public let seconds: UInt64

        /// Its nanoseconds at that moment.
        public let nanoseconds: UInt32

        /// This machine's own uptime when that reading arrived.
        let heardAt: TimeInterval
    }

    private var sockets: [Int32] = []

    public init() throws {
        for port in [Self.eventPort, Self.generalPort] {
            sockets.append(try Self.listening(on: port))
        }
    }

    deinit {
        for handle in sockets {
            #if canImport(Glibc)
            Glibc.close(handle)
            #else
            Darwin.close(handle)
            #endif
        }
    }

    /**
     Waits until the receiver has announced its clock and said what time it is.

     Both are needed and they arrive in different messages, so this returns once
     it has seen an Announce and a Follow_Up.

     @param timeout How long to wait before giving up.
     @returns What the clock said, or nil where it said nothing in time.
     */
    public func read(timeout: TimeInterval = 10) -> Reading? {
        let deadline = Date().addingTimeInterval(timeout)
        var identity: UInt64?
        var time: (seconds: UInt64, nanoseconds: UInt32, heardAt: TimeInterval)?

        while Date() < deadline {
            guard let message = receive(before: deadline) else { continue }

            switch message.type {
            case .announce:
                identity = message.grandmasterIdentity ?? identity

            case .followUp:
                if let stamp = message.timestamp {
                    time = (stamp.seconds, stamp.nanoseconds, ProcessInfo.processInfo.systemUptime)
                }

            case .other:
                break
            }

            if let identity, let time {
                return Reading(identity: identity,
                               seconds: time.seconds,
                               nanoseconds: time.nanoseconds,
                               heardAt: time.heardAt)
            }
        }

        return nil
    }

    /**
     What that clock reads now, carried forward from when it was last heard.

     @param reading What the clock said earlier.
     @param ahead How far past now to report, which an anchor needs because it
     says when the first frame sounds and no frame can arrive before it is sent.
     @returns Its seconds and the fraction of a second, the latter as the 64-bit
     binary fraction the anchor carries rather than as nanoseconds.
     */
    public static func now(from reading: Reading, ahead: TimeInterval = 0) -> (seconds: Int64, fraction: Int64) {
        let elapsed = ProcessInfo.processInfo.systemUptime - reading.heardAt
        let total = Double(reading.seconds) + Double(reading.nanoseconds) / 1_000_000_000 + elapsed + ahead

        let seconds = Int64(total)
        let fraction = total - Double(seconds)

        // The anchor carries the fraction as a 64-bit binary fraction, which is
        // what makes the measured value of 207788735369052160 about eleven
        // milliseconds rather than an implausible number of nanoseconds.
        return (seconds, Int64(fraction * Double(1 << 62)) << 2)
    }

    // MARK: - Private

    private enum MessageType {
        case announce
        case followUp
        case other
    }

    private struct Message {
        let type: MessageType
        let grandmasterIdentity: UInt64?
        let timestamp: (seconds: UInt64, nanoseconds: UInt32)?
    }

    private static func listening(on port: UInt16) throws -> Int32 {
        #if canImport(Glibc)
        let handle = socket(AF_INET, Int32(SOCK_DGRAM.rawValue), 0)
        #else
        let handle = socket(AF_INET, SOCK_DGRAM, 0)
        #endif
        guard handle >= 0 else { throw TCPFailure.socketCouldNotBeOpened }

        var reuse: Int32 = 1
        setsockopt(handle, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = INADDR_ANY

        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(handle, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else {
            #if canImport(Glibc)
            Glibc.close(handle)
            #else
            Darwin.close(handle)
            #endif
            throw TCPFailure.socketCouldNotBeOpened
        }

        return handle
    }

    /// Waits on both sockets for one message, and reads whichever answers first.
    private func receive(before deadline: Date) -> Message? {
        var descriptors = sockets.map { pollfd(fd: $0, events: Int16(POLLIN), revents: 0) }
        let remaining = max(0, Int32(deadline.timeIntervalSinceNow * 1000))

        guard poll(&descriptors, nfds_t(descriptors.count), remaining) > 0 else { return nil }

        for (index, descriptor) in descriptors.enumerated() where descriptor.revents & Int16(POLLIN) != 0 {
            var buffer = [UInt8](repeating: 0, count: 256)
            let count = recv(sockets[index], &buffer, buffer.count, 0)
            guard count >= 34 else { continue }

            return Self.parsed(Array(buffer[0..<count]))
        }

        return nil
    }

    /// Reads the header and, for the two messages that matter, what follows it.
    private static func parsed(_ bytes: [UInt8]) -> Message {
        // The low nibble of the first byte names the message. 0 is Sync, 8 is
        // Follow_Up and 11 is Announce.
        switch bytes[0] & 0x0F {
        case 0x0B where bytes.count >= 64:
            return Message(type: .announce,
                           grandmasterIdentity: unsigned64(bytes, at: 53),
                           timestamp: nil)

        case 0x08 where bytes.count >= 44:
            // A PTP timestamp is six bytes of seconds and four of nanoseconds.
            var seconds: UInt64 = 0
            for index in 34..<40 { seconds = seconds << 8 | UInt64(bytes[index]) }
            var nanoseconds: UInt32 = 0
            for index in 40..<44 { nanoseconds = nanoseconds << 8 | UInt32(bytes[index]) }

            return Message(type: .followUp, grandmasterIdentity: nil, timestamp: (seconds, nanoseconds))

        default:
            return Message(type: .other, grandmasterIdentity: nil, timestamp: nil)
        }
    }

    private static func unsigned64(_ bytes: [UInt8], at offset: Int) -> UInt64 {
        var value: UInt64 = 0
        for index in offset..<(offset + 8) { value = value << 8 | UInt64(bytes[index]) }

        return value
    }
}
