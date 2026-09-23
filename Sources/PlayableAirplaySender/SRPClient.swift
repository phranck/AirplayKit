//
//  SRPClient.swift
//  The sender's half of the password-authenticated agreement pairing runs on.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

import BigInt
import Crypto
import Foundation

/// What can go wrong on the sender's side of the exchange.
public enum SRPError: Error, Equatable {
    /// The receiver's public value is zero modulo the group, which RFC 5054 says to refuse.
    case receiverPublicValueIsZero

    /// The receiver's proof did not match, so it does not hold the same secret and is not who it claims.
    case receiverProofDidNotMatch
}

/**
 SRP-6a over the 3072-bit group, with SHA-512, as HomeKit pairing runs it.

 Both sides end up holding the same 64-byte secret, and neither the password nor
 the secret crosses the wire. The sender is the client here.

 Where a value is padded and where it is not is the part of this that fails
 quietly. `k` and `u` hash their operands padded to the modulus's length, and
 the proofs hash every operand at its natural length. Getting that the wrong way
 round produces a receiver that refuses the proof and looks exactly like a wrong
 password.
 */
public struct SRPClient {
    /// The name HomeKit pairing runs under, which is fixed and not a user's name.
    public static let userName = "Pair-Setup"

    /// What transient pairing uses in place of a code on a screen.
    public static let transientPassword = "3939"

    private let password: String
    private let secretExponent: BigUInt

    /// The sender's public value, which goes to the receiver in M3.
    public let publicValue: BigUInt

    /**
     Starts an exchange.

     @param password The four digits from the receiver's screen, or
     `transientPassword` on the transient path.
     @param privateExponent The sender's secret, which is 32 random bytes in
     ordinary use. Supplied here so a test can pin it; leave it out otherwise.
     */
    public init(password: String, privateExponent: Data? = nil) {
        let secret = privateExponent ?? Data((0..<32).map { _ in UInt8.random(in: 0...255) })

        self.password = password
        self.secretExponent = BigUInt(secret)
        self.publicValue = SRPGroup.generator.power(self.secretExponent, modulus: SRPGroup.modulus)
    }

    /**
     What comes out of a completed exchange.

     @property sessionKey The 64-byte shared secret, which every later key is derived from.
     @property clientProof What the receiver is sent in M3 to prove this side holds it.
     @property expectedReceiverProof What M4 has to carry for the receiver to be believed.
     */
    public struct Agreement {
        public let sessionKey: Data
        public let clientProof: Data
        public let expectedReceiverProof: Data
    }

    /**
     Works out the shared secret and the two proofs from what the receiver sent in M2.

     @param salt The salt from M2.
     @param receiverPublicValue The receiver's public value from M2.
     @returns The secret and the proofs.
     @throws `SRPError.receiverPublicValueIsZero` where the receiver's value is
     zero modulo the group, which cannot be a real public value and would make
     the shared secret predictable.
     */
    public func agree(salt: Data, receiverPublicValue: Data) throws -> Agreement {
        let modulus = SRPGroup.modulus
        let generator = SRPGroup.generator

        let receiverPublic = BigUInt(receiverPublicValue)
        guard receiverPublic % modulus != 0 else { throw SRPError.receiverPublicValueIsZero }

        // Padded operands: both sides have to agree how many bytes a number
        // occupies before hashing it, or a short value hashes differently here
        // than there.
        let multiplier = BigUInt(Data(SHA512.hash(data: SRPGroup.padded(modulus) + SRPGroup.padded(generator))))
        let scrambler = BigUInt(Data(SHA512.hash(data: SRPGroup.padded(publicValue) + SRPGroup.padded(receiverPublic))))

        let credentials = Data(SHA512.hash(data: Data("\(Self.userName):\(password)".utf8)))
        let privateKey = BigUInt(Data(SHA512.hash(data: salt + credentials)))

        // S = (B - k * g^x) ^ (a + u * x) mod N. The subtraction can go
        // negative, so it is taken modulo the group before it is raised.
        let generatorToPrivate = generator.power(privateKey, modulus: modulus)
        let offset = (multiplier * generatorToPrivate) % modulus
        let base = (receiverPublic + modulus - offset) % modulus
        let exponent = secretExponent + scrambler * privateKey
        let sharedValue = base.power(exponent, modulus: modulus)

        // At its natural length rather than padded, which is what the receiver
        // hashes too.
        let sessionKey = Data(SHA512.hash(data: sharedValue.serialize()))

        let clientProof = Self.clientProof(salt: salt,
                                           publicValue: publicValue,
                                           receiverPublicValue: receiverPublic,
                                           sessionKey: sessionKey)

        let receiverProof = Data(SHA512.hash(data: publicValue.serialize() + clientProof + sessionKey))

        return Agreement(sessionKey: sessionKey,
                         clientProof: clientProof,
                         expectedReceiverProof: receiverProof)
    }

    /**
     Checks the receiver's proof from M4 against what it should be.

     Compared in constant time, so the number of leading bytes that happened to
     match is not readable from how long the comparison took.

     Skipping this check means the receiver is never authenticated at all, and a
     machine on the same network can accept the session and take the audio.

     @param received The proof the receiver sent in M4.
     @param expected What the agreement says it should be.
     @throws `SRPError.receiverProofDidNotMatch` where they differ.
     */
    public static func verify(receiverProof received: Data, against expected: Data) throws {
        guard received.count == expected.count else { throw SRPError.receiverProofDidNotMatch }

        var difference: UInt8 = 0
        for (left, right) in zip(received, expected) {
            difference |= left ^ right
        }

        guard difference == 0 else { throw SRPError.receiverProofDidNotMatch }
    }

    // MARK: - Private

    /// `H( H(N) XOR H(g) | H(I) | salt | A | B | K )`, every operand at its natural length.
    private static func clientProof(salt: Data,
                                    publicValue: BigUInt,
                                    receiverPublicValue: BigUInt,
                                    sessionKey: Data) -> Data {
        let hashedModulus = Data(SHA512.hash(data: SRPGroup.modulus.serialize()))
        let hashedGenerator = Data(SHA512.hash(data: SRPGroup.generator.serialize()))
        let mask = Data(zip(hashedModulus, hashedGenerator).map { $0 ^ $1 })
        let hashedUserName = Data(SHA512.hash(data: Data(userName.utf8)))

        return Data(SHA512.hash(data: mask
                                + hashedUserName
                                + salt
                                + publicValue.serialize()
                                + receiverPublicValue.serialize()
                                + sessionKey))
    }
}
