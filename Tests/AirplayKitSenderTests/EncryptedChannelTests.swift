//
//  EncryptedChannelTests.swift
//  The framing, checked against frames another library produced.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

import Crypto
import XCTest
@testable import AirplayKitSender

final class EncryptedChannelTests: XCTestCase {

    private static let key = Data(hexString: "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")

    private static let plaintext = Data("RTSP/1.0 200 OK\r\nCSeq: 1\r\n\r\n".utf8)

    /// The same plaintext under counter 0, produced by `cryptography`'s ChaCha20Poly1305.
    private static let frameAtZero =
        Data(hexString: "1c004aec116182d788e133536c518f0c052af2f2a09090977b6de1f2f118720fdd1b068c84ac8d0adec6332ab8f5")

    /// And under counter 1, which is the same message and a different frame.
    private static let frameAtOne =
        Data(hexString: "1c00cd03a00f9a1b812809849e6c72dad28acf3eb86b3651409cce6eb85129b90be136c5b6bb78875b4b0439cf94")

    // MARK: - Against the other implementation

    func testAFrameIsTheOneAnotherLibraryProduces() throws {
        var channel = EncryptedChannel(key: Self.key)

        XCTAssertEqual(try channel.seal(Self.plaintext), Self.frameAtZero)
    }

    func testTheCounterMovesOnAfterEveryFrame() throws {
        var channel = EncryptedChannel(key: Self.key)

        _ = try channel.seal(Self.plaintext)

        // The same bytes again, and a different frame, because the counter has
        // moved. A repeat here would be the one mistake this construction
        // cannot survive.
        XCTAssertEqual(try channel.seal(Self.plaintext), Self.frameAtOne)
    }

    func testAFrameFromTheOtherImplementationOpens() throws {
        var channel = EncryptedChannel(key: Self.key)

        let opened = try channel.open(Self.frameAtZero)

        XCTAssertEqual(opened?.message, Self.plaintext)
        XCTAssertEqual(opened?.consumed, Self.frameAtZero.count)
    }

    // MARK: - Splitting

    func testAMessageLongerThanAFrameIsSplit() throws {
        var channel = EncryptedChannel(key: Self.key)
        let message = Data((0..<1029).map { UInt8($0 % 251) })

        let sealed = try channel.seal(message)

        // 1024 and then 5, each carrying two length bytes and a sixteen-byte
        // tag of its own.
        XCTAssertEqual(sealed.count, 1029 + 2 * (2 + 16))
    }

    func testASplitMessageComesBackWhole() throws {
        var sender = EncryptedChannel(key: Self.key)
        var receiver = EncryptedChannel(key: Self.key)
        let message = Data((0..<1029).map { UInt8($0 % 251) })

        var remaining = try sender.seal(message)
        var rebuilt = Data()

        while let frame = try receiver.open(remaining) {
            rebuilt += frame.message
            remaining = remaining.dropFirst(frame.consumed)
        }

        XCTAssertEqual(rebuilt, message)
        XCTAssertTrue(remaining.isEmpty)
    }

    func testAnEmptyMessageIsStillAFrame() throws {
        var sender = EncryptedChannel(key: Self.key)
        var receiver = EncryptedChannel(key: Self.key)

        // Sending nothing still has to move both counters, or every frame after
        // it fails to open.
        let sealed = try sender.seal(Data())

        XCTAssertEqual(sealed.count, 2 + 16)
        XCTAssertEqual(try receiver.open(sealed)?.message, Data())
    }

    // MARK: - A buffer that is not a whole frame yet

    func testAPartialFrameIsNotReadYet() throws {
        var channel = EncryptedChannel(key: Self.key)

        XCTAssertNil(try channel.open(Data()))
        XCTAssertNil(try channel.open(Self.frameAtZero.prefix(1)))
        XCTAssertNil(try channel.open(Self.frameAtZero.dropLast()))
    }

    func testWhatFollowsAFrameIsLeftAlone() throws {
        var channel = EncryptedChannel(key: Self.key)
        let buffer = Self.frameAtZero + Data([0xDE, 0xAD])

        let opened = try channel.open(buffer)

        XCTAssertEqual(opened?.consumed, Self.frameAtZero.count)
    }

    // MARK: - Refusing what does not open

    func testAFrameWithATamperedLengthIsRefused() throws {
        var channel = EncryptedChannel(key: Self.key)
        var tampered = Self.frameAtZero
        tampered[0] = tampered[0] - 1
        tampered = tampered.dropLast()

        // The length bytes authenticate the frame, so changing one fails the
        // tag rather than being believed.
        XCTAssertThrowsError(try channel.open(tampered)) { error in
            XCTAssertEqual(error as? EncryptedChannelFailure, .frameCouldNotBeOpened)
        }
    }

    func testAFrameClaimingToBeLongerThanOneIsRefusedRatherThanWaitedFor() {
        // The length bytes are authenticated and so cannot be changed in
        // flight, but they are whatever the other end wrote. Waiting for a
        // frame this construction never produces means holding a buffer
        // somebody else decides the size of.
        var channel = EncryptedChannel(key: Self.key)
        let oversized = Data([0x01, 0x40]) + Data(repeating: 0, count: 64)

        XCTAssertThrowsError(try channel.open(oversized)) { error in
            XCTAssertEqual(error as? EncryptedChannelFailure, .frameCouldNotBeOpened)
        }
    }

    func testAFrameOfExactlyTheLargestSizeIsStillRead() throws {
        var sender = EncryptedChannel(key: Self.key)
        var receiver = EncryptedChannel(key: Self.key)
        let full = Data(repeating: 0xAB, count: EncryptedChannel.maximumFrameLength)

        let sealed = try sender.seal(full)

        XCTAssertEqual(try receiver.open(sealed)?.message, full)
    }

    func testAFrameUnderTheWrongKeyIsRefused() {
        var other = Data(Self.key)
        other[0] ^= 0x01
        var channel = EncryptedChannel(key: other)

        XCTAssertThrowsError(try channel.open(Self.frameAtZero)) { error in
            XCTAssertEqual(error as? EncryptedChannelFailure, .frameCouldNotBeOpened)
        }
    }

    func testAFrameReadOutOfOrderIsRefused() throws {
        var channel = EncryptedChannel(key: Self.key)

        // The second frame handed over first: its counter does not match, which
        // is what keeps a replayed or reordered frame out.
        XCTAssertThrowsError(try channel.open(Self.frameAtOne)) { error in
            XCTAssertEqual(error as? EncryptedChannelFailure, .frameCouldNotBeOpened)
        }
    }
}

private extension Data {
    /// Reads a hexadecimal string, ignoring the whitespace a long one is broken across lines with.
    init(hexString: String) {
        let digits = hexString.filter { !$0.isWhitespace }
        var bytes = [UInt8]()
        bytes.reserveCapacity(digits.count / 2)

        var index = digits.startIndex
        while index < digits.endIndex {
            let next = digits.index(index, offsetBy: 2)
            bytes.append(UInt8(digits[index..<next], radix: 16)!)
            index = next
        }

        self.init(bytes)
    }
}
