# The AirPlay 2 audio sender protocol

## What this document is for

This is the protocol reference a Swift AirPlay 2 **sender** is written from. It covers what a sender has to put on the wire to find a receiver, pair with it, encrypt the session, set up an audio stream, send audio, keep the session alive, and hold several receivers in step. It targets macOS and Linux, and multi-room playback to several speakers at once is treated as a first-class case rather than an extension.

Every claim carries the source it came from, at the place the claim is made. Every claim also carries one of three confidence markings.

| Marking | Meaning |
|---|---|
| **confirmed** | A primary source states it outright. Apple's own published code or documentation, an RFC, or a working implementation whose author states it as measured behaviour. |
| **likely** | Two independent sources agree and neither is authoritative, or one source states it and a second implementation behaves consistently with it. |
| **open** | Unsettled. Sources disagree, or no source states it, or it is stated once without corroboration. |

An open question written down is worth more than a plausible guess, so the open items are collected at the end with a note on what would settle each one.

## What this document deliberately does not cover

AirPlay video, screen mirroring, and photo streaming are out of scope. So is the receiver side: nothing here describes what a receiver must do beyond what a sender needs to predict of it. FairPlay (`et=3`, `et=5`) and the MFi authentication chain are named where they appear in a TXT record, but the FairPlay handshake itself is not described, because it needs Apple key material that a clean-room sender does not have. AirPlay 1 is covered only where the AirPlay 2 path inherits from it, which is most of the RTP layer and all of the timing layer.

Legal note on provenance. Everything here is a protocol fact: a field name, a byte layout, a constant, a message order. No source code has been copied from any project, and in particular none from a GPL or AGPL project.

## Discovery

### The two Bonjour services

A receiver advertises itself with multicast DNS. Two service types matter to an audio sender, and a modern receiver publishes both ([openairplay, Service Discovery](https://openairplay.github.io/airplay-spec/service_discovery.html), **confirmed**).

| Service | Usual port | What it is for |
|---|---|---|
| `_raop._tcp` | 49152 and upwards | Remote Audio Output Protocol. The audio service. Its instance name is the receiver's MAC address without separators, then `@`, then the display name, for example `5855CA1AE288@Apple TV`. |
| `_airplay._tcp` | 7000 | The general AirPlay service. On AirPlay 2 it carries the capability bitfield and the pairing public key. |

Take the port from the SRV record rather than assuming it. Port 7000 for `_airplay._tcp` is usual but not guaranteed, and the `_raop._tcp` port is allocated from the ephemeral range and changes between reboots ([openairplay, Service Discovery](https://openairplay.github.io/airplay-spec/service_discovery.html), **confirmed**).

A sender must ignore TXT keys it does not know, and must not assume any given key is present. The record is extensible and Apple has added keys across releases ([openairplay, Service Discovery](https://openairplay.github.io/airplay-spec/service_discovery.html), **confirmed**).

### The `_raop._tcp` TXT keys

A representative record from an Apple TV 2 reads as follows ([openairplay, Service Discovery](https://openairplay.github.io/airplay-spec/service_discovery.html), **confirmed**).

```text
txtvers=1 ch=2 cn=0,1,2,3 da=true et=0,3,5 md=0,1,2 pw=false sv=false
sr=44100 ss=16 tp=UDP vn=65537 vs=130.14 am=AppleTV2,1 sf=0x4
```

| Key | Example | Meaning | Confidence |
|---|---|---|---|
| `txtvers` | `1` | Version of the TXT record format. | confirmed |
| `ch` | `2` | Audio channel count. | confirmed |
| `cn` | `0,1,2,3` | Codecs the receiver accepts, as a comma-separated list. `0` is PCM, `1` is Apple Lossless, `2` is AAC, `3` is AAC ELD, and [pyatv](https://pyatv.dev/documentation/protocols/) adds `4` for Opus. | confirmed |
| `et` | `0,3,5` | Encryption types the receiver accepts. `0` is none, `1` is RSA, `3` is FairPlay, `4` is MFiSAP, `5` is FairPlay SAPv2.5. The same five values appear in [pyatv's own table](https://pyatv.dev/documentation/protocols/#raop), with `1` noted as the AirPort Express case. | confirmed |
| `md` | `0,1,2` | Metadata kinds the receiver accepts. `0` is text, `1` is artwork, `2` is progress. | confirmed |
| `pw` | `false` | Whether the receiver is password protected. On older receivers the key is present only when a password is set. | confirmed |
| `sr` | `44100` | Sample rate in hertz. | confirmed |
| `ss` | `16` | Sample size in bits. | confirmed |
| `tp` | `UDP` | Transport for the audio stream. | confirmed |
| `vs` | `130.14` | Server version, the AirTunes build. | confirmed |
| `vn` | `65537` | Version number. | confirmed |
| `am` | `AppleTV2,1` | Device model. | confirmed |
| `da` | `true` | The receiver accepts RFC 2617 digest authentication. Apple's own sender reads the key into a boolean it calls `rfc2617DigestAuthKey` ([Cozzi, Service discovery](https://web.archive.org/web/20220214214811/https://emanuelecozzi.net/docs/airplay2/discovery/)). pyatv does not consume it. | likely |
| `sv` | `false` | No primary source states its semantics. | open |
| `sf` | `0x4` | Status flags. See the table below. | confirmed |
| `pk` | 64 hex characters | The receiver's Ed25519 long-term public key, 32 bytes hex encoded. Present on AirPlay 2 receivers. | confirmed |
| `flags` | `0x404` | The AirPlay 2 spelling of `sf`, seen on `_airplay._tcp`. | likely |
| `features` | `0x445F8A00,0x1C340` | The capability bitfield. See below. | confirmed |

A second table of the same records exists, recovered from Apple's own sender, and it gives the name the sender reads each key into. It settles `da` as a boolean called `rfc2617DigestAuthKey`, and it carries three keys the table above does not: `ft` is the features bitfield in its `_raop._tcp` spelling, `ov` is the OS version, and `vv` is a number it calls the vodka version. `sv` appears in neither table, so it stays **open** ([Cozzi, Service discovery](https://web.archive.org/web/20220214214811/https://emanuelecozzi.net/docs/airplay2/discovery/), **likely**).

### The `_airplay._tcp` TXT keys

| Key | Meaning | Confidence |
|---|---|---|
| `deviceid` | The receiver's MAC address, colon separated. | confirmed |
| `features` | The 64-bit capability bitfield. | confirmed |
| `flags` | The status flags, the same 20-bit value that `_raop._tcp` calls `sf`. | likely |
| `model` | Device model, for example `AppleTV2,1`. | confirmed |
| `srcvers` | AirPlay source version. | confirmed |
| `pk` | The receiver's Ed25519 long-term public key as hex. | confirmed |
| `pi`, `psi`, `gid` | Pairing and group identifiers, written as UUIDs. | confirmed |
| `manufacturer`, `serialNumber`, `fv`, `osvers`, `protovers`, `acl`, `hmid`, `rsf` | Descriptive or access-control fields a sender does not need for audio. | confirmed |

Source for the whole table: [openairplay, Service Discovery](https://openairplay.github.io/airplay-spec/service_discovery.html).

### The `features` bitfield

`features` is a 64-bit bitmask written as two 32-bit hexadecimal values separated by a comma. The value before the comma is the low word, holding bits 0 to 31. The value after it is the high word, holding bits 32 to 63. Both the comma and the high word are optional, because the field was 32 bits originally and was widened later ([openairplay, Service Discovery](https://openairplay.github.io/airplay-spec/service_discovery.html), **confirmed**).

To test bit 40, take the high word and test its bit 8, because 40 minus 32 is 8.

These are the bits an audio sender reads ([openairplay, Features](https://openairplay.github.io/airplay-spec/features.html), **confirmed** for the names, and see the pairing section for what each one implies).

| Bit | Name |
|---|---|
| 9 | Audio |
| 11 | AudioRedundant |
| 18 to 21 | AudioFormat1 to AudioFormat4 |
| 27 | SupportsLegacyPairing |
| 30 | RAOP |
| 32 | IsCarPlay, also read as SupportsVolume |
| 38 | SupportsCoreUtilsPairingAndEncryption |
| 40 | SupportsBufferedAudio |
| 41 | SupportsPTP |
| 43 | SupportsSystemPairing |
| 46 | SupportsHKPairingAndAccessControl |
| 48 | SupportsTransientPairing |
| 51 | SupportsUnifiedPairSetupAndMFi |
| 52 | SupportsSetPeersExtendedMessage |

Two of these carry a note in the specification's own source that the rendered page drops. Bits 40 and 41, SupportsBufferedAudio and SupportsPTP, are each annotated as the bit "needed for device to show as supporting multi-room audio" ([openairplay, `src/features.md`](https://raw.githubusercontent.com/openairplay/airplay-spec/master/src/features.md), **confirmed**). That is the clearest published statement of what multi-room needs, and it names both bits rather than either one alone.

**The bit names are not settled, and a sender does not need them to be.** Three published tables of this field exist, and they disagree about names whilst agreeing about numbers. openairplay calls bit 38 `SupportsCoreUtilsPairingAndEncryption` and bit 48 `SupportsTransientPairing`. pyatv swaps those two names round, and its own comment says there "seems to be some inconsistencies" in the published tables ([pyatv, `pyatv/protocols/airplay/utils.py`](https://github.com/postlund/pyatv/blob/master/pyatv/protocols/airplay/utils.py), **confirmed** as a description of pyatv). The third table was recovered from Apple's own sender by reverse engineering, and it agrees with pyatv: bit 38 is `SupportsUnifiedMediaControl` and bit 48 is `SupportsCoreUtilsPairingAndEncryption` ([Cozzi, Features](https://web.archive.org/web/20220214214810/https://emanuelecozzi.net/docs/airplay2/features/), **likely**).

What settles the question is that neither property is a single bit. Cozzi's table carries a condition beside each name, and the two that matter read `48 || 43` for transient pairing and `38 || 46 || 43 || 48` for CoreUtils pairing and encryption, so transient pairing is not a bit at all but a property derived from two of them. openairplay's raw source says the same thing from the other side. Its note on bit 48 reads that `SupportsSystemPairing` implies `SupportsTransientPairing`, and its note on bit 38 reads that `SupportsHKPairingAndAccessControl`, `SupportsSystemPairing` and `SupportsTransientPairing` each imply `SupportsCoreUtilsPairingAndEncryption` ([openairplay, `src/features.md`](https://raw.githubusercontent.com/openairplay/airplay-spec/master/src/features.md), **confirmed**). Compute the derived property over all four bits and the naming disagreement stops mattering, which is what pyatv does in code.

Cozzi's table also gives the minimal set a receiver must declare for multi-room audio as bits 9, 11, 30, 40, 41, and 51, which is `features=0x40000a00,0x80300` (**likely**). And it makes volume support the **absence** of bit 32 rather than its presence, because bit 32 set means CarPlay, so it gates both `SupportsVolume` and `SupportsInitialVolume` on that bit being clear.

The same tables classify a receiver by kind. A `model` beginning with `AppleTV` is an Apple TV and one beginning with `AudioAccessory` is a HomePod. A receiver is a third-party speaker when bit 26 or bit 51 is set, and a third-party television when it sets bit 0 or bit 49 as well ([Cozzi, Features](https://web.archive.org/web/20220214214810/https://emanuelecozzi.net/docs/airplay2/features/), **likely**). Bit 26 is where the two tables part company hardest, since openairplay calls it `HasUnifiedAdvertiserInfo` and puts `RAOP` at bit 30, whilst Cozzi calls bit 26 MFi authentication and puts `HasUnifiedAdvertiserInfo` at bit 30. The condition is the same pair of bits either way.

### The `sf` and `flags` status bits

`sf` on `_raop._tcp`, and `flags` on `_airplay._tcp`, hold a 20-bit status value. Each bit is a state rather than a capability ([openairplay, Status Flags](https://openairplay.github.io/airplay-spec/status_flags.html), **confirmed**).

| Bit | Name |
|---|---|
| 0 | Problem Detected |
| 1 | Not Configured |
| 2 | Audio Cable Attached |
| 3 | PIN Required |
| 6 | SupportsAirPlayFromCloud |
| 7 | Password Required |
| 9 | OneTimePairingRequired |
| 10 | DeviceWasSetupForHKAccessControl |
| 11 | DeviceSupportsRelay |
| 12 | SilentPrimary |
| 13 | TightSyncIsGroupLeader |
| 14 | TightSyncBuddyNotReachable |
| 15 | IsAppleMusicSubscriber |
| 16 | CloudLibraryIsOn |
| 17 | ReceiverSessionIsActive |

Bits 4, 5, 8, 18, and 19 have no documented meaning.

Two values turn up constantly in the wild and both decompose cleanly against this table.

```text
sf=0x4   = bit 2                       Audio Cable Attached
sf=0x644 = bits 2, 6, 9, 10            Audio Cable Attached,
                                       SupportsAirPlayFromCloud,
                                       OneTimePairingRequired,
                                       DeviceWasSetupForHKAccessControl
```

Bit 9 is the one that says pairing is needed at all. A receiver advertising `sf=0x4` sets no pairing bit, and shairport-sync's classic AirPlay build publishes exactly that value whilst requiring no pairing whatsoever ([shairport-sync, `bonjour_strings.c`](https://github.com/mikebrady/shairport-sync/blob/master/bonjour_strings.c), **confirmed**).

**What bit 9 asks for is not settled.** Its published name, `OneTimePairingRequired`, reads either way: as a one-off transient pairing, or as a pairing done once and stored. pyatv calls the same bit the legacy-pairing bit and treats it, together with bit 3 `PINRequired`, as meaning only that pairing is mandatory ([pyatv, `pyatv/protocols/airplay/utils.py`](https://github.com/postlund/pyatv/blob/master/pyatv/protocols/airplay/utils.py), **confirmed** as a description of pyatv). A working sender treats `sf=0x644` as the Apple TV PIN case ([airplay2-sender-cpp, README](https://github.com/akustikrausch/airplay2-sender-cpp), **likely**). Read bit 9 as "this receiver needs pairing" and take the kind from `features`, which is what the next section does. The bit arithmetic itself is exact; only the reading of the name is **open**.

### Deciding how to reach a receiver

The decision a sender has to make from the TXT records is which authentication path to run. The mapping below is what a working sender uses ([airplay2-sender-cpp, `raop_auth.h`](https://github.com/akustikrausch/airplay2-sender-cpp), **likely**).

| Observation | Path |
|---|---|
| `pw=true`, or status bit 7 Password Required | RTSP digest authentication, reactive on the first 401 response. |
| `am` beginning with `AirPort` | `POST /auth-setup`, the MFiSAP one-shot. |
| `features` bit 46 SupportsHKPairingAndAccessControl set, and status bit 9 OneTimePairingRequired set | HomeKit pairing with the on-screen PIN, then pair-verify. |
| `features` bit 43 or bit 48 set, which is the derived transient-pairing property, and no pairing status bit set | HomeKit transient pairing, no user interaction. |
| None of the above | Plain AirPlay 1 RTSP with no authentication. |

pyatv makes the same decision from the same two fields and states its rules exactly, which is worth having beside the table above because the two agree on substance and differ on naming ([pyatv, `pyatv/protocols/airplay/utils.py`](https://github.com/postlund/pyatv/blob/master/pyatv/protocols/airplay/utils.py) and [`pyatv/protocols/airplay/auth/__init__.py`](https://github.com/postlund/pyatv/blob/master/pyatv/protocols/airplay/auth/__init__.py), **confirmed** as a description of pyatv).

pyatv reads `sf` first and falls back to `flags`. A set bit 7, value 0x80, means a password is required. A set bit 9, value 0x200, or a set bit 3, value 0x8, means pairing is mandatory. pyatv names bit 9 the legacy-pairing bit whilst openairplay names it `OneTimePairingRequired`, which is a naming disagreement rather than a behavioural one, since both readings lead a sender to pair.

pyatv decides AirPlay 2 against AirPlay 1 from `features`, treating the receiver as AirPlay 2 when its bit 38 or its bit 48 is set, and its own comment says openly that this is a guess rather than a known rule (**open**). It then chooses transient pairing when bit 43 `SupportsSystemPairing` or bit 48 is set, and no pairing at all otherwise.

A sender must also be ready for the receiver to disagree with its reading of the TXT record, because the record can be stale and the access policy can change without it. Two recoveries are worth building in ([airplay2-sender-cpp, `raop_sender.cpp`](https://github.com/akustikrausch/airplay2-sender-cpp), **likely**).

A transient pair-setup that is answered with HTTP 470 means the receiver refuses transient pairing and wants a PIN. The sender restarts on the PIN path. A `POST /pair-pin-start` answered with HTTP 403 means the receiver has no on-screen PIN to show, which is what a macOS AirPlay receiver does, so the sender tries transient pairing once instead.

## HomeKit pairing

AirPlay 2 authenticates with the HomeKit Accessory Protocol pairing exchange. The sender plays the part HomeKit calls the controller, and the receiver plays the accessory. There are two phases, and which of them run depends on the receiver.

The messages are carried as HTTP `POST` requests on the same TCP connection that later carries RTSP, with `Content-Type: application/octet-stream` and a TLV8 body ([openairplay, HomeKit Based Pairings](https://openairplay.github.io/airplay-spec/pairing/hkp.html), **confirmed**).

### TLV8

TLV8 is a flat sequence of records. Each record is one type byte, one length byte, and that many value bytes. There is no nesting at the wire level, although a decrypted value is often itself a TLV8 sequence. A value longer than 255 bytes is split into consecutive records carrying the same type byte, and the reader joins them back together. This matters for the SRP public key, which is 384 bytes and therefore always arrives in two records.

These are the type numbers, from Apple's own HomeKit accessory implementation ([Apple, `HomeKitADK/HAP/HAPPairing.h`](https://github.com/apple/HomeKitADK/blob/master/HAP/HAPPairing.h), **confirmed**).

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
| 0x13 | Flags |
| 0xFF | Separator |

The Error type carries one of these codes ([Apple, `HomeKitADK/HAP/HAPPairing.h`](https://github.com/apple/HomeKitADK/blob/master/HAP/HAPPairing.h), **confirmed**).

| Value | Name |
|---|---|
| 0x01 | Unknown |
| 0x02 | Authentication |
| 0x03 | Backoff |
| 0x04 | MaxPeers |
| 0x05 | MaxTries |
| 0x06 | Unavailable |
| 0x07 | Busy |

pyatv carries one more type that Apple's accessory header does not list, `Name` at 0x11, which it marks as Apple-internal, and it enumerates the Method values: `PairSetup` is 0x00, `PairSetupWithAuth` is 0x01, `PairVerify` is 0x02, `AddPairing` is 0x03, `RemovePairing` is 0x04, and `ListPairing` is 0x05 ([pyatv, `pyatv/auth/hap_tlv8.py`](https://github.com/postlund/pyatv/blob/master/pyatv/auth/hap_tlv8.py), **confirmed**).

### The `X-Apple-HKP` header

Every pairing request carries an `X-Apple-HKP` header saying which pairing mode the sender wants. A working sender sends `4` for transient pairing and `3` for pairing with a PIN ([airplay2-sender-cpp, `raop_sender.cpp`](https://github.com/akustikrausch/airplay2-sender-cpp), **likely**). The openairplay specification names mode `4` as the transient mode used by HomePod and AirPort Express ([openairplay, HomeKit Based Pairings](https://openairplay.github.io/airplay-spec/pairing/hkp.html), **likely**).

One receiver enumerates the whole set in its own source ([openairplay, `airplay2-receiver`, `ap2-receiver.py`](https://github.com/openairplay/airplay2-receiver/blob/master/ap2-receiver.py), **confirmed** as a statement about that implementation).

| Value | Name it gives |
|---|---|
| 0 | Unauthenticated, for a receiver advertising neither transient nor system pairing. |
| 2 | Pair-setup is complete and pair-verify begins. |
| 3 | System pairing, which it ties to `features` bit 43. |
| 4 | Transient pairing. |
| 6 | HomeKit. |
| 7 | HomeKit administration. |

That receiver defines the constant and never reads it back, so the list documents what the values mean rather than what it enforces. pyatv labels `3` as HAP and `4` as transient, and it answers a `/pair-verify` that carries no such header with a 501 ([pyatv, `pyatv/protocols/airplay/server_auth.py`](https://github.com/postlund/pyatv/blob/master/pyatv/protocols/airplay/server_auth.py), **confirmed** as a description of pyatv). owntone picks between `3` and `4` on exactly the same split, normal against transient ([owntone, `src/outputs/airplay.c`](https://github.com/owntone/owntone-server/blob/master/src/outputs/airplay.c), **confirmed**).

Which value the PIN path wants is the part still **open**. Three senders send `3` there and it works, whilst the receiver's own list reserves `3` for system pairing and puts HomeKit at `6`. Send `3` for the PIN and `4` for transient, because that is what every working sender does.

Alongside `X-Apple-HKP`, a pairing request carries the sender's identity headers, and a receiver's access-control gate reads them before it reads the TLV body. Sending them matters: their absence is a documented cause of a 403 response ([airplay2-sender-cpp, `raop_sender.cpp`](https://github.com/akustikrausch/airplay2-sender-cpp), **likely**).

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

`Client-Instance` carries the same value as `DACP-ID`. Both are random per session: `DACP-ID` is a 64-bit value written as uppercase hexadecimal without leading zeros, and `Active-Remote` is a random 32-bit decimal number ([airplay2-sender-cpp, `raop_sender.cpp`](https://github.com/akustikrausch/airplay2-sender-cpp), **likely**).

### Making the PIN appear

On the PIN path, an Apple TV renders its four-digit code only after it receives an empty `POST /pair-pin-start`. Sending pair-setup M1 on its own returns the SRP material without ever putting a code on the screen, so the user waits for something that never appears ([airplay2-sender-cpp, `raop_sender.cpp`](https://github.com/akustikrausch/airplay2-sender-cpp), **likely**, and the same behaviour is what pyatv's pairing start and owntone's pin-start payload both do).

### Pair-setup, M1 to M6

Pair-setup runs SRP-6a. The client is the sender.

The group is the 3072-bit group from [RFC 5054](https://www.rfc-editor.org/rfc/rfc5054.txt), whose generator is `g = 5` (**confirmed**). The hash is SHA-512 rather than the SHA-1 that RFC 5054 uses in its own examples ([Apple, `HomeKitADK/HAP/HAPPairingPairSetup.c`](https://github.com/apple/HomeKitADK/blob/master/HAP/HAPPairingPairSetup.c), **confirmed**). The SRP user name is the literal string `Pair-Setup` (**confirmed**, same source). The password is the PIN: the four digits on the receiver's screen on the PIN path, and the fixed string `3939` on the transient path ([openairplay, HomeKit Based Pairings](https://openairplay.github.io/airplay-spec/pairing/hkp.html), **confirmed** for the value `3939`).

RFC 5054 defines `PAD()` as left-padding a value with zero bytes until its length equals the length of `N`, which for the 3072-bit group is 384 bytes ([RFC 5054](https://www.rfc-editor.org/rfc/rfc5054.txt), **confirmed**). HomeKit applies that padding to the operands of `k` and `u`, and not to the operands of `x` or to `S` ([airplay2-sender-cpp, `airplay_crypto.cpp`](https://github.com/akustikrausch/airplay2-sender-cpp), cross-checked there against `ejurgensen/pair_ap`, **likely**).

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

SRP literature calls those two proofs M1 and M2, which collides with the HomeKit message numbers M1 to M6. They are named `clientProof` and `serverProof` here so the two never have to be told apart from context.

`K` is 64 bytes, because SHA-512 produces 64 bytes. That length matters later, in the audio key.

The message flow is as follows. Every message is a `POST /pair-setup` with a TLV8 body, and the State type carries the message number.

| Message | Direction | TLV8 contents |
|---|---|---|
| M1 | sender to receiver | State = 1, Method = 0. On the transient path, additionally Flags = 0x10. |
| M2 | receiver to sender | State = 2, Salt, PublicKey = B. Or State = 2 and Error. |
| M3 | sender to receiver | State = 3, PublicKey = A, Proof = clientProof. |
| M4 | receiver to sender | State = 4, Proof = serverProof. Or State = 4 and Error. |
| M5 | sender to receiver | State = 5, EncryptedData. |
| M6 | receiver to sender | State = 6, EncryptedData. |

Flags value 0x10 in M1 is the transient pairing flag ([airplay2-sender-cpp, `raop_sender.cpp`](https://github.com/akustikrausch/airplay2-sender-cpp), **likely**).

The sender must check the `serverProof` carried in message M4 against its own computation of it, in constant time. Failing to check it means the receiver is never authenticated, and a machine on the same network can accept the session and take the audio ([airplay2-sender-cpp, `SECURITY.md`](https://github.com/akustikrausch/airplay2-sender-cpp), **confirmed** that this is the consequence).

pyatv does not perform this check, nor does it verify the receiver's Ed25519 signature in M6 or the pair-verify response in M4 ([pyatv, `pyatv/auth/hap_srp.py`](https://github.com/postlund/pyatv/blob/master/pyatv/auth/hap_srp.py), **confirmed**, its own source carries the outstanding notes). A new sender should do better than that from the first version, because retrofitting a check that has to fail closed means changing behaviour users have already come to rely on.

M5 and M6 exchange long-term Ed25519 identities and only run on the PIN path.

The key that encrypts M5 and M6 is derived with HKDF-SHA-512 over `K`, 32 bytes out ([Apple, `HomeKitADK/HAP/HAPPairingPairSetup.c`](https://github.com/apple/HomeKitADK/blob/master/HAP/HAPPairingPairSetup.c), **confirmed** for every string below).

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

The salt and info strings are passed without their terminating zero byte, so `Pair-Setup-Encrypt-Salt` is 23 bytes and not 24. Apple's own code strips it explicitly ([Apple, `HomeKitADK/HAP/HAPPairingPairSetup.c`](https://github.com/apple/HomeKitADK/blob/master/HAP/HAPPairingPairSetup.c), **confirmed**).

M5 carries a TLV8 sequence encrypted with `SessionKey` under ChaCha20-Poly1305, with no additional authenticated data and the nonce `PS-Msg05`. The inner sequence holds Identifier, PublicKey, and Signature. The signed material is the concatenation below, signed with the sender's long-term Ed25519 secret ([Apple, `HomeKitADK/HAP/HAPPairingPairSetup.c`](https://github.com/apple/HomeKitADK/blob/master/HAP/HAPPairingPairSetup.c), **confirmed** for the field order).

```text
iOSDeviceInfo = ControllerX (32 bytes) | iOSDevicePairingID | iOSDeviceLTPK (32 bytes)
```

`iOSDevicePairingID` is a UUID in its lowercase text form, used as raw bytes ([airplay2-sender-cpp, `raop_sender.cpp`](https://github.com/akustikrausch/airplay2-sender-cpp), **likely**). `iOSDeviceLTPK` is the Ed25519 public key derived from the sender's 32-byte seed.

M6 carries the mirror image, encrypted with the same `SessionKey` under the nonce `PS-Msg06`. Its inner sequence holds the receiver's Identifier and its long-term public key. Both are stored, because pair-verify needs them and because storing them is what lets a later session skip the PIN entirely ([Apple, `HomeKitADK/HAP/HAPPairingPairSetup.c`](https://github.com/apple/HomeKitADK/blob/master/HAP/HAPPairingPairSetup.c), **confirmed** for the material, and [airplay2-sender-cpp](https://github.com/akustikrausch/airplay2-sender-cpp) for the reuse, **likely**).

```text
AccessoryInfo = AccessoryX (32 bytes) | AccessoryPairingID | AccessoryLTPK (32 bytes)
```

The signed material for M6 is signed with the receiver's long-term secret and verified against `AccessoryLTPK`, which the sender also finds in the `pk` TXT key. Nonce `PS-Msg04` exists too and belongs to the MFi hardware-authentication variant, which an ordinary sender does not use ([Apple, `HomeKitADK/HAP/HAPPairingPairSetup.c`](https://github.com/apple/HomeKitADK/blob/master/HAP/HAPPairingPairSetup.c), **confirmed**).

### Transient pairing

Transient pairing exists so a sender can get an encrypted session without a user ever typing anything. It is requested by setting Flags to 0x10 in M1 and it **stops at M4**. There is no M5, no M6, no long-term identity, and no pair-verify ([openairplay, HomeKit Based Pairings](https://openairplay.github.io/airplay-spec/pairing/hkp.html), **confirmed**).

That leaves the SRP session key `K` as the session's shared secret, and `K` is 64 bytes.

**An AirPlay receiver wants the ordinary `Control-Salt` derivation, over the full 64-byte `K`, with nothing truncated.** The transient path and the pair-verify path derive the channel keys identically, and the only thing transient pairing changes is which secret goes in (**confirmed**).

Four implementations say so and none disagrees. A receiver hard-codes the salt `Control-Salt` with the info strings `Control-Read-Encryption-Key` and `Control-Write-Encryption-Key`, and on transient completion it feeds the raw SRP session key straight into them, unmodified and 64 bytes long ([openairplay, `airplay2-receiver`, `ap2/pairing/hap.py`](https://github.com/openairplay/airplay2-receiver/blob/master/ap2/pairing/hap.py), **confirmed**; its README records an iPhone X on iOS 13.3 as the sender it was tested against). pyatv's own receiver double does the same, using one pair of strings for both paths ([pyatv, `pyatv/protocols/airplay/server_auth.py`](https://github.com/postlund/pyatv/blob/master/pyatv/protocols/airplay/server_auth.py), **confirmed**). The pairing library that drives owntone's sender holds a single key table for both its normal and its transient client, and its header states outright that the shared secret is 32 bytes after a normal pairing and 64 after a transient one ([pair_ap, `pair_homekit.c` and `pair.h`](https://github.com/ejurgensen/pair_ap/blob/master/pair_homekit.c), **confirmed**). owntone passes that 64-byte secret on at its full length ([owntone, `src/outputs/airplay.c`](https://github.com/owntone/owntone-server/blob/master/src/outputs/airplay.c), **confirmed**).

The `SplitSetupSalt` derivation is real Apple code and belongs to a different protocol. It lives in the HomeKit accessory library, which pairs an accessory to a HomeKit controller over HAP rather than over AirPlay's RTSP endpoints. Its own non-transient path uses `Control-Salt` with the same two info strings, so the AirPlay strings are the HomeKit strings, and the split-setup names exist only for HomeKit's own transient shortcut ([Apple, `HomeKitADK/HAP/HAPPairingPairSetup.c`](https://github.com/apple/HomeKitADK/blob/master/HAP/HAPPairingPairSetup.c) and [`HAP/HAPPairingPairVerify.c`](https://github.com/apple/HomeKitADK/blob/master/HAP/HAPPairingPairVerify.c), **confirmed** as a statement about those files). No AirPlay implementation examined here references `SplitSetupSalt` at all.

The one place the 64-byte length does matter is the audio key, which is clamped to 32 bytes and not derived. owntone's own comment says it plainly: after a transient pairing the key is 64 bytes long, and only the first 32 are used for the audio payload. That is the same clamp the `shk` section below arrives at from the other direction.

### Pair-verify

Pair-verify runs on the PIN path after pair-setup, and on every later reconnection using the stored long-term keys. It is an X25519 key agreement authenticated on both sides with Ed25519. Every message is a `POST /pair-verify` with a TLV8 body.

| Message | Direction | TLV8 contents |
|---|---|---|
| M1 | sender to receiver | State = 1, PublicKey = the sender's ephemeral X25519 public key, 32 bytes. |
| M2 | receiver to sender | State = 2, PublicKey = the receiver's ephemeral X25519 public key, EncryptedData. |
| M3 | sender to receiver | State = 3, EncryptedData. |
| M4 | receiver to sender | State = 4. |

Source for the message shape: [Apple, `HomeKitADK/HAP/HAPPairingPairVerify.c`](https://github.com/apple/HomeKitADK/blob/master/HAP/HAPPairingPairVerify.c) (**confirmed**).

The shared secret is the raw X25519 agreement output, 32 bytes. From it comes the key that protects M2 and M3 ([Apple, `HomeKitADK/HAP/HAPPairingPairVerify.c`](https://github.com/apple/HomeKitADK/blob/master/HAP/HAPPairingPairVerify.c), **confirmed**).

```text
VerifyKey = HKDF-SHA512( salt = "Pair-Verify-Encrypt-Salt",
                         info = "Pair-Verify-Encrypt-Info",
                         ikm  = X25519 shared secret, length = 32 )
```

M2's EncryptedData is decrypted with `VerifyKey` under the nonce `PV-Msg02` and no additional data. It contains the receiver's Identifier and a Signature. That signature is verified against the receiver's long-term public key over the following bytes ([Apple, `HomeKitADK/HAP/HAPPairingPairVerify.c`](https://github.com/apple/HomeKitADK/blob/master/HAP/HAPPairingPairVerify.c), **confirmed**).

```text
AccessoryCvPK (32 bytes) | AccessoryPairingID | iOSDeviceCvPK (32 bytes)
```

M3's EncryptedData is encrypted with `VerifyKey` under the nonce `PV-Msg03`. It contains the sender's Identifier and its signature over the mirror-image concatenation ([Apple, `HomeKitADK/HAP/HAPPairingPairVerify.c`](https://github.com/apple/HomeKitADK/blob/master/HAP/HAPPairingPairVerify.c), **confirmed**).

```text
iOSDeviceCvPK (32 bytes) | iOSDevicePairingID | AccessoryCvPK (32 bytes)
```

Apple's implementation also defines a pair-resume path, with the nonces `PR-Msg01` and `PR-Msg02` and the info strings `Pair-Resume-Request-Info`, `Pair-Resume-Response-Info`, and `Pair-Resume-Shared-Secret-Info`, keyed by a session identifier derived with `Pair-Verify-ResumeSessionID-Salt` and `Pair-Verify-ResumeSessionID-Info` ([Apple, `HomeKitADK/HAP/HAPPairingPairVerify.c`](https://github.com/apple/HomeKitADK/blob/master/HAP/HAPPairingPairVerify.c), **confirmed** that the mechanism exists). Whether AirPlay receivers accept pair-resume, and whether a sender gains anything from it, is **open**.

## The encrypted control channel

### The framing

From the moment pair-verify M3 is sent, or from M4 on the transient path, every byte on the control connection is encrypted. The very next request is already encrypted, and sending it in the clear makes an Apple TV close the socket almost immediately ([airplay2-sender-cpp, README](https://github.com/akustikrausch/airplay2-sender-cpp), **confirmed** as observed behaviour).

The framing is HomeKit's ([openairplay, HomeKit Based Pairings](https://openairplay.github.io/airplay-spec/pairing/hkp.html), **confirmed**).

```text
+--------+--------+----------------------------+------------------+
| len lo | len hi |   ciphertext (len bytes)   |  Poly1305 tag    |
|        |        |                            |    (16 bytes)    |
+--------+--------+----------------------------+------------------+
  16-bit little-endian plaintext length
```

The two length bytes are the additional authenticated data for the AEAD. The plaintext is chunked so that no frame carries more than 1024 bytes ([airplay2-sender-cpp, README](https://github.com/akustikrausch/airplay2-sender-cpp), **likely**; the openairplay page states the framing but not the chunk size).

The nonce is 12 bytes: four zero bytes, then a 64-bit counter in little-endian order. The counter starts at zero and increases by one per frame. The two directions keep separate counters ([openairplay, HomeKit Based Pairings](https://openairplay.github.io/airplay-spec/pairing/hkp.html), **confirmed**).

```text
nonce = 00 00 00 00 | counter as 8 bytes little-endian
```

Never reuse a counter value with the same key. ChaCha20-Poly1305 loses all of its guarantees on a repeat, and a sender that resets a counter without rekeying has broken its own session confidentiality.

### The keys

Both keys are HKDF-SHA-512 over the pairing shared secret, 32 bytes out. The shared secret is the X25519 agreement output after pair-verify, and the SRP session key `K` after transient pairing ([openairplay, HomeKit Based Pairings](https://openairplay.github.io/airplay-spec/pairing/hkp.html) and [Apple, `HomeKitADK/HAP/HAPPairingPairVerify.c`](https://github.com/apple/HomeKitADK/blob/master/HAP/HAPPairingPairVerify.c), **confirmed**).

```text
ControlWrite = HKDF-SHA512( "Control-Salt", "Control-Write-Encryption-Key", secret, 32 )
ControlRead  = HKDF-SHA512( "Control-Salt", "Control-Read-Encryption-Key",  secret, 32 )
```

The names are written from the controller's point of view, which is the sender's point of view. The sender encrypts with `ControlWrite` and decrypts with `ControlRead`. A receiver implementation such as shairport-sync sees them the other way round, because it is the accessory.

## The event channel, and why the session dies without it

The session-level SETUP response gives the sender an `eventPort`. The sender opens a second TCP connection to the receiver on that port. The receiver then pushes RTSP requests down it, such as `POST /command` carrying an `updateInfo` payload, and the sender must answer each one ([airplay2-sender-cpp, README](https://github.com/akustikrausch/airplay2-sender-cpp), **confirmed** as observed behaviour against an Apple TV).

This connection is the keep-alive. An Apple TV tears the whole session down roughly 25 to 30 seconds after RECORD unless the sender is decrypting these pushed events and answering them. `POST /feedback` on the control channel is not a substitute ([airplay2-sender-cpp, README](https://github.com/akustikrausch/airplay2-sender-cpp), **confirmed** as observed behaviour).

The framing is identical to the control channel: two little-endian length bytes as additional data, ciphertext, 16-byte tag, 12-byte nonce of four zero bytes and an 8-byte little-endian counter, with independent counters per direction.

The keys come from the same shared secret under a different salt, and they are **swapped** relative to the control channel, because the event channel is a connection in the opposite direction ([airplay2-sender-cpp, README and `raop_sender.cpp`](https://github.com/akustikrausch/airplay2-sender-cpp), **likely**).

```text
EventsWrite = HKDF-SHA512( "Events-Salt", "Events-Write-Encryption-Key", secret, 32 )
EventsRead  = HKDF-SHA512( "Events-Salt", "Events-Read-Encryption-Key",  secret, 32 )

decrypt the receiver's pushed events with EventsWrite
encrypt the sender's responses      with EventsRead
```

The response has to be minimal. This is the single most expensive detail in the whole protocol to get wrong, because getting it wrong produces a session that stays connected and plays nothing at all.

```text
RTSP/1.0 200 OK
Server: AirTunes/550.10
CSeq: <echoed from the request, when the request carried one>

```

Adding `Content-Length: 0` or `Audio-Latency: 0` to that response corrupts the receiver's realtime timeline, and the result is a live session that renders silence ([airplay2-sender-cpp, README](https://github.com/akustikrausch/airplay2-sender-cpp), **confirmed** as observed behaviour, and stated there as the final cause of a long-running silent-playback defect).

## The RTSP layer

### What the requests look like

After pair-verify the sender speaks RTSP over the encrypted control connection. The request URI is built from the sender's own address as the receiver sees it, and a random 32-bit session identifier. That same identifier is reused as the RTP synchronisation source ([airplay2-sender-cpp, `raop_sender.cpp`](https://github.com/akustikrausch/airplay2-sender-cpp), attributed there to pyatv, **likely**).

```text
rtsp://<sender ip>/<session id>
```

AirPlay 2 has no RTSP `Session` header, because there is no transport-mode SETUP to issue one. The session is identified by that URI ([airplay2-sender-cpp, `raop_sender.cpp`](https://github.com/akustikrausch/airplay2-sender-cpp), **likely**).

Pairing requests use an `HTTP/1.1` request line and the SETUP family uses an `RTSP/1.0` one, on the same socket. Real receivers parse both ([airplay2-sender-cpp, `raop_sender.cpp`](https://github.com/akustikrausch/airplay2-sender-cpp), **likely**).

`POST /feedback` is the one request that must carry an `RTSP/1.0` request line rather than `HTTP/1.1`. A receiver's RTSP parser ignores the HTTP form silently, so its liveness timer never resets ([airplay2-sender-cpp, `raop_sender.cpp`](https://github.com/akustikrausch/airplay2-sender-cpp), **likely**).

### GET /info

`GET /info` comes before any SETUP and is required. The reply is a binary property list describing the receiver ([openairplay, GET /info](https://openairplay.github.io/airplay-spec/audio/rtsp_requests/get_info.html), **confirmed**; [airplay2-sender-cpp, README](https://github.com/akustikrausch/airplay2-sender-cpp) states that it is required, **likely**).

```text
GET /info RTSP/1.0
X-Apple-ProtocolVersion: 1
CSeq: 0
DACP-ID: ADA239F4521B1802
Active-Remote: 753030410
User-Agent: AirPlay/550.10
```

The response body is `application/x-apple-binary-plist` and carries at least these keys ([openairplay, GET /info](https://openairplay.github.io/airplay-spec/audio/rtsp_requests/get_info.html), **confirmed**).

| Key | Type | Meaning |
|---|---|---|
| `deviceID` | string | MAC address. |
| `model` | string | Model designation. |
| `name` | string | Display name. |
| `protocolVersion` | string | AirPlay protocol version. |
| `sourceVersion` | string | Firmware or server version. |
| `features` | integer | The capability bitfield as a number rather than as the hex-pair text form. |
| `statusFlags` | integer | The status flags as a number. |
| `manufacturer` | string | Manufacturer. |
| `sdk` | string | For example `AirPlay;2.0.2`. |
| `build` | string | Build number. |

Reading `features` and `statusFlags` here rather than from the TXT record is the more reliable route, because the reply is generated on the spot and the TXT record can be stale.

An Apple sender issues `GET /info` twice, and the two requests ask different questions ([Cozzi, RTSP](https://web.archive.org/web/20220214214845/https://emanuelecozzi.net/docs/airplay2/rtsp/), **confirmed** from a capture of an iPhone against a Sonos One).

The first carries a binary property list body of `{'qualifier': ['txtAirPlay']}` and asks for the `_airplay._tcp` TXT record as a plist, which is how a receiver with a thin TXT record can still declare everything about itself. The second carries no body at all and returns the keys that only exist at this point, of which `initialVolume` is the one a sender wants. The first reply is also where a receiver declares its output latency, in a key called `audioLatencies` holding one dictionary per audio type, each with `inputLatencyMicros`, `outputLatencyMicros`, an integer `type` naming the stream type it applies to, and an optional `audioType` of `default` or `media`. The captured Sonos One reports 400000 microseconds of output latency for every combination.

### SETUP, the session

SETUP is an RTSP **method** on the session URI. It is not `POST /setup`, which returns 404 ([airplay2-sender-cpp, README](https://github.com/akustikrausch/airplay2-sender-cpp), **confirmed** as observed behaviour). The body is a binary property list with `Content-Type: application/x-apple-binary-plist` ([openairplay, SETUP](https://openairplay.github.io/airplay-spec/audio/rtsp_requests/setup.html), **likely**; the page documents the AirPlay 1 form in full and the AirPlay 2 form only by content type).

There are two SETUP requests. The first describes the session and the sender. The second describes one audio stream. The field list below is what a working sender sends for the session ([airplay2-sender-cpp, `raop_sender.cpp`](https://github.com/akustikrausch/airplay2-sender-cpp), **likely** for the whole set).

| Key | Type | Value and meaning |
|---|---|---|
| `deviceID` | string | The sender's MAC address, colon separated. |
| `macAddress` | string | The same value again. |
| `sessionUUID` | string | A version 4 UUID in uppercase text form, fresh per session. |
| `timingPort` | integer | The UDP port the sender's timing server is bound to. |
| `timingProtocol` | string | `NTP`, `PTP`, or `None`. See the timing section. |
| `isMultiSelectAirPlay` | boolean | True when the sender may address more than one receiver. |
| `groupContainsGroupLeader` | boolean | False when the sender is not joining an existing group. |
| `model` | string | The sender's model string, for example `iPhone14,3`. |
| `name` | string | The sender's display name. |
| `osName` | string | For example `iPhone OS`. |
| `osVersion` | string | For example `16.5`. |
| `osBuildVersion` | string | For example `20F66`. |
| `sourceVersion` | string | The AirPlay source version the sender claims. |
| `senderSupportsRelay` | boolean | False for a sender that does not relay. |
| `statsCollectionEnabled` | boolean | False. |

A capture of an Apple sender carries four more keys that no open sender sends, and they are the ones the PTP path needs ([Cozzi, RTSP](https://web.archive.org/web/20220214214845/https://emanuelecozzi.net/docs/airplay2/rtsp/), **confirmed** from that capture).

| Key | Type | Value and meaning |
|---|---|---|
| `groupUUID` | string | The group's UUID in uppercase text form. The sender sends it even when addressing a single receiver. |
| `timingPeerInfo` | dictionary | The sender's own timing identity: an `Addresses` array holding its IPv4 and IPv6 addresses, and an `ID`, which in the capture is the same UUID as `groupUUID`. |
| `timingPeerList` | array | An array of dictionaries of that shape, one per timing peer. In the capture it holds the sender alone. |
| `ekey`, `eiv`, `et` | data, data, integer | The AirPlay 1 audio key, its initialisation vector, and the encryption type. The capture carries `et: 0`, meaning none, with both byte strings present and unused. |

The reply is a binary property list. The key that matters is `eventPort`, the TCP port for the event channel ([airplay2-sender-cpp, `raop_sender.cpp`](https://github.com/akustikrausch/airplay2-sender-cpp), **likely**).

`timingPort` means different things in the request and in the reply, and the reply's meaning is the opposite way round from what its name suggests. On the PTP path the reply carries `timingPort: 0`, because no timing channel is opened at all, and the reply's `timingPeerInfo` carries the receiver's own addresses instead. On the NTP path the receiver opens a timing channel and names its port there ([Cozzi, RTSP](https://web.archive.org/web/20220214214845/https://emanuelecozzi.net/docs/airplay2/rtsp/), **confirmed** for the PTP half, which comes from a capture whose `timingProtocol` reads `PTP` and whose reply reads `timingPort: 0`, and **likely** for the NTP half, which that page states without a capture behind it). The request's `timingPort` is the sender's own, which is what the open senders fill in, because on their NTP path the sender is the one running a timing server.

### SETUP, the stream

The second SETUP carries a `streams` array holding one dictionary per stream. For realtime audio it looks like this ([airplay2-sender-cpp, `raop_sender.cpp`](https://github.com/akustikrausch/airplay2-sender-cpp), **likely** for the whole set).

| Key | Type | Value | Meaning |
|---|---|---|---|
| `type` | integer | 96 (0x60) | Realtime audio over UDP. |
| `ct` | integer | 2 | Compression type. 1 is PCM, 2 is ALAC, 4 is AAC-LC, 8 is AAC-ELD, and 32 is Opus. |
| `audioFormat` | integer | 0x40000 | One bit per format. Bit 18 is ALAC at 44100 Hz, 16 bit, 2 channels. |
| `audioMode` | string | `default` | |
| `spf` | integer | 352 | Samples per frame. |
| `sr` | integer | 44100 | Sample rate. |
| `shk` | data | 32 bytes | The audio key. See below. |
| `controlPort` | integer | | The sender's UDP control port. |
| `latencyMin` | integer | 11025 | Minimum acceptable latency in frames. |
| `latencyMax` | integer | 88200 | Maximum acceptable latency in frames. |
| `isMedia` | boolean | true | |
| `supportsDynamicStreamID` | boolean | false | |
| `streamConnectionID` | integer | the session id | The numeric RTSP session identifier, not a separate string. |

The `ct` values come from a receiver's own comment naming the table, and `audioFormat` is a bitfield with one bit per concrete format rather than a small enumeration ([openairplay, `airplay2-receiver`, `ap2-receiver.py`](https://github.com/openairplay/airplay2-receiver/blob/master/ap2-receiver.py) and [`ap2/connections/audio.py`](https://github.com/openairplay/airplay2-receiver/blob/master/ap2/connections/audio.py), **confirmed**). Bits 2 to 17 are PCM at various rates and channel counts, bits 18 to 21 are the four ALAC variants, bits 22 and 23 are AAC-LC at 44100 Hz and 48000 Hz, bits 24 to 27 and 31 to 32 are AAC-ELD variants, and bits 28 to 30 are Opus. Bit 18 is therefore ALAC at 44100 Hz, 16 bit, stereo, which is the value 0x40000 that a working sender sends ([airplay2-sender-cpp, `raop_sender.cpp`](https://github.com/akustikrausch/airplay2-sender-cpp), **likely**, and the two agree). A third table, recovered from Apple's own sender, enumerates all thirty-one bits with the same meanings, so the mapping is settled ([Cozzi, Audio](https://web.archive.org/web/20220214214824/https://emanuelecozzi.net/docs/airplay2/audio/), **confirmed**).

`type` names the kind of stream, and audio is two of five values ([Cozzi, RTSP](https://web.archive.org/web/20220214214845/https://emanuelecozzi.net/docs/airplay2/rtsp/), **likely**).

| Value | Stream |
|---|---|
| 96 | General audio, realtime. |
| 103 | General audio, buffered. |
| 110 | Screen. |
| 120 | Playback. |
| 130 | Remote control. |

A capture of an Apple sender fills the realtime dictionary the same way the stream table above does: `ct: 2`, `audioFormat: 262144` which is 0x40000, `spf: 352`, `audioMode: default`, `isMedia: true`, `latencyMin: 11025`, `latencyMax: 88200`, `supportsDynamicStreamID: true`, its own `controlPort`, and a 32-byte `shk`. It carries no `shiv` and no `clientID`, and no `streamConnectionID` either ([Cozzi, RTSP](https://web.archive.org/web/20220214214845/https://emanuelecozzi.net/docs/airplay2/rtsp/), **confirmed** from that capture).

Two implementations fill this dictionary differently. pyatv sends `ct: 1` with `audioFormat: 0x800`, which is a PCM format ([pyatv, `pyatv/protocols/raop/protocols/airplayv2.py`](https://github.com/postlund/pyatv/blob/master/pyatv/protocols/raop/protocols/airplayv2.py), **confirmed** as a description of pyatv). The ALAC choice above is the safer one, for the reason given below under the payload, and it is also what Apple itself sends.

The reply carries a `streams` array of its own. The sender reads `dataPort` from the first entry, which is the UDP port the audio goes to, and `controlPort`, which is where sync packets and retransmit requests go ([airplay2-sender-cpp, `raop_sender.cpp`](https://github.com/akustikrausch/airplay2-sender-cpp), **likely**).

An AirPlay 2 SETUP response carries no `Session` header and nothing useful in `Transport`, so a sender that looks for ports there finds nothing. The ports are in the plist body, which is where a receiver puts them ([shairport-sync, `rtsp.c`](https://github.com/mikebrady/shairport-sync/blob/master/rtsp.c), **confirmed** for what the receiver sends).

### The audio key, `shk`

`shk` is the ChaCha20-Poly1305 key for the audio payload, sent in the stream SETUP body as 32 bytes of data. It is **not** derived with HKDF.

A receiver takes the value it was given and uses it as the cipher key directly, with no derivation step, and rejects any length other than 32 bytes ([shairport-sync, `rtsp.c`](https://github.com/mikebrady/shairport-sync/blob/master/rtsp.c), **confirmed**).

What the sender should put in it is less settled. pyatv puts an arbitrary per-session value there and its own comment says the key only has to be some per-session value ([pyatv, `pyatv/protocols/raop/protocols/airplayv2.py`](https://github.com/postlund/pyatv/blob/master/pyatv/protocols/raop/protocols/airplayv2.py), **confirmed** as a description of pyatv). Against a current Apple TV that is reported not to work: only the first 32 bytes of the pairing shared secret decode correctly there, and an HKDF-derived key produces noise, which reads as the Apple TV deriving the audio key from the pairing secret rather than honouring `shk` ([airplay2-sender-cpp, README](https://github.com/akustikrausch/airplay2-sender-cpp), **confirmed** as observed behaviour against that device).

Both readings are satisfied by one choice, so make it. Set `shk` to the first 32 bytes of the pairing shared secret, and use that same value as the cipher key. A receiver that honours `shk` then gets the right key, and a receiver that derives its own gets the same key anyway.

The clamp to 32 bytes is what makes the two pairing paths behave the same. After pair-verify the shared secret is the 32-byte X25519 output, so the clamp does nothing. After transient pairing the shared secret is the 64-byte SRP session key `K`, and passing all 64 bytes to a ChaCha20 key rejects on every single audio packet, so nothing is sent and the receiver drops the session after its no-audio timeout. The control and event keys are unaffected, because HKDF accepts input key material of any length, which is why pairing and cover artwork keep working whilst the audio never starts ([airplay2-sender-cpp, README](https://github.com/akustikrausch/airplay2-sender-cpp), **confirmed** as observed behaviour, corroborated there by owntone's constant for the same length).

### RECORD, and the order that works

The order below is what a working sender uses against a current Apple TV, and it is stated there as load-bearing ([airplay2-sender-cpp, README and `raop_sender.cpp`](https://github.com/akustikrausch/airplay2-sender-cpp), **confirmed** as observed behaviour).

```text
1.  pair-setup and pair-verify            control channel becomes encrypted here
2.  GET /info
3.  SETUP (session)                       reply gives eventPort
4.  connect TCP to eventPort              the event channel must be OPEN
5.  RECORD
6.  SETUP (stream)                        reply gives dataPort and controlPort
7.  SET_PARAMETER volume
8.  first SYNC packet, then the RTP audio loop
```

A capture of an Apple sender arrives at the same order independently. It sends `GET /info` with the `txtAirPlay` qualifier, then the session SETUP, then the second bodyless `GET /info`, then RECORD, then SETPEERS, then the volume requests and a `POST /feedback` loop. The stream SETUP comes later, at the moment audio is about to start, and FLUSH follows it ([Cozzi, Protocols](https://web.archive.org/web/20220214214828/https://emanuelecozzi.net/docs/airplay2/protocols/), **confirmed** as a description of that capture). That puts RECORD between the two SETUPs, which is the one ordering constraint the working sender calls load-bearing, and two independent sources now agree on it.

What fails when it is done differently:

- Sending the stream SETUP in the clear right after pair-verify makes the receiver close the socket within about one millisecond.
- Using `POST /setup` instead of the SETUP method returns 404.
- Omitting `GET /info` before SETUP is rejected.
- Sending RECORD before the event channel is connected gives `RECORD 500` and `FLUSH 455`.
- Sending RECORD after the stream SETUP rather than between the two SETUPs leaves the receiver outside its record state, and it will not render the realtime stream.

RECORD on this path carries an empty body and the ordinary identity headers. Some Apple TVs answer it with 500 even when everything is correct, which is not fatal on the realtime path: the SYNC packets anchor the timeline instead ([airplay2-sender-cpp, `raop_sender.cpp`](https://github.com/akustikrausch/airplay2-sender-cpp), **likely**).

On AirPlay 1 the RECORD request is different. There it carries `Range: npt=0-`, an `RTP-Info` header naming the sequence number and RTP timestamp of the first audio packet, and the `Session` header from SETUP. The reply carries `Audio-Latency` ([openairplay, RECORD](https://openairplay.github.io/airplay-spec/audio/rtsp_requests/record.html), **confirmed**).

```text
RTP-Info: seq=<16-bit initial sequence number>;rtptime=<32-bit initial RTP timestamp>
```

## Realtime audio, payload type 96

### The packet

Realtime audio goes over UDP to the `dataPort` the stream SETUP returned. Each packet is a standard 12-byte RTP header ([RFC 3550](https://www.rfc-editor.org/rfc/rfc3550.txt)) followed by the payload. All fields are big-endian.

```text
 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|1 0 0 0 0 0 0 0|M|   PT = 96   |      sequence number          |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                        RTP timestamp                          |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                    SSRC = the session id                      |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                          payload ...                          |
```

The first byte is always 0x80, meaning RTP version 2 with no padding, no extension, and no contributing sources. The second byte is 0xE0 on the first packet of a stream and 0x60 afterwards, which is payload type 96 with the marker bit set on the first packet only. The marker bit is set again on the first packet after a FLUSH ([openairplay, RTP Streams](https://openairplay.github.io/airplay-spec/audio/rtp_streams.html), **confirmed**, and [airplay2-sender-cpp, `raop_sender.cpp`](https://github.com/akustikrausch/airplay2-sender-cpp), **likely** for the SSRC choice).

The sequence number is a 16-bit counter that starts at a random value and wraps. The RTP timestamp counts frames at 44100 Hz. Its starting value and its relationship to the clock are covered in the timing section.

Each packet carries exactly 352 frames. That number is fixed in RAOP and is what the receiver expects ([airplay2-sender-cpp, `raop_sender.cpp`](https://github.com/akustikrausch/airplay2-sender-cpp), **likely**; it also appears as the first ALAC parameter in every published AirPlay SDP, which corroborates it).

### The payload is ALAC, whatever you ask for

On the realtime stream the receiver fixes the codec at ALAC and ignores both `ct` and `audioFormat`. A sender must ALAC-encode.

This is visible in a receiver's own SETUP handling. shairport-sync reads `audioFormat` **only** in the branch for stream type 103, and never in the branch for stream type 96, where the format is fixed at ALAC, 16 bit, 44100 Hz, stereo ([shairport-sync, `rtsp.c`](https://github.com/mikebrady/shairport-sync/blob/master/rtsp.c) and [`AIRPLAY2.md`](https://github.com/mikebrady/shairport-sync/blob/master/AIRPLAY2.md), **confirmed**). A working sender reports the same behaviour from the other side, against an Apple TV ([airplay2-sender-cpp, README](https://github.com/akustikrausch/airplay2-sender-cpp), **confirmed** as observed behaviour).

The cheapest correct way to satisfy that is the uncompressed ALAC escape. ALAC's bitstream has an escape flag that means "the samples that follow are raw", so a sender can produce a valid ALAC frame without implementing any of the prediction machinery. The bitstream is read most-significant-bit first.

The field order below comes from Apple's own ALAC decoder ([Apple, `macosforge/alac`, `ALACDecoder.cpp`](https://github.com/macosforge/alac/blob/master/codec/ALACDecoder.cpp), **confirmed**).

```text
 3 bits   element tag          1 = ID_CPE, a channel pair element
 4 bits   elementInstanceTag   0
12 bits   unusedHeader         0, and the decoder errors if it is not
 1 bit    partialFrame         0, so the frame length comes from the configuration
 2 bits   bytesShifted         0
 1 bit    escape flag          1, meaning the samples are uncompressed
          then, for each of the 352 frames:
16 bits       left sample, most-significant bit first
16 bits       right sample, most-significant bit first
 3 bits   element tag          7 = ID_END
          zero-pad to the next byte boundary
```

The element tag numbers come from the same source: `ID_SCE` is 0, `ID_CPE` is 1, `ID_CCE` is 2, `ID_LFE` is 3, `ID_DSE` is 4, `ID_PCE` is 5, `ID_FIL` is 6, and `ID_END` is 7 ([Apple, `macosforge/alac`, `ALACBitUtilities.h`](https://github.com/macosforge/alac/blob/master/codec/ALACBitUtilities.h), **confirmed**).

Two details are worth stating because they are easy to get wrong. The two channels are interleaved one sample at a time, not written as two blocks. And `mixBits` and `mixRes` are not present at all in the uncompressed case, because Apple's decoder sets them to zero rather than reading them ([Apple, `macosforge/alac`, `ALACDecoder.cpp`](https://github.com/macosforge/alac/blob/master/codec/ALACDecoder.cpp), **confirmed**).

### The ALAC configuration, and the `fmtp` parameter list

The eleven numbers in an AirPlay `a=fmtp:96` line are the fields of Apple's `ALACSpecificConfig`, in declaration order ([Apple, `macosforge/alac`, `ALACAudioTypes.h`](https://github.com/macosforge/alac/blob/master/codec/ALACAudioTypes.h), **confirmed** for the struct; [openairplay, ANNOUNCE](https://openairplay.github.io/airplay-spec/audio/rtsp_requests/announce.html), **confirmed** for the example line).

```text
a=fmtp:96 352 0 16 40 10 14 2 255 0 0 44100
```

| Position | Field | Value here |
|---|---|---|
| 1 | `frameLength` | 352 |
| 2 | `compatibleVersion` | 0 |
| 3 | `bitDepth` | 16 |
| 4 | `pb` | 40 |
| 5 | `mb` | 10 |
| 6 | `kb` | 14 |
| 7 | `numChannels` | 2 |
| 8 | `maxRun` | 255 |
| 9 | `maxFrameBytes` | 0 |
| 10 | `avgBitRate` | 0 |
| 11 | `sampleRate` | 44100 |

AirPlay 2 sends no SDP, so this line matters only on the AirPlay 1 path and as the definition of what `audioFormat` and `spf` are describing.

### Encrypting the payload

The ALAC frame is encrypted with ChaCha20-Poly1305 under the `shk` key. The additional authenticated data is bytes 4 to 11 of the RTP header, which is the RTP timestamp and the SSRC, eight bytes in total. The nonce is a 64-bit counter that starts at zero and increases by one per packet, padded to twelve bytes with four leading zero bytes, exactly as on the control channel.

The counter is **appended to the packet after the ciphertext and the tag**, as eight little-endian bytes, so the receiver can decrypt a packet that arrived out of order ([airplay2-sender-cpp, `raop_sender.cpp`](https://github.com/akustikrausch/airplay2-sender-cpp), attributed there to pyatv, **likely**).

```text
+---------------------+------------------+------------------+------------------+
| 12-byte RTP header  |    ciphertext    |  Poly1305 tag    | nonce counter    |
|                     |                  |    (16 bytes)    |   (8 bytes, LE)  |
+---------------------+------------------+------------------+------------------+
        AAD = header bytes 4 to 11
```

One published diagram of that trailer puts the nonce first and the tag after it. A receiver's own decryption reads it the other way round, taking the last eight bytes as the nonce and the sixteen before them as the tag, which is what the combined-mode AEAD call expects, so the order above is the one that works ([shairport-sync, `rtp.c`](https://github.com/mikebrady/shairport-sync/blob/master/rtp.c), **confirmed**, against [Cozzi, RTP](https://web.archive.org/web/20220214214827/https://emanuelecozzi.net/docs/airplay2/rtp/)). The same receiver code path serves both the realtime and the buffered stream, which is why the two constructions are identical.

### Pacing

Frames must leave the machine at the rate wall-clock time advances, which is 44100 frames per second. A working sender runs an 8 millisecond deadline, which is about one packet per tick, and uses a token bucket so that a late tick is repaid rather than lost. The number of packets sent in one catch-up burst is capped, so a stalled thread cannot flood the network ([airplay2-sender-cpp, `raop_sender.cpp`](https://github.com/akustikrausch/airplay2-sender-cpp), **likely**).

When the source has no audio, the sender must push silence rather than stop. A receiver whose timeline stops advancing treats the stream as dead ([airplay2-sender-cpp, `raop_sender.cpp`](https://github.com/akustikrausch/airplay2-sender-cpp), **likely**).

## Buffered audio, payload type 103

Buffered audio is the path Apple uses for music. Audio arrives faster than it is played and sits in the receiver's buffer until its moment comes, which is what makes the playback delay short and the stream resistant to a lossy network. Realtime audio is the other path, used where delay matters more than robustness, such as system sounds and telephony ([shairport-sync, `AIRPLAY2.md`](https://github.com/mikebrady/shairport-sync/blob/master/AIRPLAY2.md), **confirmed**).

### The stream SETUP for buffered audio

The stream dictionary carries `type: 103`. A receiver reads `shk`, `ct`, `spf`, and, unlike the realtime case, `audioFormat` ([shairport-sync, `rtsp.c`](https://github.com/mikebrady/shairport-sync/blob/master/rtsp.c), **confirmed**).

The reply differs from the realtime reply in two ways. `dataPort` names a **TCP** port rather than a UDP one, and the reply additionally carries `audioBufferSize`, an integer naming how much audio the receiver is prepared to hold. `controlPort` is a UDP port opened once for the connection and shared with the realtime stream ([shairport-sync, `rtsp.c`](https://github.com/mikebrady/shairport-sync/blob/master/rtsp.c), **confirmed**).

`audioBufferSize` is a capacity the receiver reports, not something the sender chooses. The receiver allocates a buffer of that size, and beyond it the TCP connection simply stops draining, so flow control falls out of the transport rather than out of a protocol message ([shairport-sync, `ap2_buffered_audio_processor.c`](https://github.com/mikebrady/shairport-sync/blob/master/ap2_buffered_audio_processor.c), **confirmed**).

The fields that write-ups attach to this request sort themselves once a receiver's stream parser is read in one piece. Three of them are real and belong to the realtime stream rather than to the buffered one ([openairplay, `airplay2-receiver`, `ap2/connections/stream.py`](https://github.com/openairplay/airplay2-receiver/blob/master/ap2/connections/stream.py), **confirmed** as a statement about that implementation).

`shiv` is read only in the realtime branch, where it is the initialisation vector for the AES-CBC cipher that the older encryption types use. The buffered branch passes no initialisation vector at all, because its cipher is ChaCha20-Poly1305 keyed directly by `shk` ([openairplay, `airplay2-receiver`, `ap2/connections/audio.py`](https://github.com/openairplay/airplay2-receiver/blob/master/ap2/connections/audio.py), **confirmed**). `latencyMin` and `latencyMax` are likewise realtime-only, and there they are mandatory rather than optional, whilst `shk`, `shiv`, and `controlPort` are optional even there. `isMedia` is read by neither receiver in either branch, although Apple's own sender does send it. `clientID` appears in no implementation examined here, so it stays **open**.

`streamConnectionID` and `supportsDynamicStreamID` are read straight out of the per-stream dictionary, for both stream types, and neither is gated behind a feature bit. What sits at the connection level is a separate `streamConnections` key inside that same dictionary ([openairplay, `airplay2-receiver`, `ap2/connections/stream.py`](https://github.com/openairplay/airplay2-receiver/blob/master/ap2/connections/stream.py), **confirmed**).

`audioMode` is both a key and a request. Apple's own sender sends `audioMode: default` inside the realtime stream dictionary ([Cozzi, RTSP](https://web.archive.org/web/20220214214845/https://emanuelecozzi.net/docs/airplay2/rtsp/), **confirmed** from a capture), and a separate `POST /audioMode` request exists beside it, which both receivers accept and neither acts on ([shairport-sync, `rtsp.c`](https://github.com/mikebrady/shairport-sync/blob/master/rtsp.c) and [openairplay, `airplay2-receiver`](https://github.com/openairplay/airplay2-receiver/blob/master/ap2-receiver.py), **confirmed** as a statement about those implementations).

The reply's stream descriptor carries a `streamID` as well as the ports, and that is the number a sender later names in a TEARDOWN body to take one stream down whilst leaving the session up ([openairplay, `airplay2-receiver`, `ap2/connections/stream.py`](https://github.com/openairplay/airplay2-receiver/blob/master/ap2/connections/stream.py) and [Cozzi, RTSP](https://web.archive.org/web/20220214214845/https://emanuelecozzi.net/docs/airplay2/rtsp/), **likely**, since the receiver that returns it and the capture that uses it are two different devices).

### The TCP framing

The buffered connection is a stream of length-prefixed blocks.

```text
+---------+-------------------------------------------------------+
| length  |                     block                             |
| 2 bytes |                                                       |
| BE u16  |                                                       |
+---------+-------------------------------------------------------+
  the length counts itself, so the block is (length - 2) bytes
```

Each block then looks like this ([shairport-sync, `ap2_buffered_audio_processor.c`](https://github.com/mikebrady/shairport-sync/blob/master/ap2_buffered_audio_processor.c), **confirmed**).

```text
offset  size  field
  0      4    big-endian u32: the top bit is the marker bit, always set,
              and the low 23 bits are the sequence number
  4      4    big-endian u32: timestamp
  8      4    big-endian u32: SSRC, which names the codec of THIS block
 12      n    ChaCha20-Poly1305 ciphertext
12+n    16    Poly1305 tag
28+n     8    the nonce counter, little-endian
```

The sequence number is 23 bits wide here rather than the 16 bits RTP normally gives it. The SSRC is not a stream identifier in the RTP sense: the receiver reads it to decide what codec the block holds, so the codec can change from one block to the next within a single connection.

The encryption is the same construction as the realtime path. The key is `shk` used directly. The additional authenticated data is the eight bytes at offset 4, which are the timestamp and the SSRC. The nonce is the trailing eight bytes, padded at the front with four zero bytes to make twelve ([shairport-sync, `ap2_buffered_audio_processor.c`](https://github.com/mikebrady/shairport-sync/blob/master/ap2_buffered_audio_processor.c), **confirmed**).

The realtime path uses the identical key, additional-data, and nonce construction. Only the header differs, and the eight bytes fed in as additional data are the same timestamp and SSRC in both cases ([shairport-sync, `rtp.c`](https://github.com/mikebrady/shairport-sync/blob/master/rtp.c), **confirmed**).

### The codec

Buffered audio is ALAC when lossless and AAC when lossy ([shairport-sync, `AIRPLAY2.md`](https://github.com/mikebrady/shairport-sync/blob/master/AIRPLAY2.md), **confirmed**). The AAC is AAC-LC, and it arrives as raw AAC frames with no ADTS framing at all, so a receiver builds an ADTS header itself before handing the frame to a decoder ([shairport-sync, `ap2_buffered_audio_processor.c`](https://github.com/mikebrady/shairport-sync/blob/master/ap2_buffered_audio_processor.c), **confirmed**). AAC-ELD is the realtime and mirroring codec, not the buffered one.

### What the receiver must advertise

`features` bit 40, `SupportsBufferedAudio`. The specification's own note on that bit, and on bit 41 `SupportsPTP`, is that each is the bit "needed for device to show as supporting multi-room audio" ([openairplay, `src/features.md`](https://raw.githubusercontent.com/openairplay/airplay-spec/master/src/features.md), **confirmed**).

No open sender implements buffered audio at all. pyatv and the C++ sender say so in their own documentation, and owntone hardcodes the realtime payload type in a constant whose own comment names 103 as the alternative it does not take ([pyatv](https://github.com/postlund/pyatv), [airplay2-sender-cpp](https://github.com/akustikrausch/airplay2-sender-cpp), and [owntone, `src/outputs/airplay.c`](https://github.com/owntone/owntone-server/blob/master/src/outputs/airplay.c), **confirmed**). A sender that wants multi-room is building this path from the receiver side of the sources, not from an existing sender.

### FLUSHBUFFERED

`FLUSHBUFFERED` carries four fields: `flushFromSeq`, `flushFromTS`, `flushUntilSeq`, and `flushUntilTS`. With no `flushFromSeq` it is an immediate flush up to the `until` point, which is what a stop does. With `flushFromSeq` present it is a range flush, which drops only the blocks between the two points and leaves audio queued beyond them alone. That is what makes a track change seamless: the tail of the old track goes and the head of the new one stays ([shairport-sync, `rtsp.c`](https://github.com/mikebrady/shairport-sync/blob/master/rtsp.c) and [openairplay, `airplay2-receiver`](https://github.com/openairplay/airplay2-receiver/blob/master/ap2-receiver.py), **confirmed** by both).

## Timing and synchronisation

### The short answer

**AirPlay 2 multi-room audio uses PTP, IEEE 1588.** Classic AirPlay uses the NTP-anchored model with SYNC packets, and does not use PTP at all. shairport-sync states both outright, and it runs a separate daemon, nqptp, purely to handle the PTP side of an AirPlay 2 session ([shairport-sync, README](https://github.com/mikebrady/shairport-sync/blob/master/README.md) and [nqptp, README](https://github.com/mikebrady/nqptp/blob/main/README.md), **confirmed**).

The NTP model has not gone away. A sender that puts the string `NTP` in `timingProtocol` gets a working single-receiver session out of a current Apple TV, a HomePod, and a macOS receiver. That is what pyatv does and what the C++ sender does, and both work ([pyatv, `pyatv/protocols/raop/protocols/airplayv2.py`](https://github.com/postlund/pyatv/blob/master/pyatv/protocols/raop/protocols/airplayv2.py), **confirmed**, and [UxPlay wiki, AirPlay2](https://github.com/FDH2/UxPlay/wiki/AirPlay2) carries a capture with that exact value, **confirmed**).

All three values are attested literally. `NTP` appears in a capture and in pyatv's audio session, and `None` appears in pyatv's remote-control-only session ([pyatv, `pyatv/protocols/airplay/ap2_session.py`](https://github.com/postlund/pyatv/blob/master/pyatv/protocols/airplay/ap2_session.py), **confirmed**). `PTP` appears in a capture of an iPhone addressing a Sonos One, in a session SETUP that carries `timingPeerInfo` and `timingPeerList` beside it ([Cozzi, RTSP](https://web.archive.org/web/20220214214845/https://emanuelecozzi.net/docs/airplay2/rtsp/), **confirmed**).

What the NTP path does not buy is multi-room, and it does not reach every receiver. shairport-sync refuses an NTP stream outright, logging that it cannot handle one. owntone's AirPlay 2 sender implements only NTP timing, and for exactly that reason cannot stream to a shairport-sync receiver ([music-assistant issue 6243](https://github.com/music-assistant/support/issues/6243) and [cliairplay issue 78](https://github.com/music-assistant/cliairplay/issues/78), **confirmed** as reports of behaviour).

So the honest position for a sender that wants several speakers in step is this. NTP is the quickest route to one Apple receiver playing audio. PTP is what the rest of the design has to be built around, and nothing else in the published record keeps several receivers in step.

### What decides which

No source states the rule as a sentence. Three independent observations point the same way, so this is **likely** rather than confirmed: the receiver advertises `features` bit 41 `SupportsPTP`, the specification annotates that bit as required for multi-room, and the implementations that only speak NTP are exactly the ones that fail against PTP-only receivers.

### PTP, what is actually known

PTP traffic sits on UDP ports 319 and 320. Port 319 carries the event messages, meaning Sync, Delay_Req, Pdelay_Req, and Pdelay_Resp, and port 320 carries the general messages, meaning Announce, Follow_Up, Delay_Resp, Pdelay_Resp_Follow_Up, Management, and Signaling. nqptp requires exclusive use of both, and shairport-sync's author states that an AirPlay source will only send and respond on those two ports ([shairport-sync, `AIRPLAY2.md`](https://github.com/mikebrady/shairport-sync/blob/master/AIRPLAY2.md), [nqptp, README](https://github.com/mikebrady/nqptp/blob/main/README.md), and [shairport-sync discussion 1712](https://github.com/mikebrady/shairport-sync/discussions/1712), **confirmed**).

nqptp is a passive monitor. It does not originate PTP messages, does not respond to them, and does not take part in master-clock election. It watches the traffic, keeps a record of one clock identified by its 64-bit clock identity, and publishes to shairport-sync a local timestamp, an offset that converts local time into master-clock time, and the moment that clock became master ([nqptp, README](https://github.com/mikebrady/nqptp/blob/main/README.md) and [shairport-sync discussion 1712](https://github.com/mikebrady/shairport-sync/discussions/1712), **confirmed**). nqptp's own README says it is not a PTP clock and uses only part of IEEE 1588-2008.

Put those two together and the shape of the sender's job follows. The receiver only listens. Something has to be originating the PTP messages, and the only other party is the sender. **The sender runs a real, message-originating PTP implementation and the receivers discipline their clocks to it** (**likely**, because it follows from two confirmed facts rather than from a statement).

Two more things follow from nqptp's own source. It binds UDP 319 and 320 and never joins a PTP multicast group, so the sender's messages reach it as unicast to each peer's address, which is also why a receiver has to be handed the peer list before any of the clock traffic means anything to it ([nqptp, `nqptp.c`](https://github.com/mikebrady/nqptp/blob/main/nqptp.c) and [`nqptp-utilities.c`](https://github.com/mikebrady/nqptp/blob/main/nqptp-utilities.c), **likely**, because it is an inference from what the code does not do). And the sender does send Announce messages. nqptp handles exactly three message types, Announce, Sync, and Follow_Up, and out of the Announce it reads `grandmasterIdentity`, `grandmasterPriority1`, `grandmasterPriority2`, the clock quality word, and `stepsRemoved` ([nqptp, `nqptp-message-handlers.c`](https://github.com/mikebrady/nqptp/blob/main/nqptp-message-handlers.c), **confirmed**).

So the sender behaves as a two-step PTP master. It announces itself with the full Best Master Clock fields, then sends Sync and Follow_Up, and the receiver takes its offset from that pair. The receiver need never send Delay_Req: nqptp originates nothing at all beyond a single Announce it sends to wake a clock that has stopped talking.

What is genuinely **open**: whether the receivers run a real Best Master Clock election or simply accept the sender that announces, which PTP domain number is used, and which PTP profile applies. shairport-sync's author says plainly that it is not clear how potential clock masters are permitted to be used, and hedges the profile question with "possibly" 802.1AS ([shairport-sync discussion 1712](https://github.com/mikebrady/shairport-sync/discussions/1712), **confirmed** as a statement of what is unknown).

Apple publishes nothing about this. Its AirPlay deployment guide does not mention PTP, clock synchronisation, or timing at all, and its published table of ports lists AirPlay against 80, 443, 554, 3689, 5000, 5353, 6000, 7000, and the ephemeral range, with no 319 and no 320 ([Apple, Use AirPlay with Apple devices](https://support.apple.com/guide/deployment/use-airplay-dep9151c4ace/web) and [Apple, TCP and UDP ports used by Apple software products](https://support.apple.com/en-us/103229), **confirmed** as a negative finding).

### The anchor

This is the mechanism that ties a clock reading to a position in the audio, and it is the same idea on both timing paths.

On the PTP path it is the `SETRATEANCHORTIME` request. Its body carries these fields ([shairport-sync, `rtsp.c`](https://github.com/mikebrady/shairport-sync/blob/master/rtsp.c) and [openairplay, `airplay2-receiver`](https://github.com/openairplay/airplay2-receiver/blob/master/ap2-receiver.py), **confirmed** by both).

| Field | Meaning |
|---|---|
| `networkTimeTimelineID` | The PTP clock identity that the following time is expressed against. |
| `networkTimeSecs` | The seconds part of that network time. |
| `networkTimeFrac` | The fractional part, fixed point. |
| `rtpTime` | The RTP timestamp that corresponds to that network time. |
| `rate` | The low bit decides playback. Odd means play or resume, even means pause. |

Given that pair, and the sample rate, a receiver computes the network time at which any other RTP timestamp should sound, by linear extrapolation from the anchor. Nothing else is needed to place a frame in time.

The realtime AirPlay 2 stream carries the same anchor as a UDP packet on the receiver's control port instead, and its type is 215. It is the classic SYNC packet with the NTP time replaced by a network time in nanoseconds and the master's clock identity appended ([shairport-sync, `rtp.c`](https://github.com/mikebrady/shairport-sync/blob/master/rtp.c), **confirmed**, and a second source names the same type carrying the same triple of an RTP time, an eight-byte network time and a second RTP time, [Cozzi, RTCP](https://web.archive.org/web/20220214214831/https://emanuelecozzi.net/docs/airplay2/rtcp/), **confirmed**).

```text
offset  size  field
  0      1    bit 0x10 marks the first packet of a session
  1      1    215, the packet type
  2      2    not read
  4      4    the RTP timestamp that should be sounding at the network time
              below, which is the anchor frame minus the stream latency
  8      8    the network time in nanoseconds, on the master clock
 16      4    the RTP timestamp that network time refers to
 20      8    the 64-bit PTP clock identity of that master
```

The difference between the two RTP timestamps is the latency the sender is asking for, and a receiver expects 77175 frames there, which is one and three quarter seconds at 44100 Hz. shairport-sync logs anything else as unusual. Note also what its AirPlay 2 control receiver does not handle: it accepts type 215 and the retransmit reply, and logs every other type as unknown, so the classic SYNC packet reaches it and does nothing ([shairport-sync, `rtp.c`](https://github.com/mikebrady/shairport-sync/blob/master/rtp.c), **confirmed**). That is the mechanism behind its refusal of an NTP stream.

On the NTP path the anchor is carried instead by the SYNC packet itself, which pairs the current NTP time with the RTP timestamp of the next audio packet, and is repeated once a second so the receiver can keep correcting ([openairplay, `src/audio/rtp_streams.md`](https://raw.githubusercontent.com/openairplay/airplay-spec/master/src/audio/rtp_streams.md), **confirmed**).

### What a sender does to keep several receivers in step

Putting the pieces together gives the following, which is **likely** as a whole because each piece is sourced but no source assembles them.

1. Every receiver in the group locks its own clock to one master clock, over PTP on ports 319 and 320. The sender originates that traffic.
2. The sender tells each receiver who else is in the group with `SETPEERS`, so every receiver watches the same addresses for clock traffic. A receiver hands that list straight to its PTP component.
3. The sender sends each receiver the same anchor with `SETRATEANCHORTIME`: the same `networkTimeTimelineID`, the same `networkTimeSecs` and `networkTimeFrac`, and the same `rtpTime`. That is one sentence saying "this audio frame sounds at this instant on that clock", and it is identical for every member.
4. Each receiver then places every other frame by extrapolating from that anchor at the sample rate, and subtracts its own output latency locally.

The consequence worth holding onto is that the sender never has to know any receiver's latency, and never has to reconcile one receiver's latency against another's. The differences cancel inside each device. What the sender owes every receiver is one clock and one anchor, identical for all of them.

`rate` is what starts and stops the group together. Its low bit means play when odd and pause when even, so a pause is one anchor message to each member rather than a separate stop protocol.

### The NTP path, in full

A sender on this path runs two UDP servers of its own, binds them **before** sending SETUP, and advertises their ports in it. One is the timing server, named by `timingPort` in the session SETUP. The other is the control socket, named by `controlPort` in the stream SETUP, which both sends SYNC packets and receives retransmit requests ([airplay2-sender-cpp, `raop_sender.cpp`](https://github.com/akustikrausch/airplay2-sender-cpp), **likely**, and the same division appears in the classic `Transport` header as `timing_port` and `control_port`, [openairplay, SETUP](https://openairplay.github.io/airplay-spec/audio/rtsp_requests/setup.html), **confirmed**).

The receiver sends **unsolicited inbound UDP** to both. On a machine whose firewall drops unsolicited inbound UDP, and on a network-address-translated virtual machine, the handshake stalls at the session SETUP and times out with no other symptom ([airplay2-sender-cpp, README](https://github.com/akustikrausch/airplay2-sender-cpp), **confirmed** as a diagnosed case).

The payload types are these ([openairplay, `src/audio/rtp_streams.md`](https://raw.githubusercontent.com/openairplay/airplay-spec/master/src/audio/rtp_streams.md), **confirmed**).

| Decimal | Hex | Port | Direction | Purpose |
|---|---|---|---|---|
| 82 | 0x52 | timing | receiver to sender | Timing request. |
| 83 | 0x53 | timing | sender to receiver | Timing reply. |
| 84 | 0x54 | control | sender to receiver | Time sync. |
| 85 | 0x55 | control | receiver to sender | Retransmit request. |
| 86 | 0x56 | control | sender to receiver | Retransmit reply. |
| 96 | 0x60 | data | sender to receiver | Audio. |

On the wire the second byte of each of these carries the marker bit as well, so payload type 84 appears as 0xD4, 83 appears as 0xD3, and 86 appears as 0xD6.

These packets are not fully RTP-conformant. They carry an eight-byte header, which is the standard twelve-byte RTP header with the four-byte SSRC left out ([openairplay, `src/audio/rtp_streams.md`](https://raw.githubusercontent.com/openairplay/airplay-spec/master/src/audio/rtp_streams.md) and [RFC 3550, section 5.1](https://www.rfc-editor.org/rfc/rfc3550.html), **confirmed**).

The SYNC packet is twenty bytes and goes to the receiver's control port once a second.

```text
offset  size  field
  0      1    0x80 normally, 0x90 on the first packet after RECORD or FLUSH
              (the extension bit, not the marker bit, marks the first one)
  1      1    0xD4, which is payload type 84 with the marker bit set
  2      2    0x0007
  4      4    RTP timestamp the receiver should currently be playing,
              which is the current timestamp minus the latency
  8      8    current NTP time, 64 bit
 16      4    RTP timestamp of the next audio packet
```

The marker bit is set on every SYNC packet, and it is the extension bit that distinguishes the first one after RECORD or FLUSH ([openairplay, `src/audio/rtp_streams.md`](https://raw.githubusercontent.com/openairplay/airplay-spec/master/src/audio/rtp_streams.md), **confirmed**; a working sender sets exactly 0x80 and 0x90 in that byte, which is the same statement, [airplay2-sender-cpp, `raop_sender.cpp`](https://github.com/akustikrausch/airplay2-sender-cpp), **confirmed**).

The timing exchange is the receiver asking and the sender answering, roughly every three seconds. Both packets are thirty-two bytes: the eight-byte header, then three NTP timestamps of eight bytes each, which are the origin, receive, and transmit times.

```text
offset  size  field
  0      1    protocol byte, echoed from the request
  1      1    0xD3, payload type 83 with the marker bit set
  2      2    0x0007
  4      4    zero padding
  8      8    origin time, copied from the request's transmit timestamp
 16      8    receive time, the sender's NTP clock when the request arrived
 24      8    transmit time, the sender's NTP clock when the reply left
```

NTP time here is the standard 64-bit fixed-point form: seconds since 1 January 1900 in the high 32 bits, and a binary fraction of a second in the low 32 bits ([RFC 3550, section 4](https://www.rfc-editor.org/rfc/rfc3550.html), **confirmed**).

Converting between that and the 44100 Hz RTP timeline is a shift in each direction, which avoids any 64-bit overflow ([airplay2-sender-cpp, `raop_sender.cpp`](https://github.com/akustikrausch/airplay2-sender-cpp), attributed there to pyatv, which in turn credits RAOP-Player for the arithmetic, **likely**).

```text
timestamp = ((ntp >> 16) * rate) >> 16
ntp       = ((timestamp << 16) / rate) << 16
```

The RTP timestamp a sender writes into an audio packet starts at the latency value and advances by 352 per packet. A working sender uses a fixed latency of 22050 plus the sample rate, which is 66150 frames at 44100 Hz, or one and a half seconds, and does not adjust it from anything the receiver says ([pyatv, `pyatv/protocols/raop/protocols/__init__.py`](https://github.com/postlund/pyatv/blob/master/pyatv/protocols/raop/protocols/__init__.py), **confirmed** as a description of pyatv, and the C++ sender uses the same constant).

### Retransmission

The receiver asks for a lost packet with payload type 85 on the sender's control port, naming the first missing sequence number and how many are missing. The sender answers with payload type 86: a four-byte header followed by the complete original audio packet, which brings its own RTP header with it, so the embedded sequence number sits at offset 6 of the reply. Both of a receiver's code paths read it at exactly that offset ([shairport-sync, `rtp.c`](https://github.com/mikebrady/shairport-sync/blob/master/rtp.c), **confirmed**). The last two bytes of that four-byte header are a 16-bit counter of the sender's own, which is what the specification means when it says the audio packet follows the sequence number ([openairplay, `src/audio/rtp_streams.md`](https://raw.githubusercontent.com/openairplay/airplay-spec/master/src/audio/rtp_streams.md), **likely**).

A sender therefore has to keep a backlog of packets it has already sent. A ring of 1024 entries indexed by the low ten bits of the sequence number is enough, and a request for something older than that is simply not answered ([airplay2-sender-cpp, `raop_sender.cpp`](https://github.com/akustikrausch/airplay2-sender-cpp), **likely**).

**The request is eight bytes, and a receiver's own sending code settles it** ([shairport-sync, `rtp.c`](https://github.com/mikebrady/shairport-sync/blob/master/rtp.c), **confirmed**).

```text
offset  size  field
  0      1    0x80
  1      1    0xD5, which is payload type 85 with the marker bit set,
              and the same byte on both AirPlay versions
  2      2    a sequence number of the receiver's own, which
              shairport-sync always sets to 1, big-endian
  4      2    the first missing sequence number, big-endian
  6      2    how many are missing, big-endian
```

pyatv reads the same eight bytes at the same offsets ([pyatv, `pyatv/protocols/raop/packets.py`](https://github.com/postlund/pyatv/blob/master/pyatv/protocols/raop/packets.py), **confirmed**). openairplay's twelve-byte description puts the two fields after an eight-byte header rather than inside it, and neither the receiver that sends these requests nor the sender that parses them uses that layout ([openairplay, `src/audio/rtp_streams.md`](https://raw.githubusercontent.com/openairplay/airplay-spec/master/src/audio/rtp_streams.md)). Read the pair at offset 4.

Buffered audio needs none of this, because TCP recovers loss itself. No source states that outright, so treat it as **likely**.

## Grouped output

### SETPEERS is a clock peer list, not a session

`SETPEERS` carries `Content-Type: /peer-list-changed` and a binary property list holding a flat array of IP address strings. That array is the list of PTP timing peers ([pyatv documentation](https://pyatv.dev/documentation/protocols/), [openairplay, `airplay2-receiver`](https://github.com/openairplay/airplay2-receiver/blob/master/ap2-receiver.py), and [shairport-sync, `rtsp.c`](https://github.com/mikebrady/shairport-sync/blob/master/rtsp.c), **confirmed** by all three).

What shairport-sync does with it settles what it is for. It takes the sender's own address together with every address in the array, and hands the whole list to nqptp, the PTP monitor ([shairport-sync, `rtsp.c`](https://github.com/mikebrady/shairport-sync/blob/master/rtsp.c), **confirmed**). The receiver is being told which addresses to watch for clock traffic.

A capture of an Apple sender shows what goes in the array. Addressing one receiver, it lists that receiver's IPv4 address, its IPv6 link-local address, and then the sender's own two addresses. Adding a second speaker to the group adds that speaker's two addresses in the middle, and the message is resent to the receiver already playing ([Cozzi, RTSP](https://web.archive.org/web/20220214214845/https://emanuelecozzi.net/docs/airplay2/rtsp/), **confirmed** from that capture). So the array is every party to the group including the sender and including the recipient, in address order rather than in role order, and it is resent on every change of membership.

`SETPEERSX` is the extended form. It carries `Content-Type: /peer-list-changed-x` and requires `features` bit 52, `SupportsSetPeersExtendedMessage`. Its body is an array of dictionaries rather than of strings, and each dictionary carries these keys ([openairplay, `airplay2-receiver`](https://github.com/openairplay/airplay2-receiver/blob/master/ap2-receiver.py), **confirmed**).

| Key | Type | Meaning |
|---|---|---|
| `Addresses` | array of strings | The peer's IP addresses. |
| `ClockID` | integer | The peer's PTP clock identity. |
| `ClockPorts` | dictionary | A map from a per-device identifier to a port number. |
| `DeviceType` | integer | The kind of device. |
| `ID` | string | The peer's identifier, a GUID. |
| `SupportsClockPortMatchingOverride` | boolean | |

That is the whole published record. shairport-sync accepts `SETPEERSX` and parses nothing from it, so it corroborates only that the method exists.

### How a sender addresses several receivers

The published sources do not state a rule, and this stays **open**. What they do show is that `SETPEERS` and `SETPEERSX` are about clock peers rather than about session topology: nothing in them nominates a receiver to relay audio to other receivers.

A capture of a second speaker being added narrows it a little. The sender's `SETPEERS` goes out on the RTSP session of the receiver that is already playing, and it names the new speaker's addresses rather than handing anything over to it. The session SETUP that opened that same connection carried a `timingPeerList` naming the sender itself as the timing peer. Both observations fit one session per receiver, and neither of them rules out a leader ([Cozzi, RTSP](https://web.archive.org/web/20220214214845/https://emanuelecozzi.net/docs/airplay2/rtsp/), **likely**).

The reading the evidence supports, and it is **likely** rather than confirmed, is that a sender opens a full session to every receiver separately, sends each of them the same `SETRATEANCHORTIME` values, and uses `SETPEERS` to tell each receiver about the others so that all of them lock to the same clock. Each receiver then works out for itself when to play each frame.

### The grouping fields

| Where | Key | Meaning | Confidence |
|---|---|---|---|
| TXT | `gid` | The group's UUID. A receiver that is not in a group publishes its own `pi` value here instead. | confirmed |
| TXT | `igl` | Is group leader, `0` or `1`. | confirmed |
| TXT | `gcgl` | Group contains a discoverable leader, `0` or `1`. Apple's sender reads it into a field it calls `groupContainsDiscoverableLeader`, whilst the session SETUP key of nearly the same name is spelled `groupContainsGroupLeader`. | confirmed |
| TXT | `pi` | The receiver's own persistent identifier. | confirmed |
| TXT | `psi` | The public AirPlay pairing identifier, a separate persistent value. | confirmed |
| plist | `isGroupLeader` | The same idea as `igl`, spelled out, seen in an `updateInfo` event body rather than in a TXT record. | confirmed |
| plist | `groupContainsGroupLeader` | Sent by the sender in the session SETUP. | likely |
| plist | `isMultiSelectAirPlay` | Sent by the sender in the session SETUP. Apple's own sender sends it true, and so does pyatv. One receiver parses it into a field and never reads that field again, and no source says what it means, so send it true and expect nothing of it. | confirmed as a field |

Sources: [shairport-sync, `bonjour_strings.c`](https://github.com/mikebrady/shairport-sync/blob/master/bonjour_strings.c) for what a receiver actually publishes, [pyatv documentation](https://pyatv.dev/documentation/protocols/) for the captured examples, [Cozzi, Service discovery](https://web.archive.org/web/20220214214811/https://emanuelecozzi.net/docs/airplay2/discovery/) for the name Apple's sender reads each key into, and [openairplay, `airplay2-receiver`, `ap2/connections/session_properties.py`](https://github.com/openairplay/airplay2-receiver/blob/master/ap2/connections/session_properties.py) for the one field a receiver parses and never uses.

## Volume

Volume is a `SET_PARAMETER` request with `Content-Type: text/parameters` and a one-line body. There is no plist form and no separate AirPlay 2 surface for it.

```text
SET_PARAMETER rtsp://<sender ip>/<session id> RTSP/1.0
CSeq: 12
Content-Type: text/parameters
Content-Length: 18

volume: -11.123877
```

The value is an attenuation in decibels. It runs from -30.0, the quietest, to 0.0, the loudest. The value -144 is a sentinel meaning muted rather than an attenuation ([openairplay, Volume Control](https://openairplay.github.io/airplay-spec/audio/volume_control.html), **confirmed**, and [pyatv, `pyatv/protocols/airplay/utils.py`](https://github.com/postlund/pyatv/blob/master/pyatv/protocols/airplay/utils.py), **confirmed** for the same constants).

Mapping a percentage onto it is linear across that range, with zero per cent special-cased to the mute sentinel.

```text
percentage 0            ->  -144.0
percentage p in 0..100  ->  (p * 3.0 - 300.0) / 10.0
```

The arrangement of that expression matters on Apple silicon. Written as `-30 + 0.3 * p`, a compiler that fuses the multiply and the add lands a hair below zero at one hundred per cent, and the text that goes on the wire becomes `-0.000000` ([airplay2-sender-cpp, `raop_sender.cpp`](https://github.com/akustikrausch/airplay2-sender-cpp), **confirmed** as a diagnosed case on Apple clang for arm64).

A current value can be read back with `GET_PARAMETER` and a body naming `volume` ([UxPlay wiki, AirPlay2](https://github.com/FDH2/UxPlay/wiki/AirPlay2), **confirmed** from a capture). What comes back can sit below the range a sender writes: a captured Sonos One answers with `volume: -100`, and the same page gives `initialVolume` as an integer from -144 to 0 ([Cozzi, RTSP](https://web.archive.org/web/20220214214845/https://emanuelecozzi.net/docs/airplay2/rtsp/), **confirmed** from that capture). Treat -30 as the floor of what a sender sets and not as the floor of what it may read.

`SET_PARAMETER` carries the rest of the per-session parameters under other content types, which is worth knowing so the volume request is not mistaken for a request of its own. `text/parameters` also carries `progress: start/current/end`, an `image/jpeg` body is the artwork, and `application/x-dmap-tagged` is now-playing information in DAAP form ([Cozzi, RTSP](https://web.archive.org/web/20220214214845/https://emanuelecozzi.net/docs/airplay2/rtsp/), **confirmed**). Those three are what the `md` TXT key says a receiver accepts.

Two TXT keys decide whether the sender has to attenuate for itself. `sv` is software volume and `sm` is software mute, and each says whether the receiver can attenuate in hardware or whether the sender must scale the samples before they leave ([pyatv documentation](https://pyatv.dev/documentation/protocols/), **confirmed**).

pyatv's starting volume is 33 per cent when the receiver reports no `initialVolume` in its `GET /info` reply, and its volume steps are five percentage points ([pyatv, `pyatv/protocols/raop/__init__.py`](https://github.com/postlund/pyatv/blob/master/pyatv/protocols/raop/__init__.py), **confirmed** as a description of pyatv). A receiver keeps whatever volume it had if the sender never sends one, which reads to a user as a connected session that plays nothing, so a sender should send a volume once the stream is up.

How per-device volume works across a group is **open**. `SET_PARAMETER` is a per-session request, so if a sender holds one session per receiver then one request per receiver follows mechanically, but no source states that as policy.

## Receiver latency

A sender proposes a range in the stream SETUP with `latencyMin` and `latencyMax`, in frames. The values a working sender uses are 11025 and 88200, which at 44100 Hz are a quarter of a second and two seconds ([pyatv, `pyatv/protocols/raop/protocols/airplayv2.py`](https://github.com/postlund/pyatv/blob/master/pyatv/protocols/raop/protocols/airplayv2.py) and [airplay2-sender-cpp, `raop_sender.cpp`](https://github.com/akustikrausch/airplay2-sender-cpp), **confirmed** for both senders).

On AirPlay 1 the receiver answers RECORD with an `Audio-Latency` header ([openairplay, RECORD](https://openairplay.github.io/airplay-spec/audio/rtsp_requests/record.html), **confirmed**). **The unit is frames**, and a receiver's own code settles it. shairport-sync answers RECORD with `Audio-Latency: 11025`, and the comment beside that line reads the number as the receiver's absolute minimum latency, to which the sender adds whatever latency it asks for. Its arithmetic is in frames throughout: AirPlay's figure of 77175 plus 11025 is exactly 88200, which is two seconds at 44100 Hz ([shairport-sync, `rtsp.c`](https://github.com/mikebrady/shairport-sync/blob/master/rtsp.c), **confirmed**). openairplay labels its captured value of 2205 as milliseconds, which is a mislabel, since read as frames it is 50 milliseconds. On the AirPlay 2 path the same receiver answers `Audio-Latency: 0`.

Neither sender uses the announced value. Both run a fixed latency of 22050 plus the sample rate ([pyatv, `pyatv/protocols/raop/protocols/__init__.py`](https://github.com/postlund/pyatv/blob/master/pyatv/protocols/raop/protocols/__init__.py), **confirmed**).

What a receiver typically wants is documented in round terms. An AirPlay 1 source sets around 2.0 to 2.25 seconds. AirPlay 2 can use much shorter latencies, around half a second ([shairport-sync, README](https://github.com/mikebrady/shairport-sync/blob/master/README.md), **confirmed**).

`audioLatencies` and `outputLatencyMicros` are real, and they come from the receiver rather than from the sender. They appear in the reply to the first `GET /info`, where `audioLatencies` is an array of dictionaries and each one carries `inputLatencyMicros`, `outputLatencyMicros`, an integer `type` naming the stream type it applies to, and an optional `audioType` of `default` or `media`. A captured Sonos One reports 400000 microseconds of output latency for every combination it lists ([Cozzi, RTSP](https://web.archive.org/web/20220214214845/https://emanuelecozzi.net/docs/airplay2/rtsp/), **confirmed** from that capture). Neither open sender reads them.

How a sender reconciles different latencies across several receivers in a group is **open**, and nothing in the reachable record addresses it. The mechanism that makes reconciliation unnecessary is worth stating, though, because it is what the anchor is for: the sender tells every receiver the same network time for the same RTP timestamp, and each receiver subtracts its own output latency locally. On that model the sender never needs to know any receiver's latency, and the differences cancel inside each device.

## Open questions

These could not be settled from the sources named below. Each carries what would settle it.

1. **Which PTP domain number and which PTP profile AirPlay 2 uses.** The transport is settled: the traffic is unicast to each peer, because nqptp receives it without ever joining a multicast group. The domain number is a header field, so one captured packet between a Mac and a HomePod names it, and the profile follows from the intervals and the fields in the same capture.
2. **Whether the receivers run a Best Master Clock election or simply accept the sender that announces.** Announce messages are exchanged and they carry the full grandmaster identity, both priority fields, the clock quality word and `stepsRemoved`, so the question is no longer whether they exist. A capture of a Mac and two HomePods settles it by showing whether either speaker ever announces a clock of its own.
3. **Whether an AirPlay 2 session that declares `NTP` uses the classic SYNC and timing packet layouts byte for byte.** The PTP path is settled, and its anchor is the type 215 control packet described under the anchor above. Two independent senders drive Apple receivers with the classic 0xD4 SYNC packet and the audio plays in step, which is strong evidence for the NTP path, but no capture of such a session is published. A capture of one settles it.
4. **The true names of `features` bits 26, 30, 38 and 48.** Three tables disagree and only Apple can settle them. This no longer blocks a sender, because every table agrees on the numbers and the properties a sender reads are derived over several bits rather than carried by one.
5. **Whether `clientID` is a field of any SETUP.** It appears in no receiver, no sender, and no capture examined here. Sending it and watching for a rejection costs one request.
6. **What `isMultiSelectAirPlay` does.** Apple's own sender sends it true and one receiver parses it and never reads it again. Copy Apple until something behaves differently.
7. **Which `X-Apple-HKP` value the PIN path wants.** A receiver's own list reserves 3 for system pairing and puts HomeKit at 6 and 7, whilst three senders send 3 for the PIN path and are answered. Pairing with a PIN against an Apple TV whilst sending 6 settles it.
8. **Whether a sender opens one session per receiver or addresses a group through a leader.** A capture of a second speaker joining shows `SETPEERS` going out on the existing receiver's own session, which fits one session each without proving it. Counting RTSP connections in a capture of a Mac playing to two speakers settles it.
9. **Per-device volume inside a group.** No source describes it. The same capture settles it.

The source that could not be reached during the first pass is reachable after all. `emanuelecozzi.net` still does not resolve, with or without the `www.` prefix, and no mirror or fork of its content was found. The Internet Archive holds every page of `emanuelecozzi.net/docs/airplay2` as it stood in February 2022, and those pages are cited throughout the sections above. They carry what a reverse engineer read out of Apple's own sender, plus captures of an iPhone streaming to a Sonos One, and between them they settled the `da` TXT key, the `features` bit names, the literal `PTP` spelling, the four session SETUP fields the open senders never send, the two forms of `GET /info`, the stream type numbers, the message order, and what goes in a `SETPEERS` array.

What that site does not carry is pairing. Its pairing page is four headings with the word TODO under each, so the most cited unofficial AirPlay 2 reference says nothing about pair-setup, pair-verify, transient pairing, or the channel keys. Those were settled from implementations instead.

## Sources

### Apple's own published material

- [Apple, HomeKitADK, `HAP/HAPPairing.h`](https://github.com/apple/HomeKitADK/blob/master/HAP/HAPPairing.h). The authoritative TLV8 type numbers and pairing error codes.
- [Apple, HomeKitADK, `HAP/HAPPairingPairSetup.c`](https://github.com/apple/HomeKitADK/blob/master/HAP/HAPPairingPairSetup.c). The pair-setup HKDF salts and info strings, the ChaCha20-Poly1305 nonce labels, the signed field order, and the SRP parameters.
- [Apple, HomeKitADK, `HAP/HAPPairingPairVerify.c`](https://github.com/apple/HomeKitADK/blob/master/HAP/HAPPairingPairVerify.c). The pair-verify message shape, its HKDF strings, its nonces, and the exact bytes each side signs.
- [Apple, `macosforge/alac`, `ALACAudioTypes.h`](https://github.com/macosforge/alac/blob/master/codec/ALACAudioTypes.h). The `ALACSpecificConfig` field order, which is what the eleven `fmtp` numbers are.
- [Apple, `macosforge/alac`, `ALACBitUtilities.h`](https://github.com/macosforge/alac/blob/master/codec/ALACBitUtilities.h). The ALAC element tag numbers.
- [Apple, `macosforge/alac`, `ALACDecoder.cpp`](https://github.com/macosforge/alac/blob/master/codec/ALACDecoder.cpp). The exact bit fields at the start of an ALAC element and the uncompressed escape.
- [Apple, Use AirPlay with Apple devices](https://support.apple.com/guide/deployment/use-airplay-dep9151c4ace/web) and [Apple, TCP and UDP ports used by Apple software products](https://support.apple.com/en-us/103229). Useful as confirmed negatives: neither mentions PTP or ports 319 and 320.

### Standards

- [RFC 5054](https://www.rfc-editor.org/rfc/rfc5054.txt). The SRP computations, the `PAD()` convention, and the 3072-bit group whose generator is 5.
- [RFC 3550](https://www.rfc-editor.org/rfc/rfc3550.html). The RTP header layout and the NTP timestamp format, which is where the eight-byte truncated header in AirPlay's control packets comes from.

### The unofficial specification

- [openairplay, Unofficial AirPlay Specification](https://openairplay.github.io/airplay-spec/). Service discovery, the features bits, the status flags, volume control, RTP streams, GET /info, RECORD, and ANNOUNCE. Its SETPEERS, POST /command, POST /feedback, and POST /audioMode pages are empty stubs, which is itself worth knowing.
- [openairplay, `src/features.md`](https://raw.githubusercontent.com/openairplay/airplay-spec/master/src/features.md) and [`src/audio/rtp_streams.md`](https://raw.githubusercontent.com/openairplay/airplay-spec/master/src/audio/rtp_streams.md). The raw sources carry per-bit notes and packet layouts that the rendered pages drop.
- [Cozzi, AirPlay 2 Internals](https://web.archive.org/web/20220214214810/https://emanuelecozzi.net/docs/airplay2/), read through the Internet Archive because the site itself no longer resolves. Its [Features](https://web.archive.org/web/20220214214810/https://emanuelecozzi.net/docs/airplay2/features/) page carries the bit names and the conditions Apple's own sender evaluates, its [Service discovery](https://web.archive.org/web/20220214214811/https://emanuelecozzi.net/docs/airplay2/discovery/) page maps every TXT key to the field the sender reads it into, its [RTSP](https://web.archive.org/web/20220214214845/https://emanuelecozzi.net/docs/airplay2/rtsp/) page is a capture of an iPhone streaming to a Sonos One with full request and reply bodies, its [Protocols](https://web.archive.org/web/20220214214828/https://emanuelecozzi.net/docs/airplay2/protocols/) page gives the message order, its [Audio](https://web.archive.org/web/20220214214824/https://emanuelecozzi.net/docs/airplay2/audio/) page enumerates every `audioFormat` bit, and its [RTCP](https://web.archive.org/web/20220214214831/https://emanuelecozzi.net/docs/airplay2/rtcp/) page names the control packet types including the type 215 anchor. Its [pairing](https://web.archive.org/web/20220214214819/https://emanuelecozzi.net/docs/airplay2/pairing/) page is a stub and carries nothing.

### Receiver implementations

- [shairport-sync](https://github.com/mikebrady/shairport-sync). An AirPlay 2 receiver. `AIRPLAY2.md` for the two stream types and the latencies, `rtsp.c` for the SETUP handling and `SETRATEANCHORTIME` and `FLUSHBUFFERED` and `SETPEERS`, `ap2_buffered_audio_processor.c` for the buffered TCP framing, `rtp.c` for the realtime framing, and `bonjour_strings.c` for what a receiver actually publishes in its TXT records.
- [nqptp](https://github.com/mikebrady/nqptp). shairport-sync's PTP helper. Its README is the clearest published statement of what the receiver side of AirPlay 2 timing does, and by omission of what the sender must do. Its `nqptp-message-handlers.c` names the three PTP message types an AirPlay sender actually sends and the Announce fields it fills in, and `nqptp-utilities.c` shows it binding both ports without joining any multicast group.
- [shairport-sync discussion 1712](https://github.com/mikebrady/shairport-sync/discussions/1712). The maintainer's own account of what is known and unknown about AirPlay 2 PTP. The most honest source in this list.
- [openairplay, `airplay2-receiver`](https://github.com/openairplay/airplay2-receiver). A Python AirPlay 2 receiver, tested against an iPhone X on iOS 13.3 by its own README. The `ct` value table, the `audioFormat` bit table, `SETPEERSX`, and `FLUSHBUFFERED`. Its `ap2/pairing/hap.py` carries the transient channel-key derivation, its `ap2/connections/stream.py` shows which SETUP keys each stream type actually reads, and its `ap2-receiver.py` enumerates the `X-Apple-HKP` values.
- [UxPlay wiki, AirPlay2](https://github.com/FDH2/UxPlay/wiki/AirPlay2). Real captures, including a SETUP whose `timingProtocol` reads `NTP`, the timing packet exchange, and volume requests.

### Sender implementations

- [pair_ap](https://github.com/ejurgensen/pair_ap). The pairing library owntone's sender uses. It settles the transient channel keys, because it derives them with one key table for both the normal and the transient client, and its header states that the resulting secret is 32 bytes after a normal pairing and 64 after a transient one.
- [owntone](https://github.com/owntone/owntone-server), `src/outputs/airplay.c`. An AirPlay 2 sender built on pair_ap. It passes the full 64-byte transient secret to the control channel whilst clamping the audio key to 32 bytes, it chooses `X-Apple-HKP` 3 or 4 on the same split as everyone else, and it records an Apple TV 4 answering a transient pair-setup with 470.
- [pyatv](https://github.com/postlund/pyatv) and its [protocol documentation](https://pyatv.dev/documentation/protocols/). The most complete open sender for AirPlay 2 realtime audio, with an unusually frank record of what it does not implement. Its TXT key table, its HKDF strings, its TLV8 tags, its volume mapping, and its SETUP bodies were all read directly.
- [airplay2-sender-cpp](https://github.com/akustikrausch/airplay2-sender-cpp), which sits in this repository at `third_party/airplay2-sender-cpp` under Apache-2.0. A working AirPlay 2 realtime sender, verified by its author against an Apple TV 4K, a HomePod, and a macOS receiver. It is the only source in this list that reports the request order, the event-channel keep-alive, the minimal 200 OK, and the audio key clamp as measured behaviour from the sending side. Its RAOP transport is in part a C++ port of pyatv, and its crypto core was reconstructed from the documentation sources above. Read here as one source among others; none of its code is reproduced in this document.
