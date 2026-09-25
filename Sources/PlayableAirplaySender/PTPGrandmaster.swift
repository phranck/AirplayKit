//
//  PTPGrandmaster.swift
//  One clock shared by the receivers of an AirPlay 2 group.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

import Foundation

#if canImport(Glibc)
import Glibc
private let datagramSocket = Int32(SOCK_DGRAM.rawValue)
#else
import Darwin
private let datagramSocket = SOCK_DGRAM
#endif

/// Emits one gPTP timeline to all registered timing peers.
package final class PTPGrandmaster {
    struct Observation {
        var grandmasterClockID: UInt64?
        var announcements = 0
        var delayRequests = 0
        var peerDelayRequests = 0
    }

    struct Ports {
        let event: UInt16
        let general: UInt16
        let peerEvent: UInt16
        let peerGeneral: UInt16

        static let airPlay = Ports(event: 319, general: 320,
                                   peerEvent: 319, peerGeneral: 320)
    }

    private let eventSocket: Int32
    private let generalSocket: Int32
    private let ports: Ports
    private let state = NSLock()
    private var peers: [String: in_addr] = [:]
    private var observations: [String: Observation] = [:]
    private var open = true
    private var thread: Thread?
    private let clockID: UInt64

    let eventPort: UInt16
    let generalPort: UInt16

    init(clockID: UInt64, ports: Ports = .airPlay) throws {
        let event = try Self.bind(port: ports.event)
        do {
            let general = try Self.bind(port: ports.general)
            eventSocket = event.handle
            generalSocket = general.handle
            eventPort = event.port
            generalPort = general.port
        } catch {
            Self.close(event.handle)
            throw error
        }
        self.clockID = clockID
        self.ports = ports

        let worker = Thread { [weak self] in self?.run() }
        worker.name = "PlayableAirplay.ptp"
        thread = worker
        worker.start()
    }

    deinit { close() }

    /// Adds one receiver's IPv4 timing address. Repeating it is harmless.
    func register(_ address: String) throws {
        var ipv4 = in_addr()
        guard inet_pton(AF_INET, address, &ipv4) == 1 else {
            throw TCPFailure.hostCouldNotBeResolved(address)
        }
        state.lock()
        peers[address] = ipv4
        if observations[address] == nil { observations[address] = Observation() }
        state.unlock()
    }

    func unregister(_ address: String) {
        state.lock()
        peers.removeValue(forKey: address)
        observations.removeValue(forKey: address)
        state.unlock()
    }

    func observation(for address: String) -> Observation? {
        state.lock()
        defer { state.unlock() }
        return observations[address]
    }

    /// A reading on the clock this sender announces to every member.
    func reading() -> PTPClock.Reading? {
        guard let stamp = Self.timestamp() else { return nil }
        return PTPClock.Reading(identity: clockID, seconds: stamp.seconds,
                                nanoseconds: stamp.nanoseconds,
                                heardAt: ProcessInfo.processInfo.systemUptime)
    }

    func close() {
        state.lock()
        guard open else { state.unlock(); return }
        open = false
        state.unlock()

        if let thread, Thread.current !== thread {
            let deadline = Date().addingTimeInterval(2)
            while !thread.isFinished, Date() < deadline {
                Thread.sleep(forTimeInterval: 0.002)
            }
            guard thread.isFinished else { return }
        }
        Self.close(eventSocket)
        Self.close(generalSocket)
    }

    // MARK: - Clock loop

    private func run() {
        var syncSequence: UInt16 = 0
        var announceSequence: UInt16 = 0
        var nextSync: TimeInterval = 0
        var nextAnnounce: TimeInterval = 0

        while isOpen {
            let now = ProcessInfo.processInfo.systemUptime
            let recipients = peerSnapshot()

            if now >= nextSync {
                for peer in recipients {
                    guard let stamp = Self.timestamp() else { continue }
                    send(PTPWire.sync(clockID: clockID, sequence: syncSequence),
                         on: eventSocket, to: peer, port: ports.peerEvent)
                    send(PTPWire.followUp(clockID: clockID, sequence: syncSequence,
                                          timestamp: stamp),
                         on: generalSocket, to: peer, port: ports.peerGeneral)
                }
                syncSequence &+= 1
                nextSync = now + 0.125
            }

            if now >= nextAnnounce {
                let packet = PTPWire.announce(clockID: clockID, sequence: announceSequence)
                for peer in recipients {
                    send(packet, on: generalSocket, to: peer, port: ports.peerGeneral)
                }
                announceSequence &+= 1
                nextAnnounce = now + 1
            }

            receiveOne()
        }
    }

    private var isOpen: Bool {
        state.lock()
        defer { state.unlock() }
        return open
    }

    private func peerSnapshot() -> [in_addr] {
        state.lock()
        defer { state.unlock() }
        return Array(peers.values)
    }

    private func receiveOne() {
        var descriptors = [pollfd(fd: eventSocket, events: Int16(POLLIN), revents: 0),
                           pollfd(fd: generalSocket, events: Int16(POLLIN), revents: 0)]
        guard poll(&descriptors, nfds_t(descriptors.count), 20) > 0 else { return }

        for (index, descriptor) in descriptors.enumerated() where descriptor.revents & Int16(POLLIN) != 0 {
            var bytes = [UInt8](repeating: 0, count: 256)
            var source = sockaddr_in()
            var length = socklen_t(MemoryLayout<sockaddr_in>.size)
            let count = withUnsafeMutablePointer(to: &source) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    recvfrom(descriptors[index].fd, &bytes, bytes.count, 0, $0, &length)
                }
            }
            guard count >= 34, let peer = registeredAddress(for: source.sin_addr) else { continue }
            let packet = Data(bytes[..<count])

            if let announcement = PTPWire.announcement(packet) {
                state.lock()
                observations[peer]?.grandmasterClockID = announcement.grandmasterClockID
                observations[peer]?.announcements += 1
                state.unlock()
                continue
            }

            guard let request = PTPWire.request(packet),
                  let receivedAt = Self.timestamp() else { continue }

            switch request.kind {
            case .delay:
                state.lock()
                observations[peer]?.delayRequests += 1
                state.unlock()
                send(PTPWire.delayResponse(clockID: clockID, sequence: request.sequence,
                                           receivedAt: receivedAt,
                                           requesterClockID: request.clockID,
                                           requesterPort: request.portNumber),
                     on: generalSocket, to: source.sin_addr, port: ports.peerGeneral)

            case .peerDelay:
                state.lock()
                observations[peer]?.peerDelayRequests += 1
                state.unlock()
                send(PTPWire.peerDelayResponse(clockID: clockID, sequence: request.sequence,
                                               receivedAt: receivedAt,
                                               requesterClockID: request.clockID,
                                               requesterPort: request.portNumber),
                     on: eventSocket, to: source.sin_addr, port: ports.peerEvent)
                if let sentAt = Self.timestamp() {
                    send(PTPWire.peerDelayFollowUp(clockID: clockID, sequence: request.sequence,
                                                   sentAt: sentAt,
                                                   requesterClockID: request.clockID,
                                                   requesterPort: request.portNumber),
                         on: generalSocket, to: source.sin_addr, port: ports.peerGeneral)
                }

            case .signaling:
                break
            }
        }
    }

    private func registeredAddress(for address: in_addr) -> String? {
        state.lock()
        defer { state.unlock() }
        return peers.first { $0.value.s_addr == address.s_addr }?.key
    }

    private func send(_ packet: Data, on handle: Int32, to peer: in_addr, port: UInt16) {
        var destination = sockaddr_in()
        destination.sin_family = sa_family_t(AF_INET)
        destination.sin_port = port.bigEndian
        destination.sin_addr = peer
        packet.withUnsafeBytes { bytes in
            withUnsafePointer(to: &destination) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    _ = sendto(handle, bytes.baseAddress, bytes.count, 0,
                               $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }

    private static func timestamp() -> PTPWire.Timestamp? {
        var instant = timespec()
        guard clock_gettime(CLOCK_MONOTONIC, &instant) == 0,
              instant.tv_sec >= 0, instant.tv_nsec >= 0,
              instant.tv_nsec < 1_000_000_000
        else { return nil }
        return PTPWire.Timestamp(seconds: UInt64(instant.tv_sec),
                                 nanoseconds: UInt32(instant.tv_nsec))
    }

    private static func bind(port: UInt16) throws -> (handle: Int32, port: UInt16) {
        let handle = socket(AF_INET, datagramSocket, 0)
        guard handle >= 0 else { throw PTPFailure.portsCouldNotBeOpened(port: port) }

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = INADDR_ANY
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                DarwinOrGlibcBind(handle, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else {
            close(handle)
            throw PTPFailure.portsCouldNotBeOpened(port: port)
        }

        var assigned = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let found = withUnsafeMutablePointer(to: &assigned) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(handle, $0, &length)
            }
        }
        guard found == 0 else {
            close(handle)
            throw PTPFailure.portsCouldNotBeOpened(port: port)
        }
        return (handle, UInt16(bigEndian: assigned.sin_port))
    }

    private static func close(_ handle: Int32) {
        #if canImport(Glibc)
        _ = Glibc.close(handle)
        #else
        _ = Darwin.close(handle)
        #endif
    }
}

private func DarwinOrGlibcBind(_ handle: Int32, _ address: UnsafePointer<sockaddr>,
                               _ length: socklen_t) -> Int32 {
    #if canImport(Glibc)
    return Glibc.bind(handle, address, length)
    #else
    return Darwin.bind(handle, address, length)
    #endif
}
