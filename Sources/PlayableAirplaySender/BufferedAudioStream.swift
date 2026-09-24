//
//  BufferedAudioStream.swift
//  The audio path Apple's own senders take.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

import Crypto
import Foundation

/**
 Audio over TCP, as a stream of length-prefixed blocks.

 This is stream type 103, which is what an iPhone uses and what a Sonos plays.
 The realtime path exists beside it and is what the older sender here speaks,
 and a receiver that accepts realtime may still render nothing from it.

 ```text
 2 bytes   big-endian length, counting itself
 4 bytes   big-endian: the marker bit, then a 23-bit sequence number
 4 bytes   big-endian timestamp
 4 bytes   big-endian synchronisation source, which names this block's codec
 n bytes   ciphertext
 16 bytes  Poly1305 tag
 8 bytes   the nonce counter, little-endian
 ```

 Flow control falls out of TCP. The receiver reports how much it will hold, and
 beyond that it simply stops draining the connection, so there is no message to
 send and nothing to wait for.
 */
public final class BufferedAudioStream {
    private let connection: TCPConnection
    private let key: SymmetricKey

    private var sequence: UInt32 = 0
    private var timestamp: UInt32
    private var nonce: UInt64 = 0

    /**
     Opens the connection the audio goes down.

     @param host The receiver.
     @param port The data port its stream SETUP reply named.
     @param audioKey The session's audio key, which the SETUP also carried as `shk`.
     @param startTimestamp Where this stream's timeline begins.
     */
    public init(host: String, port: UInt16, audioKey: Data, startTimestamp: UInt32 = 0) throws {
        self.connection = try TCPConnection(host: host, port: port, timeout: 30)
        self.key = SymmetricKey(data: audioKey)
        self.timestamp = startTimestamp
    }

    deinit {
        close()
    }

    /**
     Wakes whoever is writing, without releasing the connection.

     A receiver whose buffer is full stops reading and the write waits in the
     socket, which is the designed behaviour rather than a fault, so a sender
     that wants to stop has to bring that write back before it can wait for the
     thread that is in it.
     */
    public func stop() {
        connection.stop()
    }

    /// Closes the connection, once nothing is inside a call on it.
    public func close() {
        connection.close()
    }

    /**
     Where the next block will sit on the stream's timeline.

     What a fresh anchor names, because an anchor ties a position in the audio
     to an instant on a clock and this is the position the next block will
     carry.

     Read on the thread that writes, which is the one that moves it, so there is
     nothing here to synchronise.
     */
    public var nextTimestamp: UInt32 { timestamp }

    /**
     Sends one packet's worth of samples.

     @param samples Interleaved 16-bit stereo, `ALACFrame.framesPerPacket * 2` of them.
     @throws Whatever the socket reports. A receiver whose buffer is full does
     not refuse: it stops reading, and this waits in the socket until it starts
     again.
     */
    public func write(_ samples: [Int16]) throws {
        let payload = ALACFrame.packed(samples, frames: ALACFrame.framesPerPacket)

        try connection.write(try Self.block(payload: payload,
                                            sequence: sequence,
                                            timestamp: timestamp,
                                            nonce: nonce,
                                            key: key))

        sequence = (sequence + 1) & 0x7F_FFFF
        timestamp = timestamp &+ UInt32(ALACFrame.framesPerPacket)
        nonce += 1
    }

    /**
     Builds one block, which is the whole of what goes over the wire.

     Apart from the connection, so the layout can be read back and checked
     without a receiver on the other end. Every field in here is one a receiver
     reads at a fixed offset, and getting one wrong produces noise rather than a
     refusal, which is the kind of mistake nothing reports.

     @param payload The packed frame.
     @param sequence This block's number, which wraps at 23 bits.
     @param timestamp Where this block sits on the stream's timeline.
     @param nonce The counter, which rises by one per block and never repeats
     under one key.
     @param key The session's audio key.
     @returns The block, length prefix and all.
     */
    static func block(payload: Data,
                      sequence: UInt32,
                      timestamp: UInt32,
                      nonce: UInt64,
                      key: SymmetricKey) throws -> Data {
        // The marker bit is set on every block, and the sequence number is 23
        // bits wide here rather than the 16 an RTP header gives it.
        var header = Data()
        header.append(bigEndian: 0x8000_0000 | (sequence & 0x7F_FFFF))
        header.append(bigEndian: timestamp)
        header.append(bigEndian: UInt32(ALACFrame.format))

        // The timestamp and the source, which are the eight bytes at offset 4.
        let additional = Data(header.suffix(8))
        let box = try ChaChaPoly.seal(payload,
                                      using: key,
                                      nonce: try counterNonce(nonce),
                                      authenticating: additional)

        var counter = Data()
        withUnsafeBytes(of: nonce.littleEndian) { counter.append(contentsOf: $0) }

        let block = header + box.ciphertext + box.tag + counter
        var framed = Data()
        framed.append(bigEndian: UInt16(block.count + 2))

        return framed + block
    }

    // MARK: - Private

    /// Four zero bytes and then the counter, little-endian, as every AirPlay nonce is.
    private static func counterNonce(_ counter: UInt64) throws -> ChaChaPoly.Nonce {
        var bytes = Data(repeating: 0, count: 4)
        withUnsafeBytes(of: counter.littleEndian) { bytes.append(contentsOf: $0) }

        return try ChaChaPoly.Nonce(data: bytes)
    }
}

extension Data {
    /// Appends a number most significant byte first, which everything in this family is.
    mutating func append(bigEndian value: UInt32) {
        append(UInt8((value >> 24) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8(value & 0xFF))
    }

    /// The same for a sixteen-bit one.
    mutating func append(bigEndian value: UInt16) {
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8(value & 0xFF))
    }
}
