//
//  SessionKeysTests.swift
//  The derivations, checked against the HKDF a receiver runs.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

import XCTest
@testable import AirplayKitSender

final class SessionKeysTests: XCTestCase {

    /// The 64-byte secret the SRP vector in `SRPClientTests` ends on.
    private static let secret = Data(hexString: """
        8c8c19042a2f628750ee2e87e46f042ca3a79112970eadb3370e1fd75e255f11\
        9e4b1a8c9277817d6c8c560528f4b4214ea0b9631ff5c938955f43943184ae80
        """)

    // MARK: - Against the other implementation

    /**
     Every expected value below was produced by the `hkdf` module the
     `openairplay/airplay2-receiver` checkout uses, over the same secret and the
     same strings. An implementation checked only against itself would agree
     with its own mistakes.
     */
    func testEveryChannelKeyMatchesTheReceiversOwnDerivation() {
        let keys = SessionKeys(secret: Self.secret)

        XCTAssertEqual(keys.controlWrite,
                       Data(hexString: "1eb9c92dd37d14c6b1d5a99b023358e08733dc037a79aa158e44c084ffc09407"))
        XCTAssertEqual(keys.controlRead,
                       Data(hexString: "1699e4528b8d14815a0c1694cd475bd925ea2bddcb0cb988e03ddbc0d55a74d0"))
        XCTAssertEqual(keys.eventsWrite,
                       Data(hexString: "77213bad76ad895aef8047951b2a4a31202444e3e8570cfed6edc6e5713ea561"))
        XCTAssertEqual(keys.eventsRead,
                       Data(hexString: "b46a2f87c6da7a9563412d4bbd551720421415c1b580e104d99d067be6ea942e"))
    }

    // MARK: - The audio key, which is the one that is not derived

    func testTheAudioKeyIsTheFirstThirtyTwoBytesOfTheSecret() {
        let keys = SessionKeys(secret: Self.secret)

        XCTAssertEqual(keys.audio, Data(Self.secret.prefix(32)))
        XCTAssertEqual(keys.audio.count, 32)
    }

    func testAThirtyTwoByteSecretIsItsOwnAudioKey() {
        // After pair-verify the secret is already 32 bytes, so the clamp has
        // nothing to take off and must not pad it either.
        let short = Data(Self.secret.prefix(32))

        XCTAssertEqual(SessionKeys(secret: short).audio, short)
    }

    // MARK: - The four keys are four keys

    func testNoTwoChannelKeysAreTheSame() {
        let keys = SessionKeys(secret: Self.secret)
        let all = [keys.controlWrite, keys.controlRead, keys.eventsWrite, keys.eventsRead]

        XCTAssertEqual(Set(all).count, 4)
        XCTAssertTrue(all.allSatisfy { $0.count == SessionKeys.channelKeyLength })
    }

    func testADifferentSecretGivesDifferentKeys() {
        var other = Self.secret
        other[0] ^= 0x01

        XCTAssertNotEqual(SessionKeys(secret: other), SessionKeys(secret: Self.secret))
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
