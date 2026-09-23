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

        queue.async { [weak self] in self?.answerWhatArrives() }
    }

    deinit {
        close()
    }

    /// Stops answering and closes the connection.
    public func close() {
        lock.lock()
        isOpen = false
        lock.unlock()

        connection.close()
    }

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

            while let request = Self.requestEnd(in: plaintext) {
                let head = String(data: Data(plaintext.prefix(request)), encoding: .utf8) ?? ""
                plaintext = Data(plaintext.dropFirst(request))

                try? answer(echoing: Self.sequence(in: head))
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

    private func answer(echoing sequence: String?) throws {
        var text = "RTSP/1.0 200 OK\r\nServer: AirTunes/550.10\r\n"
        if let sequence {
            text += "CSeq: \(sequence)\r\n"
        }
        text += "\r\n"

        try connection.write(try write.seal(Data(text.utf8)))
    }
}
