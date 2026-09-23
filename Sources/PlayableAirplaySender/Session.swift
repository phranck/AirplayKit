//
//  Session.swift
//  Bringing a session up, as far as the port the audio goes to.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

import Foundation

/// What can go wrong bringing a session up, beyond what the socket or the receiver reports.
public enum SessionFailure: Error, Equatable {
    /// A reply that should have been a property list was not one.
    case replyIsNotAPropertyList

    /// A reply did not carry something the next step cannot be taken without.
    case replyIsMissing(String)
}

/**
 Which audio path a stream takes.

 The two differ in more than a number. Realtime is RTP over UDP and is what the
 present C++ sender speaks. Buffered is a stream of blocks over TCP, it is what
 Apple's own senders use, and it is the one a Sonos plays.
 */
public enum StreamKind: Int {
    case realtime = 0x60
    case buffered = 103
}

/**
 A session on an already paired connection.

 The order here is not a matter of taste. RECORD has to fall between the two
 SETUPs, and the event channel has to be open before RECORD, or the receiver
 answers 500 and will not render anything afterwards.
 */
public struct Session {
    /// ALAC at 44100 Hz, 16 bit, stereo, which is bit 18 of the format bitfield.
    public static let alacStereo44100 = 0x40000

    /// How many frames one packet or block carries, which RAOP fixes.
    public static let framesPerPacket = 352

    /// What the receiver answered the stream SETUP with.
    public struct Stream {
        /// Where the audio goes. A UDP port on the realtime path and a TCP port on the buffered one.
        public let dataPort: UInt16

        /// The UDP port for timing and retransmission, which both paths share.
        public let controlPort: UInt16

        /// How much audio the receiver will hold, which only the buffered path reports.
        public let audioBufferSize: Int?
    }

    private let connection: ReceiverConnection
    private let sessionIdentifier: String
    private let uri: String

    /// The numeric session identifier, which the URI names and which a stream is tied to.
    private let streamConnectionIdentifier: Int64

    /// The TCP port the receiver wants its event channel on.
    public private(set) var eventPort: UInt16 = 0

    /**
     Prepares a session on a paired connection.

     @param connection A connection that has already paired, so everything from
     here is encrypted.
     */
    public init(connection: ReceiverConnection) {
        self.connection = connection
        self.sessionIdentifier = UUID().uuidString.uppercased()
        self.streamConnectionIdentifier = Int64(UInt32.random(in: 1...UInt32.max))
        self.uri = "rtsp://\(connection.localAddress)/\(streamConnectionIdentifier)"
    }

    /**
     Asks the receiver what it is.

     Answered without pairing at all, and a session SETUP sent without it having
     been asked is rejected.

     @returns What the receiver says about itself.
     */
    public func askWhatItIs() throws -> [String: Any] {
        let reply = try connection.send(RTSPRequest(method: "GET", uri: "/info"))

        return try Self.propertyList(reply.body)
    }

    /**
     Opens the session, and learns the port the event channel goes on.

     @param senderName What the receiver should show as the source.
     @returns The event channel's port.
     */
    public mutating func open(senderName: String) throws -> UInt16 {
        // No timing channel is opened, and the receiver is told so rather than
        // being left to wait for one. PTP would mean becoming a clock peer,
        // which is the multi-room question and not this one.
        let body: [String: Any] = [
            "deviceID": Self.deviceIdentifier,
            "macAddress": Self.deviceIdentifier,
            "sessionUUID": sessionIdentifier,
            "timingProtocol": "None",
            "timingPort": 0,
            "isMultiSelectAirPlay": false,
            "groupContainsGroupLeader": false,
            "senderSupportsRelay": false,
            "statsCollectionEnabled": false,
            "model": "PlayableAirplay1,1",
            "name": senderName,
            "osName": "PlayableAirplay",
            "osVersion": "1.0",
            "osBuildVersion": "1",
            "sourceVersion": "550.10",
        ]

        let reply = try connection.send(RTSPRequest(method: "SETUP",
                                                    uri: uri,
                                                    headers: [("Content-Type", Self.propertyListType)],
                                                    body: try Self.encoded(body)))

        let answer = try Self.propertyList(reply.body)
        guard let port = answer["eventPort"] as? Int else {
            throw SessionFailure.replyIsMissing("eventPort")
        }

        eventPort = UInt16(port)

        return eventPort
    }

    /**
     Tells the receiver to start recording, which is the state it has to be in
     before a stream will render.

     Some receivers answer this with 500 even when everything is right, which is
     why the answer is not insisted on.
     */
    public func record() {
        // Deliberately swallowed. A refusal here is survivable and a thrown
        // error would stop a session that goes on to play perfectly well.
        _ = try? connection.send(RTSPRequest(method: "RECORD", uri: uri))
    }

    /**
     Opens one audio stream and learns where to send it.

     @param kind Which path the audio takes.
     @param audioKey The `shk` the audio is encrypted under, which is the
     session's audio key.
     @returns The ports the receiver named.
     */
    public func openStream(_ kind: StreamKind, audioKey: Data) throws -> Stream {
        var stream: [String: Any] = [
            "type": kind.rawValue,
            "ct": 2,
            "audioFormat": Self.alacStereo44100,
            "spf": Self.framesPerPacket,
            "sr": 44100,
            "shk": audioKey,
            "isMedia": true,
            "audioMode": "default",
            "latencyMin": 11025,
            "latencyMax": 88200,
            "supportsDynamicStreamID": false,
            // The numeric session identifier rather than a separate random
            // string, and a receiver refuses the whole request without it.
            "streamConnectionID": streamConnectionIdentifier,
        ]

        // Only the realtime path has the sender open a control port of its own;
        // on the buffered path the receiver names both and TCP does the rest.
        if kind == .realtime {
            stream["controlPort"] = 0
        }

        let reply = try connection.send(RTSPRequest(method: "SETUP",
                                                    uri: uri,
                                                    headers: [("Content-Type", Self.propertyListType)],
                                                    body: try Self.encoded(["streams": [stream]])))

        let answer = try Self.propertyList(reply.body)
        guard let streams = answer["streams"] as? [[String: Any]], let first = streams.first else {
            throw SessionFailure.replyIsMissing("streams")
        }
        guard let dataPort = first["dataPort"] as? Int else {
            throw SessionFailure.replyIsMissing("dataPort")
        }

        return Stream(dataPort: UInt16(dataPort),
                      controlPort: UInt16(first["controlPort"] as? Int ?? 0),
                      audioBufferSize: first["audioBufferSize"] as? Int)
    }

    /**
     Sets the receiver's own volume.

     @param volume From 0 for silent to 1 for full. Carried as decibels from -30
     to 0, with -144 meaning muted, which is the scale RAOP uses rather than a
     fraction.
     */
    public func setVolume(_ volume: Float) throws {
        let decibels = volume <= 0 ? -144.0 : Double(volume) * 30.0 - 30.0
        let body = Data(String(format: "volume: %f\r\n", decibels).utf8)

        try connection.send(RTSPRequest(method: "SET_PARAMETER",
                                        uri: uri,
                                        headers: [("Content-Type", "text/parameters")],
                                        body: body))
    }

    // MARK: - Private

    static let propertyListType = "application/x-apple-binary-plist"

    /// What the sender calls itself by address. Not a real interface, and no receiver checks.
    static let deviceIdentifier = "02:00:00:00:00:00"

    static func encoded(_ value: [String: Any]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0)
    }

    static func propertyList(_ data: Data) throws -> [String: Any] {
        guard !data.isEmpty,
              let value = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dictionary = value as? [String: Any]
        else { throw SessionFailure.replyIsNotAPropertyList }

        return dictionary
    }
}
