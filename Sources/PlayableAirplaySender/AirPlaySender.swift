//
//  AirPlaySender.swift
//  One session to one receiver, taking audio from whoever has it.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

import Foundation

/// What can go wrong opening a session, beyond what each step reports for itself.
public enum SenderFailure: Error, Equatable {
    /**
     There is no timeline to place audio on.

     Either the receiver announced no clock at all, or it announced a reading
     that will not go on one. The two are the same thing to a session, which
     has nothing to anchor its first frame against in either case.
     */
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
     How much audio is gathered before any of it is sent.

     Without this the pump starts draining the moment the first packet lands, and
     from then on it consumes at exactly the rate a live source produces, so the
     ring sits a few tens of milliseconds from empty for the whole session. That
     was measured: at a change of source there was 0.07 seconds in it. Every
     hiccup in the source therefore reaches the speaker, as a hole that is heard
     as crackle.

     Half a second is what the ring stands off from empty instead, and because
     producer and consumer run at the same rate it stays that far off for the
     rest of the session. It is bought with silence at the start, which costs
     nothing: the anchor has already placed the first frame ``anchorLead``
     seconds into the future, and this sits inside that.
     */
    static let primeFrames = ALACFrame.sampleRate / 2

    /**
     Whether a ring holding this many samples has the cushion yet.

     Apart, because the ring counts samples and the cushion is named in frames,
     and a comparison that mixes the two is out by a factor of the channel count
     in one direction or the other. Neither mistake reports itself: too small a
     cushion sounds like the fault it was meant to cure, and too large a one is
     a second of latency nobody asked for.

     @param samplesHeld What the ring says it is holding.
     */
    static func hasCushion(samplesHeld: Int) -> Bool {
        samplesHeld >= primeFrames * ALACFrame.channelCount
    }

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

    /**
     What the receiver's clock said when the session was brought up.

     Kept because a fresh anchor needs a time on that same clock, and this is
     what can still say one. The clock itself is closed once the session is up,
     so there is nothing left listening to correct it with, and a reading
     carried forward by this machine's own uptime is what remains.
     */
    private let clockReading: PTPClock.Reading

    private let lock = NSLock()
    private let ring: SampleRing
    private var open = true
    private var pump: Thread?

    /// Whether the ring is still filling to ``primeFrames`` before anything is sent.
    private var priming = true

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

        // A reading that will not go on a timeline is the same to this session
        // as no reading at all: there is nothing to place the first frame
        // against, and anchoring to a made-up time plays silence.
        guard let time = PTPClock.now(from: reading, ahead: Self.anchorLead) else {
            throw SenderFailure.receiverAnnouncedNoClock
        }

        try session.setAnchor(rtpTime: 0,
                              seconds: time.seconds,
                              fraction: time.fraction,
                              timelineIdentifier: Int64(bitPattern: reading.identity))

        clockReading = reading
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
        frames.withUnsafeBufferPointer { write($0) }
    }

    /**
     Hands the session the next audio to play, from a buffer the caller already
     holds.

     The route for an audio callback, where the samples arrive as a pointer.
     They go from there into the ring and nowhere else on the way, so nothing
     on this path allocates.

     @param samples Interleaved samples, two per frame.
     @returns What became of them.
     */
    public func write(_ samples: UnsafeBufferPointer<Int16>) -> WriteOutcome {
        guard isRunning else { return .ended }

        return ring.write(samples) ? .taken : .bufferFull
    }

    /**
     Throws away the audio this session is holding and has not sent.

     For a caller that changes source. Without it the old source's tail goes on
     leaving at real time whilst the new one has not started, and a source that
     is trickling to a stop leaves the ring repeatedly almost empty, so the pump
     alternates between the little that is there and padding silence. That is
     heard as crackle rather than as an ending.

     Afterwards the pump pads continuously, which is quiet, until the new source
     produces. The session stays up, so nothing is paired again and no anchor is
     set again.

     What this cannot do is take back what the receiver already has. The anchor
     buys a lead of ``anchorLead``, and everything inside it is at the speaker
     already, so the cut is heard about that much later.

     @returns How many frames were thrown away.
     */
    @discardableResult
    public func discardHeldAudio() -> Int {
        let held = ring.held
        ring.clear()

        // Gathered again before anything goes out, exactly as at the start. A
        // new source that is sent the instant its first packet lands leaves the
        // ring at the edge of empty for as long as it plays.
        lock.lock()
        priming = true
        lock.unlock()

        return held / ALACFrame.channelCount
    }

    /// How many frames are waiting, which is how far ahead of the speaker the source has run.
    public var heldFrames: Int { ring.held / ALACFrame.channelCount }

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

     Closing a socket whilst another thread is inside a call on it is a use
     after free in slow motion: the descriptor number is handed to whatever
     opens next, and the write the thread was part way through lands in
     somebody else's file. It is silent, and it is not a crash.

     Clearing the flag is not enough to prevent it. The pump's ordinary
     blocking point is the write itself, and a receiver whose buffer is full
     simply stops reading, so sitting in `send` for tens of seconds is the
     designed behaviour rather than a fault. The flag is only looked at between
     packets.

     So the socket is shut down first, which brings that write back at once
     with a failure, and only then is the thread waited for and the descriptor
     released.

     The wait is bounded by ``pumpExitTimeout``. Where it runs out the sockets
     are left open and leak rather than being reused underneath a thread still
     inside them, which is the lesser of the two.

     Calling it twice is allowed, and releasing the session does it anyway.
     */
    public func close() {
        lock.lock()
        guard open else { return lock.unlock() }
        open = false
        lock.unlock()

        // Before the wait rather than after it, because the wait is for a
        // thread that is in the socket and this is what gets it out.
        audio.stop()

        // Not from the pump itself, which would wait for its own exit. The pump
        // clears the flag and returns when the connection fails under it.
        var pumpLeft = true
        if let pump, !pump.isFinished, Thread.current !== pump {
            let deadline = Date().addingTimeInterval(Self.pumpExitTimeout)
            while !pump.isFinished, Date() < deadline {
                Thread.sleep(forTimeInterval: 0.002)
            }

            pumpLeft = pump.isFinished
        }
        pump = nil

        // Leaked on purpose where the pump is still in there. A descriptor
        // nobody reuses costs one entry in a table; one reused underneath a
        // live write costs somebody else's data.
        if pumpLeft { audio.close() }

        events.close()
        connection.stop()
        connection.close()
        ring.clear()
    }

    /// Why the session ended, where it ended by itself rather than being closed.
    public private(set) var endedBecause: String?

    /**
     What the sender has had to make up, because the source did not keep up.

     A hole in the audio is heard as crackle rather than as a gap, so it gets
     reported as a bad speaker or a bad connection and points nowhere near the
     sender. Nothing else says it happened: a caller that is never refused a
     write concludes its audio arrived whole, and it did, just not in time.
     */
    public struct Underruns: Equatable {
        /// Packets sent as silence because the ring had nothing in time.
        public var packets: Int

        /// Those packets as a length of audio.
        public var duration: TimeInterval { Double(packets) * ALACFrame.packetDuration }

        /// How long the pump waited for frames in total, including the waits that ended in frames.
        public var waited: TimeInterval

        /**
         How many times the sender fell further behind than the anchor's lead
         could absorb, and placed a fresh one.

         Different from the other two, and worse. A padded packet is a hole in
         the audio; this is the whole stream having slipped past the moment the
         anchor promised, which the receiver answers by discarding audio that is
         already late. Nothing else reports it: the session stays connected, the
         writes keep being taken, and what comes out of the speaker is silence.

         Any of these in a run is worth looking at. Several in a row means the
         machine is not keeping up with real time at all.
         */
        public var fellBehind: Int

        /// Nothing invented, nothing waited for and nothing slipped, which is what a closed session reports.
        public static let none = Underruns(packets: 0, waited: 0, fellBehind: 0)

        public init(packets: Int, waited: TimeInterval, fellBehind: Int = 0) {
            self.packets = packets
            self.waited = waited
            self.fellBehind = fellBehind
        }
    }

    /**
     How much silence has been invented, how long the sender has waited, and
     how often it slipped past the anchor it gave.

     Counted from the start of the session and never reset, so two readings a
     few seconds apart say what happened in between. A run with none of this is
     a run where the audio arrived in time; a run with any of it has an
     explanation for what was heard, and ``Underruns/fellBehind`` explains the
     case where nothing was heard at all.
     */
    public var underruns: Underruns {
        lock.lock()
        defer { lock.unlock() }

        return tally
    }

    private var tally = Underruns.none

    // MARK: - Private

    /**
     Whether the cushion is still building, and lets it through once it is there.

     Reading it is what ends the priming, because the pump is the only thing
     that needs to know and asking is the moment the answer matters.

     The ring is asked before the lock is taken rather than inside it, so the
     two locks are never held at once and the order they are taken in cannot
     matter.
     */
    private var isStillPriming: Bool {
        let held = ring.held

        lock.lock()
        defer { lock.unlock() }

        guard priming else { return false }

        if Self.hasCushion(samplesHeld: held) {
            priming = false

            return false
        }

        return true
    }

    /**
     Records one packet's wait, and whether it ended in silence.

     @param start When the pump began waiting, on the same monotonic clock it
     paces by.
     @param invented Whether the wait ran out and a packet of silence went in
     place of audio.
     */
    private func noteWait(from start: TimeInterval, invented silence: Bool) {
        let waited = ProcessInfo.processInfo.systemUptime - start

        lock.lock()
        tally.waited += waited
        if silence { tally.packets += 1 }
        lock.unlock()
    }

    /**
     Whether the pump has slipped further behind than the anchor's lead can
     absorb.

     Apart, and named, because the comparison is the whole of the decision and
     the two sides of it are easy to put the wrong way round. `due` is where the
     schedule says the pump should be, `now` is where it is, and being behind
     means `now` has gone past.

     @param due Where the pump's own schedule stands, on the monotonic clock it
     paces by.
     @param now That same clock, read at this moment.
     */
    static func hasFallenBehindTheAnchor(due: TimeInterval, now: TimeInterval) -> Bool {
        now - due > anchorLead
    }

    /**
     Tells the receiver when the next block it is sent will sound.

     The answer to having fallen behind. The stream's timestamps advance by a
     packet per block whatever happens, and the first anchor turned those
     timestamps into a promise about when each one sounds. Once the pump is
     later than that promise by more than the lead it was given, every block
     after it arrives after its own moment and the receiver discards it, so the
     session plays silence whilst looking healthy. Starting the schedule again
     without saying so leaves that state for the rest of the session, because
     only a fresh anchor gets out of it.

     So this places the next block ``anchorLead`` into the future and says so,
     which is exactly what brought the session up in the first place.

     The reading is the one taken then, carried forward by this machine's
     uptime, because the clock stopped listening once the session was up.

     @param nextBlock The timestamp the next block will carry.
     */
    private func placeAFreshAnchor(for nextBlock: UInt32) {
        lock.lock()
        tally.fellBehind += 1
        lock.unlock()

        guard let time = PTPClock.now(from: clockReading, ahead: Self.anchorLead) else { return }

        // Swallowed, because this runs on the pump and a refused anchor leaves
        // the session exactly where it already was. The count above is what
        // says it happened either way.
        try? session.setAnchor(rtpTime: nextBlock,
                               seconds: time.seconds,
                               fraction: time.fraction,
                               timelineIdentifier: Int64(bitPattern: clockReading.identity))
    }

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
                var filled = false
                let startedWaiting = ProcessInfo.processInfo.systemUptime
                let priming = self.isStillPriming

                if priming {
                    // Silence goes out whilst the cushion builds. The timeline
                    // runs either way, and this is inside the lead the anchor
                    // bought, so the listener waits no longer for it.
                    for index in packet.indices { packet[index] = 0 }
                }
                else {
                    // A live source fills this ring at the same nominal rate as
                    // it is drained, so the two drift against each other
                    // constantly. Padding an empty ring with silence at the
                    // first miss puts a hole in the audio several times a
                    // second, which is heard as crackle rather than as a gap. So
                    // wait for the frames that are almost certainly on their
                    // way, and pad only when they are genuinely not coming.
                    let waitUntil = startedWaiting + packetDuration * 4
                    while !filled, ProcessInfo.processInfo.systemUptime < waitUntil, self.isRunning {
                        filled = self.ring.read(into: &packet)
                        if !filled { Thread.sleep(forTimeInterval: 0.001) }
                    }
                }

                // Nothing arrived, so the source has stopped. The timeline has
                // to keep running or the receiver decides the stream has died.
                if !filled {
                    for index in packet.indices { packet[index] = 0 }
                }

                // Counted whether or not it ended in frames, because a pump that
                // keeps nearly running out is about to, and that is visible here
                // before anything is audible. Silence sent whilst the cushion
                // builds is not counted: it is the plan rather than a shortfall.
                if !priming {
                    self.noteWait(from: startedWaiting, invented: !filled)
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
                else if Self.hasFallenBehindTheAnchor(due: due, now: now) {
                    // Further behind than the lead can absorb, so catching up
                    // would send a burst that arrives late anyway. The schedule
                    // starts again from here, and the receiver is told when the
                    // next block sounds, because nothing else gets the session
                    // out of playing silence.
                    self.placeAFreshAnchor(for: self.audio.nextTimestamp)

                    // Read again rather than reusing the value above, because
                    // placing an anchor sends a request and waits for its
                    // answer. A schedule starting from before that wait is
                    // already behind by the length of it, and would ask for
                    // another anchor on the very next packet.
                    due = ProcessInfo.processInfo.systemUptime
                }
            }
        }

        thread.name = "PlayableAirplay.audio"
        thread.start()
        pump = thread
    }
}
