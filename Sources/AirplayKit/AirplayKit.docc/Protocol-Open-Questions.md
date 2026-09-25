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

An iPhone sent 8 on four pair-verify requests (measured 2026-09-22, captured, F-021), while a Mac sent 6 on pair-verify with stored credentials against two Apple receivers (F-134) and 4 on pair-setup with an unfamiliar test receiver (F-073). One receiver's published constant list stops at 7. The captures do not isolate which difference between the senders or pairing states caused 6 versus 8, nor what 8 means.

What settles it: a receiver that logs the value and accepts 3, 4, 6 and 8 in turn under otherwise identical conditions, showing whether the value changes what it does.

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

### 14. What a receiver must do about asyncPTPClockConfig

A macOS 27.2 sender that asked for `asyncPTPClockConfig` and received an ordinary SETUP reply waited eight seconds, asked `GET /info` once more, and gave up without sending the stream SETUP (measured 2026-09-22, decrypted, F-077). The receiver in that run writes nothing at all on its event channel, so the `updateTimingPeerInfo` message Apple's own strings and one open implementation both describe could never have arrived. The reply shape is not the gate, because shairport-sync sends the same three keys and works, and the absence of PTP on the receiver is not the gate either, because nqptp is not a PTP clock. <doc:Protocol-Timing> carries both.

What settles it: making that receiver push `updateTimingPeerInfo` on the event channel and watching whether the stream SETUP follows. A 2026-09-24 macOS attempt reached only `GET /info`, so the experimental event push was never exercised.

### 15. How a sender reconciles different receiver latencies

Two controlled receiver channels got different anchors that mapped the same media to the same PTP clock within about 2.7 microseconds (measured 2026-09-24, decrypted, F-119). Their output latencies and audible synchronisation were not measured, so the remaining question is where latency compensation happens.

What settles it: capture anchors and reported `outputLatencyMicros` from two real receivers with different output latencies, then measure their acoustic output.

### 16. Whether a macOS sender is stricter than an iOS one

Every comparison so far put macOS 27.2 against iOS 18.7, so platform and version moved together. Two of the keys in the session SETUP are new in OS 27, so the older sender was not taking a more lenient path through the same protocol but speaking an earlier one.

What settles it: an iOS 27 device against the same receiver.

### 17. Which additional timing information other receiver models need

Two Sonos receivers did not converge when a diagnostic sender advertised a shared group UUID and timing identity but sent no PTP traffic (measured 2026-09-24, F-124). With an active sender PTP clock sending Sync, Follow_Up and Announce and answering Delay_Req, both Sonos receivers used a shared anchor; two and three real receivers then played an audible test tone that the operator judged simultaneous (measured 2026-09-24, F-125 and F-126). This establishes a working path for those Sonos receivers, not the exact Apple sender profile or support across other receiver models. The probe used IPv4 peer lists and did not establish whether other models require IPv6 peers or different timing messages.

What settles the remaining question: capture a working Apple group with the sender's PTP packets and complete peer lists visible, then test other receiver models against this sender.

### 18. How an authorized third-party sender pairs under home-members-only access

The local sender received `403 Forbidden` for its first transient `POST /pair-setup` to a HomePod mini while it advertised `acl=1` (F-130 and F-132). After the operator changed the Home app access setting, Emma advertised `acl=0` and accepted the unchanged request; a 30-second mixed Sonos and HomePod group was audible and judged simultaneous (F-135, F-137 and F-138). Restoring the original rule returned the announcement to `acl=1` and the same first pairing request to 403 (F-138). This establishes the access rule as the gate for this sender's fresh transient path on this HomePod. A Sonos that accepted transient pairing also advertised `acl=1`, so the field is not a universal admission rule across brands.

Eter Radio on this Mac connected successfully with `POST /pair-verify` and `X-Apple-HKP: 6`, as did the earlier macOS group capture (F-134 and F-136). Both used an existing pairing; neither capture shows how those credentials were obtained. Whether this library can obtain authorized credentials for Emma under the restored rule, and by what supported user action, remains open. An Apple Home access setting and any AirPlay password requirement must be treated separately.

What settles it: observe an authorized first pairing to this HomePod under the restrictive rule, including the required user interaction and resulting credential storage, then verify a fresh session using those credentials. Do not infer those steps from a pair-verify-only capture.

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
| How a member is removed from a group | The leaving receiver got `SETRATEANCHORTIME` with `rate: 0`, then `FLUSHBUFFERED`, then a stream `TEARDOWN` (measured 2026-09-24, decrypted, F-120). A shorter peer list on the remaining receiver was observed in a separate run (F-033); it was not preserved without gaps in the two-probe run. | <doc:Protocol-Control> |
| Whether two members receive identical anchors | No. Their 48 kHz streams received different anchor fields, but the same clock identity and equivalent media-to-clock mappings within about 2.7 microseconds (measured 2026-09-24, decrypted, F-119). Audible synchronisation remains untested. | <doc:Protocol-Timing> |
| What a PTP clock identity is made of | The device's six-byte hardware address with `0008` after it, which is why none of them ends in the `fffe` of standard EUI-64 (measured 2026-09-22, decrypted, F-076) | <doc:Protocol-Timing> |
| Whether a receiver has to speak PTP before a sender will send audio | No. nqptp answers nothing, originates nothing, and is not a PTP clock, and a session whose timing fails still reaches playback | <doc:Protocol-Timing> |
| Whether one Bonjour service type is enough to find every receiver | No. A receiver can publish `_airplay._tcp` alone, and the group identity is published there and in no RAOP record (measured 2026-09-22, browsed, F-066 and F-068) | <doc:Protocol-Finding-Receivers> |
| Whether both TXT records can be read without Bonjour | Yes. `GET /info?txtAirPlay&txtRAOP` returns each record verbatim in its counted DNS-SD form (measured 2026-09-22, queried, F-071) | <doc:Protocol-Finding-Receivers> |
| Whether a macOS sender refuses a receiver on its own machine | No. It stops at the same point with the receiver on a second machine (measured 2026-09-22, decrypted, F-077) | <doc:Protocol-Timing> |
