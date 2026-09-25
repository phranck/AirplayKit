//
//  SessionKeys.swift
//  Everything the shared secret turns into once pairing is done.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

import Crypto
import Foundation

/**
 The keys a paired session runs on.

 All four channel keys are HKDF-SHA-512 over the pairing secret, 32 bytes out,
 differing only in the salt and info strings. The audio key is not derived at
 all: it is the first 32 bytes of the secret itself.

 The names are written from the sender's point of view. A receiver sees the read
 and write keys the other way round, because it is the accessory and this is the
 controller.

 @property controlWrite What the sender encrypts control requests with.
 @property controlRead What the sender decrypts the receiver's answers with.
 @property eventsWrite What the receiver's pushed events are decrypted with.
 @property eventsRead What the sender's answers on the event channel are encrypted with.
 @property audio The key the audio payload is encrypted under, which the stream SETUP also carries as `shk`.
 */
package struct SessionKeys: Equatable {
    public let controlWrite: Data
    public let controlRead: Data
    public let eventsWrite: Data
    public let eventsRead: Data
    public let audio: Data

    /**
     Derives every key from the secret pairing produced.

     @param secret The shared secret. After transient pairing that is the
     64-byte SRP session key, and after pair-verify the 32-byte X25519
     agreement. Both go in whole; only the audio key is shortened, and that is
     a clamp rather than a derivation.
     */
    public init(secret: Data) {
        controlWrite = Self.derive(secret, salt: "Control-Salt", info: "Control-Write-Encryption-Key")
        controlRead = Self.derive(secret, salt: "Control-Salt", info: "Control-Read-Encryption-Key")
        eventsWrite = Self.derive(secret, salt: "Events-Salt", info: "Events-Write-Encryption-Key")
        eventsRead = Self.derive(secret, salt: "Events-Salt", info: "Events-Read-Encryption-Key")

        // The first 32 bytes, not a hash of them and not the whole thing. A
        // transient secret is 64 bytes and the cipher takes 32, and handing it
        // all 64 makes every packet fail rather than sound wrong.
        audio = Data(secret.prefix(32))
    }

    /// How long every derived channel key is.
    static let channelKeyLength = 32

    /**
     One HKDF-SHA-512 derivation.

     The salt and info strings go in without a terminating zero byte, so
     `Control-Salt` is twelve bytes rather than thirteen.

     @param secret The input keying material.
     @param salt The salt string.
     @param info The info string.
     @returns 32 bytes.
     */
    private static func derive(_ secret: Data, salt: String, info: String) -> Data {
        let key = HKDF<SHA512>.deriveKey(inputKeyMaterial: SymmetricKey(data: secret),
                                         salt: Data(salt.utf8),
                                         info: Data(info.utf8),
                                         outputByteCount: channelKeyLength)

        return key.withUnsafeBytes { Data($0) }
    }
}
