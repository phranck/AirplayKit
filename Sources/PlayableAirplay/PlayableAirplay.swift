//
//  PlayableAirplay.swift
//  The Swift face of the library.
//
//  The C module underneath is what Swift can import on macOS and on Linux
//  alike, and it is an implementation detail. Nothing outside this file calls a
//  pa_ function, and nothing outside it sees a C buffer or an opaque pointer.
//
//  Copyright © 2026 cocoa:naut. All rights reserved.
//

import CPlayableAirplay
import Dispatch
import Foundation

// MARK: - Receiver

/// One AirPlay receiver, as discovery found it on the network.
public struct AirPlayReceiver: Identifiable, Hashable, Sendable {
    /// Stable across sightings, taken from the service instance name.
    public let id: String

    /// What a person calls it, such as "Room B".
    public let name: String

    /// Where to reach it, as a host name rather than an address, since addresses move.
    public let host: String

    /// The port its RTSP service listens on.
    public let port: UInt16

    /// Whether it announced the AirPlay 2 pairing key. A receiver without one needs the older path.
    public let supportsAirPlay2: Bool
}

// MARK: - Failures

/// Why a session could not be opened, or why it stopped.
public enum AirPlayError: Error, Sendable {
    /// The receiver could not be reached at all.
    case unreachable

    /// The receiver answered and refused the pairing.
    case pairingRefused

    /// The session was set up and the receiver ended it.
    case sessionEnded

    /// Something was asked for that this library cannot use, such as an empty host name.
    case invalidRequest

    /// The sender failed for a reason the caller can do nothing about.
    case senderFailed
}

// MARK: - Discovery

/// Watches the network for AirPlay receivers.
///
/// Browsing starts when the instance is created and stops when it is released or
/// when ``stop()`` is called, so holding on to it is what keeps it running.
///
/// The C layer reports on a thread of its own, and this hands every change to a
/// queue the caller names, so a list on screen never updates from the wrong place.
public final class AirPlayDiscovery {
    /// The receivers currently visible, sorted by name.
    ///
    /// Read this on the queue changes are delivered to, which is where it is written.
    public private(set) var receivers: [AirPlayReceiver] = []

    /// Whether browsing could be started at all, which needs an mDNS responder on the machine.
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

        handle = pa_discovery_start({ context, receivers, count in
            guard let context, let receivers else { return }

            let discovery = Unmanaged<AirPlayDiscovery>.fromOpaque(context).takeUnretainedValue()
            let found = (0..<count).map { AirPlayReceiver(receivers[$0]) }

            discovery.queue.async {
                discovery.receivers = found
                discovery.onChange(found)
            }
        }, context)
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
/// One session reaches one receiver. Several at once would each start their own
/// timeline against their own clock, so the receivers would drift apart.
public final class AirPlaySession {
    /// What became of frames handed to ``write(_:)-([Int16])``.
    public enum WriteOutcome: Sendable {
        /// The frames are on their way.
        case taken

        /// The buffer is full because the sender has not caught up yet. A live
        /// source drops these frames and carries on; one that can pause offers
        /// them again.
        case bufferFull

        /// The receiver ended the session, and it wants closing.
        case ended
    }

    /// The audio a session takes. Fixed, because this is what AirPlay carries.
    public static let sampleRate = Int(PA_SAMPLE_RATE)

    /// How many channels a frame holds, interleaved.
    public static let channelCount = Int(PA_CHANNELS)

    /// Whether the receiver is still taking audio.
    public var isRunning: Bool { pa_session_is_running(handle) }

    /// The receiver's own volume, from 0 for silent to 1 for full.
    ///
    /// This moves the receiver's control rather than scaling the samples, so it
    /// survives a track change. Anything outside the range is brought into it,
    /// and reading it back gives what was actually sent.
    public var volume: Float {
        get { sentVolume }
        set {
            sentVolume = min(max(newValue, 0), 1)
            pa_session_set_volume(handle, sentVolume)
        }
    }

    private var handle: OpaquePointer?
    private var sentVolume: Float = 1

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
        var result = PAResultOK
        guard let opened = pa_session_open(host, port, senderName, &result) else {
            throw AirPlayError(result)
        }

        handle = opened
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
        guard let base = samples.baseAddress, frameCount > 0 else { return .taken }

        if pa_session_write(handle, base, frameCount) { return .taken }

        return isRunning ? .bufferFull : .ended
    }

    /// Ends the session. Calling it twice is allowed, and releasing the session does it anyway.
    func close() {
        guard let handle else { return }

        pa_session_close(handle)
        self.handle = nil
    }
}

// MARK: - Describing a failure

extension AirPlayError: CustomStringConvertible {
    /// The sentence the layer underneath gives for this, in English, for a log rather than a person.
    public var description: String { String(cString: pa_result_description(result)) }
}

// MARK: - Crossing the C boundary

private extension AirPlayReceiver {
    init(_ receiver: PAReceiver) {
        self.init(id: Self.string(from: receiver.id, capacity: Int(PA_MAX_ID)),
                  name: Self.string(from: receiver.name, capacity: Int(PA_MAX_NAME)),
                  host: Self.string(from: receiver.host, capacity: Int(PA_MAX_HOST)),
                  port: receiver.port,
                  supportsAirPlay2: receiver.supportsAirPlay2)
    }

    /// The fixed C buffers arrive in Swift as tuples of CChar, and this is where they stop being that.
    static func string<Buffer>(from buffer: Buffer, capacity: Int) -> String {
        withUnsafePointer(to: buffer) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { String(cString: $0) }
        }
    }
}

private extension AirPlayError {
    init(_ result: PAResult) {
        switch result {
        case PAResultUnreachable:     self = .unreachable
        case PAResultPairingRefused:  self = .pairingRefused
        case PAResultSessionEnded:    self = .sessionEnded
        case PAResultInvalidArgument: self = .invalidRequest
        default:                      self = .senderFailed
        }
    }

    var result: PAResult {
        switch self {
        case .unreachable:    return PAResultUnreachable
        case .pairingRefused: return PAResultPairingRefused
        case .sessionEnded:   return PAResultSessionEnded
        case .invalidRequest: return PAResultInvalidArgument
        case .senderFailed:   return PAResultInternal
        }
    }
}
