//
//  PairSetup.swift
//  The four messages transient pairing is, without the transport under them.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

import Foundation

/// What a receiver can say went wrong, as HomeKit numbers it.
package enum PairingError: UInt8, Error, Equatable {
    case unknown = 0x01
    case authentication = 0x02
    case backoff = 0x03
    case maximumPeers = 0x04
    case maximumTries = 0x05
    case unavailable = 0x06
    case busy = 0x07
}

/// What can go wrong reading a receiver's answer, beyond the receiver saying so itself.
package enum PairSetupFailure: Error, Equatable {
    /// The body was not a TLV8 sequence, or ended in the middle of an item.
    case answerIsNotReadable

    /// The receiver named a state other than the one this step expects.
    case unexpectedState(expected: UInt8, received: UInt8?)

    /// The answer is missing something the next step cannot be taken without.
    case answerIsMissing(HomeKitTLVType)

    /// The receiver reported a failure of its own.
    case receiverRefused(PairingError)

    /// The receiver reported a failure whose number has no name here.
    case receiverRefusedWithUnknownCode(UInt8)
}

/**
 Transient pairing, as a sequence of messages rather than a connection.

 Four messages, and the sender speaks first. The receiver never learns the
 password and the sender never learns a long-term identity, which is the whole
 point of the transient path: an encrypted session without anybody typing
 anything.

 Nothing here opens a socket. A caller hands each answer in and gets the next
 message back, which is what lets the whole exchange be tested without a
 receiver and lets the transport be chosen elsewhere.

 ```swift
 var pairing = PairSetup()
 let m1 = pairing.start()
 let m3 = try pairing.answer(toSetupStart: receiverAnswer)
 let keys = try pairing.finish(with: receiverProofAnswer)
 ```
 */
package struct PairSetup {
    /// The flag that asks for the transient path rather than the one ending in a stored identity.
    static let transientFlag: UInt32 = 0x10

    /// The method number for pair-setup.
    static let pairSetupMethod: UInt8 = 0x00

    private let password: String
    private let privateExponent: Data?
    private var client: SRPClient?
    private var agreement: SRPClient.Agreement?

    /**
     Starts a transient exchange.

     @param password What stands in for a code on a screen, which on the
     transient path is fixed.
     @param privateExponent The sender's secret, which is 32 fresh random bytes
     in ordinary use. Supplied here so a test can drive the whole exchange
     against a recorded one; leave it out otherwise.
     */
    public init(password: String = SRPClient.transientPassword, privateExponent: Data? = nil) {
        self.password = password
        self.privateExponent = privateExponent
    }

    /**
     The first message, which asks for transient pairing.

     @returns The TLV8 body of M1.
     */
    public func start() -> Data {
        HomeKitTLV.encode([
            HomeKitTLVItem(.state, Data([0x01])),
            HomeKitTLVItem(.method, Data([Self.pairSetupMethod])),
            HomeKitTLVItem(.flags, Self.flagsValue(Self.transientFlag)),
        ])
    }

    /**
     A flags value as the field carries it, little-endian and no longer than it
     needs to be.

     Apple's own parser takes any length up to four bytes and refuses only what
     is longer, and it reads what it takes little-endian. So the shortest form
     that holds the value is a legal one, and for the transient flag that is the
     single byte this has always sent.

     Written out rather than converted. `UInt8(_:)` on a `UInt32` ends the
     process for anything above 0xFF, so the next flag this ever needs would
     have taken the application down rather than failing, and it would have gone
     on the wire as the wrong number in any case.

     @param flags The value to carry.
     @returns One to four bytes, least significant first.
     */
    static func flagsValue(_ flags: UInt32) -> Data {
        var bytes = Data()
        var remaining = flags

        // At least one byte. A field of no length is not the same thing as a
        // field carrying nought, and this has to be able to say the second.
        repeat {
            bytes.append(UInt8(remaining & 0xFF))
            remaining >>= 8
        } while remaining != 0

        return bytes
    }

    /**
     Reads M2 and produces M3.

     M2 carries the salt and the receiver's public value. M3 carries this
     sender's public value and its proof that it holds the same secret.

     @param answer The TLV8 body the receiver sent.
     @returns The TLV8 body of M3.
     @throws A `PairSetupFailure`, or the receiver's own refusal where it sent one.
     */
    public mutating func answer(toSetupStart answer: Data) throws -> Data {
        let items = try Self.read(answer, expectingState: 0x02)

        guard let salt = items.value(for: .salt) else {
            throw PairSetupFailure.answerIsMissing(.salt)
        }
        guard let receiverPublicValue = items.value(for: .publicKey) else {
            throw PairSetupFailure.answerIsMissing(.publicKey)
        }

        let client = SRPClient(password: password, privateExponent: privateExponent)
        let agreement = try client.agree(salt: salt, receiverPublicValue: receiverPublicValue)

        self.client = client
        self.agreement = agreement

        return HomeKitTLV.encode([
            HomeKitTLVItem(.state, Data([0x03])),
            HomeKitTLVItem(.publicKey, SRPGroup.padded(client.publicValue)),
            HomeKitTLVItem(.proof, agreement.clientProof),
        ])
    }

    /**
     Reads M4 and ends the exchange.

     The receiver's proof is checked rather than taken on trust. Without that
     check the receiver is never authenticated, and a machine on the same
     network can accept the session and take the audio.

     @param answer The TLV8 body the receiver sent.
     @returns The keys the session runs on.
     @throws A `PairSetupFailure`, the receiver's own refusal, or
     `SRPError.receiverProofDidNotMatch` where its proof is wrong.
     */
    public func finish(with answer: Data) throws -> SessionKeys {
        guard let agreement else {
            throw PairSetupFailure.unexpectedState(expected: 0x04, received: nil)
        }

        let items = try Self.read(answer, expectingState: 0x04)

        guard let proof = items.value(for: .proof) else {
            throw PairSetupFailure.answerIsMissing(.proof)
        }

        try SRPClient.verify(receiverProof: proof, against: agreement.expectedReceiverProof)

        return SessionKeys(secret: agreement.sessionKey)
    }

    // MARK: - Private

    /// Parses an answer, turning a refusal into an error rather than into a missing field.
    private static func read(_ body: Data, expectingState state: UInt8) throws -> [HomeKitTLVItem] {
        guard let items = HomeKitTLV.decode(body) else {
            throw PairSetupFailure.answerIsNotReadable
        }

        // A refusal is checked before the state, because a receiver that
        // refuses still names a state and the reason is the useful part.
        if let code = items.value(for: .error)?.first {
            guard let named = PairingError(rawValue: code) else {
                throw PairSetupFailure.receiverRefusedWithUnknownCode(code)
            }
            throw PairSetupFailure.receiverRefused(named)
        }

        guard items.value(for: .state)?.first == state else {
            throw PairSetupFailure.unexpectedState(expected: state,
                                                   received: items.value(for: .state)?.first)
        }

        return items
    }
}
