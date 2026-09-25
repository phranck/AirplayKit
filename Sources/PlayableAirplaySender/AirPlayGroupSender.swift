//
//  AirPlayGroupSender.swift
//  One audio timeline and one PTP clock for multiple receivers.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

import Foundation

package enum GroupFailure: Error, Equatable {
    case needsReceiver
    case duplicateReceiver
    case receiverNotInGroup
    case volumeUnavailable
    case groupEnded
}

package final class AirPlayGroupSender {
    package struct Endpoint {
        package let id: String
        package let host: String
        package let port: UInt16

        package init(id: String, host: String, port: UInt16) {
            self.id = id
            self.host = host
            self.port = port
        }
    }

    private let timing: Session.Timing
    private let clock: PTPGrandmaster
    private let ring = SampleRing(capacity: AirPlaySender.ringFrames * ALACFrame.channelCount)
    private let senderName: String
    private let volumeMemory: ReceiverVolumeMemory?
    private let state = NSLock()
    private let changes = NSLock()
    private var members: [GroupMember] = []
    private var timeline: GroupTimeline?
    private var nextFrame: UInt64 = 0
    private var running = true
    private var priming = true
    private var pump: Thread?
    private var volumePoller: Thread?
    private var eventHandler: ((String, EventChannel.Request) -> Void)?
    private var volumeHandler: ((String, Float) -> Void)?
    private var memberLossHandler: ((String, String) -> Void)?
    private var handlerForStop: ((String?) -> Void)?
    private var lastFailure: String?

    package init(receivers: [Endpoint], senderName: String,
                 volumeMemory: ReceiverVolumeMemory? = nil) throws {
        guard !receivers.isEmpty else { throw GroupFailure.needsReceiver }
        guard Set(receivers.map(\.id)).count == receivers.count else {
            throw GroupFailure.duplicateReceiver
        }
        timing = Session.Timing.newGroup()
        clock = try PTPGrandmaster(clockID: UInt64(bitPattern: timing.clockIdentifier))
        self.senderName = senderName
        self.volumeMemory = volumeMemory

        do {
            for endpoint in receivers {
                let member = try GroupMember(id: endpoint.id, host: endpoint.host,
                                             port: endpoint.port, senderName: senderName,
                                             timing: timing)
                members.append(member)
                try volumeMemory?.restoreVolume(for: endpoint.id) { try member.setVolume($0) }
                if let level = member.currentVolume { volumeMemory?.remember(level, for: endpoint.id) }
                try clock.register(member.connection.peerAddress)
            }
            try publishPeers(to: members)

            // Both receivers first contest their own clocks. The sender's
            // Announce and Sync traffic must reach them before the first anchor.
            Thread.sleep(forTimeInterval: 5)
            guard let reading = clock.reading() else {
                throw SenderFailure.receiverAnnouncedNoClock
            }
            let mapping = GroupTimeline(reading: reading,
                                        ahead: AirPlaySender.anchorLead,
                                        sampleRate: ALACFrame.sampleRate)
            guard let anchor = mapping.anchor(forFrame: 0) else {
                throw SenderFailure.receiverAnnouncedNoClock
            }
            for member in members {
                try member.start(timestamp: anchor.rtpTime,
                                 seconds: anchor.seconds,
                                 fraction: anchor.fraction,
                                 clockIdentifier: timing.clockIdentifier)
            }
            timeline = mapping
            for member in members {
                let id = member.id
                member.events.stoppedHandler = { [weak self] reason in
                    self?.memberStopped(id: id, reason: reason)
                }
            }
            startPump()
            startVolumePoller()
        } catch {
            close()
            throw error
        }
    }

    deinit { close() }

    package var isRunning: Bool {
        state.lock()
        defer { state.unlock() }
        return running
    }

    package var memberIDs: [String] {
        state.lock()
        defer { state.unlock() }
        return members.map(\.id)
    }

    package var heldFrames: Int { ring.held / ALACFrame.channelCount }

    package func discardHeldAudio() -> Int { ring.drain() / ALACFrame.channelCount }

    package var groupID: String { timing.groupUUID }

    package var endedBecause: String? {
        state.lock()
        defer { state.unlock() }
        return lastFailure
    }

    package var stoppedHandler: ((String?) -> Void)? {
        get {
            state.lock()
            defer { state.unlock() }
            return handlerForStop
        }
        set {
            state.lock()
            handlerForStop = newValue
            state.unlock()
        }
    }

    package func write(_ samples: UnsafeBufferPointer<Int16>) -> WriteOutcome {
        guard isRunning else { return .ended }
        return ring.write(samples) ? .taken : .bufferFull
    }

    package func add(_ endpoint: Endpoint) throws {
        changes.lock()
        defer { changes.unlock() }
        guard isRunning else { throw GroupFailure.groupEnded }
        guard !memberIDs.contains(endpoint.id) else { throw GroupFailure.duplicateReceiver }

        let member = try GroupMember(id: endpoint.id, host: endpoint.host,
                                     port: endpoint.port, senderName: senderName,
                                     timing: timing)
        var committed = false
        defer { if !committed { member.close(); clock.unregister(member.connection.peerAddress) } }
        try volumeMemory?.restoreVolume(for: endpoint.id) { try member.setVolume($0) }
        if let level = member.currentVolume { volumeMemory?.remember(level, for: endpoint.id) }
        try clock.register(member.connection.peerAddress)

        state.lock()
        let peers = members + [member]
        state.unlock()
        do {
            try publishPeers(to: peers)
            Thread.sleep(forTimeInterval: 3)

            state.lock()
            defer { state.unlock() }
            guard running, let anchor = timeline?.anchor(forFrame: nextFrame) else {
                throw GroupFailure.groupEnded
            }
            try member.start(timestamp: anchor.rtpTime,
                             seconds: anchor.seconds,
                             fraction: anchor.fraction,
                             clockIdentifier: timing.clockIdentifier)
            members.append(member)
            let id = member.id
            member.events.stoppedHandler = { [weak self] reason in
                self?.memberStopped(id: id, reason: reason)
            }
            member.events.requestHandler = eventHandler.map { handler in
                { request in handler(id, request) }
            }
            committed = true
        } catch {
            recordFailure("adding \(endpoint.id): \(error)")
            state.lock()
            let remaining = members
            state.unlock()
            try? publishPeers(to: remaining)
            throw error
        }
    }

    package func remove(_ id: String) throws {
        changes.lock()
        defer { changes.unlock() }
        guard isRunning else { throw GroupFailure.groupEnded }
        state.lock()
        guard let index = members.firstIndex(where: { $0.id == id }) else {
            state.unlock()
            throw GroupFailure.receiverNotInGroup
        }
        let departing = members.remove(at: index)
        let remaining = members
        state.unlock()
        departing.events.stoppedHandler = nil
        departing.close()
        clock.unregister(departing.connection.peerAddress)
        if remaining.isEmpty {
            close()
        } else {
            do { try publishPeers(to: remaining) }
            catch {
                recordFailure("updating peers after removing \(id): \(error)")
                throw error
            }
        }
    }

    package func volume(of id: String) throws -> Float? {
        state.lock()
        let member = members.first { $0.id == id }
        state.unlock()
        guard let member else { throw GroupFailure.receiverNotInGroup }
        return member.currentVolume
    }

    package func setVolume(_ level: Float, of id: String) throws {
        guard isRunning else { throw GroupFailure.groupEnded }
        state.lock()
        let member = members.first { $0.id == id }
        state.unlock()
        guard let member else { throw GroupFailure.receiverNotInGroup }
        let clamped = min(max(level, 0), 1)
        try member.setVolume(clamped)
        sendVolumeChange(id: id, level: clamped)
    }

    package func setVolume(_ level: Float) throws {
        guard isRunning else { throw GroupFailure.groupEnded }
        state.lock()
        let current = members
        state.unlock()
        let clamped = min(max(level, 0), 1)
        for member in current {
            try member.setVolume(clamped)
            sendVolumeChange(id: member.id, level: clamped)
        }
    }

    package var averageVolume: Float? {
        state.lock()
        let current = members
        state.unlock()
        let levels = current.compactMap(\.currentVolume)
        guard !current.isEmpty, levels.count == current.count else { return nil }
        return levels.reduce(0, +) / Float(levels.count)
    }

    package func setAverageVolume(_ level: Float) throws {
        guard level.isFinite else { throw GroupFailure.volumeUnavailable }
        guard isRunning else { throw GroupFailure.groupEnded }
        state.lock()
        let current = members
        state.unlock()
        let levels = current.compactMap(\.currentVolume)
        guard levels.count == current.count,
              let planned = GroupVolumePlan.levels(for: levels, average: level) else {
            throw GroupFailure.volumeUnavailable
        }
        for (member, adjusted) in zip(current, planned) {
            try member.setVolume(adjusted)
            sendVolumeChange(id: member.id, level: adjusted)
        }
    }

    package func observeVolume(_ handler: ((String, Float) -> Void)?) {
        state.lock()
        volumeHandler = handler
        state.unlock()
    }

    package func observeMemberLoss(_ handler: ((String, String) -> Void)?) {
        state.lock()
        memberLossHandler = handler
        state.unlock()
    }

    package func observeEvents(_ handler: ((String, EventChannel.Request) -> Void)?) {
        state.lock()
        eventHandler = handler
        let current = members
        state.unlock()
        for member in current {
            let id = member.id
            member.events.requestHandler = handler.map { callback in
                { request in callback(id, request) }
            }
        }
    }

    package func close() {
        state.lock()
        guard running else { state.unlock(); return }
        running = false
        let current = members
        members = []
        let worker = pump
        let poller = volumePoller
        let stopped = handlerForStop
        let failure = lastFailure
        state.unlock()

        for member in current { member.audio.stop() }
        if let worker, Thread.current !== worker {
            let deadline = Date().addingTimeInterval(AirPlaySender.pumpExitTimeout)
            while !worker.isFinished, Date() < deadline {
                Thread.sleep(forTimeInterval: 0.002)
            }
        }
        if let poller, Thread.current !== poller {
            let deadline = Date().addingTimeInterval(AirPlaySender.pumpExitTimeout)
            while !poller.isFinished, Date() < deadline {
                Thread.sleep(forTimeInterval: 0.002)
            }
        }
        for member in current { member.close() }
        clock.close()
        ring.drain()
        stopped?(failure)
    }

    private func publishPeers(to current: [GroupMember]) throws {
        for member in current {
            let others = current.filter { $0 !== member }.map { $0.connection.peerAddress }
            try member.session.setPeers([member.connection.localAddress] + others)
        }
    }

    private func recordFailure(_ detail: String) {
        state.lock()
        lastFailure = detail
        state.unlock()
    }

    private func memberStopped(id: String, reason: String) {
        // The event reader must not do RTSP cleanup on its own queue. A member
        // can stop while another membership change is already in progress.
        let worker = Thread { [weak self] in
            guard let self else { return }
            do {
                if self.memberIDs.count == 1 {
                    self.recordFailure("event channel \(id): \(reason)")
                }
                try self.remove(id)
                self.state.lock()
                let handler = self.running ? self.memberLossHandler : nil
                self.state.unlock()
                handler?(id, reason)
            } catch GroupFailure.receiverNotInGroup {
                // An explicit removal already retired this member.
            } catch GroupFailure.groupEnded {
                // The group was dissolved while cleanup was queued.
            } catch {
                self.recordFailure("removing failed member \(id): \(error)")
                self.close()
            }
        }
        worker.name = "PlayableAirplay.groupMemberLoss"
        worker.start()
    }

    private func startPump() {
        let worker = Thread { [weak self] in self?.pumpLoop() }
        worker.name = "PlayableAirplay.groupAudio"
        pump = worker
        worker.start()
    }

    private func startVolumePoller() {
        let worker = Thread { [weak self] in self?.volumeLoop() }
        worker.name = "PlayableAirplay.groupVolume"
        volumePoller = worker
        worker.start()
    }

    private func volumeLoop() {
        while isRunning {
            state.lock()
            let current = members
            state.unlock()
            for member in current where !member.isClosed {
                if let level = try? member.refreshVolume() {
                    sendVolumeChange(id: member.id, level: level)
                }
                if let level = member.currentVolume { volumeMemory?.remember(level, for: member.id) }
            }
            Thread.sleep(forTimeInterval: 1)
        }
    }

    private func sendVolumeChange(id: String, level: Float) {
        volumeMemory?.remember(level, for: id)
        state.lock()
        let handler = volumeHandler
        state.unlock()
        handler?(id, level)
    }

    private func pumpLoop() {
        let packetSamples = ALACFrame.framesPerPacket * ALACFrame.channelCount
        var packet = [Int16](repeating: 0, count: packetSamples)
        var due = ProcessInfo.processInfo.systemUptime

        while isRunning {
            if priming, ring.held >= AirPlaySender.primeFrames * ALACFrame.channelCount {
                priming = false
            }
            var filled = false
            if !priming {
                let until = ProcessInfo.processInfo.systemUptime + ALACFrame.packetDuration * 4
                while !filled, isRunning, ProcessInfo.processInfo.systemUptime < until {
                    filled = ring.read(into: &packet)
                    if !filled { Thread.sleep(forTimeInterval: 0.001) }
                }
            }
            if !filled { for index in packet.indices { packet[index] = 0 } }

            state.lock()
            let current = members
            nextFrame &+= UInt64(ALACFrame.framesPerPacket)
            state.unlock()
            do {
                for member in current { try member.write(packet) }
            } catch {
                recordFailure("audio write: \(error)")
                close()
                return
            }

            due += ALACFrame.packetDuration
            let now = ProcessInfo.processInfo.systemUptime
            if due > now {
                Thread.sleep(forTimeInterval: due - now)
            } else if now - due > AirPlaySender.anchorLead {
                do { try reanchor() }
                catch {
                    recordFailure("group reanchor: \(error)")
                    close()
                    return
                }
                due = ProcessInfo.processInfo.systemUptime
            }
        }
    }

    private func reanchor() throws {
        changes.lock()
        defer { changes.unlock() }
        guard let reading = clock.reading() else { throw SenderFailure.receiverAnnouncedNoClock }
        state.lock()
        let frame = nextFrame
        let current = members
        state.unlock()
        let now = GroupTimeline(reading: reading, ahead: AirPlaySender.anchorLead,
                                sampleRate: ALACFrame.sampleRate)
        let mapping = GroupTimeline(baseSeconds: now.baseSeconds
                                    - Double(frame) / Double(ALACFrame.sampleRate),
                                    sampleRate: ALACFrame.sampleRate)
        guard let anchor = mapping.anchor(forFrame: frame) else {
            throw SenderFailure.receiverAnnouncedNoClock
        }
        for member in current {
            try member.session.setAnchor(rtpTime: anchor.rtpTime,
                                         seconds: anchor.seconds,
                                         fraction: anchor.fraction,
                                         timelineIdentifier: timing.clockIdentifier)
        }
        state.lock()
        timeline = mapping
        state.unlock()
    }
}
