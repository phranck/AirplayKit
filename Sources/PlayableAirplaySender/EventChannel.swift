//
//  EventChannel.swift
//  The second connection, which is what keeps a session alive.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

import Foundation

/**
 The connection the receiver pushes requests down.

 It has to be open before RECORD, or the receiver answers 500 and never enters
 the state a stream renders in. It also has to be answered: a receiver tears the
 whole session down roughly 25 to 30 seconds after RECORD unless the sender is
 reading these and replying, and a `POST /feedback` on the control connection is
 not a substitute.

 The keys are swapped relative to the control connection, because this is a
 connection in the opposite direction. What the receiver sends is opened with
 `eventsWrite` and what this answers is sealed with `eventsRead`.

 The reply has to be minimal. Adding `Content-Length: 0` or `Audio-Latency: 0`
 to it corrupts the receiver's timeline, and the result is a session that stays
 connected and renders silence. That is the single most expensive detail in this
 protocol to get wrong, and it is why nothing is added to it here.
 */
public final class EventChannel {
    private let connection: TCPConnection
    private var read: EncryptedChannel
    private var write: EncryptedChannel
    private let queue = DispatchQueue(label: "PlayableAirplay.events")

    // Read by the queue's thread and written by whoever closes, so it is
    // guarded rather than left to chance.
    private let lock = NSLock()
    private var isOpen = true

    /**
     Told when this channel stops answering, and why.

     The whole session depends on it: a receiver tears everything down roughly
     half a minute after RECORD unless these are answered, so a channel that
     falls over silently ends the audio later, somewhere else, for no visible
     reason. Whoever set this up gets to hear about it instead.
     */
    public var stoppedHandler: ((String) -> Void)?

    private var running: Bool {
        lock.lock()
        defer { lock.unlock() }

        return isOpen
    }

    /// Records that the channel is finished and says why, once.
    private func stopped(because reason: String) {
        lock.lock()
        let wasOpen = isOpen
        isOpen = false
        lock.unlock()

        guard wasOpen else { return }

        stoppedHandler?(reason)
    }

    /**
     Opens the channel and begins answering what arrives on it.

     @param host The receiver.
     @param port The port its session SETUP reply named.
     @param keys The session's keys.
     */
    public init(host: String, port: UInt16, keys: SessionKeys) throws {
        self.connection = try TCPConnection(host: host, port: port, timeout: 30)
        self.read = EncryptedChannel(key: keys.eventsWrite)
        self.write = EncryptedChannel(key: keys.eventsRead)

        queue.setSpecific(key: Self.readingThread, value: true)
        queue.async { [weak self] in
            self?.answerWhatArrives()

            // Signalled however the loop ended, including by throwing, so a
            // caller waiting on it is never waiting on something that has
            // already gone.
            self?.finished.signal()
        }
    }

    deinit {
        close()
    }

    /**
     Stops answering and closes the connection.

     In three steps, because the reading thread is parked in `recv` with a
     timeout of half a minute and closing a descriptor does not wake it. It is
     shut down first, which brings the read back at once; then this waits for
     the thread to leave; and only then is the descriptor released. Closing
     first would leave that thread inside a call on a number the next `open` in
     the process can be handed.

     The wait is bounded, because a thread that has not left is a worse thing to
     block a caller on for ever than to leave running. Where it runs out, the
     descriptor is left open and leaks rather than being reused underneath
     somebody, which is the lesser of the two.

     Calling it twice is allowed, and releasing the channel does it anyway.
     */
    public func close() {
        lock.lock()
        let wasOpen = isOpen
        isOpen = false
        lock.unlock()

        guard wasOpen else { return }

        connection.stop()

        // Not from the reading thread itself, which would wait for its own exit.
        if DispatchQueue.getSpecific(key: Self.readingThread) == nil {
            guard finished.wait(timeout: .now() + Self.exitTimeout) == .success else { return }
        }

        connection.close()
    }

    /// How long closing waits for the reading thread before leaving it to itself.
    static let exitTimeout: TimeInterval = 2

    /// Marks the queue the reading runs on, so closing from it does not wait for itself.
    static let readingThread = DispatchSpecificKey<Bool>()

    /// Signalled once the reading thread is out of the socket for good.
    private let finished = DispatchSemaphore(value: 0)

    // MARK: - Private

    private func answerWhatArrives() {
        var buffer = Data()
        var plaintext = Data()

        while running {
            do {
                buffer += try connection.read()
            }
            catch TCPFailure.timedOut {
                // Nothing pushed for a while is ordinary, so keep waiting.
                continue
            }
            catch {
                stopped(because: "the event connection closed")
                return
            }

            // A frame that will not open never will. The counter is deliberately
            // left where it was, so the same bytes are at the head of the buffer
            // next time round and they fail again for ever, in silence. The
            // session then looks healthy and the receiver tears it down half a
            // minute later, which is the most expensive way this can go wrong.
            do {
                while let frame = try read.open(buffer) {
                    plaintext += frame.message
                    buffer = Data(buffer.dropFirst(frame.consumed))
                }
            }
            catch {
                stopped(because: "a frame on the event channel could not be opened")
                return
            }

            // A reply that did not reach the socket ends the channel, for the
            // same reason a frame that will not open does. Sealing has already
            // moved the counter, so from here this side and the receiver
            // disagree about every later frame.
            do {
                try Self.answerRequests(in: &plaintext,
                                        sealedWith: &write,
                                        sendingThrough: connection.write)
            }
            catch {
                stopped(because: "a reply on the event channel could not be written")
                return
            }
        }
    }

    /// Where a pushed request's headers end, since only the headers are read here.
    private static func requestEnd(in bytes: Data) -> Int? {
        guard let range = bytes.range(of: Data("\r\n\r\n".utf8)) else { return nil }

        return bytes.distance(from: bytes.startIndex, to: range.upperBound)
    }

    /// The `CSeq` a pushed request carried, which the answer echoes when there was one.
    private static func sequence(in head: String) -> String? {
        for line in head.components(separatedBy: "\r\n") {
            guard line.lowercased().hasPrefix("cseq:") else { continue }

            return line.dropFirst("cseq:".count).trimmingCharacters(in: .whitespaces)
        }

        return nil
    }

    /**
     Answers every whole request at the front of the buffer and leaves the rest
     of it alone.

     Kept apart from the socket so that the failure it guards against can be
     provoked without one, which is also why it is not private.

     A reply is sealed before it is written, and sealing advances the counter.
     So a write that does not happen leaves this side one frame ahead of the
     receiver, every later reply fails to open there, the keep-alive stops being
     answered, and the receiver tears the session down about half a minute later
     with nothing anywhere saying why. The counter and the socket are one thing:
     once the bytes have not gone, the channel is over, which is why this stops
     at the first failure rather than going on to the next request.

     @param plaintext What has been decrypted and not yet answered. Whatever is
     answered comes off the front of it.
     @param channel The direction replies are sealed with, whose counter each
     reply moves.
     @param send Where a sealed reply goes.
     @throws Whatever `send` throws, at the first reply that does not go.
     */
    static func answerRequests(in plaintext: inout Data,
                               sealedWith channel: inout EncryptedChannel,
                               sendingThrough send: (Data) throws -> Void) throws {
        while let request = requestEnd(in: plaintext) {
            let head = String(data: Data(plaintext.prefix(request)), encoding: .utf8) ?? ""
            plaintext = Data(plaintext.dropFirst(request))

            try send(try channel.seal(reply(echoing: sequence(in: head))))
        }
    }

    /**
     The whole of a reply to a pushed request.

     A status line, a server name, and the `CSeq` where the request carried one.
     Nothing else: `Content-Length: 0` or `Audio-Latency: 0` in here corrupts the
     receiver's timeline, and what that produces is a session that stays
     connected and renders silence.

     @param sequence The `CSeq` to echo, or nil where the request carried none.
     */
    static func reply(echoing sequence: String?) -> Data {
        var text = "RTSP/1.0 200 OK\r\nServer: AirTunes/550.10\r\n"
        if let sequence {
            text += "CSeq: \(sequence)\r\n"
        }
        text += "\r\n"

        return Data(text.utf8)
    }
}
