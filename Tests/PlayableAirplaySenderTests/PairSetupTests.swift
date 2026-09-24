//
//  PairSetupTests.swift
//  The four messages, driven against ones a receiver actually produced.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

import XCTest
@testable import PlayableAirplaySender

final class PairSetupTests: XCTestCase {

    /// The sender secret the recorded exchange below was produced against.
    private static let senderSecret =
        Data(hexString: "0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20")

    /**
     M2 exactly as `ap2/pairing/srp.py` in the `build/airplay2-receiver`
     checkout produced it, TLV8 encoded: state 2, the salt, and a 384-byte
     public value that the format had to split across two records.
     */
    private static let receiverM2 = Data(hexString: """
        06010202100102030405060708090a0b0c0d0e0f1003ff65ffbaccbc43d55625adfe1d345101ff843c115c7d5\
        25ed6c7c879b487e8163f76c2c1da112a8831eeae6723d132e5b679f6b6d691a7c663c9709894039955f307dc\
        42a0dc0386fac11ea888505c6482585063e9f376b7fd05ebfd551e86571948f9af225aae97ff9c0e036de6f34\
        8f25a22d31b537f6d4190fa62ba8f12f7d7d29cda472baaf404e8b57641c58d2e4486aa88962993376b2bfcae\
        d1aa3dda51af5f79509a4ba508da948d917818857565426514be26208df6cf5dc262bc59d096793be502c18d4\
        a863bdeb5ccfd2c957dae272957d5b3e3a9d6d4cf1263a287723fdfea344697a75172d4f70349af8b6a7ca8f8\
        744875f86f5057803d5a4f03817d4d2a5fc2b5d24eafb4a99ddc37f2cb4bd90e4ef6b69e1642c5e106f86eddd\
        543467953b3359f024dd9e694249d3248583b807a2ef38d9aa0ceaf35377d436bc1b554b3bcf579c4d44e7bf0\
        a4ce6f69210f280d360d58fe477c398a4332a218f779c61d5ac1aceecd397cf04a09971f84f16bed00ea868af\
        79784f9eef2cfcd4d
        """)

    /// M4 from the same exchange: state 4 and the receiver's proof.
    private static let receiverM4 = Data(hexString: """
        06010404405c4e6594142d050aa1fc9d321b950c5eef63772e5b5daccbe2c94498efc738087a92be076b195a3\
        b7bcc1f51b05715446834e5d3205a1edd11e8454d3d25adf7
        """)

    // MARK: - The first message

    func testTheFirstMessageAsksForTransientPairing() {
        let items = HomeKitTLV.decode(PairSetup().start())

        XCTAssertEqual(items?.value(for: .state), Data([0x01]))
        XCTAssertEqual(items?.value(for: .method), Data([0x00]))
        XCTAssertEqual(items?.value(for: .flags), Data([0x10]))
    }

    func testTheFirstMessageIsTheSameBytesItHasAlwaysBeen() {
        // Byte for byte, because this is what a receiver reads and it is
        // measured to work. Anything that changes it changes the protocol.
        XCTAssertEqual(PairSetup().start(),
                       Data([0x06, 0x01, 0x01,
                             0x00, 0x01, 0x00,
                             0x13, 0x01, 0x10]))
    }

    // MARK: - The flags field

    func testTheTransientFlagIsOneByteAndStaysOne() {
        // Apple's parser refuses a flags value longer than four bytes and takes
        // anything shorter, so the shortest form that holds the value is legal.
        // One byte is also what a working sender was read sending.
        XCTAssertEqual(PairSetup.flagsValue(PairSetup.transientFlag), Data([0x10]))
    }

    func testAFlagTooLargeForAByteIsCarriedRatherThanTrapped() {
        // The hazard: converting a UInt32 to a UInt8 ends the process above
        // 0xFF, so the next flag this ever needs would have taken the
        // application down instead of failing.
        XCTAssertEqual(PairSetup.flagsValue(0x100), Data([0x00, 0x01]))
        XCTAssertEqual(PairSetup.flagsValue(0x1234_5678), Data([0x78, 0x56, 0x34, 0x12]))
        XCTAssertEqual(PairSetup.flagsValue(UInt32.max), Data([0xFF, 0xFF, 0xFF, 0xFF]))
    }

    func testAFlagsValueOfNoughtIsStillAByte() {
        // A field of no length is not the same thing as a field carrying
        // nought, and the encoding has to be able to say the second.
        XCTAssertEqual(PairSetup.flagsValue(0), Data([0x00]))
    }

    func testEveryFlagsValueFitsWhatTheFieldAccepts() {
        // Four bytes is the most Apple's parser takes, so nothing this produces
        // may be longer than that.
        for flags in [UInt32(0), 1, 0x10, 0xFF, 0x100, 0xFFFF, 0x1_0000, UInt32.max] {
            let value = PairSetup.flagsValue(flags)

            XCTAssertGreaterThanOrEqual(value.count, 1, "\(flags)")
            XCTAssertLessThanOrEqual(value.count, 4, "\(flags)")
        }
    }

    // MARK: - The whole exchange, against a recorded receiver

    func testTheThirdMessageCarriesThePublicValueAndTheProof() throws {
        var pairing = PairSetup(privateExponent: Self.senderSecret)

        let items = HomeKitTLV.decode(try pairing.answer(toSetupStart: Self.receiverM2))

        XCTAssertEqual(items?.value(for: .state), Data([0x03]))
        // Padded to the group's length, so it is split into two records and
        // comes back out as one.
        XCTAssertEqual(items?.value(for: .publicKey)?.count, 384)
        XCTAssertEqual(items?.value(for: .proof),
                       Data(hexString: """
                            5046f5cefe1a994c7a341977154a27f425d308fb6e3b5559aea1529263695a5e\
                            aaffd300ed618b7c1452287154aee26d3b67b66abeb0052422d551aea77d81c7
                            """))
    }

    func testTheExchangeEndsHoldingTheKeysTheReceiverDerived() throws {
        var pairing = PairSetup(privateExponent: Self.senderSecret)

        _ = try pairing.answer(toSetupStart: Self.receiverM2)
        let keys = try pairing.finish(with: Self.receiverM4)

        XCTAssertEqual(keys.controlWrite,
                       Data(hexString: "1eb9c92dd37d14c6b1d5a99b023358e08733dc037a79aa158e44c084ffc09407"))
        XCTAssertEqual(keys.audio,
                       Data(hexString: "8c8c19042a2f628750ee2e87e46f042ca3a79112970eadb3370e1fd75e255f11"))
    }

    // MARK: - A receiver that will not play along

    func testAReceiverThatRefusesIsReportedAsRefusing() {
        var pairing = PairSetup(privateExponent: Self.senderSecret)
        let refusal = HomeKitTLV.encode([
            HomeKitTLVItem(.state, Data([0x02])),
            HomeKitTLVItem(.error, Data([0x02])),
        ])

        XCTAssertThrowsError(try pairing.answer(toSetupStart: refusal)) { error in
            XCTAssertEqual(error as? PairSetupFailure, .receiverRefused(.authentication))
        }
    }

    func testARefusalIsReadEvenWhenItNamesAnUnexpectedState() {
        // The reason is the useful part, so it is read before the state is
        // judged rather than being hidden behind a complaint about the state.
        var pairing = PairSetup(privateExponent: Self.senderSecret)
        let refusal = HomeKitTLV.encode([
            HomeKitTLVItem(.state, Data([0x06])),
            HomeKitTLVItem(.error, Data([0x03])),
        ])

        XCTAssertThrowsError(try pairing.answer(toSetupStart: refusal)) { error in
            XCTAssertEqual(error as? PairSetupFailure, .receiverRefused(.backoff))
        }
    }

    func testARefusalCodeWithNoNameIsStillARefusal() {
        var pairing = PairSetup(privateExponent: Self.senderSecret)
        let refusal = HomeKitTLV.encode([HomeKitTLVItem(.error, Data([0x7F]))])

        XCTAssertThrowsError(try pairing.answer(toSetupStart: refusal)) { error in
            XCTAssertEqual(error as? PairSetupFailure, .receiverRefusedWithUnknownCode(0x7F))
        }
    }

    func testAnAnswerNamingTheWrongStateIsRefused() {
        var pairing = PairSetup(privateExponent: Self.senderSecret)
        let wrong = HomeKitTLV.encode([HomeKitTLVItem(.state, Data([0x04]))])

        XCTAssertThrowsError(try pairing.answer(toSetupStart: wrong)) { error in
            XCTAssertEqual(error as? PairSetupFailure, .unexpectedState(expected: 0x02, received: 0x04))
        }
    }

    func testAnAnswerWithoutASaltIsRefused() {
        var pairing = PairSetup(privateExponent: Self.senderSecret)
        let incomplete = HomeKitTLV.encode([
            HomeKitTLVItem(.state, Data([0x02])),
            HomeKitTLVItem(.publicKey, Data(repeating: 0x01, count: 384)),
        ])

        XCTAssertThrowsError(try pairing.answer(toSetupStart: incomplete)) { error in
            XCTAssertEqual(error as? PairSetupFailure, .answerIsMissing(.salt))
        }
    }

    func testAnAnswerThatIsNotAMessageIsRefused() {
        var pairing = PairSetup(privateExponent: Self.senderSecret)

        XCTAssertThrowsError(try pairing.answer(toSetupStart: Data([0x06]))) { error in
            XCTAssertEqual(error as? PairSetupFailure, .answerIsNotReadable)
        }
    }

    // MARK: - The check that decides whether the receiver is who it says

    func testAWrongReceiverProofEndsTheExchange() throws {
        var pairing = PairSetup(privateExponent: Self.senderSecret)
        _ = try pairing.answer(toSetupStart: Self.receiverM2)

        var tampered = Self.receiverM4
        tampered[tampered.count - 1] ^= 0x01

        XCTAssertThrowsError(try pairing.finish(with: tampered)) { error in
            XCTAssertEqual(error as? SRPError, .receiverProofDidNotMatch)
        }
    }

    func testFinishingBeforeTheExchangeHasRunIsRefused() {
        let pairing = PairSetup(privateExponent: Self.senderSecret)

        XCTAssertThrowsError(try pairing.finish(with: Self.receiverM4)) { error in
            XCTAssertEqual(error as? PairSetupFailure, .unexpectedState(expected: 0x04, received: nil))
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
