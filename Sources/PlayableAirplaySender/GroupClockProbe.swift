//
//  GroupClockProbe.swift
//  Measures whether two receivers follow one sender clock.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

import Foundation

/// A group experiment with optional audio. It never changes receiver volume.
package enum GroupClockProbe {
    package struct Result {
        package let address: String
        package let announcedClock: UInt64?
        package let announcements: Int
        package let delayRequests: Int
        package let peerDelayRequests: Int
        package let anchorAccepted: Bool
    }

    package static func run(first: String, second: String, port: UInt16 = 7000,
                            toneSeconds: Int = 0) throws -> [Result] {
        try run(hosts: [first, second], port: port, toneSeconds: toneSeconds)
    }

    package static func run(hosts: [String], port: UInt16 = 7000,
                            toneSeconds: Int = 0) throws -> [Result] {
        guard hosts.count >= 2 else { return [] }
        // A locally administered identity that agrees in the PTP header and
        // both RTSP session bodies, and is fresh for each probe.
        let timing = Session.Timing.newGroup()
        let clock = try PTPGrandmaster(clockID: UInt64(bitPattern: timing.clockIdentifier))
        defer { clock.close() }

        var members: [GroupMember] = []
        defer { members.forEach { $0.close() } }
        for host in hosts {
            members.append(try GroupMember(id: host, host: host, port: port,
                                           senderName: "PlayableAirplay clock probe", timing: timing))
        }

        for member in members {
            try clock.register(member.connection.peerAddress)
        }
        for member in members {
            let peers = [member.connection.localAddress]
                + members.compactMap { other in
                    other === member ? nil : other.connection.peerAddress
                }
            try member.session.setPeers(peers)
        }

        Thread.sleep(forTimeInterval: 5)
        guard let reading = clock.reading(),
              let anchor = PTPClock.now(from: reading, ahead: AirPlaySender.anchorLead)
        else { throw SenderFailure.receiverAnnouncedNoClock }

        let accepted = members.map { member in
            (try? member.start(timestamp: 0,
                                seconds: anchor.seconds,
                                fraction: anchor.fraction,
                                clockIdentifier: timing.clockIdentifier)) != nil
        }

        if toneSeconds > 0, accepted.allSatisfy({ $0 }) {
            // One packet source and one pacing loop keep both audio streams on
            // precisely the RTP positions named by their identical anchors.
            let packetCount = toneSeconds * ALACFrame.sampleRate / ALACFrame.framesPerPacket
            var due = ProcessInfo.processInfo.systemUptime
            var frame = 0
            for _ in 0..<packetCount {
                var samples = [Int16](repeating: 0,
                                      count: ALACFrame.framesPerPacket * ALACFrame.channelCount)
                for index in 0..<ALACFrame.framesPerPacket {
                    let angle = 2 * Double.pi * 440 * Double(frame) / Double(ALACFrame.sampleRate)
                    let value = Int16(3000 * sin(angle))
                    samples[index * 2] = value
                    samples[index * 2 + 1] = value
                    frame += 1
                }
                for member in members { try member.write(samples) }
                due += ALACFrame.packetDuration
                let wait = due - ProcessInfo.processInfo.systemUptime
                if wait > 0 { Thread.sleep(forTimeInterval: wait) }
            }
            Thread.sleep(forTimeInterval: AirPlaySender.anchorLead + 0.5)
        }

        return members.enumerated().map { index, member in
            let observed = clock.observation(for: member.connection.peerAddress)
            return Result(address: member.connection.peerAddress,
                          announcedClock: observed?.grandmasterClockID,
                          announcements: observed?.announcements ?? 0,
                          delayRequests: observed?.delayRequests ?? 0,
                          peerDelayRequests: observed?.peerDelayRequests ?? 0,
                          anchorAccepted: accepted[index])
        }
    }
}
