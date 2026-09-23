//
//  BufferedBlockTests.swift
//  The framing a receiver reads, checked byte by byte.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

import Crypto
import XCTest
@testable import PlayableAirplaySender

/**
 The block layout, built by the stream itself and read back the way a receiver
 reads it.

 This is the one place where a wrong bit produces noise rather than an error, so
 every field is taken out of the bytes at the offset a receiver reads it from,
 and the payload is opened with the construction from the other side.
 */
final class BufferedBlockTests: XCTestCase {

    private let key = SymmetricKey(data: Data((0..<32).map { UInt8($0) }))

    private func block(sequence: UInt32 = 0,
                       timestamp: UInt32 = 0,
                       nonce: UInt64 = 0,
                       samples: [Int16] = []) throws -> Data {
        try BufferedAudioStream.block(payload: ALACFrame.packed(samples, frames: ALACFrame.framesPerPacket),
                                      sequence: sequence,
                                      timestamp: timestamp,
                                      nonce: nonce,
                                      key: key)
    }

    // MARK: - The header a receiver reads

    func testTheLengthCountsItself() throws {
        let built = try block()

        XCTAssertEqual(Int(built[0]) << 8 | Int(built[1]), built.count)
    }

    func testTheMarkerBitIsSetAndTheSequenceIsTwentyThreeBits() throws {
        // The sequence is wider here than the sixteen bits an RTP header gives
        // it, and the top bit is the marker rather than part of the number.
        let word = try block(sequence: 0x7F_FFFF)[2...5].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }

        XCTAssertEqual(word >> 31, 1)
        XCTAssertEqual(word & 0x7F_FFFF, 0x7F_FFFF)
    }

    func testTheTimestampAndTheCodecSitWhereTheReceiverLooks() throws {
        let built = try block(timestamp: 0x0102_0304)

        // Offsets 4 and 8 of the block, which is 6 and 10 after the length.
        XCTAssertEqual(built[6...9].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }, 0x0102_0304)
        XCTAssertEqual(built[10...13].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }, UInt32(ALACFrame.format))
    }

    func testTheNonceIsTheLastEightBytesLittleEndian() throws {
        let trailer = try block(nonce: 0x0102_0304_0506_0708).suffix(8)

        XCTAssertEqual(Array(trailer), [0x08, 0x07, 0x06, 0x05, 0x04, 0x03, 0x02, 0x01])
    }

    // MARK: - What a receiver gets back out of it

    func testAReceiverDecryptsThePayloadWithTheTimestampAndTheCodecAsItsAdditionalData() throws {
        let samples = (0..<(ALACFrame.framesPerPacket * ALACFrame.channelCount)).map { Int16(truncatingIfNeeded: $0) }
        let built = try block(sequence: 7, timestamp: 352, nonce: 3, samples: samples)

        let opened = try Self.opened(built, using: key)

        XCTAssertEqual(opened, ALACFrame.packed(samples, frames: ALACFrame.framesPerPacket))
    }

    func testATamperedTimestampFailsTheTag() throws {
        var built = try block(timestamp: 100)

        // The timestamp is authenticated, so moving a block in time is not
        // something anything in the middle can do quietly.
        built[6] ^= 0x01

        XCTAssertThrowsError(try Self.opened(built, using: key))
    }

    /// Opens a block the way a receiver does, from the offsets alone.
    private static func opened(_ built: Data, using key: SymmetricKey) throws -> Data {
        let body = built.dropFirst(2)
        let additional = Data(body.dropFirst(4).prefix(8))
        let counter = Data(body.suffix(8))
        let sealed = Data(body.dropFirst(12).dropLast(8))

        let box = try ChaChaPoly.SealedBox(nonce: try ChaChaPoly.Nonce(data: Data(repeating: 0, count: 4) + counter),
                                           ciphertext: sealed.dropLast(16),
                                           tag: sealed.suffix(16))

        return try ChaChaPoly.open(box, using: key, authenticating: additional)
    }

    // MARK: - What the sequence does over a long stream

    func testTheSequenceWrapsWithoutTouchingTheMarkerBit() throws {
        // Twenty three bits is about eleven hours at 352 frames a packet, so a
        // long listen reaches the wrap. A sequence that ran into the marker bit
        // would clear it and the receiver would stop placing the blocks.
        for sequence in [UInt32(0), 0x7F_FFFF, 0x80_0000, 0xFF_FFFF] {
            let word = try block(sequence: sequence)[2...5].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }

            XCTAssertEqual(word >> 31, 1)
            XCTAssertEqual(word & 0x7F_FFFF, sequence & 0x7F_FFFF)
        }
    }
}
