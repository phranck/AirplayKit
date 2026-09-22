# Test log

Every experiment run against real AirPlay hardware, in the order it happened, with what it showed and what it cost to find out.

This is the raw material. `airplay2-sender-protocol.md` beside it is the tidy account, written from the published record and from what is recorded here. Nothing is removed from this file, including the runs that answered nothing, because a method that does not work is worth as much to the next person as one that does.

## How to read this, and how to write from it

Entries are appended in the order they happened and never rewritten. Each one names the date, what was done, and what came out of it.

**Every finding carries a number, `F-001` upwards, and the numbers are never reused.** A finding is one claim that can be true or false on its own. The number is what the protocol document cites, so a reader of that document can come back here and see the observation it rests on rather than taking the claim on trust. When a later run contradicts an earlier finding, the earlier one stays exactly as it is and the new one says which number it overturns.

Each finding is marked for how far the evidence reaches. **Confirmed** means it was observed directly in this run. **Likely** means it follows from something observed without having been observed itself. **Open** means it is not settled, and then the finding says what would settle it.

Findings about the protocol and findings about the measuring are both numbered, because a method that produced a wrong answer once will produce it again. A finding whose subject is the recording rather than AirPlay is marked **method**.

## The network these were run on

Nine AirPlay receivers, measured on 2026-09-22.

| Name | Model announced | Host | What it is |
|---|---|---|---|
| Kapella | `Mac16,11` | `Kapella.local` | The Mac these tests run on, receiving as well as sending |
| MacServer | `Macmini9,1` | `MacServer-3.local` | A Mac mini |
| Wohnzimmer | `AppleTV11,1` | `Wohnzimmer-2.local` | An Apple TV 4K, 2nd generation |
| Emma | `AudioAccessory5,1` | `Emma.local` | A HomePod mini |
| Wohnzimmer | `Arc` | `Sonos-38420B4C8BEC.local` | A Sonos Arc with two surrounds |
| Esszimmer | `One` | `Sonos-48A6B8F7CA56.local` | Two Sonos One as a stereo pair |
| Badezimmer | `One` | `Sonos-38420B60C6CE.local` | A Sonos One |
| Balkon | `Bookshelf` | `Sonos-542A1B58D1EE.local` | A Sonos bookshelf speaker |
| Werkstatt | `Bookshelf` | `Sonos-542A1B58D1F8.local` | A Sonos bookshelf speaker |

The Mac is on Ethernet as `en0`, address `10.0.0.193`, link-local `fe80::4fa:a6a1:43ab:8f9d`, hardware address `d0:11:e5:18:ff:5b`. Its peer-to-peer interfaces `awdl0` and `llw0` share the hardware address `be:fe:b6:55:3e:2e`.

## 2026-09-22, what a receiver says about itself over Bonjour

**What was done.** Browsed `_raop._tcp` with `dns-sd -Z` and read every TXT record.

**F-001** **Every receiver announces an `am` field, and it was being thrown away (confirmed).** Apple's receivers put the identifier their hardware is known by everywhere else into it, such as `AudioAccessory5,1` for a HomePod mini or `AppleTV11,1` for an Apple TV. Everybody else puts what they like into it: the Sonos speakers announce product names, so `Arc`, `One` and `Bookshelf`.

**F-002** **macOS keeps a picture of every Apple device it knows, filed under that same identifier (confirmed).** Every model is registered as a content type tagged with the class `com.apple.device-model-code`, so the identifier out of the Bonjour record resolves straight to a type and from there to the photograph AirDrop shows.

```text
Mac16,11           -> com.apple.macmini-2024-2
Macmini9,1         -> com.apple.macmini-2020
AppleTV11,1        -> com.apple.apple-tv-4k-2nd
AudioAccessory5,1  -> com.apple.homepod-mini-1
AudioAccessory1,1  -> com.apple.homepod-1
iPhone17,1         -> com.apple.iphone-16-pro-1
S13                -> not declared
```

The picture comes back with representations from 16 by 16 up to 2048 by 2048, whatever the logical size says.

**F-003** **The declarations also name an SF Symbol per model (confirmed).** Sweeping `/System/Library/CoreServices/CoreTypes.bundle` yields 2022 type declarations, and walking a type's conformance tree outwards finds the nearest one that names a symbol.

```text
Mac16,11           -> macmini.gen3.fill
Macmini9,1         -> macmini.gen2
AppleTV11,1        -> appletv
AudioAccessory5,1  -> homepodmini
AudioAccessory1,1  -> homepod
```

**F-004 (method)** **Learning: the harvested symbol name is not always the name an SF Symbol export uses (confirmed).** The declaration for a HomePod mini says `homepodmini`, whilst the SVG export carries `homepod.mini`. macOS resolves both, so this only bites where the name is used away from macOS. Anything that generates a symbol table for another platform has to check every harvested name against the symbol set it will draw from, and fail loudly on a miss rather than shipping a table with a hole in it.

**F-005** **A Sonos speaker serves a picture of itself (confirmed).** Its UPnP device description at `http://<host>:1400/xml/device_description.xml` carries an `iconList`, and the entry resolves on the same host. The Esszimmer speaker returned a description of 9594 bytes naming `/img/icon-S18.png`, which came back as a 48 by 48 RGBA PNG of 429 bytes. The Arc names `/img/icon-S19.png`. So a speaker that macOS has never heard of can still be drawn as itself, by asking it.

**F-006** **Reading that description needs the elements matched by local name (confirmed).** It sits in the UPnP namespace, so asking for `iconList` alone finds nothing. Both of these work on macOS and were tried against the live device:

```text
XQuery   //*:iconList/*:icon/*:url
XPath    //*[local-name()='iconList']/*[local-name()='icon']/*[local-name()='url']
```

**F-007** **A bonded Sonos set is detectable, but not from Bonjour (confirmed).** Esszimmer announces `am=One` and its description says `modelName Sonos One`, both of which describe one speaker. The truth is in the zone topology, which any player answers for the whole network:

```text
ChannelMapSet="RINCON_48A6B8F7CA5601400:LF,LF;RINCON_542A1BC43C9C01400:RF,RF"
HTSatChanMapSet="RINCON_38420B4C8BEC01400:LF,RF;RINCON_7828CA179E7201400:LR;RINCON_F0F6C181657401400:RR"
```

The first is the Esszimmer stereo pair, one device per channel. The second is the Wohnzimmer Arc with two surrounds. The second device of a pair also appears as a member carrying `Invisible="1"`.

## 2026-09-22 08:20, this Mac playing to two Apple receivers

**What was done.** `tcpdump` on `en0` whilst macOS played to the Apple TV and the HomePod mini as a group, filtering PTP, RTSP, Bonjour and small UDP. 4583 packets.

**F-008** **A sender opens one RTSP session per receiver (confirmed).** Two connections, to two different receivers, from two different local ports, over IPv6 link-local. No leader, no single session addressing a group.

```text
fe80::4fa:a6a1:43ab:8f9d.58387 -> fe80::c2d:e455:8c63:6da4.7000     (381 packets)
fe80::4fa:a6a1:43ab:8f9d.58367 -> fe80::1447:801e:9b8f:914a.7000    (371 packets)
```

**F-009** **PTP is unicast over IPv6 link-local, on ports 319 and 320, in domain 0 (confirmed).** The packets are PTPv2 with the version 1 compatibility flag set, and the flags field carries `timescale` and `unicast`. Not one multicast PTP packet appeared.

**F-010** **The Announce message carries these values (confirmed).**

| Field | Value |
|---|---|
| `priority1` | 248 |
| `clockClass` | 248 |
| `clockAccuracy` | 33, which is 0x21 |
| `clockVariance` | 17258 |
| `priority2` | differs per device |
| `stepsRemoved` | 0 |
| `timeSource` | 0xa0 |

**F-011** **The receivers contest the master election between themselves, and `priority2` decides it (confirmed).** Both announced. The Apple TV claimed `priority2` 247 and the HomePod mini claimed 233. The lower value wins under the standard algorithm, and the device that claimed 233 went on to send 514 Sync and 514 Follow_Up messages whilst the other sent two of each and then stopped.

```text
fe80::c2d:e455:8c63:6da4   p2=233   sync 514   follow up 514   delay resp 512   announce 66
fe80::1447:801e:9b8f:914a  p2=247   sync   2   follow up   2   delay req  512   announce  1
```

The loser then slaves, and its Delay_Req messages are addressed to the Mac rather than to the winner.

**F-012** **This overturns what the published record suggested (confirmed).** `airplay2-sender-protocol.md` recorded as **likely** that the sender runs the PTP master and the receivers discipline their clocks to it. The opposite happens: the receivers elect a master among themselves, and the sender is not a candidate.

**F-013** **Clock identities are not derived from a visible hardware address (confirmed).** Every identity seen ends in `0008` rather than in the `fffe` that the standard EUI-64 padding produces.

```text
f434f09b9d400008   the Apple TV
9c3e53a0ad550008   the HomePod mini
d011e56376620008   the requester the grandmaster answers, which is this Mac
```

The Mac's identity begins with `d011e5`, which is the Apple prefix of its Ethernet address `d0:11:e5:18:ff:5b`, and continues with bytes that match none of its interfaces.

**F-014 (method)** **Learning: count PTP message types on the type field and nowhere else (confirmed).** A first pass matched `msg type : ([a-z ]+)` loosely across the line and reported 512 Delay_Req messages from a device that sent none. The string had come from `control : 2 (peer delay req msg)` on a Follow_Up, which is a different field entirely. The conclusion drawn from it was wrong in a way that read as a finding. Anchor the pattern on `msg type : X msg,` including the comma.

## 2026-09-22 08:26, the same again across every interface

**What was done.** The same run with `tcpdump -i pktap,all`, to catch the peer-to-peer interfaces.

**F-015 (method)** **It did not work, and the file says so (confirmed).** The pcapng holds Interface Description Blocks for `en0` and `lo0` only. Naming `awdl0` and `llw0` explicitly in a later run made no difference either.

**F-016 (method)** **Learning: read the interface list back out of the file (confirmed).** A pcapng carries one Interface Description Block per interface that produced a packet, each with the interface name in option code 2. Reading them is the only way to know what a capture actually covered, and the capture script now prints them at the end of every run. Without that, two runs were read as findings about AirPlay when they were findings about the recording.

## 2026-09-22 08:34, an iPhone playing to this Mac

**What was done.** macOS switched on as an AirPlay receiver, an iPhone at `10.0.0.173` playing to it, `tcpdump` recording as before. 3181 packets, of which 1927 RTSP and 794 PTP.

**F-017** **The same sender is again not a PTP source (confirmed).** All 794 PTP packets come from the iPhone and are addressed to the Mac. The Mac sends none. It receives Sync, Follow_Up, Delay_Resp and Announce, and Delay_Resp cannot arrive without a Delay_Req having gone out.

**F-018** **This Mac's own PTP is never captured, in either role (confirmed).** Twice as a sender and once as a receiver, its PTP transmissions are absent whilst its RTSP is recorded in both directions on the same interface in the same file. That is a property of the recording rather than of AirPlay. PTP is timestamped in the network hardware, and that transmit path does not pass the packet filter. Seeing it needs a vantage point off this machine, such as the packet capture built into the router.

**F-019** **The transport differs by direction (confirmed).** The Mac sending to Apple receivers used IPv6 link-local. The iPhone sending to the Mac used IPv4 on the ordinary network. Nothing in the published record accounts for the difference.

**F-020** **Only the prologue of an RTSP session is readable (confirmed).** Everything after pair-verify rides the encrypted channel. What appears in the clear is this, in this order, repeated as the sender reconnects:

```text
GET /info?txtAirPlay&txtRAOP RTSP/1.0
GET /info RTSP/1.0
POST /pair-verify RTSP/1.0      X-Apple-HKP: 8
```

**F-021** **Apple's own sender uses `X-Apple-HKP: 8` (confirmed).** Four pair-verify requests, all carrying 8. The published record names only 3 and 4.

**F-022** **Two devices that have paired before skip pair-setup entirely (confirmed).** Not one `POST /pair-setup` appeared. The sender goes straight to pair-verify.

**F-023** **The sender asks `/info` repeatedly, with parameters (confirmed).** Eight requests carrying `?txtAirPlay&txtRAOP` and two without, in one session. The responses are binary property lists.

## 2026-09-22 08:55, an iPhone playing to a receiver that reads the encrypted channel

**What was done.** `openairplay/airplay2-receiver` run on this Mac as `PlayableProbe`, with an iPhone at `10.0.0.173` playing to it. The receiver holds the pairing keys, so it prints the control channel in the clear.

**What was actually captured.** The run wrote nothing to a file, for the reason in F-030, so what is recorded here comes from the terminal and covers the single receiver playing on its own. The part where a second speaker joins is not in it. The operator also reports that the volume of the iPhone itself was moved earlier than the sequence asked, at the point where only this receiver was playing, and that no sound was ever heard from the Mac.

**F-028 The order of a session, observed rather than read (confirmed).** This is the first direct sight of the request order, and it is not the order the published record describes.

```text
GET /info                 qualifier txtAirPlay
                          the channel goes encrypted here, after pair-verify
SETUP                     rtsp://10.0.0.193/8928768582649070638
GET_PARAMETER             volume
RECORD                    rtsp://10.0.0.193/8928768582649070638
SETPEERS                  rtsp://10.0.0.193/8928768582649070638
SETUP                     rtsp://10.0.0.193/8928768582649070638
```

Two things stand out. `RECORD` comes before the second `SETUP` rather than after it, and `SETPEERS` sits between them. The session is addressed by a numeric identifier in the URI, here `8928768582649070638`, and every request after the first carries the same one.

**F-029 SETPEERS carries the sender's own addresses, not the other members (confirmed).** With one receiver playing, the list holds five addresses and all five belong to the iPhone: one IPv4 and four IPv6, among them a link-local, a global and a unique local address.

```text
10.0.0.173
fe80::c74:823:970e:45fc
2a04:9546:1c0a:c01:144c:d33f:951c:9c10
fdbe:e9a4:54f4:0:1435:f725:999b:3f92
2a04:9546:1c0a:c01:c74:823:970e:45fc
```

So the name is misleading. It tells a receiver every address at which the sender can be reached, which is what a receiver needs in order to find the clock, rather than naming the other speakers in a group. Whether the list grows when a second speaker joins is **open**, and the next run answers it.

**F-030 (method) A recording made as root locks the folder it writes into (confirmed).** `tcpdump` under `sudo` created `build/captures` owned by root, and every later tool that wrote there failed with a permission error in the middle of a run. Two runs of the receiver were lost that way before the message was read. Anything that runs as root hands the whole folder back afterwards, not only the files it wrote.

**F-031 (method) The receiver plays no audio, and that is not a fault (confirmed).** Its audio thread raises and the Mac stays silent, whilst the control channel is read in full. The volume of the receiver does follow the sender, which is what says the commands arrive. Silence is the expected state for this tool.

**F-032 The sender asks the receiver for its volume before starting (confirmed).** A `GET_PARAMETER` for `volume` sits between the session `SETUP` and `RECORD`. The sender therefore takes the receiver's own level as its starting point rather than imposing one.

## 2026-09-22 09:03, the same again, written down this time

**What was done.** The same run, recorded to `airplay-sender-20260922-090345.log`, 201 lines. The iPhone played to this receiver alone, a HomePod mini joined, the volumes were moved, the HomePod left, and then this receiver left. This is the run the sequence was written for, and every step of it is in the file.

**F-033 SETPEERS is sent again whenever the group changes, and it names every member including the sender (confirmed).** Three of them in one session, and the list is the whole membership each time rather than a change to it.

```text
playing alone      10.0.0.173 and four IPv6 addresses of the sender
HomePod joins      10.0.0.154 and four of its IPv6 addresses, then the sender's five
HomePod leaves     back to the sender's five
```

The new member is listed first and the sender last. Every member contributes every address it can be reached at, one IPv4 and four IPv6, among them a link-local, a unique local and two global ones. So the request answers the question "who is in this clock group and where is each of them", and the sender counts as a member of it.

**F-034 A speaker joining an existing session changes nothing but the peer list (confirmed).** No second `SETUP`, no further `RECORD`, no new anchor, no interruption. One `SETPEERS` arrives with the enlarged list and the session carries on. The same holds in reverse when it leaves.

**F-035 The anchor is sent once, and it carries a field the published record does not mention (confirmed).**

```text
networkTimeFlags       0
networkTimeFrac        207788735369052160
networkTimeSecs        1409162
networkTimeTimelineID  -2267142311769604088
rate                   1
rtpTime                2004038641
```

`networkTimeTimelineID` is a 64 bit clock identity, printed signed here because the receiver reads it as a Python integer. `rate` is 1, which is the odd value that means play. One `SETRATEANCHORTIME` in the whole session, so the anchor is set at the start and not repeated as the group changes.

**F-036 Volume is an absolute level in decibels, sent as a text parameter (confirmed).** `SET_PARAMETER` with `volume` and a value such as `-19.799999`, `-15.949732` or `-21.144213`. Seventy seven of them arrived in one session, because a slider being dragged sends a stream of them rather than one value when it settles.

**F-037 A session is torn down in two requests, the stream and then the session (confirmed).**

```text
TEARDOWN   {'streams': [{'streamID': 1, 'type': 103}]}
TEARDOWN   {}
```

**F-038 An iPhone uses the buffered stream, type 103, not the realtime one (confirmed).** The teardown names it, and nothing in the session carries type 96. This matters for a sender: the path Apple's own phone takes to a speaker is the buffered one over TCP.

**F-039 The session identifier belongs to the session rather than to the device (confirmed).** It appears in the URI of every request after the first, and it differed between two runs against the same pair of devices: `8928768582649070638` and `2579821923116532825`.

**F-040 (method) The receiver prints no timestamps, so commands cannot be attributed to the moment they were caused (confirmed).** Seventy seven volume commands arrived and there is no way to tell which of them came from moving this receiver's own slider, which from moving the other speaker's, and which from the sender's own volume keys. Whatever runs next prefixes every line with a time, and the operator is asked to say roughly when each step was taken.

**F-041 (method) A fixed sequence with pauses in it needs no commentary, only a clock (confirmed).** F-040 asked the operator to say afterwards when each step was taken. That is unnecessary. The steps are done in a stated order with a pause between them, so a line arriving several seconds after the one before it starts the next step and everything until the next gap belongs to it. Every line now carries the time and the gap since the previous one, and the gaps do the attributing.

## What this means for the method

**F-024** **A packet recording cannot answer the questions the multi-room work turns on (confirmed).** `SETPEERS`, `SETRATEANCHORTIME`, the per-device volume commands and the teardown of a group member are all inside the encrypted control channel. No amount of recording reaches them, and repeating a run with a step that was missed the first time would not have helped.

**F-025** **A receiver holds the keys, so it can read them (likely).** Running an AirPlay 2 receiver that pairs properly and prints what it decrypts puts the whole exchange in the clear, from Apple's own sender, which is the one worth copying. `openairplay/airplay2-receiver` does exactly that.

**F-026** **It needs the port macOS holds (confirmed).** `ControlCenter` listens on `*:7000` whilst the system's own AirPlay Receiver is switched on, so that has to be off for the duration or a sender reaches the system receiver instead.

**F-027** **Setting it up on macOS 26 with Python 3.11 needs four things beyond its own requirements file (confirmed).** Its pins for `zeroconf` and `av` are old. The core dependencies install unchanged, `av` installs current at version 18.1.0, `pyaudio` needs `portaudio` from Homebrew first, and the audio module imports all three at startup whether or not any audio is wanted.

## Still open

These need the receiver run, or a vantage point off this machine.

1. Which PTP domain number and profile a group uses beyond domain 0, and whether the receivers contest the election with a full Best Master Clock exchange or accept the first announcement.
2. What this Mac transmits as PTP, which decides whether a sender is a plain slave of the elected master or a boundary clock passing the time on to the other members.
3. Whether a sender addresses each member separately for volume, and what it sends.
4. How a member leaves a group.
5. Why the transport is IPv6 link-local in one direction and IPv4 in the other.
