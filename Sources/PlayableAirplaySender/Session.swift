//
//  Session.swift
//  Bringing a session up, as far as the port the audio goes to.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

import Foundation

/// What can go wrong bringing a session up, beyond what the socket or the receiver reports.
package enum SessionFailure: Error, Equatable {
    /// A reply that should have been a property list was not one.
    case replyIsNotAPropertyList

    /// A reply did not carry something the next step cannot be taken without.
    case replyIsMissing(String)
}

/**
 Which audio path a stream takes.

 The two differ in more than a number. Realtime is RTP over UDP. Buffered is a
 stream of blocks over TCP; it is what Apple's own senders use and the path this
 package currently opens.
 */
package enum StreamKind: Int {
    case realtime = 0x60
    case buffered = 103
}

/**
 A session on an already paired connection.

 The order here is not a matter of taste. RECORD has to fall between the two
 SETUPs, and the event channel has to be open before RECORD, or the receiver
 answers 500 and will not render anything afterwards.
 */
package struct Session {
    /// Values shared across a group even though each receiver has its own session.
    package struct Timing {
        let groupUUID: String
        let clockIdentifier: Int64
        let peerID: String
        let deviceIdentifier: String
        let isGroup: Bool

        package init(groupUUID: String, clockIdentifier: Int64, peerID: String,
                     deviceIdentifier: String, isGroup: Bool) {
            self.groupUUID = groupUUID
            self.clockIdentifier = clockIdentifier
            self.peerID = peerID
            self.deviceIdentifier = deviceIdentifier
            self.isGroup = isGroup
        }

        static func newGroup() -> Timing {
            let suffix = UInt32.random(in: 1...UInt32.max)
            let clockID = UInt64(0x0200_0000_0000_0000) | UInt64(suffix) << 16 | 8
            let mac = String(format: "02:00:%02X:%02X:%02X:%02X",
                             (suffix >> 24) & 0xff, (suffix >> 16) & 0xff,
                             (suffix >> 8) & 0xff, suffix & 0xff)
            let groupID = UUID().uuidString.uppercased()
            return Timing(groupUUID: groupID,
                          clockIdentifier: Int64(bitPattern: clockID),
                          peerID: groupID,
                          deviceIdentifier: mac,
                          isGroup: true)
        }
    }

    /// What the receiver answered the stream SETUP with.
    public struct Stream {
        /// Where the audio goes. A UDP port on the realtime path and a TCP port on the buffered one.
        public let dataPort: UInt16

        /// The UDP port for timing and retransmission, which both paths share.
        public let controlPort: UInt16

        /// How much audio the receiver will hold, which only the buffered path reports.
        public let audioBufferSize: Int?

        /// The receiver's identifier for stream teardown, if it supplied one.
        public let streamID: Int?
    }

    private let connection: ReceiverConnection
    private let sessionIdentifier: String
    private let timing: Timing
    private let uri: String

    /// The numeric session identifier, which the URI names and which a stream is tied to.
    private let streamConnectionIdentifier: Int64

    /// This sender's PTP clock identity, which the anchor is expressed against.
    public let clockIdentifier: Int64

    /// The TCP port the receiver wants its event channel on.
    public private(set) var eventPort: UInt16 = 0

    /**
     Prepares a session on a paired connection.

     @param connection A connection that has already paired, so everything from
     here is encrypted.
     */
    package init(connection: ReceiverConnection, timing: Timing? = nil) {
        self.connection = connection
        let sessionIdentifier = UUID().uuidString.uppercased()
        self.sessionIdentifier = sessionIdentifier
        self.streamConnectionIdentifier = Int64(UInt32.random(in: 1...UInt32.max))
        let identity = timing ?? Timing(groupUUID: sessionIdentifier,
                                        clockIdentifier: Int64.random(in: 1...Int64.max),
                                        peerID: sessionIdentifier,
                                        deviceIdentifier: Self.deviceIdentifier,
                                        isGroup: false)
        self.timing = identity
        self.clockIdentifier = identity.clockIdentifier
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
        // PTP names the timeline that later anchors refer to. A standalone
        // session can follow the receiver's clock; group members need one
        // clock identity shared across their separate sessions.
        let body = Self.setupProperties(senderName: senderName,
                                        sessionUUID: sessionIdentifier,
                                        localAddress: connection.localAddress,
                                        timing: timing)

        let reply = try connection.send(RTSPRequest(method: "SETUP",
                                                    uri: uri,
                                                    headers: [("Content-Type", Self.propertyListType)],
                                                    body: try Self.encoded(body)))

        let answer = try Self.propertyList(reply.body)
        guard let port = answer["eventPort"] as? Int, let checked = Self.port(port) else {
            throw SessionFailure.replyIsMissing("eventPort")
        }

        eventPort = checked

        return eventPort
    }

    static func setupProperties(senderName: String, sessionUUID: String,
                                localAddress: String, timing: Timing) -> [String: Any] {
        let peer: [String: Any] = [
            "Addresses": [localAddress],
            "ID": timing.peerID,
            "ClockID": timing.clockIdentifier,
            "DeviceType": 0,
            "SupportsClockPortMatchingOverride": true,
        ]

        return [
            "deviceID": timing.deviceIdentifier,
            "macAddress": timing.deviceIdentifier,
            "sessionUUID": sessionUUID,
            "groupUUID": timing.groupUUID,
            "timingProtocol": "PTP",
            "timingPeerInfo": peer,
            "timingPeerList": [peer],
            "timingPort": 0,
            "isMultiSelectAirPlay": timing.isGroup,
            "groupContainsGroupLeader": false,
            "senderSupportsRelay": timing.isGroup,
            "statsCollectionEnabled": false,
            "model": "PlayableAirplay1,1",
            "name": senderName,
            "osName": "PlayableAirplay",
            "osVersion": "1.0",
            "osBuildVersion": "1",
            "sourceVersion": "550.10",
        ]
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
            "audioFormat": ALACFrame.format,
            "spf": ALACFrame.framesPerPacket,
            "sr": ALACFrame.sampleRate,
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
        guard let dataPort = first["dataPort"] as? Int, let checked = Self.port(dataPort) else {
            throw SessionFailure.replyIsMissing("dataPort")
        }

        // Nought where it named none and nought where it named nonsense, which
        // are the same thing to a caller: there is no control port to use.
        let control = (first["controlPort"] as? Int).flatMap(Self.port) ?? 0

        return Stream(dataPort: checked,
                      controlPort: control,
                      audioBufferSize: first["audioBufferSize"] as? Int,
                      streamID: first["streamID"] as? Int)
    }

    /**
     Tells the receiver which addresses to watch for clock traffic.

     A flat array of addresses, naming every member of the clock group except
     the receiver itself, which does not need to be told where it is.

     @param addresses The peers, which with one receiver is this sender alone.
     */
    public func setPeers(_ addresses: [String]) throws {
        try connection.send(RTSPRequest(method: "SETPEERS",
                                        uri: uri,
                                        headers: [("Content-Type", "/peer-list-changed")],
                                        body: try PropertyListSerialization.data(
                                            fromPropertyList: addresses, format: .binary, options: 0)))
    }

    /**
     Ties a position in the audio to an instant on a clock.

     Without this a receiver on the buffered path holds everything it is sent
     and plays none of it, because nothing has told it when the first frame
     sounds. A stream can receive a fresh anchor after a group change or stream
     rebuild; the mapping must remain equivalent across group members.

     @param rtpTime The timestamp the stream starts at.
     @param seconds The network time that timestamp corresponds to.
     @param fraction Its fractional part, fixed point.
     @param timelineIdentifier The clock the time is expressed against.
     */
    public func setAnchor(rtpTime: UInt32,
                          seconds: Int64,
                          fraction: Int64,
                          timelineIdentifier: Int64) throws {
        let body: [String: Any] = [
            "networkTimeFlags": 0,
            "networkTimeFrac": fraction,
            "networkTimeSecs": seconds,
            "networkTimeTimelineID": timelineIdentifier,
            // The low bit decides playback: odd plays, even pauses.
            "rate": 1,
            "rtpTime": Int64(rtpTime),
        ]

        try connection.send(RTSPRequest(method: "SETRATEANCHORTIME",
                                        uri: uri,
                                        headers: [("Content-Type", Self.propertyListType)],
                                        body: try Self.encoded(body)))
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

    /// Reads the receiver's current level after session SETUP.
    public func readVolume() throws -> Float {
        let reply = try connection.send(VolumeParameter.readRequest(uri: uri))
        return try VolumeParameter.level(from: reply.body)
    }

    /// Stops playback immediately before taking a group member out.
    func pause() throws {
        try connection.send(RTSPRequest(method: "SETRATEANCHORTIME",
                                        uri: uri,
                                        headers: [("Content-Type", Self.propertyListType)],
                                        body: try Self.encoded(["rate": 0])))
    }

    /// Discards audio the receiver has buffered beyond the last transmitted block.
    func flushBuffered(untilSequence sequence: UInt32, timestamp: UInt32) throws {
        try connection.send(RTSPRequest(method: "FLUSHBUFFERED",
                                        uri: uri,
                                        headers: [("Content-Type", Self.propertyListType)],
                                        body: try Self.encoded([
                                            "flushUntilSeq": Int64(sequence),
                                            "flushUntilTS": Int64(timestamp),
                                        ])))
    }

    /// Tears down the buffered stream and then its enclosing session.
    func teardown(streamID: Int?) throws {
        if let streamID {
            try connection.send(RTSPRequest(method: "TEARDOWN",
                                            uri: uri,
                                            headers: [("Content-Type", Self.propertyListType)],
                                            body: try Self.encoded([
                                                "streams": [["streamID": streamID,
                                                             "type": StreamKind.buffered.rawValue]],
                                            ])))
        }
        try connection.send(RTSPRequest(method: "TEARDOWN",
                                        uri: uri,
                                        headers: [("Content-Type", Self.propertyListType)],
                                        body: try Self.encoded([:])))
    }

    // MARK: - Private

    /**
     A port number from a receiver's reply, or nil where it is not one.

     These arrive in a property list the other end wrote, and nothing about
     that list is this sender's to decide. `UInt16(value)` traps on anything
     outside the range, so a receiver answering 70000, or a negative number, or
     anything at all that is listening on port 7000 before this sender has
     authenticated it, ends the whole application.

     `RTSPResponse.read` guards the same class of thing for a content length,
     and this is the same guard for the same reason.

     @param value What the reply carried.
     */
    static func port(_ value: Int) -> UInt16? {
        guard value > 0, value <= Int(UInt16.max) else { return nil }

        return UInt16(value)
    }

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

/// The text parameter the receiver uses for its own volume.
enum VolumeParameter {
    static func readRequest(uri: String) -> RTSPRequest {
        RTSPRequest(method: "GET_PARAMETER",
                    uri: uri,
                    headers: [("Content-Type", "text/parameters")],
                    body: Data("volume\r\n".utf8))
    }

    static func level(from body: Data) throws -> Float {
        guard let text = String(data: body, encoding: .utf8) else {
            throw SessionFailure.replyIsMissing("volume")
        }

        let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard lines.count == 1 else { throw SessionFailure.replyIsMissing("volume") }

        let parts = lines[0].split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              parts[0].trimmingCharacters(in: .whitespaces) == "volume",
              let decibels = Float(parts[1].trimmingCharacters(in: .whitespaces)),
              decibels.isFinite, decibels >= -144, decibels <= 0
        else { throw SessionFailure.replyIsMissing("volume") }

        return max(0, (decibels + 30) / 30)
    }
}
