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
| The Mac | `Mac16,11` | `mac.local` | The Mac these tests run on, receiving as well as sending |
| A second Mac | `Macmini9,1` | `mac-2.local` | A Mac mini |
| Room A | `AppleTV11,1` | `appletv.local` | An Apple TV 4K, 2nd generation |
| The HomePod mini | `AudioAccessory5,1` | `homepod.local` | A HomePod mini |
| Room A | `Arc` | `sonos-1.local` | A Sonos Arc with two surrounds |
| Room B | `One` | `sonos-2.local` | Two Sonos One as a stereo pair |
| Room C | `One` | `sonos-3.local` | A Sonos One |
| Room D | `Bookshelf` | `sonos-4.local` | A Sonos bookshelf speaker |
| Room E | `Bookshelf` | `sonos-5.local` | A Sonos bookshelf speaker |

The versions, read off each device rather than assumed. The Mac reports macOS 27.2, build 26B5086k, from `sw_vers`, and it is a Mac mini M4 Pro. The Apple TV reports build `24J5325d` and `ov=27.0`. The HomePod mini reports build `23L773` and `ov=26.6`. Every Sonos reports `96.1-79270`. The iPhone is an iPhone XR on iOS 18.7, which its owner states, because a sender publishes no `/info` and nothing about it can be read off the network.

The Mac is on Ethernet as `en0`, address `192.0.2.10`, link-local `fe80::1`, hardware address `02:00:00:00:00:01`. Its peer-to-peer interfaces `awdl0` and `llw0` share the hardware address `02:00:00:00:00:02`.

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

**F-005** **A Sonos speaker serves a picture of itself (confirmed).** Its UPnP device description at `http://<host>:1400/xml/device_description.xml` carries an `iconList`, and the entry resolves on the same host. The Sonos One returned a description of 9594 bytes naming `/img/icon-S18.png`, which came back as a 48 by 48 RGBA PNG of 429 bytes. The Arc names `/img/icon-S19.png`. So a speaker that macOS has never heard of can still be drawn as itself, by asking it.

**F-006** **Reading that description needs the elements matched by local name (confirmed).** It sits in the UPnP namespace, so asking for `iconList` alone finds nothing. Both of these work on macOS and were tried against the live device:

```text
XQuery   //*:iconList/*:icon/*:url
XPath    //*[local-name()='iconList']/*[local-name()='icon']/*[local-name()='url']
```

**F-007** **A bonded Sonos set is detectable, but not from Bonjour (confirmed).** It announces `am=One` and its description says `modelName Sonos One`, both of which describe one speaker. The truth is in the zone topology, which any player answers for the whole network:

```text
ChannelMapSet="RINCON_EXAMPLE2:LF,LF;RINCON_EXAMPLE3:RF,RF"
HTSatChanMapSet="RINCON_EXAMPLE1:LF,RF;RINCON_EXAMPLE4:LR;RINCON_EXAMPLE5:RR"
```

The first is the stereo pair, one device per channel. The second is the Arc with two surrounds. The second device of a pair also appears as a member carrying `Invisible="1"`.

## 2026-09-22 08:20, this Mac playing to two Apple receivers

**What was done.** `tcpdump` on `en0` whilst macOS played to the Apple TV and the HomePod mini as a group, filtering PTP, RTSP, Bonjour and small UDP. 4583 packets.

**F-008** **A sender opens one RTSP session per receiver (confirmed).** Two connections, to two different receivers, from two different local ports, over IPv6 link-local. No leader, no single session addressing a group.

```text
fe80::1.58387 -> fe80::2.7000     (381 packets)
fe80::1.58367 -> fe80::3.7000    (371 packets)
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
fe80::2   p2=233   sync 514   follow up 514   delay resp 512   announce 66
fe80::3  p2=247   sync   2   follow up   2   delay req  512   announce  1
```

The loser then slaves, and its Delay_Req messages are addressed to the Mac rather than to the winner.

**F-012** **This overturns what the published record suggested (confirmed).** `airplay2-sender-protocol.md` recorded as **likely** that the sender runs the PTP master and the receivers discipline their clocks to it. The opposite happens: the receivers elect a master among themselves, and the sender is not a candidate.

**F-013** **Clock identities are not derived from a visible hardware address (confirmed).** Every identity seen ends in `0008` rather than in the `fffe` that the standard EUI-64 padding produces.

```text
f434f09b9d400008   the Apple TV
9c3e53a0ad550008   the HomePod mini
d011e56376620008   the requester the grandmaster answers, which is this Mac
```

The Mac's identity begins with `d011e5`, which is the Apple prefix of its Ethernet address `02:00:00:00:00:01`, and continues with bytes that match none of its interfaces.

**F-014 (method)** **Learning: count PTP message types on the type field and nowhere else (confirmed).** A first pass matched `msg type : ([a-z ]+)` loosely across the line and reported 512 Delay_Req messages from a device that sent none. The string had come from `control : 2 (peer delay req msg)` on a Follow_Up, which is a different field entirely. The conclusion drawn from it was wrong in a way that read as a finding. Anchor the pattern on `msg type : X msg,` including the comma.

## 2026-09-22 08:26, the same again across every interface

**What was done.** The same run with `tcpdump -i pktap,all`, to catch the peer-to-peer interfaces.

**F-015 (method)** **It did not work, and the file says so (confirmed).** The pcapng holds Interface Description Blocks for `en0` and `lo0` only. Naming `awdl0` and `llw0` explicitly in a later run made no difference either.

**F-016 (method)** **Learning: read the interface list back out of the file (confirmed).** A pcapng carries one Interface Description Block per interface that produced a packet, each with the interface name in option code 2. Reading them is the only way to know what a capture actually covered, and the capture script now prints them at the end of every run. Without that, two runs were read as findings about AirPlay when they were findings about the recording.

## 2026-09-22 08:34, an iPhone playing to this Mac

**What was done.** macOS switched on as an AirPlay receiver, an iPhone at `192.0.2.20` playing to it, `tcpdump` recording as before. 3181 packets, of which 1927 RTSP and 794 PTP.

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

**What was done.** `openairplay/airplay2-receiver` run on this Mac as `PlayableProbe`, with an iPhone at `192.0.2.20` playing to it. The receiver holds the pairing keys, so it prints the control channel in the clear.

**What was actually captured.** The run wrote nothing to a file, for the reason in F-030, so what is recorded here comes from the terminal and covers the single receiver playing on its own. The part where a second speaker joins is not in it. The operator also reports that the volume of the iPhone itself was moved earlier than the sequence asked, at the point where only this receiver was playing, and that no sound was ever heard from the Mac.

**F-028 The order of a session, observed rather than read (confirmed).** This is the first direct sight of the request order, and it is not the order the published record describes.

```text
GET /info                 qualifier txtAirPlay
                          the channel goes encrypted here, after pair-verify
SETUP                     rtsp://192.0.2.10/8928768582649070638
GET_PARAMETER             volume
RECORD                    rtsp://192.0.2.10/8928768582649070638
SETPEERS                  rtsp://192.0.2.10/8928768582649070638
SETUP                     rtsp://192.0.2.10/8928768582649070638
```

Two things stand out. `RECORD` comes before the second `SETUP` rather than after it, and `SETPEERS` sits between them. The session is addressed by a numeric identifier in the URI, here `8928768582649070638`, and every request after the first carries the same one.

**F-029 SETPEERS carries the sender's own addresses, not the other members (confirmed).** With one receiver playing, the list holds five addresses and all five belong to the iPhone: one IPv4 and four IPv6, among them a link-local, a global and a unique local address.

```text
192.0.2.20
fe80::4
2001:db8::5
fd00::4
2001:db8::4
```

So the name is misleading. It tells a receiver every address at which the sender can be reached, which is what a receiver needs in order to find the clock, rather than naming the other speakers in a group. Whether the list grows when a second speaker joins is **open**, and the next run answers it.

**F-030 (method) A recording made as root locks the folder it writes into (confirmed).** `tcpdump` under `sudo` created `build/captures` owned by root, and every later tool that wrote there failed with a permission error in the middle of a run. Two runs of the receiver were lost that way before the message was read. Anything that runs as root hands the whole folder back afterwards, not only the files it wrote.

**F-031 (method) The receiver plays no audio, and that is not a fault (confirmed).** Its audio thread raises and the Mac stays silent, whilst the control channel is read in full. The volume of the receiver does follow the sender, which is what says the commands arrive. Silence is the expected state for this tool.

**F-032 The sender asks the receiver for its volume before starting (confirmed).** A `GET_PARAMETER` for `volume` sits between the session `SETUP` and `RECORD`. The sender therefore takes the receiver's own level as its starting point rather than imposing one.

## 2026-09-22 09:03, the same again, written down this time

**What was done.** The same run, recorded to `airplay-sender-20260922-090345.log`, 201 lines. The iPhone played to this receiver alone, a HomePod mini joined, the volumes were moved, the HomePod left, and then this receiver left. This is the run the sequence was written for, and every step of it is in the file.

**F-033 SETPEERS is sent again whenever the group changes, and it names every member including the sender (confirmed).** Three of them in one session, and the list is the whole membership each time rather than a change to it.

```text
playing alone      192.0.2.20 and four IPv6 addresses of the sender
HomePod joins      192.0.2.30 and four of its IPv6 addresses, then the sender's five
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

## 2026-09-22 09:23, steering the session from the Mac, and what a receiver tells anyone who asks

**What was done.** The same run, with the first four steps on the iPhone and the rest attempted on the Mac. It stopped after the fourth, and the reason turned out to be worth more than the run.

**F-042 macOS offers no control over another device's AirPlay session (confirmed).** Its speaker list shows which speakers exist and nothing about which are playing, and the only volume it offers is the system's own. The log ends at the moment the HomePod joined, because nothing done on the Mac afterwards reached the session at all.

**F-043 A receiver answers `GET /info` to anyone, over plain HTTP, without pairing (confirmed).** Port 7000, no headers needed, and the answer is a binary property list.

```bash
curl -s http://<host>:7000/info | plutil -convert xml1 -o - -
```

An Apple receiver returns around forty keys, among them `name`, `model`, `deviceID`, `macAddress`, `osBuildVersion`, `features`, `featuresEx`, `protocolVersion`, `sourceVersion`, the formats it accepts for each kind of stream, its current volume as `initialVolume`, and `statusFlags`.

**F-044 `senderAddress` is whoever is asking, not who is playing (confirmed).** Three queries one second apart returned `192.0.2.10:59501`, `:59502` and `:59503`, which is the port of each query's own connection. The name invites the opposite reading and it is wrong.

**F-045 `statusFlags` is the same value the receiver advertises as `sf` over Bonjour (confirmed).** the HomePod mini reports `statusFlags` 525316 and advertises `sf=0x80404`, which are the same number. So the state is already in the discovery record and costs no request at all.

**F-046 `statusFlags` moves whilst a receiver is in a session (confirmed), and which bit means busy is open.** the HomePod mini read `0x80404` at rest, and `0xA0C04` and `0x1A0904` around a session. The bits that come and go are `0x20000`, `0x800` and `0x100000`, and `0x400` is set at rest but not during. A reading taken at rest and a reading taken whilst one speaker alone is playing settle it.

**F-047 A Sonos answers `/info` with almost nothing (confirmed).** No volume, no sender, `statusFlags` 4, and it advertises `sf=0x4`. So the state of a Sonos is not readable this way, and what a Sonos is doing has to come from its own zone topology instead.

**F-048 A Mac whose AirPlay receiving is switched off does not answer `/info` at all (confirmed).** The connection is refused rather than answered emptily, which is a usable distinction in itself.

## 2026-09-22 09:30, what a receiver says about its own state

**What was done.** the HomePod mini, a HomePod mini, read four times through `GET /info` and through its Bonjour record at the same moments: at rest, whilst an iPhone played to it alone, after the playback was stopped, and after the iPhone disconnected from it.

**F-049 A receiver says both whether a sender is connected and whether audio is playing, in two separate bits (confirmed).**

| State | `statusFlags` | Bit 11, 0x800 | Bit 17, 0x20000 | Bit 20, 0x100000 |
|---|---|---|---|---|
| At rest | `0x80404` | clear | clear | clear |
| A sender connected and playing | `0x1A0C04` | set | set | set |
| Stopped, sender still connected | `0xA0C04` | set | set | clear |
| Sender disconnected | `0x80404` | clear | clear | clear |

Bits 11 and 17 move together and mean that a sender holds a session. Bit 20 means audio is flowing at this moment. The value returns exactly to its resting one, so nothing is left behind and the reading is repeatable.

What the bits are called is **open**, because the published tables disagree and none of them was measured. What each one indicates is not open, because it was.

**F-050 The Bonjour record carries the same value and follows the state live (confirmed).** `sf` in the TXT record read `0x80404`, `0x1a0c04`, `0xa0c04` and `0x80404` at the four moments, matching `statusFlags` each time. A browse therefore learns that a speaker has become busy without asking it anything, because the change arrives as an ordinary Bonjour update.

**F-051 Only an Apple receiver answers this (confirmed).** The Sonos speakers advertise `sf=0x4` at rest and return almost nothing from `/info`, with no volume and no state. What a Sonos is doing has to come from its own zone topology instead, which is the same request that reveals a stereo pair.

## 2026-09-22 09:40, what a Sonos will tell us

**What was done.** A single Sonos One asked over its UPnP services on port 1400.

**F-052 A Sonos reports everything its AirPlay record withholds (confirmed).** Three requests, no authentication, plain HTTP.

| What | Service and action | Answer seen |
|---|---|---|
| Playing or not | `AVTransport` `GetTransportInfo` | `STOPPED`, and `OK` for the status |
| Volume | `RenderingControl` `GetVolume` with channel `Master` | `5`, on a scale of 0 to 100 |
| Muted | `RenderingControl` `GetMute` with channel `Master` | `0` |
| What is on it | `AVTransport` `GetPositionInfo` | the track's address and its duration |

So the state that `sf` never reports for a Sonos is readable from the speaker itself, on a different scale and through a different protocol. Its volume is a whole number from 0 to 100 whilst AirPlay carries decibels, which is a conversion rather than a reading.

**F-053 (method) The receiver's port is fixed in its source (confirmed).** `ap2-receiver.py` hard codes 7000 in two places and takes no option for it, so two instances on one machine need a patch of two lines. That is what stands between here and watching one sender address two receivers that we control.

## 2026-09-22 09:45, every Sonos on the network, one by one

**What was done.** Each Sonos asked for its own device description, and then the zone topology used to find the ones that do not advertise AirPlay at all.

**F-054 The device description names the model properly, whilst the AirPlay record gives a short label (confirmed).** `am` in the Bonjour record carries `Arc`, `One` or `Bookshelf`, which is the same string the description calls `displayName`. The description also carries `modelName` and `modelNumber`, and those are the ones that identify the hardware.

| Room | Address | Kind | `modelName` | `modelNumber` | `am` |
|---|---|---|---|---|---|
| Room A | 192.0.2.41 | member | Sonos Arc | S19 | `Arc` |
| Room A | 192.0.2.42 | satellite | Sonos One | S18 | not advertised |
| Room A | 192.0.2.43 | satellite | Sonos One | S13 | not advertised |
| Room B | 192.0.2.44 | member | Sonos One | S18 | `One` |
| Room B | 192.0.2.45 | invisible | Sonos One SL | S22 | not advertised |
| Room C | 192.0.2.46 | member | Sonos One | S18 | `One` |
| Room D | 192.0.2.47 | member | SYMFONISK Bookshelf | S33 | `Bookshelf` |
| Room E | 192.0.2.48 | member | SYMFONISK Bookshelf | S33 | `Bookshelf` |

`Bookshelf` is IKEA's SYMFONISK, and nothing in the AirPlay record says so. A list drawing from `am` alone calls two different products by the same word, and calls an IKEA speaker by a word IKEA does not use.

**F-055 A bonded set is made of different models, and only the coordinator is on the network as far as AirPlay is concerned (confirmed).** The stereo pair is a Sonos One and a Sonos One SL. The soundbar set is an Arc with two Sonos One as surrounds, and those two are different generations, S18 and S13. Five of the eight speakers advertise `_raop._tcp`, and the other three are reachable only through the topology.

So a bonded set can be named for what it actually is rather than as one speaker, and its picture could be made from the pictures of its members, each of which serves its own.

## 2026-09-22 09:53, pause, resume, a track change and a seek

**What was done.** An iPhone played to this receiver, then paused, resumed, skipped to the next track, sought within it, and stopped. Every anchor read out in full.

**F-056 Playing and pausing are the same request with different bodies, and the pause carries nothing but the rate (confirmed).**

```text
09:53:43  start    {'networkTimeFlags': 0, 'networkTimeFrac': -8768708216239423488,
                    'networkTimeSecs': 1410493, 'networkTimeTimelineID': -2267142311769604088,
                    'rate': 1, 'rtpTime': 1442375314}
09:53:48  pause    {'rate': 0}
09:53:54  resume   {... 'networkTimeSecs': 1410503, ... 'rate': 1, 'rtpTime': 1442542965}
09:54:03  track    {... 'networkTimeSecs': 1410512, ... 'rate': 1, 'rtpTime': 3133593496}
09:54:10  seek     {'rate': 0}
09:54:12  seek     {... 'networkTimeSecs': 1410521, ... 'rate': 1, 'rtpTime': 2969409775}
```

Every `rate: 1` carries the whole set. Every `rate: 0` carries the one key and nothing else, so a receiver told to stop is not told when to stop: it stops now.

**F-057 The timeline identity is the sender's PTP clock, and it outlives the session (confirmed).** `networkTimeTimelineID` read `-2267142311769604088` in every anchor of this session and in every session recorded today, five of them over an hour, including ones to a differently named receiver. As an unsigned value that is `0xE0897E144BB70008`, which is the shape of the PTP clock identities measured from the receivers earlier: `0xF434F09B9D400008`, `0x9C3E53A0AD550008` and `0xD011E56376620008`. All of them end in `0008`.

So the anchor names the clock its times are expressed against, and that clock belongs to the sender. This is the join between the two halves of the investigation: the timing traffic on ports 319 and 320 and the anchor in the control channel refer to the same identity.

**F-058 A track change is a flush followed by a fresh anchor (confirmed).** The metadata arrives first, with the player state going to `Paused` and the new title beside it, then `FLUSHBUFFERED`, then an anchor at `rate: 1` whose `rtpTime` bears no relation to the previous one. Each track gets a timeline of its own.

**F-059 A seek is a pause and then a new anchor (confirmed).** Exactly the same two requests as a resume, two seconds apart, with the new position in `rtpTime`. Nothing distinguishes a seek from a resume except where the timeline is put.

**F-060 Metadata arrives as DMAP, and the player state comes with it (confirmed).** `dmap.persistentid` identifies the item, `dmap.itemname` names it, and `dacp.playerstate` reads `Playing` or `Paused`. It is re-sent repeatedly whilst playing rather than only when something changes.

**F-061 Stopping is a flush and then the teardown (confirmed).** `FLUSHBUFFERED` at 09:54:18 and `TEARDOWN` at the same second.

**F-062 (method) A macOS sender reaches this receiver and stops at the session SETUP (confirmed).** It resolved the receiver, fetched its device information, completed pair-verify and opened the encrypted channel, sent `SETUP`, and then showed "Could not connect". Nothing followed and it did not try again. Two causes are possible and this run cannot separate them: macOS may refuse a session to an address on the same machine, or a macOS sender may want something in the session SETUP that this receiver does not answer, since its own record says it was tested against an iPhone. Running the receiver on a second machine separates them.

**F-063 (method) The receiver dropped every session at the first anchor, through a fault of its own (confirmed).** `do_SETRATEANCHORTIME` catches the broken audio pipe and then formats a name that is not bound, so a `NameError` escapes and takes the connection with it. One word fixes it, and the patch is kept beside this log as `sources/airplay2-receiver-local.patch`. The failure looked like a protocol problem and was not one, which is the reason to read the whole traceback rather than the last line.

**F-064** **The volume of one speaker reaches that speaker alone (confirmed).** Read out of the run of 09:12, whose log carries the time and the gap on every line. Nine volume commands arrived between 09:13:47 and 09:13:48 whilst this receiver's own slider was dragged. Then nothing at all arrived until 09:14:07, the nineteen seconds during which the other member of the group had its level changed. Four more arrived from 09:14:07, one a second, which is the device's own volume buttons moving the whole group.

So there is no group command. A device's own volume control moves every member by sending each of them its own `SET_PARAMETER` on its own session, and a per device change is addressed to that device and reaches nobody else. This was narrated at the time and not written down, and the reference cited it before it existed here, which is the reason it is numbered now rather than left as prose.

## 2026-09-22 12:45, a receiver we control on a second machine

**What was done.** Set the same `openairplay/airplay2-receiver` up on the second Mac, a Mac mini M1 running macOS 27.0 build 26A428, reached over SSH. Started it as `ProbeTwo` on `en0`, address `192.0.2.11`. Then browsed both service types from this Mac and from that one, and read every TXT record of both.

This run exists to separate the two causes F-062 left standing, because there a macOS sender and the receiver sat on one machine.

**F-065 (method) `brew --prefix <formula>` answers a path whether or not the formula is installed (confirmed).** It printed `/opt/homebrew/opt/portaudio` with nothing behind it, so the compiler was handed an include path to a directory that did not exist and the build failed on a missing header rather than on a missing package. The check is `ls "$(brew --prefix portaudio)/include"`, not the prefix on its own.

**F-066 This receiver advertises `_airplay._tcp` and never `_raop._tcp` (confirmed).** `register_mdns` publishes one service and it is `_airplay._tcp.local.`. A browse for `_raop._tcp` from either machine found the eight real receivers and not this one; a browse for `_airplay._tcp` found nine. So a sender that browses only the RAOP type cannot see it, and this library browses only that type.

What this does not settle is whether any shipping hardware does the same. All eight real receivers on this network publish both, so the case is demonstrated by an implementation rather than found in the wild.

**F-067 The two service types carry the same facts under different keys, and the status word appears in both and agrees (confirmed).** Read at the same minute off three receivers. `am` in the RAOP record is `model` in the AirPlay one, and carried the same value each time: `Arc`, `AudioAccessory5,1`, `Macmini9,1`. `ov` is `osvers`, both `26.6` on the HomePod mini. `ft` is `features`, `vs` is `srcvers`, and `pk` and `pi` keep their names.

`sf` and `flags` are the same word. The Sonos read `0x4` in both, the second Mac `0x204` in both, and the HomePod mini `0x98404` in both, at the same moment. So the state this library reads out of `sf` can be read out of an AirPlay record as `flags` without a second model of what it means.

**F-068 The group identity is published in the AirPlay record and nowhere in the RAOP one (confirmed).** Every `_airplay._tcp` record carried `gid`, `gcgl` and, on the Apple devices, `igl`. The Sonos Arc's `gid` equalled its own `pi`, which is a receiver in a group of itself. The HomePod mini's `gid` held two identifiers joined by `+`, with `igl=1` and `gcgl=1` beside it. None of `gid`, `gcgl` or `igl` appears in any `_raop._tcp` record on this network.

What `igl` and `gcgl` stand for is not measured here. What is measured is that a receiver publishes which group it belongs to, and that the RAOP record this library reads does not carry it.

**F-069 A resting HomePod mini does not always report the same status word (confirmed).** F-045 and F-050 read `0x80404` off it at rest this morning, and F-050 read it again at the end of a session. At 13:03 the same device at rest read `0x98404`, so bits `0x8000` and `0x10000` had appeared. Its group identity now holds two members where the earlier readings were taken with it alone, which is a cause worth suspecting and not one this run establishes.

Neither bit falls inside the two masks this library uses, so both readings answer free and not playing, which is what the device was. The finding is a warning rather than a defect: the word carries more than the two answers taken from it, and a reading that tested the whole value against `0x80404` would already be wrong.

## 2026-09-22 13:23, what a macOS sender asks a receiver before it will send

**What was done.** Selected the receiver on the second Mac as the sound output of this Mac, four times, correcting what the receiver answered between attempts. The receiver was started fresh each time, so every attempt is an unpaired device.

Device identifiers below are replaced the way the table at the top of this file replaces them. The hardware address of this Mac is written `02:00:00:00:00:01` throughout.

**F-070 A macOS sender's first request is a plain HTTP `GET /info?txtAirPlay&txtRAOP` (confirmed).** Not RTSP, and no body. It carries exactly one header, `X-Apple-QR: BT`, and no `CSeq`. An iPhone asks the same thing differently: over RTSP, with a binary plist body reading `{'qualifier': ['txtAirPlay']}`, and it asks for the AirPlay record alone.

**F-071 Both service records can be fetched over HTTP from the receiver itself (confirmed).** Measured against the HomePod mini. `/info` answers 1453 bytes and neither record; `/info?txtAirPlay&txtRAOP` answers 2140 bytes with two extra keys, `txtAirPlay` and `txtRAOP`, each holding that Bonjour TXT record verbatim in its counted DNS-SD form. Their contents matched what the device advertises, key for key, at the same minute.

So everything this library reads out of discovery can also be read from a known host with one request, which is what a refresh of one selected receiver looks like without waiting for a Bonjour update.

**F-072 A macOS sender reads `supportedFormats` out of `/info` and stops there when it is absent (confirmed).** Compared the two `/info` answers key by key. The HomePod mini names `supportedFormats`, `supportedAudioFormatsExtended`, `pk`, `volumeControlType`, `vv`, `initialVolume`, `featuresEx`, `psi`, `macAddress` and `osBuildVersion`; the Python receiver named none of them. With those absent, three attempts ended at `/info` with nothing following it. Adding `supportedFormats`, `pk`, `volumeControlType` and `vv` took the next attempt through pairing and into the session, so the four together are what was missing. Which one alone is the gate was not separated, and `supportedFormats` is the one a sender has to read to know what it may send.

**F-073 A macOS sender pairs transiently, on the spot, with no stored pairing (confirmed).** `POST /pair-setup` carrying `X-Apple-HKP: 4`, in two stages, the second answering 64 bytes. The encrypted channel is open immediately afterwards. The request names the sender in its own headers, `X-Apple-Client-Name` and `X-Apple-Client-ID`, and `User-Agent: AirPlay/1005.7.1`.

**F-074 FairPlay runs twice before the session, over the encrypted channel (confirmed).** `POST /fp-setup` with `X-Apple-ET: 32`, first with a 16 byte body and then with a 164 byte one. Both are inside the encrypted channel, so nothing outside the receiver could have seen them.

**F-075 The session SETUP says what the sender is and what it wants, and the timing is PTP (confirmed).** One `SETUP rtsp://<receiver>/<session id>` with a 930 byte binary plist, carrying `timingProtocol: 'PTP'` and, beside it, `asyncPTPClockConfig: True`, `combinedGetInfoWithControlSetup: True`, `isMultiSelectAirPlay: True`, `senderSupportsRelay: True`, `groupUUID`, `groupContainsGroupLeader: False`, `updateSessionRequest: False`, `diagnosticsAndUsage: True`, `statsCollectionEnabled: False` and `internalBuild: False`.

It also describes itself completely: `model`, `name`, `osName: 'macOS'`, `osVersion`, `osBuildVersion`, `sourceVersion`, `deviceID` and `macAddress`, plus `sessionUUID` and `sessionCorrelationUUID`. A receiver therefore learns what kind of sender it is talking to, which nothing on the network says.

`timingPeerInfo` and `timingPeerList` both hold one entry, the sender: `{ClockID: <int64>, DeviceType: 0, ID: <uuid>, SupportsClockPortMatchingOverride: True}`. The `ID` there is the `sessionCorrelationUUID`, not a hardware address.

**F-076 The PTP clock identity is the device's hardware address with `0008` after it (confirmed).** The `ClockID` in that plist, read as unsigned, is the sender's own hardware address followed by two bytes `00 08`. Written with this file's placeholder address that is `0x0200000000010008`.

This settles what F-057 observed without explaining: every clock identity measured that day ended in `0008`, and this is why. It is not the standard EUI-64 expansion, which inserts `FFFE` in the middle; it is the six address bytes with `0008` appended.

**F-077 The sender stops after the session SETUP is answered, and it is not about sharing a machine (confirmed, and it narrows F-062).** The receiver answered `{'eventPort': <port>, 'timingPort': 0, 'timingPeerInfo': {'Addresses': ['<ipv4>'], 'ID': '<hardware address>'}}`. The sender waited eight seconds, made one more `GET /info?txtAirPlay&txtRAOP`, and showed "Could not connect". No stream level SETUP ever followed.

F-062 saw the same stop and could not tell whether macOS refuses a receiver on its own machine or wants something the receiver does not answer. The receiver is on a different machine here and it stops in the same place, so the first cause is ruled out. The eight second wait is the shape of a timeout, which points at something the sender expects to arrive rather than at the answer being rejected outright.

The same receiver completes a full session with an iPhone on iOS 18.7 and the same reply, so a macOS sender wants something at this point that an iOS sender does not.

**F-078 A receiver that reports `02:00:00:00:00:00` as its hardware address gets nothing from a macOS sender (confirmed, and it does not hold for iOS).** `netifaces` read no address on the second Mac, so the receiver published that value as its `deviceid`. Three connections arrived from this Mac and not one byte followed on any of them. Starting the receiver with a random address produced `GET /info` on the first connection. An iPhone had completed a whole session against a receiver advertising that same all zero value earlier the same day, so this is a macOS sender being stricter rather than a rule of the protocol.

**F-079 (method) The Python receiver answers an HTTP request in RTSP, and sends a header reading `None` (confirmed).** It forces `protocol_version = "RTSP/1.0"` for every reply, so a plain `GET /info HTTP/1.1` is answered `RTSP/1.0 200 OK`, which `curl` refuses outright. The HomePod mini answers the same request `HTTP/1.1 200 OK`. Several handlers also echo `CSeq` straight back, and an HTTP request carries none, so the reply read `CSeq: None`. Both are corrected in the patch kept beside this log.

`/info` is therefore an HTTP request answered in HTTP, before any RTSP session exists, and a receiver has to speak both on the same port.

**F-080 (method) Python's line iterator holds a log in its buffer (confirmed).** `stamp.py` read its input with `for line in sys.stdin`, which reads ahead by a block, so a receiver that writes a dozen lines and then waits produced an empty log file. `readline` returns what has arrived. The cost was one run spent thinking the receiver had not started.

**F-081 An iPhone playing music asks for the buffered stream, type 103 (confirmed).** Read back out of the three sessions recorded this morning, all of them from an iPhone on iOS 18.7 to the receiver on this Mac. Each teardown named the stream it was closing, and all three read `{'streams': [{'streamID': 1, 'type': 103}]}`. None used 96.

So the buffered path over TCP is what a current Apple sender uses for music, and the realtime path is not what a receiver will be offered first. What this does not say is what a sender does with a live source that cannot be buffered ahead, because all three sessions played from a library.

## 2026-09-22 13:45, what the published record says about the stop at the session SETUP

**What was done.** Read the two open senders and the two open receivers that implement this, and Apple's own symbol and string tables, against the question F-077 leaves open. The whole of it is written up beside this log as `sources/session-setup-ptp-research.md`, with a source and a confidence for every claim. Only what changes a finding here is repeated.

**F-082 F-077 and F-078 compared two things at once, and the comparison does not carry (confirmed).** Both were written as a macOS sender being stricter than an iOS one. The macOS sender is on OS 27.2 and the iPhone is on iOS 18.7, so platform and version moved together and neither finding can separate them.

It is worse than an ordinary confound, because two of the keys in the session SETUP are new in OS 27. `AsyncPTPClockConfig` and `CombinedGetInfoWithControlSetup` appear as added entries in Apple's own feature plist in the published iOS 26.5 to 27.0 diff, together with `CombinedGetInfoWithPairing` and `SkipRecord`. An iPhone on iOS 18.7 cannot send either key, so the iPhone was not taking a more lenient path through the same protocol. It was speaking an older one. Settling whether macOS is stricter needs an iOS 27 device against the same receiver, and nothing here has one.

**F-083 The receiver's reply shape is not what stops the sender (likely).** Shairport Sync answers the session SETUP with exactly the same three keys the Python receiver does, `eventPort`, a `timingPort` of zero, and a `timingPeerInfo` holding only `Addresses` and `ID`. It is documented as working with Macs from macOS 10.15 onwards. So a reply without `ClockID`, `DeviceType` or `SupportsClockPortMatchingOverride` is one Apple senders have long accepted.

Two open senders disagree about whether `ClockID` is needed, and the disagreement is about them rather than about Apple: OwnTone reads only `eventPort` and `timingPeerInfo.Addresses`, whilst Doubletake refuses a reply without `ClockID` because it derives its timeline from the receiver instead of running a clock of its own.

**F-084 The likely cause is a message the receiver never sends, not an answer it gets wrong (likely).** `asyncPTPClockConfig: True` asks the receiver to set its clock up in the background and then push its `timingPeerInfo` to the sender over the event channel, as a `POST /command` carrying `{type: 'updateTimingPeerInfo', value: <dict>}`. Two independent sources say the same thing: Apple's own receiver carries `_SendTimingPeerInfoAsyncIfNeeded` and logs `Sending timingPeerInfo to event connection`, whilst the sender side carries `Expecting Timing Peer Info async` and `eventStream didn't provide timingPeerInfo`; and Doubletake describes the identical message in prose and implements a handler for it.

The Python receiver's event channel accepts one connection, reads bytes into a file, and never writes anything at all. It cannot send that message whatever else is fixed, which fits the eight second wait exactly. This is marked likely rather than confirmed because what a sender does when the message never comes was not observed.

**F-085 A receiver does not have to speak PTP to be sent audio (confirmed).** NQPTP, which is what Shairport Sync uses for timing, says of itself that it is not a PTP clock. Read as code it handles `Announce`, `Follow_Up` and `Sync` and answers none of them; it has no `Delay_Req` at all, and the only two transmissions in the daemon are in a path that fires when a clock has gone silent. The sender is the grandmaster and the receiver listens. Shairport Sync does not even name the timing peers until the stream level SETUP, and when its timing fails outright the session still reaches playback with the audio missing.

So the Python receiver's complete absence of PTP is not on its own a reason for a sender to stop before the stream level SETUP.

**F-086 Ignoring `combinedGetInfoWithControlSetup` is not fatal (confirmed).** It asks the receiver to fold what `GET /info` would have answered into the SETUP reply under an `Info` key, saving a round trip. A receiver that ignores it gets one separate `GET /info` instead, which is exactly the request F-077 recorded arriving eight seconds later. UxPlay implements the key nowhere and an iPadOS 27 client works against it.

## 2026-09-22 16:20, browsing both services, and what the group fields say

**What was done.** Made discovery browse `_airplay._tcp` beside `_raop._tcp` and merge the two sightings of one receiver, then ran it against the network and read every receiver's group fields directly to check what the merged values mean.

**F-087 The group fields are published by everybody and none of the eight receivers shared one (confirmed).** Read at 16:20 off every `_airplay._tcp` record on the network.

| Receiver | `gid` against `pi` | `igl` | `gcgl` |
|---|---|---|---|
| All five Sonos | equal | not published | `0` |
| The Apple TV | different | `1` | `1` |
| The HomePod mini | two identifiers joined by `+` | `1` | `1` |
| The second Mac | different | `0` | `0` |

So a Sonos publishes itself as a group of one, and Apple's devices publish something else. Nothing here says what two receivers sharing a value would mean, because no two of the eight shared one and none of them was grouped at the time. A comparison is the obvious use of the field and remains an untested one, which is what the library's own documentation of it says.

**F-088 The two services disagree about a receiver's display name when it clashes (confirmed).** The Apple TV announced `Room A` on the audio service and `Room A (2)` on the AirPlay service, because a Sonos in the same room already held `Room A` on the latter. Bonjour settles a clash inside one service by putting a number after the name and settles each service on its own.

The audio service carries the name its owner gave, so a merge that has seen both takes the name from there.

**F-089 (method) A name arrives from a resolve in its wire form (confirmed).** `Room A (2)` arrives as `Room\032A\032(2)`, with a space written as a backslash and three decimal digits, and a dot inside a name written `\.`. The browse callback hands over the readable form and the resolve callback does not, so anything reading the resolve undoes it or puts the escaping on screen. This was already true of the one service browsed before and had never shown, because no receiver on this network has a space in its name.

**F-090 (method) A resolve blocks until it is answered, and a stale announcement is never answered (confirmed).** Processing a resolve waits for a result, and a receiver that goes away without withdrawing its record leaves an announcement that resolves to nothing. One test run took 82 seconds instead of 0.013 because the discovery thread sat in such a resolve, and the stop waiting for that thread waited with it. Waiting on the socket with a bound first, and giving up when nothing arrives, takes it back to 0.013.

The cost was invisible until the second service doubled the number of resolves. A blocking call on the thread that also has to notice a stop is the defect; the stale record only made it show.

## 2026-09-22 18:30, what a refused browse actually reports

**What was done.** Built the example into a bundle, signed it ad hoc with the App Sandbox entitlement and nothing else, and ran it. Then signed the same bundle again with the two network entitlements and ran it again. The bundle was deleted afterwards.

**F-091 A sandboxed application denied the network gets the same error as a machine with no responder (confirmed).** Without `com.apple.security.network.client`, `DNSServiceBrowse` returned `-65563`, which the SDK header calls `kDNSServiceErr_ServiceNotRunning`. With the entitlement, the same bundle browsed and found receivers.

So a refusal does not report itself as a refusal. The one code covers both a machine that has no responder and a process that is not allowed to reach the one it has, and nothing in the answer separates them. A library can say which of the two is likely from the platform it is on, since macOS always runs a responder and Linux often does not, and it cannot do better than that.

**F-092 The codes that do say denied exist and were not produced (open).** `kDNSServiceErr_PolicyDenied` is `-65570` and `kDNSServiceErr_NotPermitted` is `-65571`, both declared in the SDK header, alongside `kDNSServiceErr_NoAuth` and `kDNSServiceErr_Refused`. None appeared in either run. Whether a local network denial under the privacy settings produces one of them is not settled here, because the bundle was never denied at that level: it inherited the grant of the terminal that started it.

What settles it: a signed application denied local network access in the privacy settings, browsing and printing the raw code. The library maps all four to a refusal already, so the answer changes what it says and not what it does.

## 2026-09-22 19:10, what a Sonos says when asked properly

**What was done.** Called every UPnP action the Sonos work turns on against one speaker, whilst three of them were playing together as a group, and read the topology back. Then read the AirPlay group identity of every speaker at the same minute.

**F-093 A Sonos playback group is invisible in the AirPlay record (confirmed).** Three speakers were in one group at 19:10, with a fourth group holding a soundbar and its surrounds and a fifth holding one speaker alone. Every one of the five published an AirPlay `gid` equal to its own `pi`, so all five said they were a group of themselves whilst three of them were plainly not.

This overturns nothing and settles what F-087 left open from one side. A shared `gid` was never seen because a Sonos never publishes one, and the field says nothing at all about which Sonos play together. Their own topology says it exactly, so that is where it has to come from.

**F-094 A bonded set is one member with satellites inside it, not several members (confirmed).** `GetZoneGroupState` puts a `Satellite` element inside the `ZoneGroupMember` it belongs to, carrying `Invisible="1"`, and the member carries `HTSatChanMapSet` naming the channel each one takes. A soundbar with two surrounds is therefore one member with two satellites and reads as one room playing by itself, whilst three grouped rooms are three members. Anything counting members without that distinction reports a home theatre as three rooms grouped together.

**F-095 A speaker in a group reports the coordinator in place of a track (confirmed).** `GetPositionInfo` on a follower answered `TrackURI` of `x-rincon:<coordinator identifier>`, with `TrackDuration`, `TrackMetaData`, `RelTime` and `AbsTime` all reading `NOT_IMPLEMENTED`. So a follower reports playing and has nothing of its own to report about what, and everything about the audio belongs to the coordinator.

**F-096 A speaker serves a picture of itself, and says where (confirmed).** The device description carries `/img/icon-S18.png` for a Sonos One, alongside `modelName` of `Sonos One` and `modelNumber` of `S18`. One plain request to the same host fetches it, so nothing has to be shipped with an application and a model that did not exist when the application was written still draws.

**F-097 (method) The description nests three devices and repeats its element names in each (confirmed).** The speaker, its media server and its media renderer each carry `modelName`, `modelNumber` and `UDN`. The outermost is the speaker. A reader taking the last of each would describe a service instead, and the difference is invisible in the values, because they read like plausible answers.

## 2026-09-23, driving a Sonos from a sender written here

**What was done.** A Swift sender, written against the reference beside this log and using none of the vendored C++ one, was driven against `Büro`, a SYMFONISK Bookshelf (S33) at `10.0.0.125`. It paired, opened the session, opened the event channel, opened a stream on both paths, and sent audio. Everything below is what that sender read back, and the PTP findings come from listening on ports 319 and 320 whilst the session ran.

**F-098 A receiver refuses the stream SETUP without `streamConnectionID` (confirmed).** A body carrying `type`, `ct`, `audioFormat`, `spf`, `sr`, `shk`, `isMedia`, `audioMode`, the two latencies and `supportsDynamicStreamID` is answered `400 Bad Request`. Adding `streamConnectionID`, the numeric session identifier the URI also names, is the only change that was made, and both stream types then opened. The reference lists the key from a working sender and does not say it is required; it is.

**F-099 A Sonos opens the buffered stream and says how much it will hold (confirmed).** `type: 103` is answered with `dataPort`, `controlPort` and `audioBufferSize: 7130316`, which is about eighty seconds of 44100 Hz stereo. The realtime stream opens in the same session and reports no buffer size, which matches the account that only the buffered reply carries one.

**F-100 The receiver keeps the clock and announces itself as its master (confirmed).** Within a second of `SETPEERS`, the speaker began sending to the address that request named: Announce and Signalling on port 320, Sync and Follow_Up on port 319. 184 packets arrived in half a minute. So on this arrangement the sender is the follower and the receiver the grandmaster, which is the opposite way round from what a sender-led design would assume.

This answers the sender's half of open question 6 for this pairing. Nothing here says what an Apple sender transmits, because no Apple sender was in the session.

**F-101 Its clock identity is its own hardware address in EUI-64 form (confirmed).** The Announce named a grandmaster identity of `542a1bfffe58d1f8`, and the speaker's hardware address is `54:2a:1b:58:d1:f8`. The `fffe` in the middle is the ordinary expansion of a 48-bit address to 64 bits. Both `priority1` and `priority2` read 248, and the domain number is 0, which is the default domain and as far as this measurement reaches into open question 5.

**F-102 The anchor's seconds are the master clock's own uptime, not a wall clock (confirmed).** A Follow_Up carried 90787 seconds and 712649822 nanoseconds, about twenty-five hours, from a speaker that had been up about that long. That matches the order of magnitude of the one anchor measured before, F-035, which read 1409162 seconds. A sender that fills the field with Unix time is out by fifty years.

**F-103 A receiver refuses an anchor on any timeline but its own (confirmed).** `SETRATEANCHORTIME` was answered `400 Bad Request` three times over: with a `networkTimeTimelineID` invented by the sender and Unix seconds, with the same identity and the sender's own uptime, and with the session declaring `timingProtocol: None` and then `PTP`. It was accepted the moment the identity was the grandmaster identity from F-101 and the seconds were that clock's own reading. So the field is not a name the sender chooses; it is a clock the receiver already keeps, and the sender has to read it before it can speak about time at all.

**F-104 `SETPEERS` is accepted carrying the sender's address alone (confirmed).** A flat array holding one string, the sender's IPv4 address, is answered 200, and the receiver starts announcing to it immediately. That is consistent with F-029, where the list held the sender's addresses and not the receiver's.

**F-106 The anchor has to point into the future, and this is what finally made a Sonos audible (confirmed).** With the anchor naming the receiver's own clock and the instant of sending, every block still went unplayed. The anchor says when frame zero sounds, and a block cannot arrive before it is sent, so anchored on the moment of sending every block arrives after its own moment and is dropped as late. Moving frame zero two seconds ahead of the reading, and changing nothing else, produced an audible tone on the speaker. That is the first sound this project has made on a Sonos.

Nothing measured says what the smallest workable lead is, nor what an Apple sender uses. Two seconds was the first value tried and it worked.

**F-107 (method) Padding an empty ring with silence turns a live source into crackle (confirmed).** The first version of the session took a packet from a ring on its own thread and, finding fewer frames than it wanted, sent a packet of silence so the timeline would keep running. The tone came out as crackle where the same audio sent from one thread had been a clean sine.

A live source fills such a ring at the same nominal rate as it is drained, so the two drift against each other constantly and the ring is briefly short several times a second. Every one of those became a hole in the audio. Waiting up to four packet lengths for frames that are almost certainly already on their way, and padding only when they genuinely are not, restored the clean tone.

This is about a sender's own design rather than about the protocol, and it is written down because the symptom points nowhere near the cause: the session is healthy, no packet is refused, and what is heard sounds like a codec fault.

**F-108 (method) A producer that paces by sleeping falls behind, and the crackle arrives at the end (confirmed).** With the padding corrected, a fifteen second tone was clean until shortly before it finished and then crackled briefly. The producer was sleeping one packet's duration after each packet, and a sleep always overshoots a little, so it fell steadily behind real time. Over fifteen seconds that drained the ring, and the drain was audible only once it reached the bottom.

Pacing against a fixed schedule instead, so each packet is due at a time computed from the start rather than from the last sleep, gave twenty seconds clean through. Both halves matter and they fail at different ends of a stream: padding too eagerly is heard from the first second, and pacing by sleeping is heard only after the ring has run down.

**F-105 The buffered path takes the blocks without the anchor and plays none of them (confirmed).** Ten seconds of a 440 Hz tone were written to the data port as length-prefixed blocks, framed and encrypted as the reference describes, before the anchor was solved. The receiver took every block and closed nothing, and the room stayed silent rather than noisy. So a receiver on this path holds what it cannot place in time, which is why a sender that gets the framing right and the anchor wrong sees a healthy session and hears nothing.

## 2026-09-23, what an audit of the sender found

**What was done.** An auditor with no part in writing the package read all of it, looking for weaknesses, redundancy and anything it does twice. Eleven findings came back. The four below are the ones that say something a later reader would otherwise have to find again; the rest were repairs whose reasoning is in the commit that made them.

**F-109 (method) An escaped Bonjour instance name is up to four times its own length (confirmed).** A DNS-SD instance label is 63 bytes on the wire, and `DNSServiceResolve` hands back an escaped form in which a byte needing an escape becomes four characters, such as `\032` for a space. So a name of emoji or accented characters reaches 252 characters before the service type is appended. A buffer sized for a display name truncates it, and truncation is not the damage: the service type is then no longer in the string, the separator search finds nothing, and the tail of the cut becomes the receiver's name. The buffer has to be `kDNSServiceMaxDomainName`, and a name without a service type in it has to be dropped rather than read as far as it goes.

**F-110 (method) A PTP clock cannot be opened on Linux without a capability (confirmed).** The ports are 319 and 320, both below 1024, so a process without `CAP_NET_BIND_SERVICE` cannot bind them. On macOS this never appears, because the sender runs as a user who may. It is worth naming as the sender's own problem, since the failure otherwise arrives as the receiver being unreachable and sends the reader to the network.

**F-111 (method) The ALAC element header is 23 bits, so nothing in the frame is byte aligned (confirmed).** Three bits of element tag, four unused, twelve unknown, one for the frame length flag, two for wasted bytes and one for the uncompressed escape. The first sample therefore begins in the middle of the third byte, and no field after it can be read out of a hex dump. A length calculation that uses 24 gives the same byte count, because the rounding up to a byte boundary absorbs the difference, so the mistake passes its own test and survives.

**F-112 (method) A test that rebuilds the framing tests its own copy (confirmed).** The block builder sat inside the method that writes to the socket, so checking it from outside meant either a receiver on the other end or rewriting the framing in the test. The second is not a test: the two copies drift, and the one that matters is the one nothing reads back. Lifting the builder out, so it takes its inputs and returns the bytes, is what made the layout checkable at all. The test then reads every field at the offset a receiver reads it from and opens the payload with the construction from the other side.

## 2026-09-24, the sender kept no buffer, and three symptoms came of it

**What was done.** Podlive played podcasts to a Sonos through this package, and three complaints came out of that: a speaker that sounded rougher than the same source did locally, a change of podcast that crackled, and a second or two before a new one settled. F-113 is what settled all three, and it was found by instrumenting rather than by listening.

**F-113 A sender that drains as fast as it is filled keeps no buffer at all, and every hiccup in the source is heard (confirmed).** The pump began taking packets the moment the first one landed, and from then on consumed at exactly the rate a live source produces. The ring therefore sat a few tens of milliseconds from empty for the whole session. Asking it to discard at a change of source reported 0.07 seconds, then 0.01 seconds, which is the measurement: there was nothing in it to discard.

Gathering half a second before sending anything, and gathering it again after a discard, moved that to 0.51 to 0.58 seconds and it stayed there, because producer and consumer run at the same rate and the distance between them is set once. Over the same runs afterwards, not one packet of silence went out in place of audio.

The half second is free. The anchor has already placed the first frame two seconds ahead, so a cushion inside that lead delays nothing a listener can notice.

**F-114 (method) A caller whose writes are never refused still cannot tell whether its audio arrived in time (confirmed).** Podlive reported 5.1 seconds taken in 5.1 seconds with nothing refused, whilst the speaker sounded rough. Both figures were true and neither was about the question. What was missing is the consumer's side: how often the sender had to invent silence because the ring was empty when the packet was due.

That is now counted and readable, and it is what turned the third attempt at this into a measurement instead of a fourth guess. F-107 and F-108 were the same failure found by ear, twice, each after a false trail. Anything that pads, drops, or makes up data counts what it did, or the next person hears the symptom and looks in the wrong place.

**F-115 (method) A buffer that is full and a buffer that is empty produce the same complaint (confirmed).** The crackle at a change of source was first read as the session holding seconds of the old one, which is the full case, and the discard was written for it. The discard was right to write and it was not the cure. The cause was the opposite condition, and the two are told apart by one number that nothing was reporting.

## 2026-09-24, what a record says about the device, and what it does not

**What was done.** The `_airplay._tcp` records of nine receivers were read with `dns-sd`, and the UPnP descriptions and icon artwork of four Sonos speakers were fetched directly. The question was what a list has to show for a receiver: a name a person recognises, and a picture.

**F-116 Everybody but Apple publishes a manufacturer, and it is the other half of the name (confirmed).** A Sonos announces `manufacturer=Sonos` beside `model=One`, so "Sonos One" is in the record already and costs no request. Apple announces no `manufacturer` at all, and its `model` is the identifier rather than a name: `AudioAccessory5,1`, `AppleTV11,1`, `Macmini9,1`, `Mac16,12`.

Naming a receiver therefore has two cases and no more. A record with a manufacturer is named by joining the two fields; one without is Apple's and its identifier is turned into a name the way macOS turns it into a picture.

What the joined name does not give is the brand on the box. A SYMFONISK Bookshelf announces `manufacturer=Sonos` and `model=Bookshelf`, because Sonos builds it, and only the UPnP description says SYMFONISK. The AirPlay record understates it and there is nothing in the record that would say so.

**F-117 A Sonos serves a picture of itself, and the artwork is not consistent enough to use (confirmed).** Every model answers with a single 48 by 48 PNG from its `iconList`, and there is no larger one: `icon-S18_x2.png`, `icon-S18@2x.png` and `icon-S18-large.png` all answer 404, and `/img/` itself answers 403.

What comes back differs in kind. `icon-S33.png` for a SYMFONISK Bookshelf and `icon-S19.png` for a Sonos Arc are dark product photographs. `icon-S18.png` for a Sonos One is a pale line drawing, and beside the other two in a list it reads as a fault in the application rather than as a speaker.

Nothing in the description says which of the two a model will serve. A rule guessing it from the image would have to tell a line drawing from a photograph of a white speaker, and Sonos sells those.

**F-118 Apple's symbol catalogue is shaped like Apple's hardware and nobody else's (confirmed).** Read out of `name_availability.plist` in `CoreGlyphs.bundle`, which holds 9524 symbols. Every Apple product that receives AirPlay has one shaped like itself: `homepod`, `homepod.mini`, `homepod.2`, `appletv`, `macmini.gen3`, `laptopcomputer`. For everybody else there is `hifispeaker`, `hifispeaker.2` for a pair and `hifireceiver`, all generic, and there is no soundbar at all.

So a list drawn from one hand shows Apple's hardware as itself and everybody else's as a speaker. Drawing a real Sonos would mean drawing it, and at the size a list uses a Sonos One and a HomePod mini are the same picture anyway, so the useful unit is the silhouette rather than the model.

## What this means for the method

**F-024** **A packet recording cannot answer the questions the multi-room work turns on (confirmed).** `SETPEERS`, `SETRATEANCHORTIME`, the per-device volume commands and the teardown of a group member are all inside the encrypted control channel. No amount of recording reaches them, and repeating a run with a step that was missed the first time would not have helped.

**F-025** **A receiver holds the keys, so it can read them (likely).** Running an AirPlay 2 receiver that pairs properly and prints what it decrypts puts the whole exchange in the clear, from Apple's own sender, which is the one worth copying. `openairplay/airplay2-receiver` does exactly that.

**F-026** **It needs the port macOS holds (confirmed).** `ControlCenter` listens on `*:7000` whilst the system's own AirPlay Receiver is switched on, so that has to be off for the duration or a sender reaches the system receiver instead.

**F-027** **Setting it up on macOS 27.2 with Python 3.11 needs four things beyond its own requirements file (confirmed).** Its pins for `zeroconf` and `av` are old. The core dependencies install unchanged, `av` installs current at version 18.1.0, `pyaudio` needs `portaudio` from Homebrew first, and the audio module imports all three at startup whether or not any audio is wanted.

## Still open

1. Whether a receiver that answers `updateTimingPeerInfo` on the event channel gets the session through. F-084 says this is the candidate, F-083 rules out the reply shape and F-085 rules out the absence of PTP, so the event channel is what is left. Settling it means making the Python receiver write on that channel, which it has never done.
2. Whether a macOS sender is stricter than an iOS one at all, which F-082 says nothing measured so far can answer. It needs an iOS 27 device against the same receiver.
3. Which stream type a macOS sender asks for. F-081 answers it for an iPhone playing music, which used 103 three times out of three, and the macOS sender never reached the stream level SETUP.
4. Whether two receivers in one group are given the same anchor. This needs two receivers under our control in one session, which an iPhone can drive as soon as the second machine's receiver is usable.
5. Which PTP profile a group uses, and whether the receivers contest the election with a full Best Master Clock exchange or accept the first announcement. F-101 settles the domain for one speaker addressed alone, which is 0, and says both its priorities are 248. What happens when a second speaker with the same priorities joins is untouched.
6. What an Apple sender transmits as PTP. F-100 answers the other half of this for a sender written here: against one Sonos the receiver is the grandmaster and the sender only listens, so a sender need not be a clock at all. Whether an Apple sender leads instead, and whether it has to once a group has two members, is open.
9. Whether the one-way estimate F-102 rests on is good enough. The sender reads the master's time out of a Follow_Up and carries it forward on its own uptime, without a Delay_Req, so the network's one-way delay is carried as an error. It has not been measured, and it is the difference between placing one stream and holding two speakers together.
7. How a member leaves a group.
8. Why the transport is IPv6 link-local in one direction and IPv4 in the other.
