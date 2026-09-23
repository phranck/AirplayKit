//
//  PlayableAirplay.swift
//  The Swift face of the library.
//
//  The C module underneath is what Swift can import on macOS and on Linux
//  alike, and it is an implementation detail. Nothing outside this file calls a
//  pa_ function, and nothing outside it sees a C buffer or an opaque pointer.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

import CPlayableAirplay
import Dispatch
import Foundation
import PlayableAirplaySender

// MARK: - Receiver

/// One AirPlay receiver, as discovery found it on the network.
///
/// Everything here comes out of what the receiver publishes over Bonjour, which
/// is the only thing known about it before a session is opened. A receiver that
/// has gone quiet keeps its values; it simply stops appearing in the set.
public struct AirPlayReceiver: Identifiable, Hashable, Sendable {
    /// What identifies the hardware, taken from the service instance name.
    ///
    /// It stays the same across sightings, which is what lets a selection
    /// survive a receiver dropping off the network and coming back. The name can
    /// change whenever its owner renames it, so it is the wrong thing to
    /// remember a choice by.
    public let id: String

    /// What its owner called it, such as "Dining Room".
    ///
    /// This is what belongs on screen, and it is what discovery sorts by. Two
    /// receivers can carry the same name, which is another reason a selection is
    /// remembered by ``id``.
    public let name: String

    /// Where to reach it, as a host name rather than an address.
    ///
    /// An address on a home network is a lease and can differ between one
    /// sighting and the next, whilst the name keeps resolving, so this is what
    /// ``AirPlaySession`` is given.
    public let host: String

    /// The port its RTSP service listens on, which is 7000 on every receiver seen so far.
    public let port: UInt16

    /// What the receiver says it is, or an empty string where it said nothing.
    ///
    /// Apple's receivers give a model identifier, such as `AudioAccessory5,1` for
    /// a HomePod mini, `AppleTV11,1` for an Apple TV or `Mac16,11` for a Mac.
    /// That is the same code macOS files a picture of the machine under, so it is
    /// enough to draw a receiver as the thing it actually is.
    ///
    /// Everybody else gives whatever they like, and there is no register to check
    /// it against. Sonos announces product names such as `Arc`, `One` or
    /// `Bookshelf`. So this is a hint worth using where it is recognised and
    /// worth ignoring where it is not, rather than something to branch on.
    public let model: String

    /// Who built it, such as `Sonos`, or an empty string where it said nothing.
    ///
    /// The other half of a product name. With ``model`` it reads as "Sonos One"
    /// without asking the device anything, which is what `productName` does.
    ///
    /// Empty for Apple's receivers, which publish no such field, and that is
    /// what tells the two cases apart without a table of identifiers.
    ///
    /// The brand on the box is not always this. A SYMFONISK Bookshelf says
    /// `Sonos` here, because Sonos builds it, and only its own UPnP description
    /// says SYMFONISK.
    public let manufacturer: String

    /// Which group of receivers this one says it belongs to, or an empty string
    /// where it said nothing.
    ///
    /// Only the AirPlay service publishes this, and the audio service publishes
    /// nothing like it, so it is empty for a receiver found through the older
    /// service alone. Empty means unknown rather than alone.
    ///
    /// ```swift
    /// let sharing = receivers.filter {
    ///     !speaker.groupID.isEmpty && $0.groupID == speaker.groupID && $0.id != speaker.id
    /// }
    /// ```
    ///
    /// **What sharing a value means is not established, and for a Sonos it is
    /// known not to mean grouping.** Three Sonos playing together as one group,
    /// measured at that moment, each published a different value, and each was
    /// the speaker's own. Their own services answer that question properly, and
    /// `PlayableAirplayUPnP` in this package is where that lives.
    ///
    /// On the same network, eight receivers published eight different values.
    /// Apple's devices published something other than their own identifier, and
    /// a HomePod mini published two identifiers joined by `+`. What a shared
    /// value would mean for them was never seen, so treat a match as a hint
    /// worth checking rather than as a fact about what will play together.
    ///
    /// The same record carries two further grouping fields, `igl` and `gcgl`,
    /// which are not carried here because nothing measured says what a caller
    /// could do with them either.
    public let groupID: String

    /// Whether it announced the pairing key that AirPlay 2 is built on.
    ///
    /// The pairing this library performs needs that key. A receiver without one
    /// speaks the older protocol, which used an RSA challenge instead, and
    /// opening a session with it fails rather than falling back.
    public let supportsAirPlay2: Bool

    /// Whether a sender currently holds a session with it.
    ///
    /// A receiver publishes its state in the same record it publishes its name
    /// in, and changes it as the state changes, so this arrives with an ordinary
    /// Bonjour update and costs no request at all. It is what lets a list say
    /// which speakers are already in use rather than offering all of them as
    /// though every one were free.
    ///
    /// Only Apple's receivers say anything. Everybody else publishes a value
    /// that never moves, so this is false for them whatever they are doing. Read
    /// it as a receiver saying it is busy, never as one saying it is free.
    public let hasSender: Bool

    /// Whether audio is reaching it at this moment.
    ///
    /// Separate from ``hasSender``, because a sender that has stopped keeps its
    /// session. A receiver can therefore be held by somebody and silent.
    ///
    /// False for a receiver that does not report its state, exactly as above.
    public let isPlaying: Bool
}

// MARK: - Failures

/// Why a session could not be opened, or why it stopped.
///
/// These divide by what somebody can do about them. A refused pairing and an
/// unusable request are worth telling a person about; the other three are worth
/// a line in a log and a return to playing locally.
public enum AirPlayError: Error, Sendable {
    /// The receiver could not be reached at all.
    ///
    /// Usually a receiver that went to sleep or left the network between being
    /// found and being opened, which is a gap of seconds but a real one. Trying
    /// the same receiver again a moment later is reasonable.
    case unreachable

    /// The receiver answered and refused the pairing.
    ///
    /// It is reachable and it said no. A receiver already streaming from
    /// somewhere else does this, and so does one that wants a code typed into
    /// it, which this library does not ask for.
    case pairingRefused

    /// The session was set up and the receiver ended it.
    ///
    /// Something took the receiver away after it had agreed: it was switched
    /// off, or another sender took it. Whatever was playing belongs back on the
    /// machine it came from.
    case sessionEnded

    /// Something was asked for that this library cannot use, such as an empty host name.
    ///
    /// This one is a mistake in the calling code rather than anything about the
    /// network, and it is the only one that will keep happening until the code
    /// changes.
    case invalidRequest

    /// The sender failed for a reason the caller can do nothing about.
    case senderFailed
}

// MARK: - Discovery

/// Watches the network for AirPlay receivers.
///
/// Browsing starts when the instance is created and stops when it is released or
/// when ``stop()`` is called, so holding on to it is what keeps it running. An
/// instance nobody holds finds nothing, and one held for the life of the
/// application keeps a socket and a thread for that long, so the usual place to
/// hold one is whatever shows the list.
///
/// What it browses for is the service AirPlay audio receivers advertise over
/// Bonjour. That is not the same as the output devices the system knows about:
/// those hold a receiver only once the system has connected it, and connecting
/// it is what moves the whole machine's output. Browsing finds every receiver on
/// the network, connected or not, which is the point.
///
/// The layer underneath reports on a thread of its own, and this hands every
/// change to a queue the caller names, so a list on screen never updates from
/// the wrong place.
public final class AirPlayDiscovery {
    /// Why a browse is finding nothing.
    ///
    /// An empty list has several causes that look identical from outside and
    /// want opposite answers. A quiet network is not a problem; a machine that
    /// withheld local network access is one only a person can clear, and saying
    /// so is the difference between an application that looks broken and one
    /// that says what to do.
    public enum Problem: Equatable, Sendable {
        /// The responder said in as many words that this application may not look.
        ///
        /// Nothing the application does clears it. The person has to allow it in
        /// the system's privacy settings, and saying so is the whole point of
        /// telling this apart from an empty network.
        ///
        /// The number is the responder's own, kept for a log.
        case refused(code: Int32)

        /// No mDNS responder this application can reach.
        ///
        /// Two different things arrive here and the responder does not separate
        /// them. There may be none at all, which is the ordinary Linux case
        /// without `avahi-daemon` and the ordinary container case. Or there is
        /// one and this application is not allowed to reach it, which is what a
        /// sandboxed application without network access was measured getting.
        ///
        /// On macOS read it as the second, because macOS always runs one. On
        /// Linux read it as the first.
        case noResponder(code: Int32)

        /// Something else failed, and the number is what the system called it.
        ///
        /// Worth a line in a log rather than a sentence on screen, because
        /// nothing a person does is likely to change it.
        case failed(code: Int32)
    }

    /// The receivers currently visible, sorted by name.
    ///
    /// Read this on the queue changes are delivered to, which is where it is written.
    public private(set) var receivers: [AirPlayReceiver] = []

    /// Why the list is empty, or `nil` when nothing is wrong with the browse.
    ///
    /// Written on the delivery queue before each change is handed over, so a
    /// handler that arrives with an empty set can read it there and say what
    /// happened. A browse can also be refused after it started, which is what a
    /// machine withholding local network access does, so this is worth reading
    /// on every change rather than once at the beginning.
    ///
    /// ```swift
    /// let discovery = AirPlayDiscovery { [weak self] receivers in
    ///     guard receivers.isEmpty, let problem = self?.discovery?.problem else {
    ///         self?.show(receivers)
    ///         return
    ///     }
    ///
    ///     switch problem {
    ///     case .refused, .noResponder: self?.askForLocalNetworkAccess()
    ///     case .failed(let code):      self?.log("browsing failed with \(code)")
    ///     }
    /// }
    /// ```
    public private(set) var problem: Problem?

    /// Whether browsing could be started at all, which needs an mDNS responder on the machine.
    ///
    /// False means nothing will ever arrive, and ``problem`` says why.
    public var isBrowsing: Bool { handle != nil }

    private var handle: OpaquePointer?
    private let queue: DispatchQueue
    private let onChange: ([AirPlayReceiver]) -> Void

    /// Starts browsing.
    ///
    /// - Parameters:
    ///   - queue: Where changes are delivered. Defaults to the main queue, because
    ///            the usual reason to watch for receivers is to list them on screen.
    ///   - onChange: Called with the whole set each time it changes, not with what moved.
    public init(deliveringOn queue: DispatchQueue = .main,
                onChange: @escaping ([AirPlayReceiver]) -> Void) {
        self.queue = queue
        self.onChange = onChange

        // The C handler is a function pointer and captures nothing, so the
        // instance travels through the context argument. Unretained is right:
        // stop() runs before deinit returns, and the handler is not called
        // afterwards, so there is no window in which the pointer is stale.
        let context = Unmanaged.passUnretained(self).toOpaque()

        var problem = PADiscoveryProblemNone
        var code: Int32 = 0

        handle = pa_discovery_start({ context, receivers, count in
            guard let context, let receivers else { return }

            let discovery = Unmanaged<AirPlayDiscovery>.fromOpaque(context).takeUnretainedValue()
            let found = (0..<count).map { AirPlayReceiver(receivers[$0]) }

            // Read here rather than on the delivery queue, because by the time
            // that block runs the discovery may already have been stopped and
            // the handle released.
            var reported: Int32 = 0
            let problem = pa_discovery_problem(discovery.handle, &reported)

            // Built here rather than on the delivery queue, so nothing mutable
            // crosses into the block. Swift 6 refuses the capture outright.
            let state = Problem(problem, code: reported)

            discovery.queue.async {
                discovery.receivers = found
                discovery.problem = state
                discovery.onChange(found)
            }
        }, context, &problem, &code)

        // A start that failed leaves no discovery to ask, so the reason is
        // taken from the call itself and stands from the beginning.
        if handle == nil { self.problem = Problem(problem, code: code) ?? .failed(code: code) }
    }

    deinit {
        stop()
    }
}

// MARK: - Discovery, stopping

public extension AirPlayDiscovery {
    /// Stops browsing. Changes are not delivered afterwards, and calling it twice is allowed.
    func stop() {
        guard let handle else { return }

        pa_discovery_stop(handle)
        self.handle = nil
    }
}

// MARK: - Session

/// A connection to one receiver, carrying audio.
///
/// Opening one pairs with the receiver, which is several round trips and a
/// couple of seconds against a speaker that was asleep. After that the session
/// holds a buffer of a few seconds, and the sender drains it against its own
/// clock and paces packets onto the network, so writing into it never waits and
/// a refused write is usually that buffer being full.
///
/// One session reaches one receiver. Several at once would each start their own
/// timeline against their own clock, so the receivers would drift apart within a
/// minute. Holding them together needs a single timeline shared between them,
/// which the sender underneath has not done yet.
public final class AirPlaySession {
    /// What became of frames handed to ``write(_:)-([Int16])``.
    ///
    /// Two of these mean the frames were not taken, and they want opposite
    /// answers, which is why this is not a Bool.
    public enum WriteOutcome: Sendable {
        /// The frames are on their way.
        case taken

        /// The buffer is full because the sender has not caught up yet.
        ///
        /// This is back pressure rather than a failure: the sender drains in
        /// real time and the caller is ahead of it. A live source drops these
        /// frames and carries on, because a late packet is worse than a missing
        /// one. A source that can pause offers them again, which is what turns
        /// the buffer into the thing that paces the read.
        case bufferFull

        /// The receiver ended the session, and it wants closing.
        ///
        /// Further writes say the same thing, so there is nothing to be gained
        /// by carrying on.
        case ended
    }

    /// The audio a session takes. Fixed, because this is what AirPlay carries.
    public static let sampleRate = Int(PA_SAMPLE_RATE)

    /// How many channels a frame holds, interleaved.
    public static let channelCount = Int(PA_CHANNELS)

    /// Whether the receiver is still taking audio.
    public var isRunning: Bool { heldSender()?.isRunning ?? false }

    /// The receiver's own volume, from 0 for silent to 1 for full.
    ///
    /// Setting it sends a parameter to the receiver rather than scaling the
    /// samples, which is why it survives a track change, why the speaker's own
    /// display follows it, and why it costs nothing in the audio path.
    ///
    /// The protocol's range is an attenuation in decibels, so this is not a
    /// curve that sounds linear: half way up here is half way up the receiver's
    /// range, which is louder than half volume to the ear. Shape the value
    /// before setting it where a fader should sound even.
    ///
    /// Anything outside the range is brought into it, and reading it back gives
    /// what was actually sent.
    public var volume: Float {
        get {
            state.lock()
            defer { state.unlock() }

            return sentVolume
        }
        set {
            state.lock()
            sentVolume = min(max(newValue, 0), 1)
            let level = sentVolume
            let held = sender
            state.unlock()

            // Outside the lock, because setting it sends a request and waits
            // for the answer, and nothing that sends is worth blocking a write
            // behind.
            //
            // Swallowed, because a property setter has no way to report it and
            // a volume that did not arrive is not worth ending a session over.
            try? held?.setVolume(level)
        }
    }

    /**
     Everything mutable here is reached from two threads at once.

     A caller is told to write from an audio callback and to stop from wherever
     the stop button is, so the sender and the volume are read on one thread
     whilst being written on another. The lock is held only long enough to pick
     up or put down a reference, never across anything that sends.
     */
    private let state = NSLock()
    private var sender: AirPlaySender?
    private var sentVolume: Float = 1

    /// The sender, taken under the lock and used outside it.
    private func heldSender() -> AirPlaySender? {
        state.lock()
        defer { state.unlock() }

        return sender
    }

    /// Opens a session with a receiver and pairs with it.
    ///
    /// Blocks until the receiver has accepted or refused, which takes a couple of
    /// seconds on one that was asleep.
    ///
    /// - Parameters:
    ///   - receiver: Where to play, as discovery reported it.
    ///   - senderName: What the receiver shows as the source, such as "Podlive".
    /// - Throws: An ``AirPlayError`` when the receiver cannot be reached or refuses.
    public convenience init(receiver: AirPlayReceiver, senderName: String) throws {
        try self.init(host: receiver.host, port: receiver.port, senderName: senderName)
    }

    /// Opens a session with a receiver named by hand, which is how a known speaker
    /// is reached without browsing for it first.
    ///
    /// - Parameters:
    ///   - host: The receiver's host name.
    ///   - port: Its port, which is 7000 on every receiver seen so far.
    ///   - senderName: What the receiver shows as the source.
    /// - Throws: An ``AirPlayError`` when the receiver cannot be reached or refuses.
    public init(host: String, port: UInt16 = 7000, senderName: String) throws {
        guard !host.isEmpty, port != 0 else { throw AirPlayError.invalidRequest }

        do {
            sender = try AirPlaySender(host: host, port: port, senderName: senderName)
        }
        catch {
            throw AirPlayError(error)
        }
    }

    deinit {
        close()
    }
}

// MARK: - Session, playing

public extension AirPlaySession {
    /// Hands the session the next audio to play.
    ///
    /// Interleaved, signed 16 bit, two channels, 44100 Hz. The call copies what it
    /// needs and returns without waiting, because the thread producing live audio
    /// is one that must not block.
    ///
    /// - Parameter frames: Interleaved samples, ``channelCount`` of them per frame.
    /// - Returns: Whether the frames were taken, and where they were not, why.
    @discardableResult
    func write(_ frames: [Int16]) -> WriteOutcome {
        frames.withUnsafeBufferPointer { write($0) }
    }

    /// Hands the session the next audio to play, from a buffer the caller already holds.
    ///
    /// This is the one to reach for in an audio callback, where the samples arrive
    /// as a pointer and copying them into an array first would be wasted work.
    ///
    /// Samples past the last whole frame are left behind, so a buffer holding an
    /// odd number of them loses the last one.
    ///
    /// - Parameter samples: Interleaved samples, ``channelCount`` of them per frame.
    /// - Returns: Whether the frames were taken, and where they were not, why.
    @discardableResult
    func write(_ samples: UnsafeBufferPointer<Int16>) -> WriteOutcome {
        let frameCount = samples.count / Self.channelCount

        // Nothing to send is not a failure, and nothing to send it to is. A
        // closed session that answers taken tells a caller its audio is on its
        // way for ever, which is exactly what this type exists to prevent.
        guard frameCount > 0 else { return .taken }
        guard let sender = heldSender() else { return .ended }

        switch sender.write(Array(samples.prefix(frameCount * Self.channelCount))) {
        case .taken: return .taken
        case .bufferFull: return .bufferFull
        case .ended: return .ended
        }
    }

    /// Throws away the audio this session is holding and has not sent.
    ///
    /// For a caller that changes source, such as one podcast to the next. Without
    /// this the old source's tail goes on leaving at real time whilst the new one
    /// has not started, and a source trickling to a stop leaves the buffer
    /// repeatedly almost empty, so what is heard is crackle rather than an ending.
    ///
    /// Afterwards the session sends silence, which is quiet, until the new source
    /// produces. The session stays up, so nothing is paired again.
    ///
    /// What it cannot do is take back what the receiver already has. A couple of
    /// seconds of audio is already at the speaker, so the cut is heard about that
    /// much later.
    ///
    /// - Returns: How many frames were thrown away.
    @discardableResult
    func discardHeldAudio() -> Int {
        heldSender()?.discardHeldAudio() ?? 0
    }

    /// How many frames are waiting to be sent.
    ///
    /// How far ahead of the speaker the source has run, which is the latency a
    /// listener would notice on a change of source. Nought on a closed session.
    var heldFrames: Int {
        heldSender()?.heldFrames ?? 0
    }

    /// What the session has had to make up because the source did not keep up.
    ///
    /// A hole in the audio is heard as crackle rather than as a gap, so it gets
    /// blamed on the speaker or the network. Nothing else reports it: a caller
    /// whose writes are never refused concludes its audio arrived whole, and it
    /// did, just not in time.
    ///
    /// Counted from the start of the session and never reset, so two readings a
    /// few seconds apart say what happened in between.
    var underruns: AirPlaySender.Underruns {
        heldSender()?.underruns ?? .none
    }

    /// Ends the session.
    ///
    /// Calling it twice is allowed, and releasing the session does it anyway.
    ///
    /// It does not wait for what is still in the buffer, so a caller that has
    /// just written the end of a file and closes at once cuts off whatever had
    /// not gone out yet.
    func close() {
        state.lock()
        let held = sender
        sender = nil
        state.unlock()

        // Outside the lock, because closing waits for the sending thread.
        held?.close()
    }
}

// MARK: - Describing a failure

extension AirPlayError: CustomStringConvertible {
    /// What this is, in English, for a log rather than for a person.
    ///
    /// Said here rather than fetched from the C interface, which says the same
    /// thing for its own callers. Two sentences for one failure would be two
    /// sentences to keep in step, and the C one is only there because C has no
    /// other way to ask.
    public var description: String {
        switch self {
        case .unreachable: return "the receiver could not be reached"
        case .pairingRefused: return "the receiver refused the pairing"
        case .sessionEnded: return "the receiver ended the session"
        case .invalidRequest: return "the caller passed something unusable"
        case .senderFailed: return "the sender failed for a reason the caller cannot act on"
        }
    }
}

// MARK: - Crossing the C boundary

private extension AirPlayReceiver {
    init(_ receiver: PAReceiver) {
        self.init(id: Self.string(from: receiver.id, capacity: Int(PA_MAX_ID)),
                  name: Self.string(from: receiver.name, capacity: Int(PA_MAX_NAME)),
                  host: Self.string(from: receiver.host, capacity: Int(PA_MAX_HOST)),
                  port: receiver.port,
                  model: Self.string(from: receiver.model, capacity: Int(PA_MAX_MODEL)),
                  manufacturer: Self.string(from: receiver.manufacturer, capacity: Int(PA_MAX_MODEL)),
                  groupID: Self.string(from: receiver.groupID, capacity: Int(PA_MAX_GROUP)),
                  supportsAirPlay2: receiver.supportsAirPlay2,
                  hasSender: receiver.hasSender,
                  isPlaying: receiver.isPlaying)
    }

    /// The fixed C buffers arrive in Swift as tuples of CChar, and this is where they stop being that.
    static func string<Buffer>(from buffer: Buffer, capacity: Int) -> String {
        withUnsafePointer(to: buffer) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { String(cString: $0) }
        }
    }
}

private extension AirPlayDiscovery.Problem {
    /// Nothing wrong answers nil, so a caller tests for a problem rather than for a case.
    init?(_ problem: PADiscoveryProblem, code: Int32) {
        switch problem {
        case PADiscoveryProblemNone: return nil
        case PADiscoveryProblemRefused: self = .refused(code: code)
        case PADiscoveryProblemNoResponder: self = .noResponder(code: code)
        default: self = .failed(code: code)
        }
    }
}

private extension AirPlayError {
    /// Which of these a failure from the sender is, classified in one place for both faces.
    init(_ error: Error) {
        switch SenderFailureKind(error) {
        case .unreachable: self = .unreachable
        case .pairingRefused: self = .pairingRefused
        case .sessionEnded: self = .sessionEnded
        case .invalidRequest: self = .invalidRequest
        case .senderFailed: self = .senderFailed
        }
    }

}
