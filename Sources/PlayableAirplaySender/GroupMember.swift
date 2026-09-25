//
//  GroupMember.swift
//  One receiver's control, event, and audio connections within a group.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

import Foundation

final class GroupMember {
    let id: String
    let connection: ReceiverConnection
    var session: Session
    let events: EventChannel
    let audio: BufferedAudioStream
    let streamID: Int?

    private let writing = NSLock()
    private let state = NSLock()
    private let volumeAccess = NSLock()
    private var closed = false
    private var volume: Float?

    init(id: String, host: String, port: UInt16, senderName: String,
         timing: Session.Timing) throws {
        self.id = id
        let connection = try ReceiverConnection(host: host, port: port,
                                                senderName: senderName)
        self.connection = connection
        try connection.pair()
        guard let keys = connection.keys else { throw SRPError.receiverProofDidNotMatch }

        var session = Session(connection: connection, timing: timing)
        _ = try session.askWhatItIs()
        let eventPort = try session.open(senderName: senderName)
        volume = try? session.readVolume()
        let events = try EventChannel(host: host, port: eventPort, keys: keys)
        self.events = events
        session.record()
        let stream = try session.openStream(.buffered, audioKey: keys.audio)
        streamID = stream.streamID
        audio = try BufferedAudioStream(host: host, port: stream.dataPort,
                                        audioKey: keys.audio)
        self.session = session
    }

    func start(timestamp: UInt32, seconds: Int64, fraction: Int64,
               clockIdentifier: Int64) throws {
        audio.start(at: timestamp)
        try session.setAnchor(rtpTime: timestamp, seconds: seconds,
                              fraction: fraction, timelineIdentifier: clockIdentifier)
    }

    func write(_ samples: [Int16]) throws {
        writing.lock()
        defer { writing.unlock() }
        guard !isClosed else { return }
        do { try audio.write(samples) }
        catch {
            // Closing deliberately stops the socket to release an in-flight
            // write. That cancellation is not a failure of the other members.
            if isClosed { return }
            throw error
        }
    }

    func setVolume(_ level: Float) throws {
        volumeAccess.lock()
        defer { volumeAccess.unlock() }
        try session.setVolume(level)
        state.lock()
        volume = level
        state.unlock()
    }

    /// Reads the receiver again and returns only a changed level.
    func refreshVolume() throws -> Float? {
        volumeAccess.lock()
        defer { volumeAccess.unlock() }
        let level = try session.readVolume()
        state.lock()
        let prior = volume
        volume = level
        state.unlock()
        guard prior == nil || abs(prior! - level) > 0.001 else { return nil }
        return level
    }

    var currentVolume: Float? {
        state.lock()
        defer { state.unlock() }
        return volume
    }

    var isClosed: Bool {
        state.lock()
        defer { state.unlock() }
        return closed
    }

    func close() {
        state.lock()
        guard !closed else { state.unlock(); return }
        closed = true
        state.unlock()

        audio.stop()
        writing.lock()
        let sequence = audio.nextSequence
        let timestamp = audio.nextTimestamp
        audio.close()
        writing.unlock()
        try? session.pause()
        try? session.flushBuffered(untilSequence: sequence, timestamp: timestamp)
        try? session.teardown(streamID: streamID)
        events.close()
        connection.stop()
        connection.close()
    }
}
