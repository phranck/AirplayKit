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
- [Apple, Allow other people to play audio on HomePod](https://support.apple.com/en-tm/guide/homepod/apdb68d3dec5/homepod). Documents the Home app's receiver access and password choices. The operator changed and restored that setting in F-135 to F-138; the published instructions alone do not establish a device's current choice.
- [Apple, HomeKit `HMHome`](https://developer.apple.com/documentation/homekit/hmhome). Documents the public home configuration interface. It lists user access controls but no operation for changing the home-wide AirPlay speaker and TV access rule. The absence in this documented interface is not proof that no private mechanism exists. [Apple's `AirPlaySecurity` device-management payload](https://developer.apple.com/documentation/devicemanagement/airplaysecurity) applies to Apple TV on tvOS; it is not a public HomePod or home-wide setter.

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
- [airplay2-sender-cpp](https://github.com/akustikrausch/airplay2-sender-cpp), an Apache-2.0 AirPlay 2 realtime sender consulted during research. Its author reports tests against an Apple TV 4K, a HomePod and a macOS receiver. It reports the request order, event-channel keep-alive, minimal 200 OK response and audio key clamp from the sending side. Its RAOP transport is in part a port of pyatv, and its crypto core was reconstructed from the sources above. It is read here as one source among others, and none of its code is reproduced.
- [music-assistant issue 6243](https://github.com/music-assistant/support/issues/6243) and [cliairplay issue 78](https://github.com/music-assistant/cliairplay/issues/78). Reports that an NTP-only sender cannot reach a shairport-sync receiver, which is what makes the timing choice consequential rather than cosmetic.
- [doubletake](https://github.com/omarroth/doubletake). An AirPlay sender for Linux with a test receiver beside it. It is the only open implementation that handles `updateTimingPeerInfo` on the event channel and describes the message in prose, and the only one that treats `timingPeerInfo.ClockID` as mandatory, which it explains by deriving its timeline from the receiver rather than running a clock of its own.
- [Music Assistant, `airplay-cli`](https://github.com/music-assistant/airplay-cli), especially [`DESIGN.md`](https://github.com/music-assistant/airplay-cli/blob/main/DESIGN.md) and [`src/ap2_ptp.c`](https://github.com/music-assistant/airplay-cli/blob/main/src/ap2_ptp.c). A current sender implementation that reports a gPTP-dialect grandmaster on UDP 319 and 320, one shared clock for multi-room, unicast timing peer negotiation and receiver clock-readiness checks. Those are reports from that implementation, not measurements of this library. Its repository carries GPL license text, so its code is not incorporated here.

### Apple's binaries, read as symbols and strings

- [blacktop, ipsw-diffs, iOS 26.5 against iOS 27.0](https://github.com/blacktop/ipsw-diffs/tree/61157ab6a859ee24ae8c2e9a2ba08b9a5f47c991/26_5_23F77_vs_27_0_24A5355q). A published diff of Apple's own symbols, strings and feature plists between two releases. It is what dates `AsyncPTPClockConfig` and `CombinedGetInfoWithControlSetup` to OS 27, and it names the receiver-side functions behind the first of them.

  Read it for what exists rather than for what it does. A symbol name and a log string say that code is there and what it prints; neither says what it decides. Anything about control flow taken from such an extract is inference. And because the file is a diff, a string absent from it is one that did not change rather than one that does not exist.
- [UxPlay issue 535](https://github.com/FDH2/UxPlay/issues/535). The first public report of `combinedGetInfoWithControlSetup`, and the evidence that ignoring the key is survivable, because its maintainer tested an iPadOS 27 client against a receiver that implements the key nowhere and it worked.

## The measurements

Measurements began on one home network on 22 September 2026 and continued on 23 and 24 September. Each finding in the raw record gives its own date and scope.

### The network

One wired Ethernet segment with a wireless access point on it. The Mac that ran every tool is on Ethernet as `en0`, at `192.0.2.10`, with the link-local address `fe80::1` and the hardware address `02:00:00:00:00:01`. Its peer-to-peer interfaces `awdl0` and `llw0` share the hardware address `02:00:00:00:00:02`. The iPhone is at `192.0.2.20`.

### The devices

| Name | Model announced | What it is | Operating system | Role in the measurements |
|---|---|---|---|---|
| The Mac | `Mac16,11` | Mac mini M4 Pro, 2024 | macOS 27.2, build 26B5086k | The machine every tool ran on. Both an AirPlay sender and, for the receiver runs, an AirPlay receiver |
| (the phone) | not read | iPhone XR | iOS 18.7 | The Apple sender whose control channel was read, including the two-receiver test on 24 September |
| A second Mac | `Macmini9,1` | Mac mini M1, 2020 | macOS 27.0, build 26A428 | The machine the receiver ran on for the macOS sender runs and for `ProbeTwo` on 24 September |
| Room A | `AppleTV11,1` | Apple TV 4K, 2nd generation | tvOS 27.0, build 24J5325d | One of the two receivers in the group capture |
| The HomePod mini | `AudioAccessory5,1` | HomePod mini | 26.6, build 23L773 in the original capture; `ov=27.0` on 24 September | The other receiver in the Apple group capture, the status-flag readings, and the later mixed-brand test with Büro |
| Room A | `Arc` | Sonos Arc with two surrounds | Sonos 96.1-79270 | Browsed and queried only |
| Room B | `One` | Sonos One and Sonos One SL as a stereo pair | Sonos 96.1-79270 | Browsed and queried in the original survey; later test-name mapping was not recorded |
| Room C | `One` | Sonos One | Sonos 96.1-79270 | Browsed and queried in the original survey; later test-name mapping was not recorded |
| Room D | `Bookshelf` | SYMFONISK Bookshelf | Sonos 96.1-79270 | Browsed, queried and used in a single-receiver stream and an iPhone group test |
| Room E | `Bookshelf` | SYMFONISK Bookshelf | Sonos 96.1-79270 | Browsed and queried only |
| Büro | `Bookshelf` | SYMFONISK Bookshelf | Firmware not reread for this run | Played in the later two- and three-receiver tests, F-125 to F-128; same receiver as the earlier Bookshelf stream test |
| Esszimmer | `One` | Sonos One | Firmware not reread for this run | Played in the two- and three-receiver tests, F-126 and F-127 |
| Badezimmer | `One` | Sonos One | Firmware not reread for this run | Played in the three-receiver test and joined during F-127 |

Every numeric version in that table was read off the device except the phone's, which its owner states. Firmware was not reread for the three later named Sonos test entries. The Mac's version comes from `sw_vers`. The Apple TV's and the HomePod mini's come from `osBuildVersion` in their own `GET /info` answers and from the `ov` key in their Bonjour records. The original Sonos firmware comes from `SoftwareVersion` in the zone topology and from the `fv` key in their Bonjour records. The phone never answers `GET /info`, because a sender does not publish one, so nothing about it can be read off the network.

There are two Apple senders here and they are far apart in age. The phone runs an older release than everything else in the table, and the Mac runs the newest. Which of the two a measured claim came from decides how far it reaches, and the next section says which is which.

### Which receivers each claim covers

A protocol claim marked measured must be read with its finding number. The 22 September group capture used an Apple TV and a HomePod mini. Later stream experiments used a Sonos Bookshelf. On 24 September the local sender played a group tone to that Bookshelf and two Sonos One receivers, with the operator judging them simultaneous (F-126). The two controlled Python receivers on the Macs exposed both decrypted sides of one iPhone group session on the same day. Their audio output was silent or distorted, so they established control messages and anchor arithmetic, not audible synchronisation.

The iPhone drove the decrypted group control sessions; the local Swift sender drove the Sonos stream experiments. The macOS 27.2 sender established what its `/info`, pairing, FairPlay and session SETUP do against the test receiver, but it did not reach stream SETUP there. A later macOS attempt against `ProbeTwo` reached only `GET /info`, so it did not exercise the experimental event-channel reply. These are different paths and cannot be treated as a platform comparison.

The Sonos Bookshelf accepted a buffered stream from this library after the stream descriptor included `streamConnectionID`, announced its PTP clock, refused an anchor on an unknown timeline, and played when the first frame was placed ahead of that clock (measured 2026-09-23, F-098 to F-106). Later, it and two Sonos One receivers played the group tone (F-126). Other Sonos devices in the table were only browsed or queried. No conclusion about these three speakers automatically applies to every model.

The local sender's first transient pair-setup request to the HomePod mini was refused with 403 on 24 September (F-130), before any group command. The Eter Radio capture showed stored-credential pair-verify rather than pair-setup (F-136), so it did not verify this library's fresh pairing path. With Home speaker access temporarily opened, this library played a 30-second mixed group to Büro and Emma, judged audible and simultaneous by the operator (F-137 and F-138). Restoring the previous home-members-only rule restored the 403 on the unchanged first request. How an independent sender obtains an authorized pairing under that rule remains open.

### The tools, and what each was for

| Tool | What it was used for | Its limit |
|---|---|---|
| `dns-sd -Z` | Browsing `_raop._tcp` and reading every TXT record | Reads what is advertised, and nothing behind it |
| `curl` with `plutil` | `GET /info` on port 7000, and the Sonos UPnP actions on port 1400 | Answers a question the device chooses to answer |
| `tcpdump` on `en0`, through `Scripts/capture-airplay-group.sh` | Recording PTP, RTSP, Bonjour and small UDP beside a live session | Everything after pair-verify is encrypted, and the capturing machine's own PTP never appears |
| `tcpdump` filtered to Emma's port 7000 | Recording the successful Eter Radio control connection on the same Mac (F-136) | Shows pair-verify with existing credentials, not how those credentials were first obtained |
| [openairplay, `airplay2-receiver`](https://github.com/openairplay/airplay2-receiver), run as `PlayableProbe` through `Scripts/probe-airplay-sender.sh` | Pairing properly with an Apple sender and printing the decrypted control channel | Reads only its own channel. Its README does not claim accurate PTP audio synchronisation, and the test output was distorted or silent |
| The same receiver on the second Mac, reached over SSH as `ProbeTwo` | Reading the second decrypted group channel beside `PlayableProbe` and separating the macOS sender from a receiver on the same machine | The two copies publish the same `pi`, so their TXT group identity is not evidence of grouping. The macOS attempt on 24 September reached only `GET /info` |

Two limits of the recording are worth carrying, because they shaped what could be asked at all. Everything after pair-verify rides the encrypted channel, so a packet recording reaches `GET /info` and `POST /pair-verify` and nothing else. And the capturing machine's own PTP transmissions are absent from every recording in both roles, whilst its RTSP appears in both directions in the same file, because PTP is timestamped in the network hardware and that transmit path does not pass the packet filter.

### The raw record

`Documentation/Research/test-log.md` in this repository holds every experiment in the order it happened, including the runs that answered nothing, because a method that does not work is worth as much to the next person as one that does.

Every observation in it carries a number, `F-001` upwards, and the numbers are never reused. A finding is one claim that can be true or false on its own. That number is what a measured mark in these articles cites, so a reader can go to the log and see the observation a claim rests on rather than taking the claim on trust. Findings about the measuring itself are marked as method, because a technique that produced a wrong answer once will produce it again.

`Documentation/Research/sources/` holds what the log was taken with. The patch to the receiver carries four corrections, each of which exists because a run failed without it, and the README beside it says which finding each one came from. The research note there records what the published record says about the session SETUP under PTP timing, with a source and a confidence for every claim.

## What none of this establishes

One network, one iPhone, two Macs, one Apple TV, one HomePod mini, a Sonos Bookshelf, two Sonos One receivers and three days of measurements. Every finding states which device and session it covers. The controlled Python receivers cannot establish audible group synchronisation; the Sonos and mixed Sonos/HomePod groups have operator listening feedback but no measured inter-speaker offset. A device, OS release or network outside those findings may behave differently. Where a measurement and a published source disagree, what is established is that the wire did this here, not that the source is wrong everywhere.
