//
//  ReceiverConnection.swift
//  One conversation with one receiver, from the first request to the last.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

import Foundation

/**
 The control connection to a receiver.

 One TCP connection carries everything: the pairing messages in the clear, and
 from the moment pairing finishes, every byte encrypted under the keys it
 produced. The switch happens in one place, and nothing above this has to know
 which side of it a request falls on.

 A receiver that is sent a request in the clear after pairing closes the socket
 almost at once, so the switch is not something to get approximately right.
 */
public final class ReceiverConnection {
    /// What a sender calls itself to a receiver, matching what an Apple sender sends.
    public static let userAgent = "AirPlay/550.10"

    /// The pairing mode this asks for, which is transient.
    static let transientPairingMode = "4"

    private let connection: TCPConnection
    private let senderName: String
    private let identifier: String
    private let activeRemote: String

    private var sequence = 0
    private var buffer = Data()

    private var write: EncryptedChannel?
    private var read: EncryptedChannel?

    /// The keys pairing produced, or nil whilst it has not run.
    public private(set) var keys: SessionKeys?

    /// Whether everything on this connection is encrypted from here on.
    public var isEncrypted: Bool { keys != nil }

    /// The address this end of the connection sits on, which the session SETUP names.
    public var localAddress: String { connection.localAddress }

    /// The receiver's own address, which is what anything claiming to be it is checked against.
    public var peerAddress: String { connection.peerAddress }

    /**
     Opens a connection, without pairing on it yet.

     @param host The receiver's host name or address.
     @param port Its RTSP port, which discovery reports and which is 7000 in practice.
     @param senderName What the receiver should call this sender.
     @param timeout How long to wait on the socket.
     */
    public init(host: String, port: UInt16, senderName: String, timeout: TimeInterval = 12) throws {
        self.connection = try TCPConnection(host: host, port: port, timeout: timeout)
        self.senderName = senderName

        // Both are random per session, and the receiver reads them before it
        // reads the body. Their absence is a documented cause of a refusal.
        self.identifier = String(format: "%016llX", UInt64.random(in: 1...UInt64.max))
        self.activeRemote = String(UInt32.random(in: 1...UInt32.max))
    }

    deinit {
        connection.close()
    }

    /// Closes the connection.
    public func close() {
        connection.close()
    }

    /**
     Pairs, and leaves the connection encrypted.

     Transient pairing: four messages, no code to type, no long-term identity
     stored, and the SRP session key becomes the session's secret.

     @throws Whatever the exchange or the socket reports.
     */
    public func pair() throws {
        var pairing = PairSetup()

        let m2 = try send(pairingMessage: pairing.start())
        let m4 = try send(pairingMessage: try pairing.answer(toSetupStart: m2))
        let keys = try pairing.finish(with: m4)

        self.keys = keys
        self.write = EncryptedChannel(key: keys.controlWrite)
        self.read = EncryptedChannel(key: keys.controlRead)
    }

    /**
     Sends a request and waits for its answer.

     Encrypted or not according to where the connection stands, which the caller
     does not have to know.

     @param request What to send. The identity headers are added here.
     @returns The receiver's answer.
     @throws `RTSPFailure.receiverAnswered` where the status is not 200, plus
     whatever the socket reports.
     */
    @discardableResult
    public func send(_ request: RTSPRequest) throws -> RTSPResponse {
        var carried = request
        carried.headers += identityHeaders()

        sequence += 1
        try writeOut(carried.encoded(sequence: sequence))

        let answer = try readAnswer()
        guard answer.status == 200 else {
            throw RTSPFailure.receiverAnswered(status: answer.status, reason: answer.reason)
        }

        return answer
    }

    // MARK: - Private

    /// One `POST /pair-setup`, whose answer is the next message's input.
    private func send(pairingMessage body: Data) throws -> Data {
        let request = RTSPRequest(method: "POST",
                                  uri: "/pair-setup",
                                  headers: [
                                    ("Content-Type", "application/octet-stream"),
                                    ("X-Apple-HKP", Self.transientPairingMode),
                                  ],
                                  body: body)

        return try send(request).body
    }

    private func identityHeaders() -> [(name: String, value: String)] {
        [
            ("User-Agent", Self.userAgent),
            ("Connection", "keep-alive"),
            ("DACP-ID", identifier),
            ("Client-Instance", identifier),
            ("Active-Remote", activeRemote),
            ("X-Apple-Client-Name", senderName),
        ]
    }

    private func writeOut(_ bytes: Data) throws {
        guard write != nil else { return try connection.write(bytes) }

        try connection.write(try write!.seal(bytes))
    }

    /**
     Reads until a whole answer is in hand, decrypting first where the
     connection is encrypted.

     Two buffers rather than one, because a frame that has been decrypted cannot
     go back through the cipher: `buffer` holds what the socket gave and has not
     been opened yet, and `plaintext` holds what has been opened and not yet
     read as an answer. A receiver that sends two answers in one frame is
     ordinary, and without the second buffer the tail of it would be lost.
     */
    private func readAnswer() throws -> RTSPResponse {
        while true {
            if let answer = try RTSPResponse.read(from: plaintext) {
                plaintext = Data(plaintext.dropFirst(answer.consumed))

                return answer.response
            }

            if read != nil {
                var opened = false
                while let frame = try read!.open(buffer) {
                    plaintext += frame.message
                    buffer = Data(buffer.dropFirst(frame.consumed))
                    opened = true
                }
                if opened { continue }
            }
            else if !buffer.isEmpty {
                plaintext += buffer
                buffer = Data()
                continue
            }

            // Neither buffer may grow without end. What arrives is a reply to
            // something this sender asked for, and the largest of those is a
            // session SETUP answer measured in single kilobytes, so a peer that
            // keeps feeding bytes which never form an answer is not answering.
            guard buffer.count <= Self.maximumAnswerLength,
                  plaintext.count <= Self.maximumAnswerLength
            else { throw RTSPFailure.answerIsNotReadable }

            buffer += try connection.read()
        }
    }

    /**
     The most either buffer may hold whilst waiting for one answer.

     Generous against what a receiver actually sends, and finite against one
     that has stopped making sense or was never a receiver.
     */
    static let maximumAnswerLength = 1 << 20

    /// What has been decrypted and not yet read as an answer.
    private var plaintext = Data()
}
