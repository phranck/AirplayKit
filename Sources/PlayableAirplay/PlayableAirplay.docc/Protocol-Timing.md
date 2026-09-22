# Timing

Which clock the group runs on, who runs it, and how one frame of audio is tied to one instant.

## Overview

Two speakers in the same room have to play the same frame at the same moment, and neither of their own clocks is good enough on its own. AirPlay solves that in two halves. One half puts every device on a shared clock. The other half sends one sentence saying which frame sounds at which instant on that clock, and every device works out the rest for itself.

AirPlay 2 multi-room audio runs the shared clock over PTP, the Precision Time Protocol defined in IEEE 1588. Classic AirPlay runs it over an NTP-style exchange with SYNC packets instead, and does not use PTP at all. shairport-sync states both outright, and it runs a separate daemon called nqptp purely to handle the PTP side of an AirPlay 2 session (reported confirmed, [shairport-sync, README](https://github.com/mikebrady/shairport-sync/blob/master/README.md) and [nqptp, README](https://github.com/mikebrady/nqptp/blob/main/README.md)).

The older model has not gone away. A sender that puts the string `NTP` in `timingProtocol` gets a working single-receiver session out of a current Apple TV, a HomePod and a macOS receiver. That is what pyatv does and what the C++ sender does, and both work (reported confirmed, [pyatv, `pyatv/protocols/raop/protocols/airplayv2.py`](https://github.com/postlund/pyatv/blob/master/pyatv/protocols/raop/protocols/airplayv2.py), and [UxPlay wiki, AirPlay2](https://github.com/FDH2/UxPlay/wiki/AirPlay2) carries a capture with that exact value).

All three values of `timingProtocol` are attested literally. `NTP` appears in a capture and in pyatv's audio session. `None` appears in pyatv's remote-control-only session (reported confirmed, [pyatv, `pyatv/protocols/airplay/ap2_session.py`](https://github.com/postlund/pyatv/blob/master/pyatv/protocols/airplay/ap2_session.py)). `PTP` appears in a capture of an iPhone addressing a Sonos One, in a session SETUP that carries `timingPeerInfo` and `timingPeerList` beside it (reported confirmed, [Cozzi, RTSP](https://web.archive.org/web/20220214214845/https://emanuelecozzi.net/docs/airplay2/rtsp/)).

What the NTP path does not buy is multi-room, and it does not reach every receiver. shairport-sync refuses an NTP stream outright and logs that it cannot handle one. owntone's AirPlay 2 sender implements only NTP timing, and for exactly that reason cannot stream to a shairport-sync receiver (reported confirmed as reports of behaviour, [music-assistant issue 6243](https://github.com/music-assistant/support/issues/6243) and [cliairplay issue 78](https://github.com/music-assistant/cliairplay/issues/78)).

So the honest position for a sender that wants several speakers in step is this. NTP is the quickest route to one Apple receiver playing audio. PTP is what the rest of the design has to be built around, and nothing else in the published record keeps several receivers in step.

No source states the rule for choosing between them as a sentence. Three independent observations point the same way, so this is likely rather than confirmed: the receiver advertises `features` bit 41, the specification annotates that bit as required for multi-room, and the implementations that speak only NTP are exactly the ones that fail against PTP-only receivers.

## PTP, as measured

The traffic is unicast over IPv6 link-local, on UDP ports 319 and 320, in domain 0. It is PTPv2 with the version 1 compatibility flag set, and the flags field carries `timescale` and `unicast`. Not one multicast PTP packet appeared in any run (measured 2026-09-22, captured, F-009).

That agrees with the published record and sharpens it. nqptp requires exclusive use of both ports, and shairport-sync's author states that an AirPlay source will only send and respond on those two (reported confirmed, [shairport-sync, `AIRPLAY2.md`](https://github.com/mikebrady/shairport-sync/blob/master/AIRPLAY2.md), [nqptp, README](https://github.com/mikebrady/nqptp/blob/main/README.md) and [shairport-sync discussion 1712](https://github.com/mikebrady/shairport-sync/discussions/1712)). nqptp binds both ports and never joins a PTP multicast group, which is why unicast was already the reading before it was measured (reported likely, [nqptp, `nqptp.c`](https://github.com/mikebrady/nqptp/blob/main/nqptp.c) and [`nqptp-utilities.c`](https://github.com/mikebrady/nqptp/blob/main/nqptp-utilities.c)).

```text
port 319   event messages     Sync, Delay_Req, Pdelay_Req, Pdelay_Resp
port 320   general messages   Announce, Follow_Up, Delay_Resp,
                              Pdelay_Resp_Follow_Up, Management, Signaling
```

Every Announce message carried these values (measured 2026-09-22, captured, F-010).

| Field | Value |
|---|---|
| `priority1` | 248 |
| `clockClass` | 248 |
| `clockAccuracy` | 33, which is 0x21 |
| `clockVariance` | 17258 |
| `priority2` | differs per device |
| `stepsRemoved` | 0 |
| `timeSource` | 0xa0 |

Clock identities are not derived from a visible hardware address. Every identity seen ends in `0008` rather than in the `fffe` that standard EUI-64 padding produces (measured 2026-09-22, captured, F-013).

```text
f434f09b9d400008   the Apple TV
9c3e53a0ad550008   the HomePod mini
d011e56376620008   the Mac
```

The Mac's identity begins with `d011e5`, which is the manufacturer prefix of its Ethernet address `d0:11:e5:18:ff:5b`, and continues with bytes that match none of its interfaces.

## Who runs the clock, and where the two accounts part

This is the largest disagreement between the published record and the measurement, and neither side closes it completely.

### What the published record says

nqptp is a passive monitor. It does not originate PTP messages, does not respond to them, and does not take part in master-clock election. It watches the traffic, keeps a record of one clock identified by its 64-bit clock identity, and publishes to shairport-sync a local timestamp, an offset that converts local time into master-clock time, and the moment that clock became master (reported confirmed, [nqptp, README](https://github.com/mikebrady/nqptp/blob/main/README.md) and [shairport-sync discussion 1712](https://github.com/mikebrady/shairport-sync/discussions/1712)). Its own README says it is not a PTP clock and uses only part of IEEE 1588-2008.

Put that beside the fact that somebody has to originate the messages, and the reading follows: the sender runs a real, message-originating PTP implementation and the receivers discipline their clocks to it (reported likely, because it follows from two confirmed facts rather than from a statement).

That reading is supported by what nqptp handles. It handles exactly three message types, Announce, Sync and Follow_Up, and out of the Announce it reads `grandmasterIdentity`, `grandmasterPriority1`, `grandmasterPriority2`, the clock quality word and `stepsRemoved` (reported confirmed, [nqptp, `nqptp-message-handlers.c`](https://github.com/mikebrady/nqptp/blob/main/nqptp-message-handlers.c)). So the sender announces itself with the full Best Master Clock fields, then sends Sync and Follow_Up, and the receiver takes its offset from that pair.

### What one receiver did

With a single receiver, the sender is the only clock source and behaves as the master. An iPhone playing to one Mac sent all 794 PTP packets in the recording, and the Mac's side of the exchange carried Sync, Follow_Up, Delay_Resp and Announce arriving from the iPhone (measured 2026-09-22, captured, F-017). A Delay_Resp cannot arrive without a Delay_Req having gone out, so the receiver is asking and the sender is answering.

The anchor in the control channel names the sender's own clock. `networkTimeTimelineID` read `-2267142311769604088` in every anchor of every session recorded that hour, which as an unsigned value is `0xE0897E144BB70008`, and that is the shape of the identities above (measured 2026-09-22, decrypted, F-057). It is the same in sessions to differently named receivers, so it identifies a clock rather than a session. That is the join between the two halves of the protocol: the traffic on ports 319 and 320 and the anchor inside the encryption refer to the same identity.

### What two receivers did

With two receivers, both of them announce, and they contest the election between themselves. The Apple TV claimed `priority2` 247 and the HomePod mini claimed 233. The lower value wins under the standard algorithm, and the device that claimed 233 went on to send 514 Sync and 514 Follow_Up messages whilst the other sent two of each and then slaved (measured 2026-09-22, captured, F-011).

```text
fe80::c2d:e455:8c63:6da4   p2=233   sync 514   follow up 514   delay resp 512   announce 66
fe80::1447:801e:9b8f:914a  p2=247   sync   2   follow up   2   delay req  512   announce  1
```

The loser's Delay_Req messages are addressed to the Mac rather than to the winner.

### How the two fit together

The receivers do announce and do contest, and the published reading did not have that. That is what the wire did.

What the measurement does not show is the sender's own transmissions in that run. The capture never holds them. PTP is timestamped in the network hardware, and that transmit path does not pass the packet filter, so the capturing machine's own PTP is absent in every run and in both roles, whilst its RTSP appears in both directions in the same file (measured 2026-09-22, captured, F-018). So whether the sender also announced in that two-receiver run, and lost, cannot be read out of it.

Both facts stand. A sender is the only clock source when it is alone with one receiver, and receivers announce with full Best Master Clock fields and settle a grandmaster between themselves when there are two of them. What decides the case where all three announce is open: a recording taken off the sending machine, such as the packet capture built into a router, shows whether the sender announces at all and what happens when it does.

What was already open stays open. Which PTP profile applies is unsettled, and shairport-sync's author hedges it with a "possibly" towards 802.1AS (reported confirmed as a statement of what is unknown, [shairport-sync discussion 1712](https://github.com/mikebrady/shairport-sync/discussions/1712)). The domain number is settled at 0 by the measurement above.

Apple publishes nothing about any of this. Its AirPlay deployment guide does not mention PTP, clock synchronisation or timing at all, and its published table of ports lists AirPlay against 80, 443, 554, 3689, 5000, 5353, 6000, 7000 and the ephemeral range, with no 319 and no 320 (reported confirmed as a negative finding, [Apple, Use AirPlay with Apple devices](https://support.apple.com/guide/deployment/use-airplay-dep9151c4ace/web) and [Apple, TCP and UDP ports used by Apple software products](https://support.apple.com/en-us/103229)).

## The anchor

The anchor ties a clock reading to a position in the audio. It is the same idea on both timing paths.

On the PTP path it is the `SETRATEANCHORTIME` request (reported confirmed by both, [shairport-sync, `rtsp.c`](https://github.com/mikebrady/shairport-sync/blob/master/rtsp.c) and [openairplay, `airplay2-receiver`](https://github.com/openairplay/airplay2-receiver/blob/master/ap2-receiver.py)).

| Field | Meaning |
|---|---|
| `networkTimeTimelineID` | The PTP clock identity that the following time is expressed against. |
| `networkTimeSecs` | The seconds part of that network time. |
| `networkTimeFrac` | The fractional part, fixed point. |
| `rtpTime` | The RTP timestamp that corresponds to that network time. |
| `rate` | The low bit decides playback. Odd means play or resume, even means pause. |

A measured body carries one field the published record does not name, `networkTimeFlags` (measured 2026-09-22, decrypted, F-035).

```text
networkTimeFlags       0
networkTimeFrac        207788735369052160
networkTimeSecs        1409162
networkTimeTimelineID  -2267142311769604088
rate                   1
rtpTime                2004038641
```

`networkTimeFlags` was 0 in every anchor observed, so what it does is open: a value other than 0 has to turn up before it can be read at all. The integers are printed signed because the receiver reads them as signed values, and `networkTimeTimelineID` is a 64-bit clock identity.

One `SETRATEANCHORTIME` arrives in a whole session, so the anchor is set at the start and is not repeated as the group changes (measured 2026-09-22, decrypted, F-035 and F-034).

Given that pair, and the sample rate, a receiver computes the network time at which any other RTP timestamp should sound, by linear extrapolation from the anchor. Nothing else is needed to place a frame in time.

### The realtime anchor, packet type 215

The realtime AirPlay 2 stream carries the same anchor as a UDP packet on the receiver's control port instead. It is the classic SYNC packet with the NTP time replaced by a network time in nanoseconds and the master's clock identity appended (reported confirmed, [shairport-sync, `rtp.c`](https://github.com/mikebrady/shairport-sync/blob/master/rtp.c), and a second source names the same type carrying the same triple of an RTP time, an eight-byte network time and a second RTP time, [Cozzi, RTCP](https://web.archive.org/web/20220214214831/https://emanuelecozzi.net/docs/airplay2/rtcp/)).

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

The difference between the two RTP timestamps is the latency the sender is asking for, and a receiver expects 77175 frames there, which is one and three quarter seconds at 44100 Hz. shairport-sync logs anything else as unusual (reported confirmed, [shairport-sync, `rtp.c`](https://github.com/mikebrady/shairport-sync/blob/master/rtp.c)).

Its AirPlay 2 control receiver handles type 215 and the retransmit reply and logs every other type as unknown, so a classic SYNC packet reaches it and does nothing. That is the mechanism behind its refusal of an NTP stream (reported confirmed, same source).

## How a sender keeps several receivers in step

Putting the pieces together gives the following. Each piece is sourced or measured and no source assembles them, so the assembly is likely as a whole.

1. Every receiver in the group locks its clock to one master clock, over PTP on ports 319 and 320, unicast to each peer.
2. The sender tells each receiver who else is in the group with `SETPEERS`, so every receiver watches the same addresses for clock traffic. A receiver hands that list straight to its PTP component.
3. The sender sends each receiver the same anchor with `SETRATEANCHORTIME`: the same `networkTimeTimelineID`, the same `networkTimeSecs` and `networkTimeFrac`, and the same `rtpTime`. That is one sentence saying that this audio frame sounds at this instant on that clock, and it is identical for every member.
4. Each receiver places every other frame by extrapolating from that anchor at the sample rate, and subtracts its own output latency locally.

The consequence worth holding onto is that the sender never has to know any receiver's latency, and never has to reconcile one receiver's latency against another's. The differences cancel inside each device. What the sender owes every receiver is one clock and one anchor, identical for all of them.

`rate` is what starts and stops the group together. Its low bit means play when odd and pause when even, so a pause is one anchor message to each member rather than a separate stop protocol. <doc:Protocol-Control> covers what that looks like in a running session.

## The NTP path, in full

A sender on this path runs two UDP servers of its own, binds them before sending SETUP, and advertises their ports in it. One is the timing server, named by `timingPort` in the session SETUP. The other is the control socket, named by `controlPort` in the stream SETUP, which both sends SYNC packets and receives retransmit requests (reported likely, [airplay2-sender-cpp, `raop_sender.cpp`](https://github.com/akustikrausch/airplay2-sender-cpp), and the same division appears in the classic `Transport` header as `timing_port` and `control_port`, reported confirmed, [openairplay, SETUP](https://openairplay.github.io/airplay-spec/audio/rtsp_requests/setup.html)).

The receiver sends unsolicited inbound UDP to both. On a machine whose firewall drops unsolicited inbound UDP, and on a network-address-translated virtual machine, the handshake stalls at the session SETUP and times out with no other symptom (reported confirmed as a diagnosed case, [airplay2-sender-cpp, README](https://github.com/akustikrausch/airplay2-sender-cpp)).

The payload types are these (reported confirmed, [openairplay, `src/audio/rtp_streams.md`](https://raw.githubusercontent.com/openairplay/airplay-spec/master/src/audio/rtp_streams.md)).

| Decimal | Hex | Port | Direction | Purpose |
|---|---|---|---|---|
| 82 | 0x52 | timing | receiver to sender | Timing request. |
| 83 | 0x53 | timing | sender to receiver | Timing reply. |
| 84 | 0x54 | control | sender to receiver | Time sync. |
| 85 | 0x55 | control | receiver to sender | Retransmit request. |
| 86 | 0x56 | control | sender to receiver | Retransmit reply. |
| 96 | 0x60 | data | sender to receiver | Audio. |

On the wire the second byte of each of these carries the marker bit as well, so payload type 84 appears as 0xD4, 83 appears as 0xD3 and 86 appears as 0xD6.

These packets are not fully RTP-conformant. They carry an eight-byte header, which is the standard twelve-byte RTP header with the four-byte synchronisation source left out (reported confirmed, [openairplay, `src/audio/rtp_streams.md`](https://raw.githubusercontent.com/openairplay/airplay-spec/master/src/audio/rtp_streams.md) and [RFC 3550, section 5.1](https://www.rfc-editor.org/rfc/rfc3550.html)).

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

The marker bit is set on every SYNC packet, and it is the extension bit that distinguishes the first one after RECORD or FLUSH (reported confirmed, [openairplay, `src/audio/rtp_streams.md`](https://raw.githubusercontent.com/openairplay/airplay-spec/master/src/audio/rtp_streams.md), and a working sender sets exactly 0x80 and 0x90 in that byte, reported confirmed, [airplay2-sender-cpp, `raop_sender.cpp`](https://github.com/akustikrausch/airplay2-sender-cpp)).

The timing exchange is the receiver asking and the sender answering, roughly every three seconds. Both packets are thirty-two bytes: the eight-byte header, then three NTP timestamps of eight bytes each, which are the origin, receive and transmit times.

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

NTP time here is the standard 64-bit fixed-point form: seconds since 1 January 1900 in the high 32 bits, and a binary fraction of a second in the low 32 bits (reported confirmed, [RFC 3550, section 4](https://www.rfc-editor.org/rfc/rfc3550.html)).

Converting between that and the 44100 Hz RTP timeline is a shift in each direction, which avoids any 64-bit overflow (reported likely, [airplay2-sender-cpp, `raop_sender.cpp`](https://github.com/akustikrausch/airplay2-sender-cpp), attributed there to pyatv, which in turn credits RAOP-Player for the arithmetic).

```text
timestamp = ((ntp >> 16) * rate) >> 16
ntp       = ((timestamp << 16) / rate) << 16
```

On this path the anchor is carried by the SYNC packet itself, which pairs the current NTP time with the RTP timestamp of the next audio packet and is repeated once a second so the receiver can keep correcting (reported confirmed, [openairplay, `src/audio/rtp_streams.md`](https://raw.githubusercontent.com/openairplay/airplay-spec/master/src/audio/rtp_streams.md)).

The RTP timestamp a sender writes into an audio packet starts at the latency value and advances by 352 per packet. A working sender uses a fixed latency of 22050 plus the sample rate, which is 66150 frames at 44100 Hz, or one and a half seconds, and does not adjust it from anything the receiver says (reported confirmed as a description of pyatv, [pyatv, `pyatv/protocols/raop/protocols/__init__.py`](https://github.com/postlund/pyatv/blob/master/pyatv/protocols/raop/protocols/__init__.py), and the C++ sender uses the same constant).

Whether an AirPlay 2 session that declares `NTP` uses these layouts byte for byte is open. Two independent senders drive Apple receivers with the classic 0xD4 SYNC packet and the audio plays in step, which is strong evidence, and no capture of such a session is published. A capture of one settles it.

## Receiver latency

A sender proposes a range in the stream SETUP with `latencyMin` and `latencyMax`, in frames. The values both working senders use are 11025 and 88200, which at 44100 Hz are a quarter of a second and two seconds (reported confirmed for both senders, [pyatv, `pyatv/protocols/raop/protocols/airplayv2.py`](https://github.com/postlund/pyatv/blob/master/pyatv/protocols/raop/protocols/airplayv2.py) and [airplay2-sender-cpp, `raop_sender.cpp`](https://github.com/akustikrausch/airplay2-sender-cpp)).

On AirPlay 1 the receiver answers RECORD with an `Audio-Latency` header, and the unit is frames (reported confirmed, [openairplay, RECORD](https://openairplay.github.io/airplay-spec/audio/rtsp_requests/record.html)). A receiver's own code settles the unit. shairport-sync answers RECORD with `Audio-Latency: 11025`, and the comment beside that line reads the number as the receiver's absolute minimum latency, to which the sender adds whatever latency it asks for. Its arithmetic is in frames throughout, and AirPlay's figure of 77175 plus 11025 is exactly 88200, which is two seconds at 44100 Hz (reported confirmed, [shairport-sync, `rtsp.c`](https://github.com/mikebrady/shairport-sync/blob/master/rtsp.c)). openairplay labels its captured value of 2205 as milliseconds, which is a mislabel, since read as frames it is 50 milliseconds. On the AirPlay 2 path the same receiver answers `Audio-Latency: 0`.

Neither open sender uses the announced value. Both run a fixed latency of 22050 plus the sample rate (reported confirmed, [pyatv, `pyatv/protocols/raop/protocols/__init__.py`](https://github.com/postlund/pyatv/blob/master/pyatv/protocols/raop/protocols/__init__.py)).

What a receiver typically wants is documented in round terms. An AirPlay 1 source sets around 2.0 to 2.25 seconds, and AirPlay 2 can use much shorter latencies, around half a second (reported confirmed, [shairport-sync, README](https://github.com/mikebrady/shairport-sync/blob/master/README.md)).

`audioLatencies` and `outputLatencyMicros` are real and they come from the receiver, in the reply to the qualified `GET /info` that <doc:Protocol-Finding-Receivers> describes. Neither open sender reads them.

How a sender reconciles different latencies across several receivers in a group is open, and nothing in the reachable record addresses it. The mechanism that makes reconciliation unnecessary is the anchor: the sender tells every receiver the same network time for the same RTP timestamp, and each receiver subtracts its own output latency locally.
