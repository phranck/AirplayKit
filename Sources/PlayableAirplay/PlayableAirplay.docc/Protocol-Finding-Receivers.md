# Finding receivers

What a receiver publishes about itself over Bonjour, and what it answers when asked directly.

## Overview

A receiver announces itself with multicast DNS, which is the name resolution that works on a local network with no DNS server behind it. Bonjour is Apple's name for that together with DNS service discovery, which is the half that lets a program ask who on this network does a given kind of thing. A receiver publishes a service record under a service type, and a sender browses for that type.

Everything a sender decides about a receiver before touching it is decided from those records, or from one plain request to the receiver. This article covers both.

## The two Bonjour services

A modern receiver publishes two service types, and both matter to an audio sender (reported confirmed, [openairplay, Service Discovery](https://openairplay.github.io/airplay-spec/service_discovery.html)).

| Service | Usual port | What it is for |
|---|---|---|
| `_raop._tcp` | 49152 and upwards | Remote Audio Output Protocol, which is the name AirPlay's audio half has carried since it was called AirTunes. Its instance name is the receiver's hardware address without separators, then `@`, then the display name, such as `5855CA1AE288@Apple TV`. |
| `_airplay._tcp` | 7000 | The general AirPlay service. On AirPlay 2 it carries the capability bitfield and the pairing public key. |

Take the port from the SRV record rather than assuming it. Port 7000 for `_airplay._tcp` is usual and not guaranteed, and the `_raop._tcp` port is allocated from the ephemeral range and changes when the receiver reboots (reported confirmed, [openairplay, Service Discovery](https://openairplay.github.io/airplay-spec/service_discovery.html)).

A sender ignores TXT keys it does not know, and assumes no key is present. The record is extensible and Apple has added keys across releases (reported confirmed, [openairplay, Service Discovery](https://openairplay.github.io/airplay-spec/service_discovery.html)).

## The `_raop._tcp` TXT keys

A TXT record is a set of `key=value` pairs published alongside the service. A representative record from an Apple TV 2 reads as follows (reported confirmed, [openairplay, Service Discovery](https://openairplay.github.io/airplay-spec/service_discovery.html)).

```text
txtvers=1 ch=2 cn=0,1,2,3 da=true et=0,3,5 md=0,1,2 pw=false sv=false
sr=44100 ss=16 tp=UDP vn=65537 vs=130.14 am=AppleTV2,1 sf=0x4
```

| Key | Example | Meaning | Mark |
|---|---|---|---|
| `txtvers` | `1` | Version of the TXT record format. | reported confirmed |
| `ch` | `2` | Audio channel count. | reported confirmed |
| `cn` | `0,1,2,3` | Codecs the receiver accepts. `0` is PCM, `1` is Apple Lossless, `2` is AAC, `3` is AAC ELD, `4` is Opus. | reported confirmed |
| `et` | `0,3,5` | Encryption types the receiver accepts. `0` is none, `1` is RSA and belongs to the AirPort Express, `3` is FairPlay, `4` is MFiSAP, `5` is FairPlay SAPv2.5. | reported confirmed |
| `md` | `0,1,2` | Metadata kinds the receiver accepts. `0` is text, `1` is artwork, `2` is progress. | reported confirmed |
| `pw` | `false` | Whether the receiver is password protected. On older receivers the key appears only when a password is set. | reported confirmed |
| `sr` | `44100` | Sample rate in hertz. | reported confirmed |
| `ss` | `16` | Sample size in bits. | reported confirmed |
| `tp` | `UDP` | Transport for the audio stream. | reported confirmed |
| `vs` | `130.14` | Server version, meaning the AirTunes build. | reported confirmed |
| `vn` | `65537` | Version number. | reported confirmed |
| `am` | `AppleTV2,1` | Device model. | reported confirmed |
| `da` | `true` | The receiver accepts RFC 2617 digest authentication. Apple's own sender reads it into a boolean it calls `rfc2617DigestAuthKey`. | reported likely |
| `sv` | `false` | Software volume. It says whether the receiver can attenuate in hardware or whether the sender must scale the samples itself. The other published table gives no semantics for it at all. | reported likely |
| `sm` | | Software mute, the companion to `sv`. | reported likely |
| `sf` | `0x4` | Status flags. See below. | reported confirmed |
| `pk` | 64 hexadecimal characters | The receiver's long-term Ed25519 public key, 32 bytes written as hexadecimal. Present on AirPlay 2 receivers. | reported confirmed |
| `flags` | `0x404` | The AirPlay 2 spelling of `sf`, seen on `_airplay._tcp`. | reported likely |
| `features` | `0x445F8A00,0x1C340` | The capability bitfield. See below. | reported confirmed |
| `ft` | | The features bitfield in its `_raop._tcp` spelling. | reported likely |
| `ov` | | The operating system version. | reported likely |
| `vv` | | A number Apple's own sender calls the vodka version. | reported likely |

The `cn` and `et` values, and the three keys `ft`, `ov` and `vv`, come from two tables read side by side ([pyatv, protocol documentation](https://pyatv.dev/documentation/protocols/) and [Cozzi, Service discovery](https://web.archive.org/web/20220214214811/https://emanuelecozzi.net/docs/airplay2/discovery/)). `sv` and `sm` come from pyatv's documentation, and the reading that no source gives `sv` a meaning is what the openairplay table says about its own coverage rather than about the key.

### What `am` is worth

`am` is the model, and Apple's receivers put into it the identifier their hardware is known by everywhere else, such as `AudioAccessory5,1` for a HomePod mini or `AppleTV11,1` for an Apple TV 4K (measured 2026-09-22, browsed, F-001). macOS files a picture of every model it knows under exactly that identifier, so the string out of the service record resolves to a picture without asking the device anything (measured 2026-09-22, queried, F-002).

Everybody else puts a short display label there instead. The five Sonos speakers on the measured network announce `Arc`, `One` and `Bookshelf` (measured 2026-09-22, browsed, F-001). Those are product names, and two different products arrive under one word: `Bookshelf` is IKEA's SYMFONISK, and `One` covers both a Sonos One and a Sonos One paired into a stereo set (measured 2026-09-22, queried, F-054).

A Sonos will say what it really is if asked over its own UPnP device description, which carries `modelName` and `modelNumber` beside the `displayName` that `am` repeats (measured 2026-09-22, queried, F-054).

| Room | Kind | `modelName` | `modelNumber` | `am` |
|---|---|---|---|---|
| Wohnzimmer | member | Sonos Arc | S19 | `Arc` |
| Wohnzimmer | satellite | Sonos One | S18 | not advertised |
| Wohnzimmer | satellite | Sonos One | S13 | not advertised |
| Esszimmer | member | Sonos One | S18 | `One` |
| Esszimmer | invisible | Sonos One SL | S22 | not advertised |
| Badezimmer | member | Sonos One | S18 | `One` |
| Balkon | member | SYMFONISK Bookshelf | S33 | `Bookshelf` |
| Werkstatt | member | SYMFONISK Bookshelf | S33 | `Bookshelf` |

Only the coordinator of a bonded set advertises `_raop._tcp` at all. Five of those eight speakers publish the service and the other three are reachable only through the zone topology that any one of them will answer for the whole network (measured 2026-09-22, queried, F-055).

### What `pk` is worth

`pk` is the pairing key, and its presence is what says a receiver speaks AirPlay 2 at all (measured 2026-09-22, browsed). A receiver without one runs the older RSA challenge instead.

## The `_airplay._tcp` TXT keys

| Key | Meaning | Mark |
|---|---|---|
| `deviceid` | The receiver's hardware address, colon separated. | reported confirmed |
| `features` | The 64-bit capability bitfield. | reported confirmed |
| `flags` | The status flags, the same value that `_raop._tcp` calls `sf`. | reported likely |
| `model` | Device model, such as `AppleTV2,1`. | reported confirmed |
| `srcvers` | AirPlay source version. | reported confirmed |
| `pk` | The receiver's long-term Ed25519 public key as hexadecimal. | reported confirmed |
| `pi` | The receiver's own persistent identifier, written as a UUID. | reported confirmed |
| `psi` | The public AirPlay pairing identifier, a separate persistent value. | reported confirmed |
| `gid` | The group's UUID. A receiver that is in no group publishes its own `pi` value here. | reported confirmed |
| `igl` | Is group leader, `0` or `1`. | reported confirmed |
| `gcgl` | Group contains a discoverable leader, `0` or `1`. | reported confirmed |
| `manufacturer`, `serialNumber`, `fv`, `osvers`, `protovers`, `acl`, `hmid`, `rsf` | Descriptive or access-control fields an audio sender does not need. | reported confirmed |

Source for the table: [openairplay, Service Discovery](https://openairplay.github.io/airplay-spec/service_discovery.html), with the grouping keys corroborated by [shairport-sync, `bonjour_strings.c`](https://github.com/mikebrady/shairport-sync/blob/master/bonjour_strings.c) for what a receiver publishes and by [Cozzi, Service discovery](https://web.archive.org/web/20220214214811/https://emanuelecozzi.net/docs/airplay2/discovery/) for the field Apple's sender reads each one into.

## The `features` bitfield

`features` is a 64-bit bitmask written as two 32-bit hexadecimal values separated by a comma. The value before the comma is the low word, holding bits 0 to 31. The value after it is the high word, holding bits 32 to 63. Both the comma and the high word are optional, because the field was 32 bits originally and was widened later (reported confirmed, [openairplay, Service Discovery](https://openairplay.github.io/airplay-spec/service_discovery.html)).

To test bit 40, take the high word and test its bit 8, because 40 minus 32 is 8.

These are the bits an audio sender reads (reported confirmed for the numbers and the openairplay names, [openairplay, Features](https://openairplay.github.io/airplay-spec/features.html)).

| Bit | Name |
|---|---|
| 9 | Audio |
| 11 | AudioRedundant |
| 18 to 21 | AudioFormat1 to AudioFormat4 |
| 26 | HasUnifiedAdvertiserInfo |
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

Bits 40 and 41 each carry a note in the specification's own source that the rendered page drops. Each is annotated as the bit a device needs for it to show as supporting multi-room audio, and the note names both bits rather than either one alone (reported confirmed, [openairplay, `src/features.md`](https://raw.githubusercontent.com/openairplay/airplay-spec/master/src/features.md)).

### The names are not settled, and a sender does not need them to be

Three published tables of this field exist. They agree about the numbers and disagree about the names. openairplay calls bit 38 `SupportsCoreUtilsPairingAndEncryption` and bit 48 `SupportsTransientPairing`. pyatv swaps those two round, and its own comment says there seem to be inconsistencies in the published tables (reported confirmed as a description of pyatv, [pyatv, `pyatv/protocols/airplay/utils.py`](https://github.com/postlund/pyatv/blob/master/pyatv/protocols/airplay/utils.py)). A third table, recovered from Apple's own sender, agrees with pyatv and makes bit 38 `SupportsUnifiedMediaControl` and bit 48 `SupportsCoreUtilsPairingAndEncryption` (reported likely, [Cozzi, Features](https://web.archive.org/web/20220214214810/https://emanuelecozzi.net/docs/airplay2/features/)).

What settles the question is that neither property is a single bit. Both tables state the property as a condition over several bits, from opposite directions.

```text
transient pairing                  bit 48 OR bit 43
CoreUtils pairing and encryption   bit 38 OR bit 46 OR bit 43 OR bit 48
```

openairplay says the same thing as implications: `SupportsSystemPairing` implies `SupportsTransientPairing`, and `SupportsHKPairingAndAccessControl`, `SupportsSystemPairing` and `SupportsTransientPairing` each imply `SupportsCoreUtilsPairingAndEncryption` (reported confirmed, [openairplay, `src/features.md`](https://raw.githubusercontent.com/openairplay/airplay-spec/master/src/features.md)). Compute the derived property over all four bits and the naming disagreement stops mattering, which is what pyatv does in code.

### What a receiver has to declare for multi-room

Bits 9, 11, 30, 40, 41 and 51, which is the value below (reported likely, [Cozzi, Features](https://web.archive.org/web/20220214214810/https://emanuelecozzi.net/docs/airplay2/features/)).

```text
features=0x40000a00,0x80300
```

The same table makes volume support the absence of bit 32 rather than its presence, because bit 32 set means CarPlay. It gates both `SupportsVolume` and `SupportsInitialVolume` on that bit being clear.

### Classifying a receiver by kind

A `model` beginning with `AppleTV` is an Apple TV and one beginning with `AudioAccessory` is a HomePod. A receiver is a third-party speaker when bit 26 or bit 51 is set, and a third-party television when it sets bit 0 or bit 49 as well (reported likely, [Cozzi, Features](https://web.archive.org/web/20220214214810/https://emanuelecozzi.net/docs/airplay2/features/)). Bit 26 is where the two tables part company hardest, since openairplay calls it `HasUnifiedAdvertiserInfo` and puts `RAOP` at bit 30, whilst the other calls bit 26 MFi authentication and puts `HasUnifiedAdvertiserInfo` at bit 30. The condition is the same pair of bits either way.

## The `sf` and `flags` status bits

`sf` on `_raop._tcp`, and `flags` on `_airplay._tcp`, hold a status value. Each bit is a state rather than a capability (reported confirmed, [openairplay, Status Flags](https://openairplay.github.io/airplay-spec/status_flags.html)).

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

Bits 4, 5, 8, 18 and 19 have no documented meaning, and the published table is 20 bits wide and stops there.

Two values turn up constantly and both decompose cleanly.

```text
sf=0x4   = bit 2                       Audio Cable Attached
sf=0x644 = bits 2, 6, 9, 10            Audio Cable Attached,
                                       SupportsAirPlayFromCloud,
                                       OneTimePairingRequired,
                                       DeviceWasSetupForHKAccessControl
```

Bit 9 is the one that says pairing is needed at all. A receiver advertising `sf=0x4` sets no pairing bit, and shairport-sync's classic AirPlay build publishes exactly that value whilst requiring no pairing whatsoever (reported confirmed, [shairport-sync, `bonjour_strings.c`](https://github.com/mikebrady/shairport-sync/blob/master/bonjour_strings.c)).

What bit 9 asks for is not settled. Its published name reads either way, as a one-off transient pairing or as a pairing done once and stored. pyatv calls the same bit the legacy-pairing bit and treats it, together with bit 3, as meaning only that pairing is mandatory (reported confirmed as a description of pyatv, [pyatv, `pyatv/protocols/airplay/utils.py`](https://github.com/postlund/pyatv/blob/master/pyatv/protocols/airplay/utils.py)). A working sender treats `sf=0x644` as the Apple TV PIN case (reported likely, [airplay2-sender-cpp, README](https://github.com/akustikrausch/airplay2-sender-cpp)). Read bit 9 as saying that this receiver needs pairing, and take the kind from `features`. The bit arithmetic is exact and only the reading of the name is open.

### What the bits actually do, measured

A HomePod mini was read four times, through `GET /info` and through its Bonjour record at the same four moments (measured 2026-09-22, queried, F-049 and F-050).

| State | `sf` and `statusFlags` | Bit 11, `0x800` | Bit 17, `0x20000` | Bit 20, `0x100000` |
|---|---|---|---|---|
| At rest | `0x80404` | clear | clear | clear |
| A sender connected and playing | `0x1A0C04` | set | set | set |
| Stopped, sender still connected | `0xA0C04` | set | set | clear |
| Sender disconnected | `0x80404` | clear | clear | clear |

Bits 11 and 17 move together and say that a sender holds a session. Bit 20 says audio is flowing at this moment. The value returns exactly to its resting one, so nothing is left behind and the reading repeats.

Two things follow that the published table does not carry. Bit 20 sits outside its 20-bit width altogether, so it has no published name. And bit 11's published name, `DeviceSupportsRelay`, reads as a capability, whilst the bit was observed changing four times in ten minutes on one unchanged device. What the bits are called stays open, because the published tables disagree and none of them was checked against a device. What each one indicates is not open, because it was measured.

The Bonjour record carries the same number that `GET /info` returns as `statusFlags`, and it follows the state live (measured 2026-09-22, queried, F-045 and F-050). A browse therefore learns that a speaker has become busy without asking it anything, because the change arrives as an ordinary Bonjour update.

None of this reaches a Sonos. All five advertise `sf=0x4` whatever they are doing (measured 2026-09-22, browsed, F-051).

## Asking a receiver about itself

`GET /info` on port 7000 is answered by anyone, over plain HTTP, without pairing, and it returns a binary property list (measured 2026-09-22, queried, F-043).

```bash
curl -s http://<host>:7000/info | plutil -convert xml1 -o - -
```

In a session it is an RTSP request with the ordinary identity headers, and it comes before any SETUP (reported confirmed, [openairplay, GET /info](https://openairplay.github.io/airplay-spec/audio/rtsp_requests/get_info.html); reported likely that it is required, [airplay2-sender-cpp, README](https://github.com/akustikrausch/airplay2-sender-cpp)).

```text
GET /info RTSP/1.0
X-Apple-ProtocolVersion: 1
CSeq: 0
DACP-ID: ADA239F4521B1802
Active-Remote: 753030410
User-Agent: AirPlay/550.10
```

The response body has content type `application/x-apple-binary-plist` and carries at least these keys (reported confirmed, [openairplay, GET /info](https://openairplay.github.io/airplay-spec/audio/rtsp_requests/get_info.html)).

| Key | Type | Meaning |
|---|---|---|
| `deviceID` | string | Hardware address. |
| `model` | string | Model designation. |
| `name` | string | Display name. |
| `protocolVersion` | string | AirPlay protocol version. |
| `sourceVersion` | string | Firmware or server version. |
| `features` | integer | The capability bitfield as a number rather than as the hexadecimal pair. |
| `statusFlags` | integer | The status flags as a number. |
| `manufacturer` | string | Manufacturer. |
| `sdk` | string | For example `AirPlay;2.0.2`. |
| `build` | string | Build number. |

An Apple receiver returns around forty keys in practice. Beyond the ten above, the reply carries `macAddress`, `osBuildVersion`, `featuresEx`, the formats it accepts for each kind of stream, and its current volume as `initialVolume` (measured 2026-09-22, queried, F-043).

Reading `features` and `statusFlags` here rather than from the TXT record is the more reliable route, because the reply is generated on the spot and the TXT record can be stale.

One key invites the wrong reading. `senderAddress` is the address of whoever is asking, not of whoever is playing. Three queries a second apart returned three consecutive port numbers, which are the ports of those three queries (measured 2026-09-22, queried, F-044).

### The two forms of the request

An Apple sender issues `GET /info` more than once, and the forms ask different questions (reported confirmed from a capture of an iPhone against a Sonos One, [Cozzi, RTSP](https://web.archive.org/web/20220214214845/https://emanuelecozzi.net/docs/airplay2/rtsp/)).

The qualified form carries a binary property list body naming what it wants, which is how a receiver with a thin TXT record still declares everything about itself.

```text
{'qualifier': ['txtAirPlay']}
```

The bodyless form returns the keys that exist only at this point, of which `initialVolume` is the one a sender wants.

The qualified reply is also where a receiver declares its own output latency, under a key called `audioLatencies` holding one dictionary per audio type.

| Field | Meaning |
|---|---|
| `inputLatencyMicros` | Input latency in microseconds. |
| `outputLatencyMicros` | Output latency in microseconds. |
| `type` | An integer naming the stream type it applies to. |
| `audioType` | Optional, either `default` or `media`. |

A captured Sonos One reports 400000 microseconds of output latency for every combination it lists (reported confirmed from that capture, [Cozzi, RTSP](https://web.archive.org/web/20220214214845/https://emanuelecozzi.net/docs/airplay2/rtsp/)).

Apple's own sender asks repeatedly and asks for both TXT records at once. One session held eight requests carrying `?txtAirPlay&txtRAOP` and two carrying nothing (measured 2026-09-22, captured, F-023).

### What other devices answer

A Sonos answers the same request with almost nothing. No volume, no sender, and `statusFlags` of 4, matching the `sf=0x4` it advertises (measured 2026-09-22, queried, F-047). What a Sonos is doing has to come from its own UPnP services on port 1400 instead, which answer without authentication over plain HTTP (measured 2026-09-22, queried, F-052).

| What | Service and action | Answer seen |
|---|---|---|
| Playing or not | `AVTransport` `GetTransportInfo` | `STOPPED`, with `OK` for the status |
| Volume | `RenderingControl` `GetVolume`, channel `Master` | `5`, on a scale of 0 to 100 |
| Muted | `RenderingControl` `GetMute`, channel `Master` | `0` |
| What is on it | `AVTransport` `GetPositionInfo` | The track's address and its duration |

Its volume is a whole number from 0 to 100 whilst AirPlay carries decibels, so reading one from the other is a conversion rather than a reading.

A Mac whose AirPlay receiving is switched off refuses the connection rather than answering emptily, which is a usable distinction in itself (measured 2026-09-22, queried, F-048).

## Deciding how to reach a receiver

The decision a sender makes from the service records is which authentication path to run (reported likely, [airplay2-sender-cpp, `raop_auth.h`](https://github.com/akustikrausch/airplay2-sender-cpp)).

| Observation | Path |
|---|---|
| `pw=true`, or status bit 7 Password Required | RTSP digest authentication, reactive on the first 401 response. |
| `am` beginning with `AirPort` | `POST /auth-setup`, the MFiSAP one-shot. |
| `features` bit 46 set, and status bit 9 set | HomeKit pairing with the on-screen PIN, then pair-verify. |
| `features` bit 43 or bit 48 set, which is the derived transient-pairing property, and no pairing status bit set | HomeKit transient pairing, with no user interaction. |
| None of the above | Plain AirPlay 1 RTSP with no authentication. |

pyatv makes the same decision from the same two fields and states its rules exactly (reported confirmed as a description of pyatv, [pyatv, `pyatv/protocols/airplay/utils.py`](https://github.com/postlund/pyatv/blob/master/pyatv/protocols/airplay/utils.py) and [`pyatv/protocols/airplay/auth/__init__.py`](https://github.com/postlund/pyatv/blob/master/pyatv/protocols/airplay/auth/__init__.py)).

```text
read sf, and fall back to flags
bit 7, value 0x80    a password is required
bit 9, value 0x200   pairing is mandatory
bit 3, value 0x8     pairing is mandatory

features bit 38 or bit 48   treat the receiver as AirPlay 2
features bit 43 or bit 48   use transient pairing
otherwise                   use no pairing at all
```

pyatv's own comment says openly that the AirPlay 2 test in that list is a guess rather than a known rule (open: only Apple settles what the bit means, and nothing a sender does depends on it, because the pairing choice below it is made from bits 43 and 48 directly).

A sender must also be ready for the receiver to disagree with its reading of the record, because the record can be stale and the access policy can change without it. Two recoveries are worth building in (reported likely, [airplay2-sender-cpp, `raop_sender.cpp`](https://github.com/akustikrausch/airplay2-sender-cpp)).

```text
transient pair-setup answered with 470   the receiver wants a PIN, restart on the PIN path
POST /pair-pin-start answered with 403   no on-screen PIN exists, try transient pairing once
```

The 403 case is what a macOS AirPlay receiver does, because it has no screen to put a code on.

Two devices that have paired before skip all of this and go straight to pair-verify (measured 2026-09-22, captured, F-022). <doc:Protocol-Pairing> covers what happens next.
