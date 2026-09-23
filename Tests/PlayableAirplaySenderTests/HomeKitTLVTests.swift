//
//  HomeKitTLVTests.swift
//  What the pairing encoding has to get right to carry a 384-byte key.
//
//  Copyright © 2026 cocoa:naut. All rights reserved.
//

import XCTest
@testable import PlayableAirplaySender

final class HomeKitTLVTests: XCTestCase {

    // MARK: - One item at a time

    func testAnItemIsATypeALengthAndItsBytes() {
        let encoded = HomeKitTLV.encode([HomeKitTLVItem(.state, Data([0x01]))])

        XCTAssertEqual(encoded, Data([0x06, 0x01, 0x01]))
    }

    func testAnItemWithNoValueIsStillWritten() {
        // Some messages are a bare flag, so an empty value has to survive the
        // round trip rather than disappearing.
        let encoded = HomeKitTLV.encode([HomeKitTLVItem(.flags, Data())])

        XCTAssertEqual(encoded, Data([0x13, 0x00]))
        XCTAssertEqual(HomeKitTLV.decode(encoded), [HomeKitTLVItem(.flags, Data())])
    }

    // MARK: - The split, which is the whole reason this is not trivial

    func testAValueLongerThanOneLengthByteIsSplit() {
        let value = Data(repeating: 0xAB, count: 384)

        let encoded = HomeKitTLV.encode([HomeKitTLVItem(.publicKey, value)])

        // 255 bytes, then the remaining 129, each with its own type and length.
        XCTAssertEqual(encoded.count, 2 + 255 + 2 + 129)
        XCTAssertEqual(encoded[0], HomeKitTLVType.publicKey.rawValue)
        XCTAssertEqual(encoded[1], 255)
        XCTAssertEqual(encoded[257], HomeKitTLVType.publicKey.rawValue)
        XCTAssertEqual(encoded[258], 129)
    }

    func testASplitValueComesBackWhole() {
        // An SRP public key over the 3072-bit group is exactly this long, so
        // this is the ordinary case rather than a corner of it.
        let value = Data((0..<384).map { UInt8($0 % 251) })

        let encoded = HomeKitTLV.encode([HomeKitTLVItem(.publicKey, value)])
        let decoded = HomeKitTLV.decode(encoded)

        XCTAssertEqual(decoded?.count, 1)
        XCTAssertEqual(decoded?.value(for: .publicKey), value)
    }

    func testAValueOfExactlyTheLimitIsNotJoinedWithWhatFollowsIt() {
        // A value of exactly 255 bytes looks like the first half of a split one.
        // What tells them apart is that a real split is followed by more of the
        // same type, and this is followed by a different type.
        let first = Data(repeating: 0x01, count: 255)
        let second = Data(repeating: 0x02, count: 4)

        let encoded = HomeKitTLV.encode([
            HomeKitTLVItem(.publicKey, first),
            HomeKitTLVItem(.proof, second),
        ])
        let decoded = HomeKitTLV.decode(encoded)

        XCTAssertEqual(decoded?.count, 2)
        XCTAssertEqual(decoded?.value(for: .publicKey), first)
        XCTAssertEqual(decoded?.value(for: .proof), second)
    }

    // MARK: - Several items

    func testItemsKeepTheOrderTheyWereGivenIn() {
        let items = [
            HomeKitTLVItem(.state, Data([0x03])),
            HomeKitTLVItem(.publicKey, Data([0xAA, 0xBB])),
            HomeKitTLVItem(.proof, Data([0xCC])),
        ]

        XCTAssertEqual(HomeKitTLV.decode(HomeKitTLV.encode(items)), items)
    }

    func testAnUnfamiliarTypeIsKeptRatherThanDropped() {
        // A receiver may send something this sender has no name for, and a
        // message is still worth reading when it does.
        let encoded = Data([0x7F, 0x02, 0x10, 0x20])

        XCTAssertEqual(HomeKitTLV.decode(encoded), [HomeKitTLVItem(type: 0x7F, value: Data([0x10, 0x20]))])
    }

    // MARK: - Bytes that do not make a message

    func testBytesThatEndInTheMiddleOfAnItemAreRefused() {
        // The length says four bytes follow and only two do, so the message is
        // truncated rather than unfamiliar, and reading on would invent a value.
        XCTAssertNil(HomeKitTLV.decode(Data([0x03, 0x04, 0x10, 0x20])))
    }

    func testAHeaderWithoutItsLengthIsRefused() {
        XCTAssertNil(HomeKitTLV.decode(Data([0x03])))
    }

    func testNoBytesAreNoItems() {
        XCTAssertEqual(HomeKitTLV.decode(Data()), [])
    }
}
