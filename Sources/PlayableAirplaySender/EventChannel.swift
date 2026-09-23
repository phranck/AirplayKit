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
    private var running = true

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
        running = false
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
                return
            }

            while let frame = try? read.open(buffer) {
                plaintext += frame.message
                buffer = Data(buffer.dropFirst(frame.consumed))
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
