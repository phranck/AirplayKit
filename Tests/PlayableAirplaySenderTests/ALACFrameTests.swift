//
//  ALACFrameTests.swift
//  The bitstream a receiver decodes, read back bit by bit.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

import XCTest
@testable import PlayableAirplaySender

/**
 What the packer writes, checked by reading it the way a decoder does.

 The frame is a bitstream rather than a struct, so nothing in it sits on a byte
 boundary and nothing about it is visible in a hex dump. A wrong field here is
 heard as noise and reported by nobody.
 */
final class ALACFrameTests: XCTestCase {

    /// The element header, which is 3 + 4 + 12 + 1 + 2 + 1 bits and so ends mid-byte.
    private static let headerBits = 23

    func testTheHeaderTakesTheUncompressedEscape() {
        var reader = BitReader(ALACFrame.packed([], frames: 1))

        XCTAssertEqual(reader.read(3), 1)     // a stereo channel-pair element
        XCTAssertEqual(reader.read(4), 0)     // unused
        XCTAssertEqual(reader.read(12), 0)    // unknown
        XCTAssertEqual(reader.read(1), 0)     // no explicit frame length
        XCTAssertEqual(reader.read(2), 0)     // no wasted bytes
        XCTAssertEqual(reader.read(1), 1)     // not compressed, which is the escape
    }

    func testTheSamplesSurviveThePackingUnchanged() {
        // Uncompressed ALAC, so the samples are in there verbatim. They do not
        // start on a byte boundary, because the header is 23 bits.
        let samples: [Int16] = [0x0102, -2, 0x3040, 0x0050]
        var reader = BitReader(ALACFrame.packed(samples, frames: 2))
        _ = reader.read(Self.headerBits)

        var read: [Int16] = []
        for _ in samples { read.append(Int16(bitPattern: UInt16(reader.read(16)))) }

        XCTAssertEqual(read, samples)
        XCTAssertEqual(reader.read(3), 7)     // the end tag
    }

    func testTooFewSamplesAreFilledWithSilenceRatherThanReadPastTheEnd() {
        // A short buffer is the end of a stream, not a mistake. Indexing past
        // the array to find that out ends the process.
        var reader = BitReader(ALACFrame.packed([0x1234], frames: 2))
        _ = reader.read(Self.headerBits)

        XCTAssertEqual(reader.read(16), 0x1234)
        XCTAssertEqual(reader.read(16), 0)
        XCTAssertEqual(reader.read(16), 0)
        XCTAssertEqual(reader.read(16), 0)
    }

    func testAFullPacketIsPackedToTheExpectedLength() {
        let samples = ALACFrame.framesPerPacket * ALACFrame.channelCount
        let bits = Self.headerBits + samples * 16 + 3

        let packed = ALACFrame.packed([Int16](repeating: 0, count: samples),
                                      frames: ALACFrame.framesPerPacket)

        XCTAssertEqual(packed.count, (bits + 7) / 8)
    }

    /// Reads a bitstream most significant bit first, as ALAC is written.
    struct BitReader {
        private let bytes: [UInt8]
        private var position = 0

        init(_ data: Data) {
            bytes = Array(data)
        }

        mutating func read(_ count: Int) -> UInt32 {
            var value: UInt32 = 0
            for _ in 0..<count {
                let bit = (bytes[position / 8] >> (7 - UInt8(position % 8))) & 1
                value = value << 1 | UInt32(bit)
                position += 1
            }

            return value
        }
    }
}
