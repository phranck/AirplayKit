# Open questions

What is still unsettled, and what would settle each one.

## Overview

An open question written down is worth more than a plausible guess. Each item below says what is not known and what experiment answers it.

Questions that the published record left open and the measurement has closed are listed at the end, so that nobody spends time on them a second time.

## Still open

### 1. Which PTP profile AirPlay 2 uses

The transport and the domain are settled. The traffic is unicast to each peer over IPv6 link-local on ports 319 and 320, in domain 0, as PTPv2 with the version 1 compatibility flag set (measured 2026-09-22, captured, F-009). The profile is not. shairport-sync's author hedges it with a "possibly" towards 802.1AS (reported confirmed as a statement of what is unknown, [shairport-sync discussion 1712](https://github.com/mikebrady/shairport-sync/discussions/1712)).

What settles it: the message intervals and the optional fields in one capture of a Mac and a HomePod, compared against the profiles that specify them.

### 2. Whether the sender is a candidate in the master-clock election

Two receivers announce and contest between themselves, and `priority2` decides it (measured 2026-09-22, captured, F-011). A sender alone with one receiver is the only clock source and behaves as the master (measured 2026-09-22, captured, F-017). What is missing is the sender's own transmissions in the two-receiver case, because the capturing machine's PTP never reaches the packet filter (measured 2026-09-22, captured, F-018).

What settles it: a recording taken off the sending machine, such as the packet capture built into a router, of a Mac playing to two HomePods. It shows whether the sender announces, with what priority, and whether it ever wins.

### 3. What the sender transmits as PTP at all

The same gap, asked as a design question. Whether the sender is a plain slave of the elected master, or a boundary clock passing the time on to the other members, changes what a sender has to implement.

What settles it: the same off-machine recording.

### 4. Whether an NTP session uses the classic packet layouts byte for byte

Two independent senders drive Apple receivers with the classic 0xD4 SYNC packet and the audio plays in step, which is strong evidence. No capture of such a session is published, and the PTP path is the one that was measured.

What settles it: a capture of a session whose session SETUP carries `timingProtocol: NTP`.

### 5. What X-Apple-HKP: 8 means

Apple's own sender sends 8 on every pair-verify request (measured 2026-09-22, captured, F-021) and 4 on a pair-setup (measured 2026-09-22, read off a receiver, F-073). The published record names only 3 and 4 as values a sender sends, and one receiver's own list of the constant stops at 7. Since 8 has only ever been seen on pair-verify, the value plausibly names the mode of that request, and that reading is not tested.

What settles it: a receiver that logs the value and accepts 3, 4 and 8 in turn, showing whether any of them changes what it does.

### 6. Which X-Apple-HKP value the PIN path wants

A receiver's own list reserves 3 for system pairing and puts HomeKit at 6 and 7, whilst three senders send 3 for the PIN path and are answered.

What settles it: pairing with a PIN against an Apple TV whilst sending 6.

### 7. What networkTimeFlags is for

It appears in every measured anchor and it was 0 every time (measured 2026-09-22, decrypted, F-035). No published source names the field at all.

What settles it: a value other than 0 turning up, which most likely needs a receiver logging anchors across a wider range of sender behaviour than pause, resume, seek and track change.

### 8. Whether clientID is a field of any SETUP

It appears in no receiver, no sender and no capture examined here.

What settles it: sending it and watching for a rejection, which costs one request.

### 9. What isMultiSelectAirPlay does

Apple's own sender sends it true and one receiver parses it and never reads it again.

What settles it: sending it false whilst addressing two receivers and seeing whether either refuses. Until then, copy Apple.

### 10. The true names of features bits 26, 30, 38 and 48

Three tables disagree and only Apple can settle them. This blocks nothing, because every table agrees on the numbers, and the properties a sender reads are derived over several bits rather than carried by one. <doc:Protocol-Finding-Receivers> gives those derivations.

### 11. What the status-flag bits are called

Bits 11, 17 and 20 were measured moving with the state of a session, and what each indicates is not open because it was observed (measured 2026-09-22, queried, F-049). What they are called is, because the published tables disagree, none of them was checked against a device, bit 20 lies outside the width the published table covers, and bit 11's published name reads as a capability whilst the bit was seen changing.

What settles it: only Apple.

### 12. Whether AirPlay receivers accept pair-resume

Apple's HomeKit implementation defines the mechanism with its own nonces and info strings, and nothing says whether an AirPlay receiver answers one.

What settles it: sending a resume request to an Apple TV that has pair-verified once, and reading the answer.

### 13. Why the transport is IPv6 link-local in one direction and IPv4 in the other

A Mac sending to Apple receivers used IPv6 link-local. An iPhone sending to the Mac used IPv4 on the ordinary network (measured 2026-09-22, captured, F-019). Nothing in the published record accounts for the difference.

What settles it: the same pair of devices recorded with each playing to the other, and the address selection each one makes read out of the connection attempts rather than out of the connection that succeeded.

### 14. How a member leaves a group, from the sender's side

A member leaving is visible from the receiving end as one `SETPEERS` with the shortened list (measured 2026-09-22, decrypted, F-033). What the sender sends to the member that is leaving was not observed, because the receiver reading the channel was never the one that left.

What settles it: two receivers under our own control in one group, with one of them removed.

### 15. What a receiver must do about asyncPTPClockConfig

A macOS 27.2 sender that asked for `asyncPTPClockConfig` and received an ordinary SETUP reply waited eight seconds, asked `GET /info` once more, and gave up without sending the stream SETUP (measured 2026-09-22, decrypted, F-077). The receiver in that run writes nothing at all on its event channel, so the `updateTimingPeerInfo` message Apple's own strings and one open implementation both describe could never have arrived. The reply shape is not the gate, because shairport-sync sends the same three keys and works, and the absence of PTP on the receiver is not the gate either, because nqptp is not a PTP clock. <doc:Protocol-Timing> carries both.

What settles it: making that receiver push `updateTimingPeerInfo` on the event channel and watching whether the stream SETUP follows.

### 16. How a sender reconciles different receiver latencies

Nothing in the reachable record addresses it. The anchor is the mechanism that makes reconciliation unnecessary, because each receiver subtracts its own output latency locally, and no source says that is the whole answer.

What settles it: a capture of a Mac playing to two receivers whose reported `outputLatencyMicros` differ, checked for any per-receiver difference in the anchor.

### 17. Whether a macOS sender is stricter than an iOS one

Every comparison so far put macOS 27.2 against iOS 18.7, so platform and version moved together. Two of the keys in the session SETUP are new in OS 27, so the older sender was not taking a more lenient path through the same protocol but speaking an earlier one.

What settles it: an iOS 27 device against the same receiver.

### 18. Whether two receivers in one group are given the same anchor

How a group is held together is read from one side only: one receiver's `SETPEERS` and one receiver's `SETRATEANCHORTIME`. That the anchor is identical for every member is the reading the rest of the design rests on, and it is not measured.

What settles it: a receiver on each of two machines in one session, with the two anchors compared directly.

## Closed by the measurement

These were open in the published record and are not open now.

| Question | Answer | Where |
|---|---|---|
| Whether a sender opens one session per receiver or addresses a group through a leader | One RTSP session per receiver. Two receivers, two connections, two local ports, no leader (measured 2026-09-22, captured, F-008) | <doc:Protocol-Session> |
| Per-device volume inside a group | One `SET_PARAMETER` per receiver on its own session. There is no group command (measured 2026-09-22, decrypted, F-036) | <doc:Protocol-Control> |
| Which PTP domain number is used | Domain 0 (measured 2026-09-22, captured, F-009) | <doc:Protocol-Timing> |
| Whether the PTP traffic is unicast or multicast | Unicast, over IPv6 link-local. No multicast PTP packet appeared at all (measured 2026-09-22, captured, F-009) | <doc:Protocol-Timing> |
| Whether the receivers run a Best Master Clock election or accept whoever announces | They announce with full Best Master Clock fields and contest it. `priority2` decides (measured 2026-09-22, captured, F-011) | <doc:Protocol-Timing> |
| Whether `SETPEERS` grows when a second speaker joins | It does, and it carries the whole membership each time rather than a change to it (measured 2026-09-22, decrypted, F-033) | <doc:Protocol-Session> |
| What a PTP clock identity is made of | The device's six-byte hardware address with `0008` after it, which is why none of them ends in the `fffe` of standard EUI-64 (measured 2026-09-22, decrypted, F-076) | <doc:Protocol-Timing> |
| Whether a receiver has to speak PTP before a sender will send audio | No. nqptp answers nothing, originates nothing, and is not a PTP clock, and a session whose timing fails still reaches playback | <doc:Protocol-Timing> |
| Whether one Bonjour service type is enough to find every receiver | No. A receiver can publish `_airplay._tcp` alone, and the group identity is published there and in no RAOP record (measured 2026-09-22, browsed, F-066 and F-068) | <doc:Protocol-Finding-Receivers> |
| Whether both TXT records can be read without Bonjour | Yes. `GET /info?txtAirPlay&txtRAOP` returns each record verbatim in its counted DNS-SD form (measured 2026-09-22, queried, F-071) | <doc:Protocol-Finding-Receivers> |
| Whether a macOS sender refuses a receiver on its own machine | No. It stops at the same point with the receiver on a second machine (measured 2026-09-22, decrypted, F-077) | <doc:Protocol-Timing> |
