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

/// What can go wrong listening for a receiver's clock.
public enum PTPFailure: Error, Equatable {
    /**
     One of the two ports could not be bound.

     They are 319 and 320, and on Linux a process may not bind below 1024
     without `CAP_NET_BIND_SERVICE`. That is a permission on this machine rather
     than anything about the receiver, and saying so is the difference between
     looking at the network and looking at the process.
     */
    case portsCouldNotBeOpened(port: UInt16)
}

/**
 What a receiver's own clock says.

 PTP is the Precision Time Protocol, standardised as IEEE 1588. Devices on one
 network keep a common clock with it, closely enough for audio: one of them is
 elected the grandmaster and sends out its time, and the others follow. AirPlay 2
 expresses the anchor on that clock, which is why a sender has to read it.

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

    /**
     Opens the two ports a receiver announces to.

     @throws `PTPFailure.portsCouldNotBeOpened` where they cannot be bound. On
     Linux a process without `CAP_NET_BIND_SERVICE` may not bind a port below
     1024, and both of these are, so an ordinary desktop application can meet
     this. It is a matter of what this machine allows rather than of the
     receiver, and it used to be reported as the receiver being unreachable.
     */
    public init() throws {
        for port in [Self.eventPort, Self.generalPort] {
            do { sockets.append(try Self.listening(on: port)) }
            catch {
                for handle in sockets { Self.closeSocket(handle) }
                sockets = []

                throw PTPFailure.portsCouldNotBeOpened(port: port)
            }
        }
    }

    deinit {
        for handle in sockets { Self.closeSocket(handle) }
    }

    /// Closing a descriptor, which the two platforms spell the same way in different modules.
    private static func closeSocket(_ handle: Int32) {
        #if canImport(Glibc)
        Glibc.close(handle)
        #else
        Darwin.close(handle)
        #endif
    }

    /**
     Waits until the receiver has announced its clock and said what time it is.

     Both are needed and they arrive in different messages, so this returns once
     it has seen an Announce and a Follow_Up.

     @param timeout How long to wait before giving up.
     @returns What the clock said, or nil where it said nothing in time.
     */
    public func read(from receiver: String, timeout: TimeInterval = 10) -> Reading? {
        let deadline = Date().addingTimeInterval(timeout)
        var identity: UInt64?
        var time: (seconds: UInt64, nanoseconds: UInt32, heardAt: TimeInterval)?

        while Date() < deadline {
            guard let heard = receive(before: deadline) else { continue }

            // Anything from anywhere else is somebody else's clock, or somebody
            // trying to be. A sender that takes an identity from one machine
            // and a time from another anchors to a reading that belongs to
            // neither, and the session then plays silence.
            guard receiver.isEmpty || heard.source == receiver else { continue }

            switch heard.message.type {
            case .announce:
                identity = heard.message.grandmasterIdentity ?? identity
                // The grandmaster changed, so whatever time was held belongs to
                // the old one and is thrown away rather than mixed in.
                time = nil

            case .followUp:
                // Only from the clock that announced itself. Two receivers
                // announcing at once is ordinary, and each one's seconds are
                // its own uptime, so a stamp from the wrong one can be days out.
                guard let identity, heard.message.sourceIdentity == identity else { break }

                if let stamp = heard.message.timestamp {
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
     binary fraction the anchor carries rather than as nanoseconds. Nil where
     the reading and the lead together do not land on a time an anchor can
     carry, which a caller answers by not anchoring rather than by anchoring to
     something else.
     */
    public static func now(from reading: Reading, ahead: TimeInterval = 0) -> (seconds: Int64, fraction: Int64)? {
        let elapsed = ProcessInfo.processInfo.systemUptime - reading.heardAt
        let total = Double(reading.seconds) + Double(reading.nanoseconds) / 1_000_000_000 + elapsed + ahead

        // Refused rather than converted. `Int64(...)` ends the process on a
        // value outside its range and on one that is not a number at all, and
        // both `reading` and `ahead` come from outside this call. A clock that
        // says something impossible is a clock not to anchor to.
        guard total.isFinite, total >= 0, total < Double(Int64.max) else { return nil }

        let seconds = Int64(total)
        let fraction = total - Double(seconds)

        // The anchor carries the fraction as a 64-bit binary fraction, which is
        // what makes the measured value of 207788735369052160 about eleven
        // milliseconds rather than an implausible number of nanoseconds.
        //
        // Half a second and above sets the top bit, which in Int64 is the sign
        // bit, so the value printed here is negative for half of all readings.
        // That is the correct bit pattern and it reaches the receiver intact: a
        // binary property list writes a negative Int64 as the same eight bytes
        // as a positive one, marker 0x13 and then the pattern, which was
        // measured rather than assumed. Swift has no unsigned path here because
        // the property list encoder takes signed integers.
        let scaled = (fraction * Double(1 << 62)) * 4

        return (seconds, Int64(bitPattern: UInt64(scaled.rounded(.down))))
    }

    /**
     How long is left before a deadline, in the milliseconds `poll` counts in.

     Clamped rather than converted. ``read(from:timeout:)`` is public and its
     timeout carries a default, so the number that arrives here is the caller's,
     and `Int32(...)` on a wait of more than about twenty-five days, or on one
     that is not a number at all, ends the process instead of waiting.

     @param deadline When the wait is over.
     @returns Nought where the deadline has passed or is not a time, and at most
     what `poll` can be handed.
     */
    static func milliseconds(until deadline: Date) -> Int32 {
        let remaining = deadline.timeIntervalSinceNow * 1000

        // False for a value that is not a number, which is how a deadline built
        // from an unusable timeout arrives here.
        guard remaining > 0 else { return 0 }
        guard remaining < Double(Int32.max) else { return Int32.max }

        return Int32(remaining)
    }

    // MARK: - Private

    private enum MessageType {
        case announce
        case followUp
        case other
    }

    private struct Message {
        let type: MessageType
        /// The clock that sent this message, which every PTP header carries.
        let sourceIdentity: UInt64
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

    /**
     Waits on both sockets for one message, and reads whichever answers first.

     Read with `recvfrom` rather than `recv`, because who sent it is half of
     whether it should be believed and `recv` throws that away.
     */
    private func receive(before deadline: Date) -> (message: Message, source: String)? {
        var descriptors = sockets.map { pollfd(fd: $0, events: Int16(POLLIN), revents: 0) }

        guard poll(&descriptors, nfds_t(descriptors.count), Self.milliseconds(until: deadline)) > 0 else {
            return nil
        }

        for (index, descriptor) in descriptors.enumerated() where descriptor.revents & Int16(POLLIN) != 0 {
            var buffer = [UInt8](repeating: 0, count: 256)
            var from = sockaddr_in()
            var length = socklen_t(MemoryLayout<sockaddr_in>.size)

            let count = withUnsafeMutablePointer(to: &from) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { address in
                    recvfrom(sockets[index], &buffer, buffer.count, 0, address, &length)
                }
            }
            guard count >= 34 else { continue }

            var text = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            let source = inet_ntop(AF_INET, &from.sin_addr, &text, socklen_t(INET_ADDRSTRLEN)) != nil
                ? String(cString: text)
                : ""

            return (Self.parsed(Array(buffer[0..<count])), source)
        }

        return nil
    }

    /// Reads the header and, for the two messages that matter, what follows it.
    private static func parsed(_ bytes: [UInt8]) -> Message {
        // Every PTP header names the clock that sent it, at offset 20.
        let source = unsigned64(bytes, at: 20)

        // The low nibble of the first byte names the message. 0 is Sync, 8 is
        // Follow_Up and 11 is Announce.
        switch bytes[0] & 0x0F {
        case 0x0B where bytes.count >= 64:
            return Message(type: .announce,
                           sourceIdentity: source,
                           grandmasterIdentity: unsigned64(bytes, at: 53),
                           timestamp: nil)

        case 0x08 where bytes.count >= 44:
            // A PTP timestamp is six bytes of seconds and four of nanoseconds.
            var seconds: UInt64 = 0
            for index in 34..<40 { seconds = seconds << 8 | UInt64(bytes[index]) }
            var nanoseconds: UInt32 = 0
            for index in 40..<44 { nanoseconds = nanoseconds << 8 | UInt32(bytes[index]) }

            return Message(type: .followUp,
                           sourceIdentity: source,
                           grandmasterIdentity: nil,
                           timestamp: (seconds, nanoseconds))

        default:
            return Message(type: .other, sourceIdentity: source, grandmasterIdentity: nil, timestamp: nil)
        }
    }

    private static func unsigned64(_ bytes: [UInt8], at offset: Int) -> UInt64 {
        var value: UInt64 = 0
        for index in offset..<(offset + 8) { value = value << 8 | UInt64(bytes[index]) }

        return value
    }
}
