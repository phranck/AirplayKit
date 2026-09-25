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
    /// The device family inferred from its published model and manufacturer.
    public enum Kind: String, Sendable {
        case homePod
        case homePodMini
        case appleTV
        case mac
        case speaker
        case unknown
    }

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
    /// what tells the two cases apart without a table of identifiers. That
    /// reading holds once ``isFullyDescribed`` is true, and until then an empty
    /// value means nobody has said yet.
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
    /// service alone. Empty means unknown rather than alone, and
    /// ``isFullyDescribed`` says which of the two an empty value is.
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
    /// the speaker's own. A manufacturer's own services answer that question
    /// properly, and this library does not speak any, because a feature that
    /// works on one make of speaker and nowhere else is not one of its.
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

    /// Whether the service carrying the whole description has been seen.
    ///
    /// A receiver announces itself twice, and only the AirPlay service publishes
    /// ``manufacturer`` and ``groupID``. One reported from the audio service
    /// alone therefore arrives with both empty, and this says that is what
    /// happened rather than that the receiver published nothing.
    ///
    /// The difference is the whole of it: an empty manufacturer is what says a
    /// receiver is Apple's, so a Sonos seen over the audio service alone reads
    /// as "One" whilst the same speaker a moment later reads as "Sonos One".
    /// This says which of the two answers is in hand.
    ///
    /// **It does not promise the rest is coming.** Measured on one network on
    /// 2026-09-24: five Sonos published both services, and one run of thirty
    /// callbacks carried no AirPlay sighting at all whilst the next run of the
    /// same binary carried them for every speaker. So a caller that holds a
    /// receiver back until this is true can hold it back for ever. What it is
    /// for is to show a name as provisional rather than to wait for one that
    /// may not be coming.
    public let isFullyDescribed: Bool

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
    /// It is reachable and it said no. For example, a HomePod mini answered
    /// `403 Forbidden` to fresh transient pairing under the home-members-only
    /// rule, then accepted the unchanged request when that rule was opened.
    /// This case alone does not reveal every receiver's reason for refusal.
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
    private let eventsLock = NSLock()
    private var eventObserver: ((AirPlayEvent) -> Void)?

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
                let changes = ReceiverEventDiff.changes(from: discovery.receivers, to: found)
                discovery.receivers = found
                discovery.problem = state
                discovery.onChange(found)
                discovery.eventsLock.lock()
                let observer = discovery.eventObserver
                discovery.eventsLock.unlock()
                for change in changes { observer?(change) }
            }
        }, context, &problem, &code)

        // A start that failed leaves no discovery to ask, so the reason is
        // taken from the call itself and stands from the beginning.
        if handle == nil { self.problem = Problem(problem, code: code) ?? .failed(code: code) }
    }

    deinit {
        stop()
    }

    /// Delivers typed receiver changes on the discovery's delivery queue.
    /// Installing it also reports the receivers already known as appearances.
    public func observeChanges(_ handler: @escaping (AirPlayEvent) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            self.eventsLock.lock()
            self.eventObserver = handler
            self.eventsLock.unlock()
            for receiver in self.receivers { handler(.receiverAppeared(receiver)) }
        }
    }

    /// Stops delivering typed receiver changes; complete snapshots still arrive.
    public func stopObservingChanges() {
        eventsLock.lock()
        eventObserver = nil
        eventsLock.unlock()
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
/// One session reaches one receiver. For synchronized playback to several
/// receivers, use ``AirPlayGroup``, which gives its members a shared PTP clock
/// and media timeline.
public final class AirPlaySession {
    /// A request pushed by the receiver on this session's event connection.
    public struct Event: Sendable {
        public let method: String
        public let path: String
        public let body: Data

        /// The command name when the body is a binary property list with a `type` key.
        public var commandType: String? {
            guard let value = try? PropertyListSerialization.propertyList(from: body, format: nil),
                  let dictionary = value as? [String: Any] else { return nil }
            return dictionary["type"] as? String
        }

        package init(_ request: EventChannel.Request) {
            method = request.method
            path = request.path
            body = request.body
        }
    }

    /// Audio the sender had to invent or delay when the source could not keep up.
    public struct Underruns: Equatable, Sendable {
        /// Packets filled with silence.
        public let packets: Int

        /// Duration of those packets, in seconds.
        public let duration: TimeInterval

        /// Total time spent waiting for source audio, in seconds.
        public let waited: TimeInterval

        /// Times the stream slipped beyond the promised playback anchor.
        public let fellBehind: Int

        fileprivate init(_ report: AirPlaySender.Underruns) {
            packets = report.packets
            duration = report.duration
            waited = report.waited
            fellBehind = report.fellBehind
        }
    }

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
    ///
    /// From the same place the wire format takes it. It used to come from the C
    /// macro instead, so the number a caller was told and the number that went
    /// into the stream were two declarations of one fact.
    public static let sampleRate = ALACFrame.sampleRate

    /// How many channels a frame holds, interleaved.
    public static let channelCount = ALACFrame.channelCount

    /// Whether the receiver is still taking audio.
    public var isRunning: Bool { heldSender()?.isRunning ?? false }

    /// The receiver's own volume, from 0 for silent to 1 for full, if known.
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
    /// `nil` means the receiver did not answer the read on opening. Assigning
    /// `nil` leaves its level alone. Anything outside the range is clamped.
    public var volume: Float? {
        get {
            if let held = heldSender() { return held.volume }

            state.lock()
            defer { state.unlock() }

            return lastVolume
        }
        set {
            guard let newValue, let held = heldSender() else { return }

            // Outside the lock, because setting it sends a request and waits
            // for the answer, and nothing that sends is worth blocking a write
            // behind.
            //
            // A failed request leaves the last known level in place. The
            // property setter cannot report the transport error to a caller.
            try? held.setVolume(newValue)
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
    private var lastVolume: Float?
    private let observers = NSLock()
    private var volumeObserver: (queue: DispatchQueue, handler: (Float) -> Void)?
    private var changeObserver: (queue: DispatchQueue, handler: (AirPlayEvent) -> Void)?

    /// The discovery identifier, or the host when opened by address.
    public private(set) var receiverID: String

    /**
     What the session had recorded when it was closed.

     Kept because the figures exist to explain a session after the fact, and
     after the fact is exactly when the sender that holds them has gone. Without
     it a caller that stops playback and then asks how the session went is told
     that nothing happened.
     */
    private var lastUnderruns = Underruns(.none)

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
    ///   - volumeMemory: Optional application-owned store for this receiver's level.
    /// - Throws: An ``AirPlayError`` when the receiver cannot be reached or refuses.
    public convenience init(receiver: AirPlayReceiver, senderName: String,
                            volumeMemory: AirPlayVolumeMemory? = nil) throws {
        try self.init(host: receiver.host, port: receiver.port, senderName: senderName,
                      receiverID: receiver.id, volumeMemory: volumeMemory)
    }

    /// Opens a session with a receiver named by hand, which is how a known speaker
    /// is reached without browsing for it first.
    ///
    /// - Parameters:
    ///   - host: The receiver's host name.
    ///   - port: Its port, which is 7000 on every receiver seen so far.
    ///   - senderName: What the receiver shows as the source.
    /// - Throws: An ``AirPlayError`` when the receiver cannot be reached or refuses.
    public convenience init(host: String, port: UInt16 = 7000, senderName: String) throws {
        try self.init(host: host, port: port, senderName: senderName,
                      receiverID: host, volumeMemory: nil)
    }

    /// Opens a known receiver with optional volume memory keyed by its stable ID.
    ///
    /// - Parameters:
    ///   - host: The receiver's host name.
    ///   - port: Its RTSP port.
    ///   - senderName: What the receiver shows as the source.
    ///   - receiverID: Stable ID from discovery; do not use its display name.
    ///   - volumeMemory: Optional application-owned store for this receiver's level.
    public init(host: String, port: UInt16 = 7000, senderName: String,
                receiverID: String, volumeMemory: AirPlayVolumeMemory?) throws {
        guard !host.isEmpty, port != 0 else { throw AirPlayError.invalidRequest }
        self.receiverID = receiverID

        do {
            sender = try AirPlaySender(host: host, port: port, senderName: senderName,
                                       receiverID: receiverID, volumeMemory: volumeMemory?.storage)
            sender?.volumeHandler = { [weak self] level in self?.deliverVolume(level) }
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
    /// Delivers volume changes made through this session or elsewhere on the receiver.
    func observeVolume(deliveringOn queue: DispatchQueue = .main,
                       _ handler: @escaping (Float) -> Void) {
        observers.lock()
        volumeObserver = (queue, handler)
        observers.unlock()
    }

    /// Stops delivering volume changes.
    func stopObservingVolume() {
        observers.lock()
        volumeObserver = nil
        observers.unlock()
    }

    /// Delivers typed PlayableAirplay events for this session.
    func observeChanges(deliveringOn queue: DispatchQueue = .main,
                        _ handler: @escaping (AirPlayEvent) -> Void) {
        observers.lock()
        changeObserver = (queue, handler)
        observers.unlock()
    }

    /// Stops delivering typed session changes.
    func stopObservingChanges() {
        observers.lock()
        changeObserver = nil
        observers.unlock()
    }

    /// Delivers receiver-pushed requests on a chosen queue, after answering them.
    ///
    /// The handler receives the original binary body. Its schema varies by
    /// receiver, so unknown commands remain available rather than being lost.
    /// Events sent before this handler is installed cannot be replayed.
    func observeEvents(deliveringOn queue: DispatchQueue = .main,
                       _ handler: @escaping (Event) -> Void) {
        heldSender()?.eventHandler = { request in
            let event = Event(request)
            queue.async { handler(event) }
        }
    }

    /// Stops delivering events from this session.
    func stopObservingEvents() {
        heldSender()?.eventHandler = nil
    }

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

        // Rebased rather than copied, so what reaches the buffer underneath is
        // the caller's own memory and nothing is allocated on a thread that
        // cannot afford it.
        let wholeFrames = UnsafeBufferPointer(rebasing: samples.prefix(frameCount * Self.channelCount))

        switch sender.write(wholeFrames) {
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
    /// few seconds apart say what happened in between. Closing the session does
    /// not reset it either: the last reading stands afterwards, because asking
    /// how a session went is something a caller does once it has stopped.
    ///
    /// `fellBehind` is the one to watch, and it means something worse than the
    /// other two. A hole in the audio is a hole; that one says the whole stream
    /// slipped past the moment the receiver was promised, which it answers by
    /// discarding audio that is already late. The session stays connected and
    /// keeps taking frames whilst the speaker is silent, so nothing else about
    /// it looks wrong.
    var underruns: Underruns {
        guard let held = heldSender() else {
            state.lock()
            defer { state.unlock() }

            return lastUnderruns
        }

        return Underruns(held.underruns)
    }

    /// Ends the session.
    ///
    /// Calling it twice is allowed, and releasing the session does it anyway.
    ///
    /// It does not wait for what is still in the buffer, so a caller that has
    /// just written the end of a file and closes at once cuts off whatever had
    /// not gone out yet.
    ///
    /// ``underruns`` goes on answering afterwards, with what the session had
    /// recorded when it stopped.
    func close() {
        // Read before the reference is put down, and written in the same
        // moment it is, so nothing reading this sees the session as having
        // recorded nothing.
        let held = heldSender()
        let recorded = held?.underruns
        let volume = held?.volume

        state.lock()
        if let recorded { lastUnderruns = Underruns(recorded) }
        if let volume { lastVolume = volume }
        sender = nil
        state.unlock()

        // Outside the lock, because closing waits for the sending thread.
        held?.close()

        // Again once it has stopped, because the pump can pad another packet
        // or two whilst it is being waited for, and those belong in the total.
        if let held {
            let afterStopping = held.underruns

            state.lock()
            lastUnderruns = Underruns(afterStopping)
            state.unlock()
        }
    }
}

private extension AirPlaySession {
    func deliverVolume(_ level: Float) {
        observers.lock()
        let volume = volumeObserver
        let changes = changeObserver
        observers.unlock()
        volume?.queue.async { volume?.handler(level) }
        let id = receiverID
        changes?.queue.async { changes?.handler(.volumeChanged(id: id, level: level)) }
    }
}

// MARK: - Describing a failure

extension AirPlayError: CustomStringConvertible {
    /// What this is, in English, for a log or a message to the caller.
    ///
    /// Said here rather than fetched from the C interface, which says the same
    /// thing for its own callers. Two sentences for one failure would be two
    /// sentences to keep in step, and the C one is only there because C has no
    /// other way to ask.
    public var description: String {
        switch self {
        case .unreachable: return "the receiver could not be reached"
        case .pairingRefused:
            return "the receiver refused the pairing. If this is a HomePod, "
                 + "check Home Settings > Speakers & TV in the Home app."
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
                  isFullyDescribed: receiver.isFullyDescribed,
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
