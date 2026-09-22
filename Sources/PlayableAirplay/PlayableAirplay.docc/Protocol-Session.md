# The session

The RTSP layer inside the encryption, the order the requests go out in, and how several receivers become one group.

## Overview

After pairing, the sender speaks RTSP over the encrypted control connection. RTSP is the Real Time Streaming Protocol, and it looks like HTTP with different method names. AirPlay 2 uses it to describe the session, describe the audio stream, name the group's clock peers and start playback.

This is the part of the protocol where the published record and the measurement disagree twice. Both disagreements are named below, where they arise.

## What the requests look like

The request URI is built from the sender's own address as the receiver sees it, and a session identifier.

```text
rtsp://<sender ip>/<session id>
```

The published record says that identifier is a random 32-bit value, and that the same value is reused as the RTP synchronisation source in the audio packets (reported likely, [airplay2-sender-cpp, `raop_sender.cpp`](https://github.com/akustikrausch/airplay2-sender-cpp), attributed there to pyatv). Apple's own sender uses a wider value. Two sessions between the same pair of devices carried `8928768582649070638` and `2579821923116532825`, both of which need more than 32 bits, and each request after the first carried the same one (measured 2026-09-22, decrypted, F-028 and F-039). So the identifier belongs to the session rather than to either device, and nothing constrains its width to 32 bits except the choice to reuse it as the RTP synchronisation source, which is a 32-bit field. A sender that makes that reuse keeps it at 32 bits, and a sender reading a receiver's logs expects up to 64 from Apple.

AirPlay 2 has no RTSP `Session` header, because there is no transport-mode SETUP to issue one. The session is identified by that URI alone (reported likely, [airplay2-sender-cpp, `raop_sender.cpp`](https://github.com/akustikrausch/airplay2-sender-cpp)).

Pairing requests use an `HTTP/1.1` request line and the SETUP family uses an `RTSP/1.0` one, on the same socket. Real receivers parse both (reported likely, same source).

`POST /feedback` is the one request that must carry an `RTSP/1.0` request line rather than `HTTP/1.1`. A receiver's RTSP parser ignores the HTTP form silently, so its liveness timer never resets (reported likely, same source).

## The order that works

The published record gives this order, and states it as load-bearing (reported confirmed as observed behaviour against a current Apple TV, [airplay2-sender-cpp, README and `raop_sender.cpp`](https://github.com/akustikrausch/airplay2-sender-cpp)).

```text
1.  pair-setup and pair-verify            the control channel becomes encrypted here
2.  GET /info
3.  SETUP (session)                       the reply gives eventPort
4.  connect TCP to eventPort              the event channel must be OPEN
5.  RECORD
6.  SETUP (stream)                        the reply gives dataPort and controlPort
7.  SET_PARAMETER volume
8.  the first SYNC packet, then the RTP audio loop
```

A capture of an Apple sender arrives at a compatible order independently. It sends `GET /info` with the `txtAirPlay` qualifier, then the session SETUP, then a second bodyless `GET /info`, then RECORD, then SETPEERS, then the volume requests and a `POST /feedback` loop, with the stream SETUP later at the moment audio is about to start and FLUSH after it (reported confirmed as a description of that capture, [Cozzi, Protocols](https://web.archive.org/web/20220214214828/https://emanuelecozzi.net/docs/airplay2/protocols/)).

This is what an iPhone on iOS 26 actually sent, with the first three requests read out of a packet recording and the rest out of a receiver that held the pairing keys (measured 2026-09-22, captured and decrypted, F-020 and F-028).

```text
GET /info?txtAirPlay&txtRAOP     asked several times, in the clear
GET /info                        in the clear
POST /pair-verify                X-Apple-HKP: 8
                                 the channel is encrypted from here on
SETUP                            the session
GET_PARAMETER                    volume
RECORD
SETPEERS
SETUP                            the stream
SETRATEANCHORTIME
SET_PARAMETER                    volume
```

Three differences from the published order matter, and the measured order is what the wire did.

`GET /info` comes before pairing, not after it. Every `GET /info` in the measured sessions was sent in the clear, before `POST /pair-verify`, and a receiver answers it to anybody without pairing at all (measured 2026-09-22, captured, F-020 and F-043). The published order puts it after the channel is encrypted. Both work, because the request is answered either way, and a sender that asks before pairing learns what it needs in order to choose a pairing path.

`GET_PARAMETER volume` sits between the session SETUP and RECORD, and the published order has no such request. The sender asks the receiver what its level is before starting, so it adopts the receiver's own level rather than imposing one (measured 2026-09-22, decrypted, F-032).

`SETRATEANCHORTIME` follows the stream SETUP, and the published order ends with a SYNC packet instead. That is the difference between the two audio paths rather than a disagreement: <doc:Protocol-Timing> covers both anchors.

The two orders agree on the one constraint the published record calls load-bearing. RECORD comes between the two SETUPs.

What fails when it is done differently (reported confirmed as observed behaviour, [airplay2-sender-cpp, README](https://github.com/akustikrausch/airplay2-sender-cpp)).

| Mistake | What happens |
|---|---|
| The stream SETUP sent in the clear right after pair-verify | The receiver closes the socket within about one millisecond. |
| `POST /setup` instead of the SETUP method | 404. |
| `GET /info` omitted before SETUP | Rejected. |
| RECORD before the event channel is connected | `RECORD 500` and `FLUSH 455`. |
| RECORD after the stream SETUP rather than between the two SETUPs | The receiver stays outside its record state and will not render the realtime stream. |

RECORD on this path carries an empty body and the ordinary identity headers. Some Apple TVs answer it with 500 even when everything is correct, which is not fatal on the realtime path, because the SYNC packets anchor the timeline instead (reported likely, [airplay2-sender-cpp, `raop_sender.cpp`](https://github.com/akustikrausch/airplay2-sender-cpp)).

On AirPlay 1 the RECORD request is different. It carries `Range: npt=0-`, an `RTP-Info` header naming the sequence number and RTP timestamp of the first audio packet, and the `Session` header from SETUP, and the reply carries `Audio-Latency` (reported confirmed, [openairplay, RECORD](https://openairplay.github.io/airplay-spec/audio/rtsp_requests/record.html)).

```text
RTP-Info: seq=<16-bit initial sequence number>;rtptime=<32-bit initial RTP timestamp>
```

## SETUP, the session

SETUP is an RTSP method on the session URI. It is not `POST /setup`, which returns 404 (reported confirmed as observed behaviour, [airplay2-sender-cpp, README](https://github.com/akustikrausch/airplay2-sender-cpp)). The body is a binary property list with `Content-Type: application/x-apple-binary-plist` (reported likely, [openairplay, SETUP](https://openairplay.github.io/airplay-spec/audio/rtsp_requests/setup.html), which documents the AirPlay 1 form in full and the AirPlay 2 form only by content type).

There are two SETUP requests. The first describes the session and the sender. The second describes one audio stream.

This is what a working sender sends for the session (reported likely for the whole set, [airplay2-sender-cpp, `raop_sender.cpp`](https://github.com/akustikrausch/airplay2-sender-cpp)).

| Key | Type | Value and meaning |
|---|---|---|
| `deviceID` | string | The sender's hardware address, colon separated. |
| `macAddress` | string | The same value again. |
| `sessionUUID` | string | A version 4 UUID in uppercase text form, fresh per session. |
| `timingPort` | integer | The UDP port the sender's timing server is bound to. |
| `timingProtocol` | string | `NTP`, `PTP` or `None`. |
| `isMultiSelectAirPlay` | boolean | True when the sender may address more than one receiver. |
| `groupContainsGroupLeader` | boolean | False when the sender is not joining an existing group. |
| `model` | string | The sender's model string, such as `iPhone14,3`. |
| `name` | string | The sender's display name. |
| `osName` | string | For example `iPhone OS`. |
| `osVersion` | string | For example `16.5`. |
| `osBuildVersion` | string | For example `20F66`. |
| `sourceVersion` | string | The AirPlay source version the sender claims. |
| `senderSupportsRelay` | boolean | False for a sender that does not relay. |
| `statsCollectionEnabled` | boolean | False. |

A capture of an Apple sender carries four more keys that no open sender sends, and they are the ones the PTP path needs (reported confirmed from that capture, [Cozzi, RTSP](https://web.archive.org/web/20220214214845/https://emanuelecozzi.net/docs/airplay2/rtsp/)).

| Key | Type | Value and meaning |
|---|---|---|
| `groupUUID` | string | The group's UUID in uppercase text form. The sender sends it even when addressing a single receiver. |
| `timingPeerInfo` | dictionary | The sender's own timing identity: an `Addresses` array holding its IPv4 and IPv6 addresses, and an `ID`, which in the capture is the same UUID as `groupUUID`. |
| `timingPeerList` | array | An array of dictionaries of that shape, one per timing peer. In the capture it holds the sender alone. |
| `ekey`, `eiv`, `et` | data, data, integer | The AirPlay 1 audio key, its initialisation vector and the encryption type. The capture carries `et: 0`, meaning none, with both byte strings present and unused. |

The reply is a binary property list. The key that matters is `eventPort`, the TCP port for the event channel that <doc:Protocol-Pairing> describes (reported likely, [airplay2-sender-cpp, `raop_sender.cpp`](https://github.com/akustikrausch/airplay2-sender-cpp)).

`timingPort` means different things in the request and in the reply, and the reply's meaning is the opposite way round from what its name suggests. On the PTP path the reply carries `timingPort: 0`, because no timing channel is opened at all, and the reply's `timingPeerInfo` carries the receiver's own addresses instead. On the NTP path the receiver opens a timing channel and names its port there (reported confirmed for the PTP half from a capture whose `timingProtocol` reads `PTP` and whose reply reads `timingPort: 0`, and reported likely for the NTP half, which that page states without a capture, [Cozzi, RTSP](https://web.archive.org/web/20220214214845/https://emanuelecozzi.net/docs/airplay2/rtsp/)). The request's `timingPort` is the sender's own, which is what the open senders fill in, because on their NTP path the sender runs the timing server.

## SETUP, the stream

The second SETUP carries a `streams` array holding one dictionary per stream. For realtime audio it looks like this (reported likely for the whole set, [airplay2-sender-cpp, `raop_sender.cpp`](https://github.com/akustikrausch/airplay2-sender-cpp)).

| Key | Type | Value | Meaning |
|---|---|---|---|
| `type` | integer | 96 (0x60) | Realtime audio over UDP. |
| `ct` | integer | 2 | Compression type. 1 is PCM, 2 is ALAC, 4 is AAC-LC, 8 is AAC-ELD, 32 is Opus. |
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

`type` names the kind of stream, and audio is two of five values (reported likely, [Cozzi, RTSP](https://web.archive.org/web/20220214214845/https://emanuelecozzi.net/docs/airplay2/rtsp/)).

| Value | Stream |
|---|---|
| 96 | General audio, realtime. |
| 103 | General audio, buffered. |
| 110 | Screen. |
| 120 | Playback. |
| 130 | Remote control. |

Apple's own sender fills the realtime dictionary the same way, with `ct: 2`, `audioFormat: 262144` which is 0x40000, `spf: 352`, `audioMode: default`, `isMedia: true`, `latencyMin: 11025`, `latencyMax: 88200`, `supportsDynamicStreamID: true`, its own `controlPort` and a 32-byte `shk`. It carries no `shiv`, no `clientID` and no `streamConnectionID` (reported confirmed from that capture, same source).

pyatv fills it differently, sending `ct: 1` with `audioFormat: 0x800`, which is a PCM format (reported confirmed as a description of pyatv, [pyatv, `pyatv/protocols/raop/protocols/airplayv2.py`](https://github.com/postlund/pyatv/blob/master/pyatv/protocols/raop/protocols/airplayv2.py)). The ALAC choice is the safer one, for the reason <doc:Protocol-Audio> gives under the payload, and it is also what Apple sends.

The reply carries a `streams` array of its own. The sender reads `dataPort` from the first entry, which is where the audio goes, and `controlPort`, which is where sync packets and retransmit requests go (reported likely, [airplay2-sender-cpp, `raop_sender.cpp`](https://github.com/akustikrausch/airplay2-sender-cpp)). The reply's stream descriptor also carries a `streamID`, which is the number a sender later names in a TEARDOWN body to take one stream down whilst leaving the session up (reported likely, [openairplay, `airplay2-receiver`, `ap2/connections/stream.py`](https://github.com/openairplay/airplay2-receiver/blob/master/ap2/connections/stream.py) and [Cozzi, RTSP](https://web.archive.org/web/20220214214845/https://emanuelecozzi.net/docs/airplay2/rtsp/)).

An AirPlay 2 SETUP response carries no `Session` header and nothing useful in `Transport`, so a sender that looks for ports there finds nothing. The ports are in the property list body (reported confirmed for what a receiver sends, [shairport-sync, `rtsp.c`](https://github.com/mikebrady/shairport-sync/blob/master/rtsp.c)).

### Which fields belong to which stream type

The fields that write-ups attach to this request sort themselves once a receiver's stream parser is read in one piece (reported confirmed as a statement about that implementation, [openairplay, `airplay2-receiver`, `ap2/connections/stream.py`](https://github.com/openairplay/airplay2-receiver/blob/master/ap2/connections/stream.py)).

| Field | Realtime, type 96 | Buffered, type 103 |
|---|---|---|
| `shk` | Read, optional | Read |
| `shiv` | Read, the initialisation vector for the AES-CBC cipher the older encryption types use | Not read at all, because the cipher is ChaCha20-Poly1305 keyed directly by `shk` |
| `ct` | Read | Read |
| `spf` | Read | Read |
| `audioFormat` | Not read. The format is fixed at ALAC | Read |
| `latencyMin`, `latencyMax` | Read, and mandatory | Not read |
| `controlPort` | Read, optional | Read, optional |
| `streamConnectionID`, `supportsDynamicStreamID` | Read, and not gated behind any feature bit | Read, likewise |
| `isMedia` | Read by neither receiver, although Apple's sender sends it | Likewise |
| `clientID` | Appears in no implementation and no capture | Likewise |

What sits at the connection level is a separate `streamConnections` key inside that same dictionary (reported confirmed, same source). Whether `clientID` is a field of any SETUP is open: sending it and watching for a rejection costs one request.

`audioMode` is both a key and a request. Apple's own sender sends `audioMode: default` inside the realtime stream dictionary (reported confirmed from a capture, [Cozzi, RTSP](https://web.archive.org/web/20220214214845/https://emanuelecozzi.net/docs/airplay2/rtsp/)), and a separate `POST /audioMode` request exists beside it, which both receivers accept and neither acts on (reported confirmed as a statement about those implementations, [shairport-sync, `rtsp.c`](https://github.com/mikebrady/shairport-sync/blob/master/rtsp.c) and [openairplay, `airplay2-receiver`](https://github.com/openairplay/airplay2-receiver/blob/master/ap2-receiver.py)).

## The audio key, `shk`

`shk` is the ChaCha20-Poly1305 key for the audio payload, sent in the stream SETUP body as 32 bytes of data. It is not derived with HKDF.

A receiver takes the value it was given and uses it as the cipher key directly, with no derivation step, and rejects any length other than 32 bytes (reported confirmed, [shairport-sync, `rtsp.c`](https://github.com/mikebrady/shairport-sync/blob/master/rtsp.c)).

What the sender should put in it is less settled. pyatv puts an arbitrary per-session value there and its own comment says the key only has to be some per-session value (reported confirmed as a description of pyatv, [pyatv, `pyatv/protocols/raop/protocols/airplayv2.py`](https://github.com/postlund/pyatv/blob/master/pyatv/protocols/raop/protocols/airplayv2.py)). Against a current Apple TV that is reported not to work: only the first 32 bytes of the pairing shared secret decode correctly there, and an HKDF-derived key produces noise, which reads as the Apple TV deriving the audio key from the pairing secret rather than honouring `shk` (reported confirmed as observed behaviour against that device, [airplay2-sender-cpp, README](https://github.com/akustikrausch/airplay2-sender-cpp)).

One choice satisfies both readings, so make it.

```text
shk = the first 32 bytes of the pairing shared secret
```

Use that same value as the cipher key. A receiver that honours `shk` gets the right key, and a receiver that derives its own gets the same key anyway.

The clamp to 32 bytes is what makes the two pairing paths behave the same. After pair-verify the shared secret is the 32-byte X25519 output, so the clamp does nothing. After transient pairing the shared secret is the 64-byte SRP session key `K`, and passing all 64 bytes to a ChaCha20 key rejects on every single audio packet, so nothing is sent and the receiver drops the session after its no-audio timeout. The control and event keys are unaffected, because HKDF accepts input key material of any length, which is why pairing and cover artwork keep working whilst the audio never starts (reported confirmed as observed behaviour, corroborated there by owntone's constant for the same length, [airplay2-sender-cpp, README](https://github.com/akustikrausch/airplay2-sender-cpp)).

## Groups

### `SETPEERS` is a clock peer list, not a session

`SETPEERS` carries `Content-Type: /peer-list-changed` and a binary property list holding a flat array of IP address strings. That array is the list of PTP timing peers (reported confirmed by all three, [pyatv, protocol documentation](https://pyatv.dev/documentation/protocols/), [openairplay, `airplay2-receiver`](https://github.com/openairplay/airplay2-receiver/blob/master/ap2-receiver.py) and [shairport-sync, `rtsp.c`](https://github.com/mikebrady/shairport-sync/blob/master/rtsp.c)).

What shairport-sync does with it settles what it is for. It takes the sender's own address together with every address in the array and hands the whole list to its PTP monitor (reported confirmed, [shairport-sync, `rtsp.c`](https://github.com/mikebrady/shairport-sync/blob/master/rtsp.c)). The receiver is being told which addresses to watch for clock traffic.

### What the array holds, and where the two accounts part

The published account comes from a capture of an Apple sender against a Sonos One. Addressing one receiver, it lists that receiver's IPv4 address, that receiver's IPv6 link-local address, and then the sender's own two addresses (reported confirmed from that capture, [Cozzi, RTSP](https://web.archive.org/web/20220214214845/https://emanuelecozzi.net/docs/airplay2/rtsp/)).

The measurement disagrees about the recipient. With one receiver playing, the list held five addresses and all five belonged to the sender. The receiver's own addresses were not in it (measured 2026-09-22, decrypted, F-029).

```text
192.0.2.20
fe80::4
2001:db8::5
fd00::4
2001:db8::4
```

That is what the wire did. A receiver does not need to be told its own address, and shairport-sync adds the sender's address to whatever arrives before handing the list on, which is consistent with a list that names everybody except the recipient.

Watched across one session as a second speaker joined and left, the list is the whole membership each time rather than a change to it (measured 2026-09-22, decrypted, F-033).

```text
playing alone       the sender's five addresses
a speaker joins     that speaker's five addresses, then the sender's five
the speaker leaves  the sender's five again
```

The new member is listed first and the sender last. Every member contributes every address it can be reached at, which here is one IPv4 address and four IPv6 ones, among them a link-local, a unique local and two global. So the request answers the question of who is in this clock group and where each of them is, and the sender counts as a member of it.

A speaker joining an existing session changes nothing else. No second SETUP, no further RECORD, no new anchor and no interruption. One `SETPEERS` arrives with the enlarged list and the session carries on, and the same holds in reverse when it leaves (measured 2026-09-22, decrypted, F-034).

### `SETPEERSX`

`SETPEERSX` is the extended form. It carries `Content-Type: /peer-list-changed-x` and requires `features` bit 52. Its body is an array of dictionaries rather than of strings, and each dictionary carries these keys (reported confirmed, [openairplay, `airplay2-receiver`](https://github.com/openairplay/airplay2-receiver/blob/master/ap2-receiver.py)).

| Key | Type | Meaning |
|---|---|---|
| `Addresses` | array of strings | The peer's IP addresses. |
| `ClockID` | integer | The peer's PTP clock identity. |
| `ClockPorts` | dictionary | A map from a per-device identifier to a port number. |
| `DeviceType` | integer | The kind of device. |
| `ID` | string | The peer's identifier, a GUID. |
| `SupportsClockPortMatchingOverride` | boolean | |

That is the whole published record of it. shairport-sync accepts `SETPEERSX` and parses nothing from it, so it corroborates only that the method exists. None of the measured sessions used it.

### One session per receiver

The published record left this open, and the measurement closes it. A Mac playing to an Apple TV and a HomePod mini as one group opened two RTSP connections, to the two receivers, from two different local ports, over IPv6 link-local. There is no leader and no single session addressing a group (measured 2026-09-22, captured, F-008).

```text
fe80::1.58387 -> fe80::2.7000     381 packets
fe80::1.58367 -> fe80::3.7000    371 packets
```

That is the reading the published evidence already leaned towards. A capture of a second speaker being added showed the sender's `SETPEERS` going out on the session of the receiver that was already playing, naming the new speaker's addresses rather than handing anything over to it, and nothing in `SETPEERS` or `SETPEERSX` nominates a receiver to relay audio to other receivers (reported likely, [Cozzi, RTSP](https://web.archive.org/web/20220214214845/https://emanuelecozzi.net/docs/airplay2/rtsp/)).

So a sender opens a full session to every receiver separately, sends each of them the same anchor, and uses `SETPEERS` to tell each receiver about the others so that all of them lock to the same clock. Each receiver then works out for itself when to play each frame. <doc:Protocol-Timing> covers the clock and the anchor.

### The grouping fields

| Where | Key | Meaning | Mark |
|---|---|---|---|
| TXT | `gid` | The group's UUID. A receiver that is in no group publishes its own `pi` value here. | reported confirmed |
| TXT | `igl` | Is group leader, `0` or `1`. | reported confirmed |
| TXT | `gcgl` | Group contains a discoverable leader, `0` or `1`. Apple's sender reads it into a field it calls `groupContainsDiscoverableLeader`, whilst the session SETUP key of nearly the same name is spelled `groupContainsGroupLeader`. | reported confirmed |
| TXT | `pi` | The receiver's own persistent identifier. | reported confirmed |
| TXT | `psi` | The public AirPlay pairing identifier, a separate persistent value. | reported confirmed |
| plist | `isGroupLeader` | The same idea as `igl`, spelled out, seen in an `updateInfo` event body rather than in a TXT record. | reported confirmed |
| plist | `groupContainsGroupLeader` | Sent by the sender in the session SETUP. | reported likely |
| plist | `isMultiSelectAirPlay` | Sent by the sender in the session SETUP. Apple's own sender sends it true, and so does pyatv. One receiver parses it into a field and never reads that field again. Send it true and expect nothing of it. | reported confirmed as a field |

Sources: [shairport-sync, `bonjour_strings.c`](https://github.com/mikebrady/shairport-sync/blob/master/bonjour_strings.c) for what a receiver publishes, [pyatv, protocol documentation](https://pyatv.dev/documentation/protocols/) for the captured examples, [Cozzi, Service discovery](https://web.archive.org/web/20220214214811/https://emanuelecozzi.net/docs/airplay2/discovery/) for the field Apple's sender reads each key into, and [openairplay, `airplay2-receiver`, `ap2/connections/session_properties.py`](https://github.com/openairplay/airplay2-receiver/blob/master/ap2/connections/session_properties.py) for the one field a receiver parses and never uses.
