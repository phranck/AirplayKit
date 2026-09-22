# Pairing

How a sender authenticates a receiver, and how everything after that becomes unreadable on the wire.

## Overview

AirPlay 2 authenticates with the pairing exchange from the HomeKit Accessory Protocol. The sender plays the part HomeKit calls the controller and the receiver plays the accessory. There are two phases, pair-setup and pair-verify, and which of them run depends on the receiver.

The messages are carried as HTTP `POST` requests on the same TCP connection that later carries RTSP, with `Content-Type: application/octet-stream` and a TLV8 body (reported confirmed, [openairplay, HomeKit Based Pairings](https://openairplay.github.io/airplay-spec/pairing/hkp.html)).

Once pairing finishes, both the control connection and a second connection called the event channel are encrypted, and this article covers those as well, because the keys for both come out of pairing.

## TLV8

TLV8 stands for type, length, value, with one byte each for the type and the length. A TLV8 body is a flat sequence of such records. There is no nesting at the wire level, although a decrypted value is often itself a TLV8 sequence.

```text
+--------+--------+---------------------------+
| type   | length |   value (length bytes)    |
| 1 byte | 1 byte |                           |
+--------+--------+---------------------------+
```

A value longer than 255 bytes is split into consecutive records carrying the same type byte, and the reader joins them back together. This matters for the SRP public key, which is 384 bytes and therefore always arrives in two records.

These are the type numbers (reported confirmed, [Apple, `HomeKitADK/HAP/HAPPairing.h`](https://github.com/apple/HomeKitADK/blob/master/HAP/HAPPairing.h)).

| Value | Name |
|---|---|
| 0x00 | Method |
| 0x01 | Identifier |
| 0x02 | Salt |
| 0x03 | PublicKey |
| 0x04 | Proof |
| 0x05 | EncryptedData |
| 0x06 | State |
| 0x07 | Error |
| 0x08 | RetryDelay |
| 0x09 | Certificate |
| 0x0A | Signature |
| 0x0B | Permissions |
| 0x0C | FragmentData |
| 0x0D | FragmentLast |
| 0x0E | SessionID |
| 0x11 | Name, which pyatv marks as Apple-internal |
| 0x13 | Flags |
| 0xFF | Separator |

The Error type carries one of these codes (reported confirmed, [Apple, `HomeKitADK/HAP/HAPPairing.h`](https://github.com/apple/HomeKitADK/blob/master/HAP/HAPPairing.h)).

| Value | Name |
|---|---|
| 0x01 | Unknown |
| 0x02 | Authentication |
| 0x03 | Backoff |
| 0x04 | MaxPeers |
| 0x05 | MaxTries |
| 0x06 | Unavailable |
| 0x07 | Busy |

The Method type carries one of these (reported confirmed, [pyatv, `pyatv/auth/hap_tlv8.py`](https://github.com/postlund/pyatv/blob/master/pyatv/auth/hap_tlv8.py), which is also where the `Name` type above comes from).

| Value | Name |
|---|---|
| 0x00 | PairSetup |
| 0x01 | PairSetupWithAuth |
| 0x02 | PairVerify |
| 0x03 | AddPairing |
| 0x04 | RemovePairing |
| 0x05 | ListPairing |

## The `X-Apple-HKP` header

Every pairing request carries an `X-Apple-HKP` header saying which pairing mode the sender wants. One receiver enumerates the whole set in its own source (reported confirmed as a statement about that implementation, [openairplay, `airplay2-receiver`, `ap2-receiver.py`](https://github.com/openairplay/airplay2-receiver/blob/master/ap2-receiver.py)).

| Value | Name it gives |
|---|---|
| 0 | Unauthenticated, for a receiver advertising neither transient nor system pairing. |
| 2 | Pair-setup is complete and pair-verify begins. |
| 3 | System pairing, which it ties to `features` bit 43. |
| 4 | Transient pairing. |
| 6 | HomeKit. |
| 7 | HomeKit administration. |

A working sender sends `4` for transient pairing and `3` for pairing with a PIN (reported likely, [airplay2-sender-cpp, `raop_sender.cpp`](https://github.com/akustikrausch/airplay2-sender-cpp)). owntone picks between `3` and `4` on the same split, normal against transient (reported confirmed, [owntone, `src/outputs/airplay.c`](https://github.com/owntone/owntone-server/blob/master/src/outputs/airplay.c)). pyatv labels `3` as HAP and `4` as transient, and answers a `/pair-verify` carrying no such header with a 501 (reported confirmed as a description of pyatv, [pyatv, `pyatv/protocols/airplay/server_auth.py`](https://github.com/postlund/pyatv/blob/master/pyatv/protocols/airplay/server_auth.py)).

Apple's own sender uses a value that appears in none of those lists. Four pair-verify requests from an iPhone XR on iOS 18.7 all carried `X-Apple-HKP: 8` (measured 2026-09-22, captured, F-021). The published record names only 3 and 4 as things a sender sends, and the receiver's own table stops at 7. What 8 means is open: a receiver that logs the value and accepts each of 3, 4 and 8 in turn shows whether it changes anything.

Which value the PIN path wants is also open. Three senders send `3` there and are answered, whilst the receiver's own list reserves `3` for system pairing and puts HomeKit at `6` (open: pairing with a PIN against an Apple TV whilst sending 6 settles it).

## The identity headers

Alongside `X-Apple-HKP`, a pairing request carries the sender's identity headers. A receiver's access-control gate reads them before it reads the TLV body, and their absence is a documented cause of a 403 response (reported likely, [airplay2-sender-cpp, `raop_sender.cpp`](https://github.com/akustikrausch/airplay2-sender-cpp)).

```text
POST /pair-setup HTTP/1.1
CSeq: 3
User-Agent: AirPlay/550.10
Connection: keep-alive
X-Apple-HKP: 4
DACP-ID: 8A4F2C19B7E03D56
Active-Remote: 1734829163
Client-Instance: 8A4F2C19B7E03D56
X-Apple-Client-Name: Playable
Content-Type: application/octet-stream
Content-Length: 6
```

`Client-Instance` carries the same value as `DACP-ID`. Both are random per session. `DACP-ID` is a 64-bit value written as uppercase hexadecimal without leading zeros, and `Active-Remote` is a random 32-bit decimal number (reported likely, [airplay2-sender-cpp, `raop_sender.cpp`](https://github.com/akustikrausch/airplay2-sender-cpp)).

## Making the PIN appear

On the PIN path, an Apple TV renders its four-digit code only after it receives an empty `POST /pair-pin-start`. Sending pair-setup M1 on its own returns the SRP material without ever putting a code on the screen, so the user waits for something that never appears (reported likely, [airplay2-sender-cpp, `raop_sender.cpp`](https://github.com/akustikrausch/airplay2-sender-cpp), and pyatv's pairing start and owntone's pin-start payload both do the same thing).

## Pair-setup, M1 to M6

Pair-setup runs SRP-6a, which is a password-authenticated key agreement. Both sides end up holding the same secret, and neither the password nor the secret crosses the wire. The client is the sender.

The parameters are fixed.

| Parameter | Value | Mark |
|---|---|---|
| Group | The 3072-bit group from RFC 5054, whose generator `g` is 5 and whose modulus `N` is 384 bytes | reported confirmed, [RFC 5054](https://www.rfc-editor.org/rfc/rfc5054.txt) |
| Hash | SHA-512, rather than the SHA-1 that RFC 5054 uses in its own examples | reported confirmed, [Apple, `HAPPairingPairSetup.c`](https://github.com/apple/HomeKitADK/blob/master/HAP/HAPPairingPairSetup.c) |
| User name | The literal string `Pair-Setup` | reported confirmed, same source |
| Password | The four digits on the receiver's screen on the PIN path, and the fixed string `3939` on the transient path | reported confirmed for `3939`, [openairplay, HomeKit Based Pairings](https://openairplay.github.io/airplay-spec/pairing/hkp.html) |

RFC 5054 defines `PAD()` as left-padding a value with zero bytes until its length equals the length of `N`, which for this group is 384 bytes (reported confirmed, [RFC 5054](https://www.rfc-editor.org/rfc/rfc5054.txt)). HomeKit applies that padding to the operands of `k` and `u`, and not to the operands of `x` or to `S` (reported likely, [airplay2-sender-cpp, `airplay_crypto.cpp`](https://github.com/akustikrausch/airplay2-sender-cpp), cross-checked there against `ejurgensen/pair_ap`).

```text
k = SHA-512( PAD(N) | PAD(g) )
u = SHA-512( PAD(A) | PAD(B) )
x = SHA-512( salt | SHA-512( "Pair-Setup" | ":" | pin ) )
A = g^a mod N                          a is 32 random bytes
S = (B - k * g^x) ^ (a + u * x) mod N
K = SHA-512(S)                         S at its natural byte length
clientProof = SHA-512( (SHA-512(N) XOR SHA-512(g)) | SHA-512("Pair-Setup") | salt | A | B | K )
serverProof = SHA-512( A | clientProof | K )
```

SRP literature calls those two proofs M1 and M2, which collides with the HomeKit message numbers M1 to M6. They are called `clientProof` and `serverProof` throughout so the two never have to be told apart from context.

`K` is 64 bytes, because SHA-512 produces 64 bytes. That length matters later, in the audio key.

Every message is a `POST /pair-setup` with a TLV8 body, and the State type carries the message number.

| Message | Direction | TLV8 contents |
|---|---|---|
| M1 | sender to receiver | State = 1, Method = 0. On the transient path, additionally Flags = 0x10. |
| M2 | receiver to sender | State = 2, Salt, PublicKey = B. Or State = 2 and Error. |
| M3 | sender to receiver | State = 3, PublicKey = A, Proof = clientProof. |
| M4 | receiver to sender | State = 4, Proof = serverProof. Or State = 4 and Error. |
| M5 | sender to receiver | State = 5, EncryptedData. |
| M6 | receiver to sender | State = 6, EncryptedData. |

Flags value 0x10 in M1 is the transient pairing flag (reported likely, [airplay2-sender-cpp, `raop_sender.cpp`](https://github.com/akustikrausch/airplay2-sender-cpp)).

### Check the server proof

The sender checks the `serverProof` carried in M4 against its own computation of it, in constant time. Failing to check it means the receiver is never authenticated, and a machine on the same network can accept the session and take the audio (reported confirmed that this is the consequence, [airplay2-sender-cpp, `SECURITY.md`](https://github.com/akustikrausch/airplay2-sender-cpp)).

pyatv does not perform this check, nor does it verify the receiver's Ed25519 signature in M6 or the pair-verify response in M4, and its own source carries the outstanding notes (reported confirmed, [pyatv, `pyatv/auth/hap_srp.py`](https://github.com/postlund/pyatv/blob/master/pyatv/auth/hap_srp.py)). A new sender does better than that from the first version, because retrofitting a check that has to fail closed means changing behaviour users have already come to rely on.

### M5 and M6, the long-term identities

M5 and M6 exchange long-term Ed25519 identities and run on the PIN path only.

The key that encrypts them is derived with HKDF-SHA-512 over `K`, 32 bytes out (reported confirmed for every string below, [Apple, `HAPPairingPairSetup.c`](https://github.com/apple/HomeKitADK/blob/master/HAP/HAPPairingPairSetup.c)).

```text
SessionKey      = HKDF-SHA512( salt = "Pair-Setup-Encrypt-Salt",
                               info = "Pair-Setup-Encrypt-Info",
                               ikm  = K, length = 32 )

ControllerX     = HKDF-SHA512( salt = "Pair-Setup-Controller-Sign-Salt",
                               info = "Pair-Setup-Controller-Sign-Info",
                               ikm  = K, length = 32 )

AccessoryX      = HKDF-SHA512( salt = "Pair-Setup-Accessory-Sign-Salt",
                               info = "Pair-Setup-Accessory-Sign-Info",
                               ikm  = K, length = 32 )
```

The salt and info strings are passed without their terminating zero byte, so `Pair-Setup-Encrypt-Salt` is 23 bytes and not 24. Apple's own code strips it explicitly (reported confirmed, [Apple, `HAPPairingPairSetup.c`](https://github.com/apple/HomeKitADK/blob/master/HAP/HAPPairingPairSetup.c)).

M5 carries a TLV8 sequence encrypted with `SessionKey` under ChaCha20-Poly1305, with no additional authenticated data and the nonce `PS-Msg05`. The inner sequence holds Identifier, PublicKey and Signature. The signed material is the concatenation below, signed with the sender's long-term Ed25519 secret (reported confirmed for the field order, [Apple, `HAPPairingPairSetup.c`](https://github.com/apple/HomeKitADK/blob/master/HAP/HAPPairingPairSetup.c)).

```text
iOSDeviceInfo = ControllerX (32 bytes) | iOSDevicePairingID | iOSDeviceLTPK (32 bytes)
```

`iOSDevicePairingID` is a UUID in its lowercase text form, used as raw bytes (reported likely, [airplay2-sender-cpp, `raop_sender.cpp`](https://github.com/akustikrausch/airplay2-sender-cpp)). `iOSDeviceLTPK` is the Ed25519 public key derived from the sender's 32-byte seed.

M6 carries the mirror image, encrypted with the same `SessionKey` under the nonce `PS-Msg06`. Its inner sequence holds the receiver's Identifier and its long-term public key.

```text
AccessoryInfo = AccessoryX (32 bytes) | AccessoryPairingID | AccessoryLTPK (32 bytes)
```

M6's signature is made with the receiver's long-term secret and verified against `AccessoryLTPK`, which the sender also finds in the `pk` TXT key. Both values are stored, because pair-verify needs them and because storing them is what lets a later session skip the PIN entirely (reported confirmed for the material, [Apple, `HAPPairingPairSetup.c`](https://github.com/apple/HomeKitADK/blob/master/HAP/HAPPairingPairSetup.c), and reported likely for the reuse, [airplay2-sender-cpp](https://github.com/akustikrausch/airplay2-sender-cpp)).

A fourth nonce, `PS-Msg04`, exists and belongs to the MFi hardware-authentication variant, which an ordinary sender does not use (reported confirmed, same source).

That stored pairing is what an Apple sender relies on. Not one `POST /pair-setup` appeared in any measured session, because the devices involved had paired before (measured 2026-09-22, captured, F-022).

## Transient pairing

Transient pairing exists so a sender can get an encrypted session without a user ever typing anything. It is requested by setting Flags to 0x10 in M1 and it stops at M4. There is no M5, no M6, no long-term identity and no pair-verify (reported confirmed, [openairplay, HomeKit Based Pairings](https://openairplay.github.io/airplay-spec/pairing/hkp.html)).

That leaves the SRP session key `K` as the session's shared secret, and `K` is 64 bytes.

An AirPlay receiver wants the ordinary `Control-Salt` derivation over the full 64 bytes, with nothing truncated. The transient path and the pair-verify path derive the channel keys identically, and the only thing transient pairing changes is which secret goes in (reported confirmed).

Four implementations say so and none disagrees. A receiver hard-codes the salt `Control-Salt` with the info strings `Control-Read-Encryption-Key` and `Control-Write-Encryption-Key`, and on transient completion it feeds the raw SRP session key straight into them, unmodified and 64 bytes long (reported confirmed, [openairplay, `airplay2-receiver`, `ap2/pairing/hap.py`](https://github.com/openairplay/airplay2-receiver/blob/master/ap2/pairing/hap.py)). pyatv's own receiver double does the same, using one pair of strings for both paths (reported confirmed, [pyatv, `pyatv/protocols/airplay/server_auth.py`](https://github.com/postlund/pyatv/blob/master/pyatv/protocols/airplay/server_auth.py)). The pairing library behind owntone's sender holds a single key table for both its normal and its transient client, and its header states outright that the shared secret is 32 bytes after a normal pairing and 64 after a transient one (reported confirmed, [pair_ap, `pair_homekit.c` and `pair.h`](https://github.com/ejurgensen/pair_ap/blob/master/pair_homekit.c)). owntone passes that 64-byte secret on at its full length (reported confirmed, [owntone, `src/outputs/airplay.c`](https://github.com/owntone/owntone-server/blob/master/src/outputs/airplay.c)).

A different derivation called `SplitSetupSalt` turns up in Apple's HomeKit accessory library and belongs to a different protocol. That library pairs an accessory to a HomeKit controller over HAP rather than over AirPlay's RTSP endpoints, and its own non-transient path uses `Control-Salt` with the same two info strings. So the AirPlay strings are the HomeKit strings, and the split-setup names exist only for HomeKit's own transient shortcut (reported confirmed as a statement about those files, [Apple, `HAPPairingPairSetup.c`](https://github.com/apple/HomeKitADK/blob/master/HAP/HAPPairingPairSetup.c) and [`HAPPairingPairVerify.c`](https://github.com/apple/HomeKitADK/blob/master/HAP/HAPPairingPairVerify.c)). No AirPlay implementation examined references `SplitSetupSalt` at all.

The one place the 64-byte length does matter is the audio key, which is clamped to 32 bytes and not derived. <doc:Protocol-Session> covers that clamp where it lives, under `shk`.

## Pair-verify

Pair-verify runs on the PIN path after pair-setup, and on every later reconnection using the stored long-term keys. It is an X25519 key agreement authenticated on both sides with Ed25519. Every message is a `POST /pair-verify` with a TLV8 body (reported confirmed for the message shape, [Apple, `HAPPairingPairVerify.c`](https://github.com/apple/HomeKitADK/blob/master/HAP/HAPPairingPairVerify.c)).

| Message | Direction | TLV8 contents |
|---|---|---|
| M1 | sender to receiver | State = 1, PublicKey = the sender's ephemeral X25519 public key, 32 bytes. |
| M2 | receiver to sender | State = 2, PublicKey = the receiver's ephemeral X25519 public key, EncryptedData. |
| M3 | sender to receiver | State = 3, EncryptedData. |
| M4 | receiver to sender | State = 4. |

The shared secret is the raw X25519 agreement output, 32 bytes. From it comes the key that protects M2 and M3 (reported confirmed, same source).

```text
VerifyKey = HKDF-SHA512( salt = "Pair-Verify-Encrypt-Salt",
                         info = "Pair-Verify-Encrypt-Info",
                         ikm  = X25519 shared secret, length = 32 )
```

M2's EncryptedData is decrypted with `VerifyKey` under the nonce `PV-Msg02` and no additional data. It contains the receiver's Identifier and a Signature, and that signature is verified against the receiver's long-term public key over these bytes (reported confirmed, same source).

```text
AccessoryCvPK (32 bytes) | AccessoryPairingID | iOSDeviceCvPK (32 bytes)
```

M3's EncryptedData is encrypted with `VerifyKey` under the nonce `PV-Msg03`. It contains the sender's Identifier and its signature over the mirror-image concatenation (reported confirmed, same source).

```text
iOSDeviceCvPK (32 bytes) | iOSDevicePairingID | AccessoryCvPK (32 bytes)
```

Apple's implementation also defines a pair-resume path, with the nonces `PR-Msg01` and `PR-Msg02`, the info strings `Pair-Resume-Request-Info`, `Pair-Resume-Response-Info` and `Pair-Resume-Shared-Secret-Info`, and a session identifier derived under `Pair-Verify-ResumeSessionID-Salt` and `Pair-Verify-ResumeSessionID-Info` (reported confirmed that the mechanism exists, same source). Whether AirPlay receivers accept pair-resume, and whether a sender gains anything from it, is open: sending a resume request to an Apple TV that has pair-verified once and reading its answer settles it.

## The encrypted control channel

From the moment pair-verify M3 is sent, or from M4 on the transient path, every byte on the control connection is encrypted. The very next request is already encrypted, and sending it in the clear makes an Apple TV close the socket almost immediately (reported confirmed as observed behaviour, [airplay2-sender-cpp, README](https://github.com/akustikrausch/airplay2-sender-cpp)). The same boundary is where a capture stops being readable: everything up to pair-verify is in the clear, and nothing after it is (measured 2026-09-22, captured, F-020).

The framing is HomeKit's (reported confirmed, [openairplay, HomeKit Based Pairings](https://openairplay.github.io/airplay-spec/pairing/hkp.html)).

```text
+--------+--------+----------------------------+------------------+
| len lo | len hi |   ciphertext (len bytes)   |  Poly1305 tag    |
|        |        |                            |    (16 bytes)    |
+--------+--------+----------------------------+------------------+
  16-bit little-endian plaintext length
```

The two length bytes are the additional authenticated data for the AEAD. The plaintext is chunked so that no frame carries more than 1024 bytes (reported likely, [airplay2-sender-cpp, README](https://github.com/akustikrausch/airplay2-sender-cpp); the openairplay page states the framing and not the chunk size).

The nonce is 12 bytes: four zero bytes, then a 64-bit counter in little-endian order. The counter starts at zero and increases by one per frame. The two directions keep separate counters (reported confirmed, [openairplay, HomeKit Based Pairings](https://openairplay.github.io/airplay-spec/pairing/hkp.html)).

```text
nonce = 00 00 00 00 | counter as 8 bytes little-endian
```

Never reuse a counter value with the same key. ChaCha20-Poly1305 loses all of its guarantees on a repeat, and a sender that resets a counter without rekeying has broken its own session confidentiality.

Both keys are HKDF-SHA-512 over the pairing shared secret, 32 bytes out. That secret is the X25519 agreement output after pair-verify, and the SRP session key `K` after transient pairing (reported confirmed, [openairplay, HomeKit Based Pairings](https://openairplay.github.io/airplay-spec/pairing/hkp.html) and [Apple, `HAPPairingPairVerify.c`](https://github.com/apple/HomeKitADK/blob/master/HAP/HAPPairingPairVerify.c)).

```text
ControlWrite = HKDF-SHA512( "Control-Salt", "Control-Write-Encryption-Key", secret, 32 )
ControlRead  = HKDF-SHA512( "Control-Salt", "Control-Read-Encryption-Key",  secret, 32 )
```

The names are written from the controller's point of view, which is the sender's. The sender encrypts with `ControlWrite` and decrypts with `ControlRead`. A receiver such as shairport-sync sees them the other way round, because it is the accessory.

## The event channel, and why the session dies without it

The session-level SETUP response gives the sender an `eventPort`. The sender opens a second TCP connection to the receiver on that port. The receiver then pushes RTSP requests down it, such as `POST /command` carrying an `updateInfo` payload, and the sender answers each one (reported confirmed as observed behaviour against an Apple TV, [airplay2-sender-cpp, README](https://github.com/akustikrausch/airplay2-sender-cpp)).

This connection is the keep-alive. An Apple TV tears the whole session down roughly 25 to 30 seconds after RECORD unless the sender is decrypting these pushed events and answering them. `POST /feedback` on the control channel is not a substitute (reported confirmed as observed behaviour, same source).

The framing is identical to the control channel: two little-endian length bytes as additional data, ciphertext, a 16-byte tag, and a 12-byte nonce of four zero bytes and an 8-byte little-endian counter, with independent counters per direction.

The keys come from the same shared secret under a different salt, and they are swapped relative to the control channel, because the event channel is a connection in the opposite direction (reported likely, [airplay2-sender-cpp, README and `raop_sender.cpp`](https://github.com/akustikrausch/airplay2-sender-cpp)).

```text
EventsWrite = HKDF-SHA512( "Events-Salt", "Events-Write-Encryption-Key", secret, 32 )
EventsRead  = HKDF-SHA512( "Events-Salt", "Events-Read-Encryption-Key",  secret, 32 )

decrypt the receiver's pushed events with EventsWrite
encrypt the sender's responses      with EventsRead
```

The response has to be minimal. This is the single most expensive detail in the protocol to get wrong, because getting it wrong produces a session that stays connected and plays nothing at all.

```text
RTSP/1.0 200 OK
Server: AirTunes/550.10
CSeq: <echoed from the request, when the request carried one>

```

Adding `Content-Length: 0` or `Audio-Latency: 0` to that response corrupts the receiver's realtime timeline, and the result is a live session that renders silence (reported confirmed as observed behaviour and named there as the final cause of a long-running silent-playback defect, [airplay2-sender-cpp, README](https://github.com/akustikrausch/airplay2-sender-cpp)).

The measurement neither confirms nor contradicts any of this. The event channel is a separate TCP connection, and what was read was the control channel of one receiver, so an event connection would not have appeared in it either way (measured 2026-09-22, decrypted, F-028).
