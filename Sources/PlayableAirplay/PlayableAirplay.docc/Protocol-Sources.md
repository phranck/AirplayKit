# Sources

Where every claim in these articles came from, and what it was measured on.

## Overview

The articles carry two kinds of claim and this one names the backing for both. The published sources come first, because a claim marked reported points at one of them. The measurements come second, because a claim marked measured is worth exactly as much as the network and the devices it was taken on, and those have to be named for the claim to be read properly.

The facts themselves are written out in the articles, in tables and fenced blocks, rather than left in the sources. That is deliberate. The most cited unofficial reference for this protocol has already gone off the air, and a link to it is worth nothing whilst a field table copied out of it is worth as much as it ever was.

## The published sources

### Apple's own published material

- [Apple, HomeKitADK, `HAP/HAPPairing.h`](https://github.com/apple/HomeKitADK/blob/master/HAP/HAPPairing.h). The TLV8 type numbers and the pairing error codes, from the accessory side of the same protocol AirPlay pairs with.
- [Apple, HomeKitADK, `HAP/HAPPairingPairSetup.c`](https://github.com/apple/HomeKitADK/blob/master/HAP/HAPPairingPairSetup.c). The pair-setup HKDF salts and info strings, the ChaCha20-Poly1305 nonce labels, the order of the signed fields, and the SRP parameters.
- [Apple, HomeKitADK, `HAP/HAPPairingPairVerify.c`](https://github.com/apple/HomeKitADK/blob/master/HAP/HAPPairingPairVerify.c). The pair-verify message shape, its HKDF strings, its nonces, and the exact bytes each side signs.
- [Apple, `macosforge/alac`, `ALACAudioTypes.h`](https://github.com/macosforge/alac/blob/master/codec/ALACAudioTypes.h). The `ALACSpecificConfig` field order, which is what the eleven `fmtp` numbers are.
- [Apple, `macosforge/alac`, `ALACBitUtilities.h`](https://github.com/macosforge/alac/blob/master/codec/ALACBitUtilities.h). The ALAC element tag numbers.
- [Apple, `macosforge/alac`, `ALACDecoder.cpp`](https://github.com/macosforge/alac/blob/master/codec/ALACDecoder.cpp). The bit fields at the start of an ALAC element and the uncompressed escape.
- [Apple, Use AirPlay with Apple devices](https://support.apple.com/guide/deployment/use-airplay-dep9151c4ace/web) and [Apple, TCP and UDP ports used by Apple software products](https://support.apple.com/en-us/103229). Useful as confirmed negatives, because neither mentions PTP or ports 319 and 320.

### Standards

- [RFC 5054](https://www.rfc-editor.org/rfc/rfc5054.txt). The SRP computations, the `PAD()` convention, and the 3072-bit group whose generator is 5.
- [RFC 3550](https://www.rfc-editor.org/rfc/rfc3550.html). The RTP header layout and the NTP timestamp format, which is where the eight-byte truncated header in AirPlay's control packets comes from.

### The unofficial specification

- [openairplay, Unofficial AirPlay Specification](https://openairplay.github.io/airplay-spec/). Service discovery, the features bits, the status flags, volume control, RTP streams, `GET /info`, RECORD and ANNOUNCE. Its SETPEERS, `POST /command`, `POST /feedback` and `POST /audioMode` pages are empty stubs, which is itself worth knowing before going looking.
- [openairplay, `src/features.md`](https://raw.githubusercontent.com/openairplay/airplay-spec/master/src/features.md) and [`src/audio/rtp_streams.md`](https://raw.githubusercontent.com/openairplay/airplay-spec/master/src/audio/rtp_streams.md). The raw sources carry per-bit notes and packet layouts that the rendered pages drop. The note saying which bits a device needs for multi-room appears only here.
- [Cozzi, AirPlay 2 Internals](https://web.archive.org/web/20220214214810/https://emanuelecozzi.net/docs/airplay2/). **This site no longer resolves.** `emanuelecozzi.net` does not answer with or without the `www.` prefix, and no mirror or fork of it was found. Every link to it in these articles goes to the Internet Archive's copy of February 2022, which holds every page. It is the most cited unofficial reference for this protocol and it exists only there.

  Its [Features](https://web.archive.org/web/20220214214810/https://emanuelecozzi.net/docs/airplay2/features/) page carries the bit names and the conditions Apple's own sender evaluates. Its [Service discovery](https://web.archive.org/web/20220214214811/https://emanuelecozzi.net/docs/airplay2/discovery/) page maps every TXT key to the field the sender reads it into. Its [RTSP](https://web.archive.org/web/20220214214845/https://emanuelecozzi.net/docs/airplay2/rtsp/) page is a capture of an iPhone streaming to a Sonos One with full request and reply bodies. Its [Protocols](https://web.archive.org/web/20220214214828/https://emanuelecozzi.net/docs/airplay2/protocols/) page gives the message order. Its [Audio](https://web.archive.org/web/20220214214824/https://emanuelecozzi.net/docs/airplay2/audio/) page enumerates every `audioFormat` bit. Its [RTCP](https://web.archive.org/web/20220214214831/https://emanuelecozzi.net/docs/airplay2/rtcp/) page names the control packet types including the type 215 anchor. Its [pairing](https://web.archive.org/web/20220214214819/https://emanuelecozzi.net/docs/airplay2/pairing/) page is four headings with the word TODO under each, so the most cited reference for this protocol says nothing at all about pair-setup, pair-verify, transient pairing or the channel keys. Those came from implementations instead.

### Receiver implementations

- [shairport-sync](https://github.com/mikebrady/shairport-sync). An AirPlay 2 receiver, and the single most useful source here, because a receiver's parser is a statement about what a sender must send. `AIRPLAY2.md` for the two stream types and the latencies, `rtsp.c` for the SETUP handling and `SETRATEANCHORTIME` and `FLUSHBUFFERED` and `SETPEERS`, `ap2_buffered_audio_processor.c` for the buffered TCP framing, `rtp.c` for the realtime framing and the retransmit request, and `bonjour_strings.c` for what a receiver publishes in its TXT records.
- [nqptp](https://github.com/mikebrady/nqptp). shairport-sync's PTP helper. Its README is the clearest published statement of what the receiver side of AirPlay 2 timing does, and by omission of what the sender must do. `nqptp-message-handlers.c` names the three PTP message types it handles and the Announce fields it reads, and `nqptp-utilities.c` shows it binding both ports without joining any multicast group.
- [shairport-sync discussion 1712](https://github.com/mikebrady/shairport-sync/discussions/1712). The maintainer's own account of what is known and unknown about AirPlay 2 PTP, and the most honest source in this list.
- [openairplay, `airplay2-receiver`](https://github.com/openairplay/airplay2-receiver). A Python AirPlay 2 receiver, tested against an iPhone X on iOS 13.3 by its own README. The `ct` value table, the `audioFormat` bit table, `SETPEERSX` and `FLUSHBUFFERED`. Its `ap2/pairing/hap.py` carries the transient channel-key derivation, its `ap2/connections/stream.py` shows which SETUP keys each stream type actually reads, and its `ap2-receiver.py` enumerates the `X-Apple-HKP` values. It is also the tool the measurements below were taken with.
- [UxPlay wiki, AirPlay2](https://github.com/FDH2/UxPlay/wiki/AirPlay2). Real captures, including a SETUP whose `timingProtocol` reads `NTP`, the timing packet exchange and volume requests.

### Sender implementations

- [pair_ap](https://github.com/ejurgensen/pair_ap). The pairing library owntone's sender uses. It settles the transient channel keys, because it derives them with one key table for both the normal and the transient client, and its header states that the resulting secret is 32 bytes after a normal pairing and 64 after a transient one.
- [owntone](https://github.com/owntone/owntone-server), `src/outputs/airplay.c`. An AirPlay 2 sender built on pair_ap. It passes the full 64-byte transient secret to the control channel whilst clamping the audio key to 32 bytes, it chooses `X-Apple-HKP` 3 or 4 on the same split as everyone else, and it records an Apple TV 4 answering a transient pair-setup with 470.
- [pyatv](https://github.com/postlund/pyatv) and its [protocol documentation](https://pyatv.dev/documentation/protocols/). The most complete open sender for AirPlay 2 realtime audio, with an unusually frank record of what it does not implement. Its TXT key table, its HKDF strings, its TLV8 tags, its volume mapping and its SETUP bodies were read directly.
- [airplay2-sender-cpp](https://github.com/akustikrausch/airplay2-sender-cpp), which sits in this repository at `third_party/airplay2-sender-cpp` under Apache-2.0. A working AirPlay 2 realtime sender, verified by its author against an Apple TV 4K, a HomePod and a macOS receiver. It is the only source in this list that reports the request order, the event-channel keep-alive, the minimal 200 OK response and the audio key clamp as measured behaviour from the sending side. Its RAOP transport is in part a port of pyatv, and its crypto core was reconstructed from the sources above. It is read here as one source among others, and none of its code is reproduced.
- [music-assistant issue 6243](https://github.com/music-assistant/support/issues/6243) and [cliairplay issue 78](https://github.com/music-assistant/cliairplay/issues/78). Reports that an NTP-only sender cannot reach a shairport-sync receiver, which is what makes the timing choice consequential rather than cosmetic.

## The measurements

Everything marked measured was observed on one home network on 22 September 2026, between 08:20 and 09:53 local time.

### The network

One wired Ethernet segment with a wireless access point on it. The Mac that ran every tool is on Ethernet as `en0`, at `10.0.0.193`, with the link-local address `fe80::4fa:a6a1:43ab:8f9d` and the hardware address `d0:11:e5:18:ff:5b`. Its peer-to-peer interfaces `awdl0` and `llw0` share the hardware address `be:fe:b6:55:3e:2e`. The iPhone is at `10.0.0.173`.

### The devices

| Name | Model announced | What it is | Operating system | Role in the measurements |
|---|---|---|---|---|
| Kapella | `Mac16,11` | Mac mini, 2024 | macOS 26 | The machine every tool ran on. Both an AirPlay sender and, for the receiver runs, an AirPlay receiver |
| (the phone) | `iPhone17,1` | iPhone 16 Pro | iOS 26 | The Apple sender whose control channel was read |
| MacServer | `Macmini9,1` | Mac mini, 2020 | not recorded | Seen in the Bonjour browse only |
| Wohnzimmer | `AppleTV11,1` | Apple TV 4K, 2nd generation | not recorded | One of the two receivers in the group capture |
| Emma | `AudioAccessory5,1` | HomePod mini | not recorded | The other receiver in the group capture, and the device the status-flag readings come from |
| Wohnzimmer | `Arc` | Sonos Arc with two surrounds | not applicable | Browsed and queried only |
| Esszimmer | `One` | Two Sonos One as a stereo pair | not applicable | Browsed and queried only |
| Badezimmer | `One` | Sonos One | not applicable | Browsed and queried only |
| Balkon | `Bookshelf` | SYMFONISK bookshelf speaker | not applicable | Browsed and queried only |
| Werkstatt | `Bookshelf` | SYMFONISK bookshelf speaker | not applicable | Browsed and queried only |

The operating system versions of the Apple TV and the HomePod mini were not recorded at the time, so no claim here rests on a particular release of either.

### Which receivers each claim covers

A protocol claim marked measured rests on the Apple devices and on nothing else. The Apple TV and the HomePod mini are the two receivers in the group capture. The Mac is the receiver that read the control channel. The iPhone is the sender in every session whose contents were read.

**None of the Sonos speakers takes part in any protocol claim.** They cannot: all five advertise `sf=0x4` whatever they are doing, and none of them answers `GET /info` with anything beyond its name. They appear in the articles only as the counter-example that shows what a non-Apple receiver withholds, and as the reason a sender reads a Sonos through its own UPnP services instead. Nothing here says how a Sonos behaves as an AirPlay receiver in a session, because no session to one was recorded.

### The tools, and what each was for

| Tool | What it was used for | Its limit |
|---|---|---|
| `dns-sd -Z` | Browsing `_raop._tcp` and reading every TXT record | Reads what is advertised, and nothing behind it |
| `curl` with `plutil` | `GET /info` on port 7000, and the Sonos UPnP actions on port 1400 | Answers a question the device chooses to answer |
| `tcpdump` on `en0`, through `Scripts/capture-airplay-group.sh` | Recording PTP, RTSP, Bonjour and small UDP beside a live session | Everything after pair-verify is encrypted, and the capturing machine's own PTP never appears |
| [openairplay, `airplay2-receiver`](https://github.com/openairplay/airplay2-receiver), run as `PlayableProbe` through `Scripts/probe-airplay-sender.sh` | Pairing properly with an Apple sender and printing the decrypted control channel | Reads one receiver's own channel. What a sender says to a different member of the same group is not in it |

Two limits of the recording are worth carrying, because they shaped what could be asked at all. Everything after pair-verify rides the encrypted channel, so a packet recording reaches `GET /info` and `POST /pair-verify` and nothing else. And the capturing machine's own PTP transmissions are absent from every recording in both roles, whilst its RTSP appears in both directions in the same file, because PTP is timestamped in the network hardware and that transmit path does not pass the packet filter.

### The raw record

`Documentation/Research/test-log.md` in this repository holds every experiment in the order it happened, including the runs that answered nothing, because a method that does not work is worth as much to the next person as one that does.

Every observation in it carries a number, `F-001` upwards, and the numbers are never reused. A finding is one claim that can be true or false on its own. That number is what a measured mark in these articles cites, so a reader can go to the log and see the observation a claim rests on rather than taking the claim on trust. Findings about the measuring itself are marked as method, because a technique that produced a wrong answer once will produce it again.

The log also holds the two session transcripts under `Documentation/Research/sources/`, and the one-word patch to the receiver that its own defect made necessary.

## What none of this establishes

One network, one iPhone, one Mac, one Apple TV, one HomePod mini, and one day. Every measured claim above is a statement about those devices on 22 September 2026 and about nothing else. A device that is not in the table was not tested, a release of an operating system that is not named was not tested, and a second network might behave differently in ways nothing here would catch. Where a measurement and a published source disagree, what is established is that the wire did this here, not that the source is wrong everywhere.
