# The AirPlay 2 sender protocol

What a sender puts on the wire, and where every statement in it came from.

## Overview

These articles are the protocol reference a Swift AirPlay 2 sender is written from. They cover what a sender has to send to find a receiver, pair with it, encrypt the session, set up an audio stream, send audio, keep the session alive, and hold several receivers in step. They target macOS and Linux, and playing to several speakers at once is treated as an ordinary case rather than as an extension.

Two bodies of knowledge stand behind them. One is the published record, which is Apple's own released source, the RFCs, the unofficial specification, and four working implementations. The other is one measurement run, made on one network on 22 September 2026, by watching what an Apple sender actually sends.

Every claim carries a mark at the place it is made, saying which of the two it came from and how far it reaches.

| Mark | Form | What it means |
|---|---|---|
| Measured | `(measured 2026-09-22, decrypted, F-033)` | Observed here. The date says when, the one word says how, and the `F-` number is the entry in the test log that holds the raw observation. |
| Reported | `(reported confirmed, [source](https://example.org/))` | A source states it. The link goes to that source. The word is the confidence the published record gave it, either `confirmed` or `likely`. |
| Open | `(open: a capture of a Mac and two HomePods settles it)` | Unsettled, followed by what would settle it. |

The four words that say how something was measured are these. `browsed` means a Bonjour browse of the service records. `queried` means a plain request to a device, such as `GET /info` over HTTP or a UPnP action. `captured` means a packet recording taken beside a live session. `decrypted` means an AirPlay 2 receiver was run that held the pairing keys and printed the control channel in the clear.

### What the measurement was

One iPhone on iOS 26, one Mac on macOS 26, a HomePod mini, an Apple TV 4K and five Sonos speakers, on one home network, on 22 September 2026. Nothing below rests on a second network or a second day.

That makes the measurement narrower than a specification and more reliable than one. It covers what those devices did, and it says nothing about a device that was not there. Where a measurement disagrees with a source, both are stated, and the measurement is what the wire did that day.

Two confidences that the published record carried as likely turn out to be wrong, and both are named where they belong. The first is who runs the clock, which <doc:Protocol-Timing> takes apart. The second is the order the requests go out in, and what `SETPEERS` carries, both of which sit in <doc:Protocol-Session>.

### What these articles do not cover

AirPlay video, screen mirroring and photo streaming are out of scope. So is the receiver side, beyond what a sender has to predict of it. FairPlay and the MFi authentication chain are named where they appear in a service record, and the FairPlay handshake itself is not described, because it needs Apple key material that a clean-room sender does not have. AirPlay 1 appears only where the AirPlay 2 path inherits from it, which is most of the RTP layer and all of the older timing layer.

Everything here is a protocol fact, meaning a field name, a byte layout, a constant, or a message order. No source code is reproduced from any project, and none from a GPL or AGPL project.

### The order to read in

<doc:Protocol-Finding-Receivers> comes first. It covers the Bonjour records a receiver publishes, the capability and status bitfields inside them, and the `GET /info` request that asks a receiver about itself without pairing. Everything a sender decides about a receiver is decided from what that article describes.

<doc:Protocol-Pairing> is next. It covers pair-setup, pair-verify, transient pairing, and the two encrypted channels that carry everything afterwards. Nothing in the articles after it is readable on the wire without it.

<doc:Protocol-Session> covers the RTSP layer that rides inside that encryption: the request order, the two SETUP bodies, and how a sender addresses several receivers as a group.

<doc:Protocol-Timing> covers PTP, the older NTP model, the anchor that ties a clock reading to a position in the audio, and receiver latency. It is the article the multi-room case turns on.

<doc:Protocol-Audio> covers the two audio paths, their packet layouts, the codec, and how a lost packet is recovered.

<doc:Protocol-Control> covers steering a session that is already running: playing, pausing, seeking, changing track, volume, metadata, and tearing the session down.

<doc:Protocol-Open-Questions> collects what is still unsettled, with what would settle each one.

<doc:Protocol-Sources> names every published source and every device the measurements were taken on.

### Every fact is written down here

A source that a claim rests on can go away, and one of the most cited references for this protocol already has. Its site no longer resolves and it survives only in an archive.

So these articles carry the facts themselves. Every byte layout, field table, constant, message order, salt, info string, payload type and arithmetic conversion is written out here as a table or a fenced block, in our own words. The citation stays beside it, because it says where the fact came from and how sure it is, and nothing here needs the reader to follow it. Where a source carries a long explanation rather than a fact, that is summarised in a sentence and linked.
