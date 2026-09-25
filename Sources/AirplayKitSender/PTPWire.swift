//
//  PTPWire.swift
//  The clock messages sent to AirPlay 2 timing peers.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

import Foundation

/// IEEE 802.1AS message layouts. Socket ownership and clock selection stay elsewhere.
enum PTPWire {
    enum RequestKind: Equatable {
        case delay
        case peerDelay
        case signaling
    }

    struct Request {
        let kind: RequestKind
        let clockID: UInt64
        let portNumber: UInt16
        let sequence: UInt16
    }

    struct Announcement {
        let sourceClockID: UInt64
        let grandmasterClockID: UInt64
    }

    struct Timestamp {
        let seconds: UInt64
        let nanoseconds: UInt32
    }

    static func sync(clockID: UInt64, sequence: UInt16) -> Data {
        var packet = header(type: 0, length: 44, flags: 0x0608,
                            clockID: clockID, sequence: sequence,
                            control: 0, interval: -3)
        packet.append(contentsOf: repeatElement(UInt8(0), count: 10))
        return packet
    }

    static func followUp(clockID: UInt64, sequence: UInt16, timestamp: Timestamp) -> Data {
        var packet = header(type: 8, length: 76, flags: 0x0408,
                            clockID: clockID, sequence: sequence,
                            control: 2, interval: -3)
        packet.append(timestamp: timestamp)

        // IEEE 802.1AS Follow_Up information TLV: organization 00-80-C2,
        // subtype 1, followed by zero rate/phase corrections for this master.
        packet.append(contentsOf: [0, 3, 0, 28, 0, 0x80, 0xC2, 0, 0, 1])
        packet.append(contentsOf: repeatElement(UInt8(0), count: 22))
        return packet
    }

    static func announce(clockID: UInt64, sequence: UInt16) -> Data {
        var packet = header(type: 11, length: 76, flags: 0x0408,
                            clockID: clockID, sequence: sequence,
                            control: 5, interval: 0)
        packet.append(contentsOf: repeatElement(UInt8(0), count: 13))
        packet.append(contentsOf: [128, 6, 0x21, 0x43, 0x6A, 128])
        packet.append(bigEndian: clockID, bytes: 8)
        packet.append(contentsOf: [0, 0, 0x20])
        packet.append(contentsOf: [0, 8, 0, 8])
        packet.append(bigEndian: clockID, bytes: 8)
        return packet
    }

    /// Accepts only complete gPTP requests in domain zero.
    static func request(_ data: Data) -> Request? {
        guard validHeader(data) else { return nil }

        let kind: RequestKind
        switch data[0] & 0x0F {
        case 1 where data.count >= 44: kind = .delay
        case 2 where data.count >= 54: kind = .peerDelay
        case 12 where data.count >= 44: kind = .signaling
        default: return nil
        }

        let clockID = data[20..<28].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        let portNumber = UInt16(data[28]) << 8 | UInt16(data[29])
        let sequence = UInt16(data[30]) << 8 | UInt16(data[31])
        guard portNumber != 0 else { return nil }
        return Request(kind: kind, clockID: clockID, portNumber: portNumber, sequence: sequence)
    }

    static func announcement(_ data: Data) -> Announcement? {
        guard validHeader(data), data[0] & 0x0F == 11, data.count >= 64 else { return nil }
        return Announcement(sourceClockID: data[20..<28].reduce(0) { $0 << 8 | UInt64($1) },
                            grandmasterClockID: data[53..<61].reduce(0) { $0 << 8 | UInt64($1) })
    }

    static func delayResponse(clockID: UInt64, sequence: UInt16,
                              receivedAt: Timestamp,
                              requesterClockID: UInt64, requesterPort: UInt16) -> Data {
        response(type: 9, clockID: clockID, sequence: sequence,
                 timestamp: receivedAt, requesterClockID: requesterClockID,
                 requesterPort: requesterPort, twoStep: false)
    }

    static func peerDelayResponse(clockID: UInt64, sequence: UInt16,
                                  receivedAt: Timestamp,
                                  requesterClockID: UInt64, requesterPort: UInt16) -> Data {
        response(type: 3, clockID: clockID, sequence: sequence,
                 timestamp: receivedAt, requesterClockID: requesterClockID,
                 requesterPort: requesterPort, twoStep: true)
    }

    static func peerDelayFollowUp(clockID: UInt64, sequence: UInt16,
                                  sentAt: Timestamp,
                                  requesterClockID: UInt64, requesterPort: UInt16) -> Data {
        response(type: 10, clockID: clockID, sequence: sequence,
                 timestamp: sentAt, requesterClockID: requesterClockID,
                 requesterPort: requesterPort, twoStep: false)
    }

    private static func response(type: UInt8, clockID: UInt64, sequence: UInt16,
                                 timestamp: Timestamp,
                                 requesterClockID: UInt64, requesterPort: UInt16,
                                 twoStep: Bool) -> Data {
        let control: UInt8 = type == 9 ? 3 : 5
        var packet = header(type: type, length: 54, flags: twoStep ? 0x0608 : 0x0408,
                            clockID: clockID, sequence: sequence,
                            control: control, interval: 127)
        packet.append(timestamp: timestamp)
        packet.append(bigEndian: requesterClockID, bytes: 8)
        packet.append(bigEndian: UInt64(requesterPort), bytes: 2)
        return packet
    }

    private static func header(type: UInt8, length: UInt16, flags: UInt16,
                               clockID: UInt64, sequence: UInt16,
                               control: UInt8, interval: Int8) -> Data {
        var packet = Data()
        packet.append(0x10 | type) // majorSdoId 1: gPTP over the AirPlay UDP ports.
        packet.append(0x12) // minor PTP version 1, PTP version 2.
        packet.append(bigEndian: UInt64(length), bytes: 2)
        packet.append(contentsOf: [0, 0]) // Domain and minorSdoId.
        packet.append(bigEndian: UInt64(flags), bytes: 2)
        packet.append(contentsOf: repeatElement(UInt8(0), count: 12)) // Correction and message-specific fields.
        packet.append(bigEndian: clockID, bytes: 8)
        packet.append(bigEndian: 1, bytes: 2) // Source port identity.
        packet.append(bigEndian: UInt64(sequence), bytes: 2)
        packet.append(control)
        packet.append(UInt8(bitPattern: interval))
        return packet
    }

    private static func validHeader(_ data: Data) -> Bool {
        data.count >= 34 && data[0] >> 4 == 1 && data[1] & 0x0F == 2
            && data[4] == 0 && UInt16(data[2]) << 8 | UInt16(data[3]) == data.count
    }
}

private extension Data {
    mutating func append(bigEndian value: UInt64, bytes: Int) {
        for shift in stride(from: (bytes - 1) * 8, through: 0, by: -8) {
            append(UInt8(truncatingIfNeeded: value >> shift))
        }
    }

    mutating func append(timestamp: PTPWire.Timestamp) {
        append(bigEndian: timestamp.seconds, bytes: 6)
        append(bigEndian: UInt64(timestamp.nanoseconds), bytes: 4)
    }
}
