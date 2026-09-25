# Steering a session

Playing, pausing, seeking, changing track, volume, metadata, and taking the session down.

## Overview

Once a session is running, everything a user does to it arrives as one of four requests. `SETRATEANCHORTIME` moves the timeline. `FLUSHBUFFERED` throws queued audio away. `SET_PARAMETER` carries volume, metadata and artwork. `TEARDOWN` ends it.

Almost everything in this article was measured, because the whole of it lives inside the encrypted control channel and a packet recording reaches none of it (measured 2026-09-22, captured, F-024).

## Playing and pausing

Playing and pausing are the same request with different bodies (measured 2026-09-22, decrypted, F-056).

```text
start   {networkTimeFlags, networkTimeFrac, networkTimeSecs, networkTimeTimelineID, rate: 1, rtpTime}
pause   {rate: 0}
resume  the full set again, with a later networkTimeSecs and a later rtpTime
```

Every `rate: 1` carries the whole set. Every `rate: 0` carries the one key and nothing else, so a receiver told to stop is not told when to stop. It stops now.

That matches what the published record says about the field, which is that the low bit of `rate` decides playback, odd meaning play or resume and even meaning pause (reported confirmed by both, [shairport-sync, `rtsp.c`](https://github.com/mikebrady/shairport-sync/blob/master/rtsp.c) and [openairplay, `airplay2-receiver`](https://github.com/openairplay/airplay2-receiver/blob/master/ap2-receiver.py)). <doc:Protocol-Timing> covers the other fields.

One observed session in full, with the time each request arrived (measured 2026-09-22, decrypted, F-056).

```text
09:53:43  start    rate 1, networkTimeSecs 1410493, rtpTime 1442375314
09:53:48  pause    rate 0
09:53:54  resume   rate 1, networkTimeSecs 1410503, rtpTime 1442542965
09:54:03  track    rate 1, networkTimeSecs 1410512, rtpTime 3133593496
09:54:10  seek     rate 0
09:54:12  seek     rate 1, networkTimeSecs 1410521, rtpTime 2969409775
```

## Changing track

A track change is a flush followed by a fresh anchor (measured 2026-09-22, decrypted, F-058).

```text
1.  SET_PARAMETER       the metadata, with the player state at Paused
                        and the new title beside it
2.  FLUSHBUFFERED
3.  SETRATEANCHORTIME   rate 1, with an rtpTime unrelated to the previous one
```

The metadata arrives first, before the audio it describes. Each track gets a timeline of its own, because the new `rtpTime` bears no relation to the old one.

## Seeking

A seek is a pause and then a new anchor, which is exactly the two requests a resume takes. Nothing distinguishes the two except where the timeline is put (measured 2026-09-22, decrypted, F-059).

## Stopping

Stopping is a flush and then two teardowns, the stream first and then the session (measured 2026-09-22, decrypted, F-061 and F-037).

```text
FLUSHBUFFERED
TEARDOWN   {'streams': [{'streamID': 1, 'type': 103}]}
TEARDOWN   {}
```

The `streamID` is the number the stream SETUP reply gave back, and naming it takes that one stream down whilst leaving the session up (reported likely, [openairplay, `airplay2-receiver`, `ap2/connections/stream.py`](https://github.com/openairplay/airplay2-receiver/blob/master/ap2/connections/stream.py) and [Cozzi, RTSP](https://web.archive.org/web/20220214214845/https://emanuelecozzi.net/docs/airplay2/rtsp/)). The bodyless TEARDOWN then ends the session.

Type 103 is the buffered stream over TCP, which is the path an iPhone takes (measured 2026-09-22, decrypted, F-038).

### Removing one member from a group

When one of two controlled receivers was deselected, its own session received
`SETRATEANCHORTIME` with only `rate: 0`, then `FLUSHBUFFERED`, then a stream
`TEARDOWN`. The remaining receiver stayed selected. A shortened `SETPEERS`
list reached the remaining receiver in a separate run; the two-receiver logs
did not preserve that channel without gaps during this removal (measured
2026-09-24, decrypted, F-120). This is the observed removal sequence, not a
replacement for the full-session stop above.

## Volume

Volume is a `SET_PARAMETER` request with `Content-Type: text/parameters` and a one-line body. There is no property list form and no separate AirPlay 2 surface for it.

```text
SET_PARAMETER rtsp://<sender ip>/<session id> RTSP/1.0
CSeq: 12
Content-Type: text/parameters
Content-Length: 18

volume: -11.123877
```

The value is an attenuation in decibels. It runs from -30.0, the quietest, to 0.0, the loudest. The value -144 is a sentinel meaning muted rather than an attenuation (reported confirmed, [openairplay, Volume Control](https://openairplay.github.io/airplay-spec/audio/volume_control.html), and reported confirmed for the same constants, [pyatv, `pyatv/protocols/airplay/utils.py`](https://github.com/postlund/pyatv/blob/master/pyatv/protocols/airplay/utils.py)).

Apple's own sender uses exactly that, sending values such as `-19.799999`, `-15.949732` and `-21.144213` (measured 2026-09-22, decrypted, F-036).

Mapping a percentage onto it is linear across that range, with zero per cent special-cased to the mute sentinel.

```text
percentage 0            ->  -144.0
percentage p in 0..100  ->  (p * 3.0 - 300.0) / 10.0
```

The arrangement of that expression matters on Apple silicon. Written as `-30 + 0.3 * p`, a compiler that fuses the multiply and the add lands a hair below zero at one hundred per cent, and the text that goes on the wire becomes `-0.000000` (reported confirmed as a diagnosed case on Apple clang for arm64, [airplay2-sender-cpp, `raop_sender.cpp`](https://github.com/akustikrausch/airplay2-sender-cpp)).

### Reading the volume back

A current value comes back from `GET_PARAMETER` with a body naming `volume` (reported confirmed from a capture, [UxPlay wiki, AirPlay2](https://github.com/FDH2/UxPlay/wiki/AirPlay2)). Apple's sender sends exactly that between the session SETUP and RECORD, so it adopts the receiver's own level rather than imposing one (measured 2026-09-22, decrypted, F-032).

The package now asks at that point. The public Swift session reports an optional level, and the C session reports whether one is known. A receiver that does not answer leaves the level unknown without preventing playback.

What comes back can sit below the range a sender writes. A captured Sonos One answers with `volume: -100`, and `initialVolume` in the `GET /info` reply is an integer from -144 to 0 (reported confirmed from that capture, [Cozzi, RTSP](https://web.archive.org/web/20220214214845/https://emanuelecozzi.net/docs/airplay2/rtsp/)). Treat -30 as the floor of what a sender sets and not as the floor of what it may read.

pyatv's starting volume is 33 per cent when the receiver reports no `initialVolume`, and its volume steps are five percentage points (reported confirmed as a description of pyatv, [pyatv, `pyatv/protocols/raop/__init__.py`](https://github.com/postlund/pyatv/blob/master/pyatv/protocols/raop/__init__.py)). A receiver keeps whatever volume it had if the sender never sends one, which reads to a user as a connected session that plays nothing, so a sender sends a volume once the stream is up.

Two TXT keys decide whether the sender has to attenuate for itself. `sv` is software volume and `sm` is software mute, and each says whether the receiver can attenuate in hardware or whether the sender must scale the samples before they leave (reported confirmed, [pyatv, protocol documentation](https://pyatv.dev/documentation/protocols/)).

### Volume in a group

The published record left this open. No source describes per-device volume inside a group, and `SET_PARAMETER` being a per-session request means that one request per receiver follows mechanically from one session per receiver, without any source saying so as policy.

The measurement closes it. The volume of one speaker reaches that speaker alone. When the other member of a group had its level changed, nothing arrived at this receiver for the nineteen seconds it took. There is no group command: the device's own volume control moves every member, and it does so by sending each of them its own `SET_PARAMETER` on its own session (measured 2026-09-22, decrypted, F-064).

In a later local session with one Sonos Bookshelf, this library polled `GET_PARAMETER` while the operator pressed the receiver's physical volume buttons. The typed callback rose from 0.54 through 0.98 and fell to 0.62 (measured 2026-09-24, F-128). This proves external volume readback during an open session with that receiver; it does not establish volume monitoring for an idle receiver without a session.

### How a user is moving the control

Seventy seven volume requests arrived in one session, because a slider being dragged sends a stream of values rather than one value when it settles (measured 2026-09-22, decrypted, F-036). The two ways of changing the volume are distinguishable by their timing: a dragged slider sends nine values inside a second, whilst the volume buttons on the device send one a second (measured 2026-09-22, decrypted, F-064).

## Metadata

Metadata arrives as DMAP, which is the tagged binary format Apple uses for its media library protocols. `dmap.persistentid` identifies the item, `dmap.itemname` names it, and `dacp.playerstate` reads `Playing` or `Paused`. It is re-sent repeatedly whilst playing rather than only when something changes (measured 2026-09-22, decrypted, F-060).

`SET_PARAMETER` carries all the per-session parameters, each under its own content type, which is worth knowing so the volume request is not mistaken for a request of its own (reported confirmed, [Cozzi, RTSP](https://web.archive.org/web/20220214214845/https://emanuelecozzi.net/docs/airplay2/rtsp/)).

| Content type | What it carries |
|---|---|
| `text/parameters` | `volume: <decibels>`, and `progress: start/current/end` |
| `image/jpeg` | The cover artwork |
| `application/x-dmap-tagged` | Now-playing information in DAAP form |

Those three are what the `md` TXT key says a receiver accepts, which <doc:Protocol-Finding-Receivers> covers.

## What a sender cannot steer

macOS offers no control over another device's AirPlay session. Its speaker list shows which speakers exist and nothing about which are playing, and the only volume it offers is the system's own. Nothing done on the Mac during a session between an iPhone and a receiver reached that session at all (measured 2026-09-22, decrypted, F-042). A sender that wants to know whether a receiver is busy reads the status flags in the Bonjour record instead, which <doc:Protocol-Finding-Receivers> describes.
