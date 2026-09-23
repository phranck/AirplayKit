//
//  SRPClientTests.swift
//  The sender's half of the agreement, checked against another implementation of the other half.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

import BigInt
import XCTest
@testable import PlayableAirplaySender

/**
 A fixed exchange, produced by a receiver's own SRP server.

 The numbers below were computed by `ap2/pairing/srp.py` from the
 `openairplay/airplay2-receiver` checkout, an implementation written from
 another source and by another author, driven with the salt and the two secret
 exponents pinned here.

 That is what makes this worth more than a round trip against itself. Where a
 value is padded and where it is not cannot be checked by an implementation
 talking to its own mirror image, because both halves would be wrong together.
 */
private enum Vector {
    static let salt = Data(hex: "0102030405060708090a0b0c0d0e0f10")

    static let senderSecret = Data(hex: "0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20")

    static let receiverPublicValue = Data(hex: """
        65ffbaccbc43d55625adfe1d345101ff843c115c7d525ed6c7c879b487e8163f\
        76c2c1da112a8831eeae6723d132e5b679f6b6d691a7c663c9709894039955f3\
        07dc42a0dc0386fac11ea888505c6482585063e9f376b7fd05ebfd551e865719\
        48f9af225aae97ff9c0e036de6f348f25a22d31b537f6d4190fa62ba8f12f7d7\
        d29cda472baaf404e8b57641c58d2e4486aa88962993376b2bfcaed1aa3dda51\
        af5f79509a4ba508da948d917818857565426514be26208df6cf5dc262bc59d0\
        96793be502c18d4a863bdeb5ccfd2c957dae272957d5b3e3a9d6d4cf1263a287\
        723fdfea344697a75172d4f70349af8b6a7ca8f8744875f86f5057803d5a4f7d\
        4d2a5fc2b5d24eafb4a99ddc37f2cb4bd90e4ef6b69e1642c5e106f86eddd543\
        467953b3359f024dd9e694249d3248583b807a2ef38d9aa0ceaf35377d436bc1\
        b554b3bcf579c4d44e7bf0a4ce6f69210f280d360d58fe477c398a4332a218f7\
        79c61d5ac1aceecd397cf04a09971f84f16bed00ea868af79784f9eef2cfcd4d
        """)

    static let sessionKey = Data(hex: """
        8c8c19042a2f628750ee2e87e46f042ca3a79112970eadb3370e1fd75e255f11\
        9e4b1a8c9277817d6c8c560528f4b4214ea0b9631ff5c938955f43943184ae80
        """)

    static let clientProof = Data(hex: """
        5046f5cefe1a994c7a341977154a27f425d308fb6e3b5559aea1529263695a5e\
        aaffd300ed618b7c1452287154aee26d3b67b66abeb0052422d551aea77d81c7
        """)

    static let receiverProof = Data(hex: """
        5c4e6594142d050aa1fc9d321b950c5eef63772e5b5daccbe2c94498efc73808\
        7a92be076b195a3b7bcc1f51b05715446834e5d3205a1edd11e8454d3d25adf7
        """)
}

final class SRPClientTests: XCTestCase {

    // MARK: - The group

    func testTheModulusIsTheThreeThousandAndSeventyTwoBitOne() {
        XCTAssertEqual(SRPGroup.modulus.bitWidth, 3072)
        XCTAssertEqual(SRPGroup.modulus.serialize().count, 384)
        XCTAssertEqual(SRPGroup.generator, 5)
    }

    func testPaddingFillsToTheModulusLength() {
        // The generator is one byte and is hashed as 384, which is the whole
        // point of the operation.
        XCTAssertEqual(SRPGroup.padded(SRPGroup.generator).count, 384)
        XCTAssertEqual(SRPGroup.padded(SRPGroup.generator).last, 5)
        XCTAssertEqual(SRPGroup.padded(SRPGroup.generator).first, 0)
    }

    func testPaddingLeavesAValueThatIsAlreadyLongEnoughAlone() {
        XCTAssertEqual(SRPGroup.padded(SRPGroup.modulus), SRPGroup.modulus.serialize())
    }

    // MARK: - Against the other implementation

    func testTheAgreementMatchesTheReceiversOwnComputation() throws {
        let client = SRPClient(password: SRPClient.transientPassword,
                               privateExponent: Vector.senderSecret)

        let agreement = try client.agree(salt: Vector.salt,
                                         receiverPublicValue: Vector.receiverPublicValue)

        XCTAssertEqual(agreement.sessionKey, Vector.sessionKey)
        XCTAssertEqual(agreement.clientProof, Vector.clientProof)
        XCTAssertEqual(agreement.expectedReceiverProof, Vector.receiverProof)
    }

    func testTheSendersPublicValueIsTheOneTheReceiverWasGiven() {
        // The vector was produced by handing the server this exact public
        // value, so it has to come out of the same secret here.
        let client = SRPClient(password: SRPClient.transientPassword,
                               privateExponent: Vector.senderSecret)

        XCTAssertEqual(client.publicValue,
                       SRPGroup.generator.power(BigUInt(Vector.senderSecret), modulus: SRPGroup.modulus))
    }

    // MARK: - Refusing what should be refused

    func testAReceiverPublicValueOfZeroIsRefused() {
        let client = SRPClient(password: SRPClient.transientPassword,
                               privateExponent: Vector.senderSecret)

        XCTAssertThrowsError(try client.agree(salt: Vector.salt, receiverPublicValue: Data([0]))) { error in
            XCTAssertEqual(error as? SRPError, .receiverPublicValueIsZero)
        }
    }

    func testAPublicValueThatIsTheModulusIsRefused() {
        // Zero modulo the group without being zero on the wire, which is the
        // form the check has to catch rather than a literal zero byte.
        let client = SRPClient(password: SRPClient.transientPassword,
                               privateExponent: Vector.senderSecret)

        XCTAssertThrowsError(try client.agree(salt: Vector.salt,
                                              receiverPublicValue: SRPGroup.modulus.serialize())) { error in
            XCTAssertEqual(error as? SRPError, .receiverPublicValueIsZero)
        }
    }

    func testTheRightReceiverProofIsAccepted() throws {
        try SRPClient.verify(receiverProof: Vector.receiverProof, against: Vector.receiverProof)
    }

    func testAReceiverProofThatDiffersInOneBitIsRefused() {
        var wrong = Vector.receiverProof
        wrong[wrong.count - 1] ^= 0x01

        XCTAssertThrowsError(try SRPClient.verify(receiverProof: wrong, against: Vector.receiverProof)) { error in
            XCTAssertEqual(error as? SRPError, .receiverProofDidNotMatch)
        }
    }

    func testAReceiverProofOfTheWrongLengthIsRefused() {
        XCTAssertThrowsError(try SRPClient.verify(receiverProof: Data([0x01]),
                                                  against: Vector.receiverProof)) { error in
            XCTAssertEqual(error as? SRPError, .receiverProofDidNotMatch)
        }
    }

    // MARK: - A different password

    func testADifferentPasswordProducesADifferentSecret() throws {
        let client = SRPClient(password: "1234", privateExponent: Vector.senderSecret)

        let agreement = try client.agree(salt: Vector.salt,
                                         receiverPublicValue: Vector.receiverPublicValue)

        XCTAssertNotEqual(agreement.sessionKey, Vector.sessionKey)
    }
}

private extension Data {
    /// Reads a hexadecimal string, ignoring any whitespace a long one is broken across lines with.
    init(hex: String) {
        let digits = hex.filter { !$0.isWhitespace }
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
