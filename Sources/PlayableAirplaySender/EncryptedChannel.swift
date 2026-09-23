//
//  EncryptedChannel.swift
//  How every byte travels once pairing is done.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

import Crypto
import Foundation

/// What can go wrong reading the other side's frames.
public enum EncryptedChannelFailure: Error, Equatable {
    /// The bytes decrypted to nothing usable, which means the wrong key, a reordered frame, or tampering.
    case frameCouldNotBeOpened
}

/**
 One direction of an encrypted connection.

 The control connection and the event channel are framed identically, and each
 direction of each keeps its own counter, so one of these is held per direction
 rather than per connection.

 A frame is a two-byte little-endian plaintext length, the ciphertext, and a
 sixteen-byte tag. Those two length bytes are also the additional authenticated
 data, so a length changed in flight fails the tag rather than being believed.

 The nonce is four zero bytes and then the counter, eight bytes little-endian.
 The counter starts at zero and rises by one per frame, and it is never reset
 whilst the key stays the same: ChaCha20-Poly1305 loses every guarantee it makes
 if a counter value is used twice under one key.
 */
public struct EncryptedChannel {
    /// The most plaintext one frame carries, which is what a longer message is split at.
    public static let maximumFrameLength = 0x400

    private let key: SymmetricKey
    private var counter: UInt64 = 0

    /**
     Holds one direction open.

     @param key The 32-byte key for this direction, which `SessionKeys` derives.
     */
    public init(key: Data) {
        self.key = SymmetricKey(data: key)
    }

    /**
     Encrypts a message, splitting it into as many frames as it needs.

     @param message The bytes to send, of any length.
     @returns The frames, ready to write to the socket in order.
     */
    public mutating func seal(_ message: Data) throws -> Data {
        var out = Data()
        var remaining = message[...]

        // An empty message is still one frame, because the other side counts
        // frames and a gap in the counter is indistinguishable from a lost one.
        repeat {
            let chunk = Data(remaining.prefix(Self.maximumFrameLength))
            let length = Self.lengthBytes(chunk.count)

            let box = try ChaChaPoly.seal(chunk,
                                          using: key,
                                          nonce: try nonce(),
                                          authenticating: length)

            out += length + box.ciphertext + box.tag
            counter += 1
            remaining = remaining.dropFirst(chunk.count)
        } while !remaining.isEmpty

        return out
    }

    /**
     Decrypts one frame from the front of whatever has arrived.

     Reads nothing beyond the frame it returns, so a caller can hand it a buffer
     that holds part of the next one.

     @param bytes Everything received and not yet consumed.
     @returns The frame's plaintext and how many bytes of the buffer it used, or
     nil where the buffer does not yet hold a whole frame. Nil is ordinary: TCP
     delivers what it likes when it likes.
     @throws `EncryptedChannelFailure.frameCouldNotBeOpened` where a complete
     frame is present and does not open.
     */
    public mutating func open(_ bytes: Data) throws -> (message: Data, consumed: Int)? {
        let header = 2
        let tag = 16
        guard bytes.count >= header else { return nil }

        let start = bytes.startIndex
        let length = Int(bytes[start]) | Int(bytes[bytes.index(after: start)]) << 8
        let total = header + length + tag
        guard bytes.count >= total else { return nil }

        let aad = Data(bytes[start..<bytes.index(start, offsetBy: header)])
        let cipherEnd = bytes.index(start, offsetBy: header + length)
        let ciphertext = Data(bytes[bytes.index(start, offsetBy: header)..<cipherEnd])
        let tagBytes = Data(bytes[cipherEnd..<bytes.index(cipherEnd, offsetBy: tag)])

        do {
            let box = try ChaChaPoly.SealedBox(nonce: try nonce(),
                                               ciphertext: ciphertext,
                                               tag: tagBytes)
            let message = try ChaChaPoly.open(box, using: key, authenticating: aad)
            counter += 1

            return (message, total)
        }
        catch {
            throw EncryptedChannelFailure.frameCouldNotBeOpened
        }
    }

    // MARK: - Private

    /// Four zero bytes, then the counter little-endian, which is twelve in total.
    private func nonce() throws -> ChaChaPoly.Nonce {
        var bytes = Data(repeating: 0, count: 4)
        withUnsafeBytes(of: counter.littleEndian) { bytes.append(contentsOf: $0) }

        return try ChaChaPoly.Nonce(data: bytes)
    }

    /// A plaintext length as the two bytes that both prefix a frame and authenticate it.
    private static func lengthBytes(_ length: Int) -> Data {
        Data([UInt8(length & 0xFF), UInt8((length >> 8) & 0xFF)])
    }
}
