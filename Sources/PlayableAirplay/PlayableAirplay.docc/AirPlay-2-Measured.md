# AirPlay 2, as measured

What an Apple sender actually sends, watched from the receiving end.

## Overview

Everything here was observed rather than read. An iPhone played to a receiver that held the pairing keys and printed the control channel in the clear, whilst a packet recording ran beside it. What follows is what arrived.

That makes it narrower than a specification and more reliable than one. It is one iPhone on iOS 26, one Mac on macOS 26, a HomePod mini, an Apple TV 4K and five Sonos speakers, on one network, on 22 September 2026. Where the sources disagree with this, this is what the wire did that day.

Every number below is a reading. Nothing is inferred from a table of flag names, because the published tables disagree with each other and none of them was checked against a device.

### Finding a receiver, and reading its state

A receiver advertises `_raop._tcp` and puts what it is into the TXT record. Three fields carry more than they look like they do.

`am` is the model. Apple's receivers give the identifier their hardware is known by everywhere else, such as `AudioAccessory5,1` for a HomePod mini or `AppleTV11,1` for an Apple TV, and macOS keeps a picture of every model it knows filed under exactly that code. Everybody else gives a short label: Sonos announces `Arc`, `One` and `Bookshelf`, which are display names rather than models, and two different products arrive under one word.

`pk` is the pairing key, and its presence is what says a receiver speaks AirPlay 2 at all.

`sf` is the state, and it changes whilst you watch. Read from a HomePod mini at four moments:

| State | `sf` | Bit 11 | Bit 17 | Bit 20 |
|---|---|---|---|---|
| At rest | `0x80404` | clear | clear | clear |
| A sender connected and playing | `0x1a0c04` | set | set | set |
| Stopped, sender still connected | `0xa0c04` | set | set | clear |
| Sender disconnected | `0x80404` | clear | clear | clear |

Bits 11 and 17 move together and say a sender holds a session. Bit 20 says audio is flowing at this moment. The value returns exactly to its resting one. A browse therefore learns that a speaker has become busy without asking it anything, because the change arrives as an ordinary Bonjour update.

Sonos speakers advertise `sf=0x4` whatever they are doing, so none of this applies to them.

### Asking a receiver about itself

`GET /info` on port 7000 is answered without pairing, over plain HTTP, and returns a binary property list.

```bash
curl -s http://<host>:7000/info | plutil -convert xml1 -o - -
```

An Apple receiver returns around forty keys, among them its name, its model, its device and hardware addresses, its build of the operating system, the formats it accepts for each kind of stream, its current volume as `initialVolume`, and `statusFlags`, which is the same number the Bonjour record carries as `sf`.

One key invites the wrong reading. `senderAddress` is the address of whoever is asking, not of whoever is playing. Three queries a second apart return three consecutive port numbers, which are the ports of those three queries.

A Sonos answers the same request with almost nothing: no volume, no state. A Mac whose AirPlay receiving is switched off refuses the connection rather than answering emptily, which is a usable distinction in itself.

### A session, in the order it happens

This is the order observed, and it is not the order the published accounts describe.

```text
GET /info?txtAirPlay&txtRAOP     asked several times
GET /info
POST /pair-verify                X-Apple-HKP: 8
                                 the channel is encrypted from here on
SETUP                            the session
GET_PARAMETER volume
RECORD
SETPEERS
SETUP                            the stream
SETRATEANCHORTIME
SET_PARAMETER volume
```

`RECORD` comes before the stream `SETUP` rather than after it, and `SETPEERS` sits between them. The session is addressed by a numeric identifier in the request URI from the first `SETUP` onwards, and that identifier belongs to the session rather than to either device: two sessions between the same pair carried different ones.

Two devices that have paired before go straight to pair-verify. No `pair-setup` appears at all, and the header value is 8.

The sender asks the receiver for its volume before starting, so it adopts the receiver's own level rather than imposing one.

### Groups

`SETPEERS` is the group, and its name invites the wrong reading a second time. It does not name the other speakers. It names every address of every member of the clock group, and the sender counts as a member.

Watched across one session as a second speaker joined and left:

```text
playing alone      the sender's five addresses
a speaker joins    that speaker's five addresses, then the sender's five
the speaker leaves the sender's five again
```

The new member is listed first and the sender last. Each member contributes one IPv4 address and four IPv6 ones, among them a link-local, a unique local and two global.

A speaker joining an existing session changes nothing else. No second `SETUP`, no further `RECORD`, no new anchor, no interruption. One `SETPEERS` arrives with the enlarged list and the session carries on. The same holds in reverse.

### Timing

AirPlay 2 keeps a group in step with PTP, and the traffic is unicast over IPv6 link-local on ports 319 and 320, in domain 0. It is PTPv2 with the version 1 compatibility flag set, and the flags field carries `timescale` and `unicast`. No multicast PTP appeared at all.

The receivers elect a master among themselves and the sender is not a candidate. Both receivers announced, one claiming `priority2` 247 and the other 233, and the lower value won: that device went on to send 514 Sync and 514 Follow_Up messages whilst the other sent two of each and then slaved.

Every Announce carried `priority1` 248, `clockClass` 248, `clockAccuracy` 33, `clockVariance` 17258, `stepsRemoved` 0 and `timeSource` 0xa0.

Clock identities are not derived from a visible hardware address. Every one seen ends in `0008` rather than in the `fffe` that standard EUI-64 padding produces.

The anchor ties that clock to a position in the audio.

```text
networkTimeFlags       0
networkTimeFrac        -8768708216239423488
networkTimeSecs        1410493
networkTimeTimelineID  -2267142311769604088
rate                   1
rtpTime                1442375314
```

`networkTimeTimelineID` is a clock identity in the same form, `0xE0897E144BB70008` read as unsigned, and it belongs to the sender. It was identical in every session recorded over an hour, to differently named receivers, so it identifies the clock rather than the session. That is the join between the two halves: the traffic on ports 319 and 320 and the anchor in the control channel refer to the same identity.

### Steering the playback

Playing and pausing are the same request with different bodies.

```text
start   {networkTimeFlags, networkTimeFrac, networkTimeSecs, networkTimeTimelineID, rate: 1, rtpTime}
pause   {rate: 0}
resume  the full set again, with a later networkTimeSecs and a later rtpTime
```

A pause carries the rate and nothing else, so a receiver told to stop is not told when to stop. It stops now.

A track change is `FLUSHBUFFERED` followed by a fresh anchor whose `rtpTime` bears no relation to the previous one, so each track gets a timeline of its own. The metadata arrives first, with the player state going to `Paused` and the new title beside it.

A seek is a pause and then a new anchor, which is exactly the two requests a resume takes. Nothing distinguishes the two except where the timeline is put.

Stopping is `FLUSHBUFFERED` and then two teardowns, the stream and then the session.

```text
TEARDOWN   {'streams': [{'streamID': 1, 'type': 103}]}
TEARDOWN   {}
```

Type 103 is the buffered stream over TCP. An iPhone takes that path, and type 96, the realtime one, appeared nowhere in any session.

### Volume

Volume is an absolute level in decibels, sent as a text parameter.

```text
SET_PARAMETER  volume => -19.799999
```

Seventy seven of them arrived in one session, because a slider being dragged sends a stream of values rather than one when it settles. The two ways of changing it are distinguishable by their timing: a dragged slider sends nine values inside a second, whilst the volume buttons on the device send one a second.

The volume of one speaker reaches that speaker alone. When the other member of a group had its level changed, nothing at all arrived here for the nineteen seconds it took. There is no group command: the device's own volume control moves every member, and it does so by sending each of them its own `SET_PARAMETER` on its own session.

### Metadata

Metadata arrives as DMAP. `dmap.persistentid` identifies the item, `dmap.itemname` names it, and `dacp.playerstate` reads `Playing` or `Paused`. It is re-sent repeatedly whilst playing rather than only when something changes.

### What this does not tell you

It says nothing about what the sender transmits as PTP. Three recordings caught the receivers' timing traffic in full and none of this Mac's own, whilst its control channel was recorded in both directions on the same interface. PTP is timestamped in the network hardware and that transmit path does not pass the packet filter, so seeing it needs a vantage point off the machine.

It says nothing about pairing from scratch, because the devices involved had already paired.

It says nothing about the realtime path, because nothing observed used it.

And it says nothing about what a macOS sender does. One attempt reached the receiver, completed pair-verify, sent the session `SETUP` and stopped there. Whether macOS refuses a session to an address on the same machine, or wants something in that request the receiver did not answer, is not settled.
