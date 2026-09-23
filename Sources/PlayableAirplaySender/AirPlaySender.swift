//
//  AirPlaySender.swift
//  One session to one receiver, taking audio from whoever has it.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

import Foundation

/// What can go wrong opening a session, beyond what each step reports for itself.
public enum SenderFailure: Error, Equatable {
    /// The receiver announced no clock, so there is no timeline to place audio on.
    case receiverAnnouncedNoClock
}

/// What became of frames handed over.
public enum WriteOutcome: Equatable {
    /// Taken, and they will be sent.
    case taken

    /// Not taken, because the sender has not caught up. A live source drops them and carries on.
    case bufferFull

    /// The session has ended and the caller should close it.
    case ended
}

/**
 A session to one receiver, on the buffered path.

 Audio arrives from whichever thread produces it and leaves on a thread of this
 session's own, and the two share nothing but a ring. Writing never waits,
 because the thread carrying live audio must not.

 The order the session is brought up in is not a matter of taste, and
 <doc:Protocol-Session> says why each step sits where it does. What is easy to
 miss is the last of them: the anchor points into the future, because it says
 when the first frame sounds and no frame can arrive before it is sent.
 */
public final class AirPlaySender {
    /// How much audio the ring holds, which is four seconds.
    static let ringFrames = ALACFrame.sampleRate * 4

    /// How long closing waits for the sending thread before going ahead regardless.
    static let pumpExitTimeout: TimeInterval = 2

    /**
     How far ahead of the clock the first frame is placed.

     Public because it is also how long a caller has to wait before closing, or
     the tail of what it wrote is never heard.
     */
    public static let anchorLead: TimeInterval = 2

    private let connection: ReceiverConnection
    private var session: Session
    private let events: EventChannel
    private let audio: BufferedAudioStream

    private let lock = NSLock()
    private let ring: SampleRing
    private var open = true
    private var pump: Thread?

    /// Whether the session is still carrying audio.
    public var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }

        return open
    }

    /**
     Opens a session and leaves it ready for audio.

     @param host The receiver.
     @param port Its RTSP port.
     @param senderName What the receiver shows as the source.
     @throws Whatever the step that failed reports.
     */
    public init(host: String, port: UInt16, senderName: String) throws {
        ring = SampleRing(capacity: Self.ringFrames * ALACFrame.channelCount)
        connection = try ReceiverConnection(host: host, port: port, senderName: senderName)
        try connection.pair()

        guard let keys = connection.keys else { throw SRPError.receiverProofDidNotMatch }

        session = Session(connection: connection)

        // Asked before the session SETUP, which a receiver rejects without it.
        _ = try session.askWhatItIs()
        let eventPort = try session.open(senderName: senderName)

        // Opened before RECORD. A receiver answers RECORD with 500 until this
        // connection exists, and then never renders anything.
        events = try EventChannel(host: host, port: eventPort, keys: keys)
        session.record()

        let stream = try session.openStream(.buffered, audioKey: keys.audio)

        // The clock is opened before the peers are named, because the receiver
        // starts announcing the moment it is told where to announce to.
        let clock = try PTPClock()
        try session.setPeers([connection.localAddress])

        // Only what comes from the receiver this session is with. Anything else
        // is another speaker's clock, or somebody pretending to be one.
        guard let reading = clock.read(from: connection.peerAddress, timeout: 12) else {
            throw SenderFailure.receiverAnnouncedNoClock
        }

        let time = PTPClock.now(from: reading, ahead: Self.anchorLead)
        try session.setAnchor(rtpTime: 0,
                              seconds: time.seconds,
                              fraction: time.fraction,
                              timelineIdentifier: Int64(bitPattern: reading.identity))

        audio = try BufferedAudioStream(host: host, port: stream.dataPort, audioKey: keys.audio)

        // Set once everything is in place, because a closure over self cannot
        // be handed out before the last stored property has a value.
        //
        // The receiver tears the session down about half a minute after RECORD
        // unless these are answered, so a channel that stops is the session
        // stopping, half a minute early and for a reason worth knowing.
        events.stoppedHandler = { [weak self] reason in
            self?.endBecauseTheEventChannelStopped(reason)
        }

        startPump()
    }

    deinit {
        close()
    }

    /**
     Hands the session the next audio to play.

     Returns at once, whatever happens. Interleaved, signed 16-bit, two channels
     at 44100 Hz, which is the only thing that goes over the wire.

     @param frames Interleaved samples, two per frame.
     @returns What became of them.
     */
    public func write(_ frames: [Int16]) -> WriteOutcome {
        guard isRunning else { return .ended }

        return ring.write(frames) ? .taken : .bufferFull
    }

    /**
     Sets the receiver's own volume.

     This moves the speaker's own control rather than scaling the samples, so it
     survives a track change and is what the listener sees on the device.

     @param volume From 0 for silent to 1 for full.
     */
    public func setVolume(_ volume: Float) throws {
        try session.setVolume(min(max(volume, 0), 1))
    }

    /**
     Ends the session and closes everything it opened.

     Waits for the sending thread to stop before closing anything. Closing a
     socket whilst another thread is inside a call on it is a use after free in
     slow motion: the descriptor number is reused by whatever opens next, and
     the write lands in somebody else's connection. So the flag goes down, the
     thread is joined, and only then do the sockets close.

     Calling it twice is allowed, and releasing the session does it anyway.
     */
    public func close() {
        lock.lock()
        guard open else { return lock.unlock() }
        open = false
        lock.unlock()

        // Not from the pump itself, which would wait for its own exit. The pump
        // clears the flag and returns when the connection fails under it.
        if let pump, !pump.isFinished, Thread.current !== pump {
            let deadline = Date().addingTimeInterval(Self.pumpExitTimeout)
            while !pump.isFinished, Date() < deadline {
                Thread.sleep(forTimeInterval: 0.002)
            }
        }
        pump = nil

        audio.close()
        events.close()
        connection.close()
        ring.clear()
    }

    /// Why the session ended, where it ended by itself rather than being closed.
    public private(set) var endedBecause: String?

    // MARK: - Private

    /// Ends the session because the channel that keeps it alive has stopped.
    private func endBecauseTheEventChannelStopped(_ reason: String) {
        lock.lock()
        let wasOpen = open
        if wasOpen { endedBecause = reason }
        lock.unlock()

        guard wasOpen else { return }

        close()
    }

    /// Takes a packet's worth out of the ring every packet's worth of time.
    private func startPump() {
        let thread = Thread { [weak self] in
            let samplesPerPacket = ALACFrame.framesPerPacket * ALACFrame.channelCount
            let packetDuration = ALACFrame.packetDuration

            // The uptime rather than the wall clock. The wall clock steps when
            // the time service corrects it and can move backwards, and the
            // receiver's own clock is read against this same monotonic
            // reference, so pacing against anything else means measuring the
            // anchor with one ruler and honouring it with another.
            var due = ProcessInfo.processInfo.systemUptime

            // Taken once and filled in place, rather than allocated per packet
            // on a thread that has a deadline.
            var packet = [Int16](repeating: 0, count: samplesPerPacket)

            while let self, self.isRunning {
                // A live source fills this ring at the same nominal rate as it
                // is drained, so the two drift against each other constantly.
                // Padding an empty ring with silence at the first miss puts a
                // hole in the audio several times a second, which is heard as
                // crackle rather than as a gap. So wait for the frames that are
                // almost certainly on their way, and pad only when they are
                // genuinely not coming.
                var filled = false
                let waitUntil = ProcessInfo.processInfo.systemUptime + packetDuration * 4
                while !filled, ProcessInfo.processInfo.systemUptime < waitUntil, self.isRunning {
                    filled = self.ring.read(into: &packet)
                    if !filled { Thread.sleep(forTimeInterval: 0.001) }
                }

                // Nothing arrived, so the source has stopped. The timeline has
                // to keep running or the receiver decides the stream has died.
                if !filled {
                    for index in packet.indices { packet[index] = 0 }
                }

                let toSend = packet

                do { try self.audio.write(toSend) }
                catch {
                    self.lock.lock()
                    self.open = false
                    self.lock.unlock()

                    return
                }

                // The deficit is kept rather than forgiven. Every block carries
                // a timestamp that advances by its own length whatever happens,
                // and the anchor turned those timestamps into a promise about
                // when each one sounds. Sending slower than the timestamps
                // advance spends the lead the anchor bought, and resetting the
                // schedule after each underrun spends it permanently, a little
                // at a time, until the receiver starts dropping audio that is
                // already late and the session plays silence whilst looking
                // healthy.
                due += packetDuration

                let now = ProcessInfo.processInfo.systemUptime
                let wait = due - now

                if wait > 0 {
                    Thread.sleep(forTimeInterval: wait)
                }
                else if now - due > Self.anchorLead {
                    // Further behind than the lead can absorb, so catching up
                    // would send a burst that arrives late anyway. Start again
                    // from here and say so by the only means this thread has.
                    due = now
                }
            }
        }

        thread.name = "PlayableAirplay.audio"
        thread.start()
        pump = thread
    }
}
