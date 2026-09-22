# Session-level SETUP and PTP in AirPlay 2, receiver side

Research note, 2026-09-22. The question is what a macOS 27.2 sender expects back from the session-level `SETUP rtsp://<host>/<session-id>` when it asks for `timingProtocol: PTP`, and what the new OS 27 keys `asyncPTPClockConfig` and `combinedGetInfoWithControlSetup` require.

## What this note is based on, and what it is not

Five kinds of source were read, and every claim below is tagged with which one it came from.

- **[impl]** Source code of an open implementation, read at a pinned commit.
- **[apple]** Symbols and format strings extracted from Apple's own binaries. Two sets were used: the public symbol and string diff between iOS 26.5 (23F77) and iOS 27.0 (24A5355q) published by `blacktop/ipsw-diffs`, and the strings inside the dyld shared cache of the macOS 27.2 (26B5086k) machine this note was written on. Strings and symbol names say what code exists and what it logs. They do not say what it decides, so anything about control flow drawn from them is marked as inference.
- **[docs]** Prose documentation written by a project.
- **[report]** A bug report or maintainer answer on an issue tracker.
- **[inference]** My reading across the above. Marked every time.

There is no published Apple specification for AirPlay 2, which every source below states in one form or another. Nothing here is normative.

Two limits on the Apple evidence are worth stating before the findings. The iOS 26.5 to 27.0 file is a **diff**, so a string absent from it is a string that did not change, not a string that does not exist. That is why the key names inside `timingPeerInfo` (`ClockID`, `DeviceType`, `SupportsClockPortMatchingOverride`) do not appear in it: they predate iOS 27. The macOS shared cache extract has the opposite property. It contains every string, but with no structure, so adjacency in the extract only reflects adjacency in the binary's string table, which usually but not always follows the function that uses them.

### Sources read

| Source | Role | Pinned at |
| --- | --- | --- |
| [mikebrady/shairport-sync](https://github.com/mikebrady/shairport-sync) | AirPlay 2 audio receiver, known to work with macOS senders | [`01078ad`](https://github.com/mikebrady/shairport-sync/tree/01078ad15d4da06dffba0c5f15ffeaf9146a2a2a) |
| [mikebrady/nqptp](https://github.com/mikebrady/nqptp) | shairport-sync's PTP helper | [`c925f27`](https://github.com/mikebrady/nqptp/tree/c925f27c1fd12e4033ac477e5a405969b0b0260b) |
| [openairplay/airplay2-receiver](https://github.com/openairplay/airplay2-receiver) | the Python receiver in question | [`6c343d3`](https://github.com/openairplay/airplay2-receiver/tree/6c343d3679ddb561c61566985acaaf587d0a3bd3) |
| [owntone/owntone-server](https://github.com/owntone/owntone-server) | AirPlay 2 **sender**, with a real PTP stack | [`a038de2`](https://github.com/owntone/owntone-server/blob/a038de21065bbbfec721c9c974e3bbd30b22fd59/src/outputs/airplay.c) |
| [omarroth/doubletake](https://github.com/omarroth/doubletake) | AirPlay **sender** for Linux, plus a test receiver | [`ae06722`](https://github.com/omarroth/doubletake/tree/ae067228d76df011375164814b729932ed55ca2f) |
| [blacktop/ipsw-diffs](https://github.com/blacktop/ipsw-diffs) | Apple symbol and string diff, iOS 26.5 to 27.0 | [`61157ab`](https://github.com/blacktop/ipsw-diffs/tree/61157ab6a859ee24ae8c2e9a2ba08b9a5f47c991/26_5_23F77_vs_27_0_24A5355q) |
| macOS 27.2 (26B5086k) dyld shared cache | Apple's own sender and receiver on the failing machine | `/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_arm64e.19` and `.38`, dated 2026-09-14 |
| [FDH2/UxPlay issue 535](https://github.com/FDH2/UxPlay/issues/535) | first public report of `combinedGetInfoWithControlSetup` | opened 2026-07-15 |
| [mikebrady/nqptp issue 44](https://github.com/mikebrady/nqptp/issues/44) | measured Mac against iPhone PTP behaviour | opened 2026-04-06 |
| [emanuelecozzi.net AirPlay 2 Internals](https://emanuelecozzi.net/docs/airplay2/rtsp/) | the standard reverse-engineering write-up | host did not resolve on 2026-09-22, so it is cited second hand only |

The emanuelecozzi.net host was unreachable from here all day, so nothing in this note rests on it alone. Where it is quoted, the quotation comes from a search index and is marked as such.

## 1. What the reply to the session-level SETUP contains for `timingProtocol: PTP`

### What working receivers actually send

Shairport Sync builds the reply in `handle_setup_2` and puts exactly three keys in it for a PTP session ([rtsp.c:2572-2654](https://github.com/mikebrady/shairport-sync/blob/01078ad15d4da06dffba0c5f15ffeaf9146a2a2a/rtsp.c#L2572-L2654)) **[impl]**:

| Key | Type | Value it sends | Meaning |
| --- | --- | --- | --- |
| `eventPort` | integer | the TCP port it just bound and called `listen` on | the port the sender connects back to for the event channel |
| `timingPort` | integer | literally `0`, with the inline comment `// dummy` | see below |
| `timingPeerInfo` | dict | `Addresses` and `ID` only | the receiver's identity as a timing peer |

Inside `timingPeerInfo`, Shairport Sync puts `Addresses` as an array holding its own connection address first and then every address of every non-loopback interface that is up, IPv4 and IPv6 alike, and `ID` as **its own IPv4 address as a string** ([rtsp.c:2573-2623](https://github.com/mikebrady/shairport-sync/blob/01078ad15d4da06dffba0c5f15ffeaf9146a2a2a/rtsp.c#L2573-L2623)) **[impl]**. It sends no `ClockID`, no `DeviceType` and no `SupportsClockPortMatchingOverride`. Shairport Sync is documented as supporting Macs from macOS 10.15 onwards ([AIRPLAY2.md:26-30](https://github.com/mikebrady/shairport-sync/blob/01078ad15d4da06dffba0c5f15ffeaf9146a2a2a/AIRPLAY2.md#L26-L30)) **[docs]**, so this reply shape is accepted by macOS senders up to whatever version its users run.

The Python receiver sends the same three keys, with `Addresses` holding one address and `ID` holding the device MAC with colons ([ap2-receiver.py:207-224](https://github.com/openairplay/airplay2-receiver/blob/6c343d3679ddb561c61566985acaaf587d0a3bd3/ap2-receiver.py#L207-L224)) **[impl]**. Its comment on `timingPort` reads `# Seems like legacy, non PTP setting`.

### What senders actually read back

OwnTone is a sender with a real PTP daemon, and its handler for the session SETUP response reads exactly two things ([airplay.c:3180-3249](https://github.com/owntone/owntone-server/blob/a038de21065bbbfec721c9c974e3bbd30b22fd59/src/outputs/airplay.c#L3180-L3249)) **[impl]**:

1. `eventPort`. If it is absent or zero, OwnTone logs `SETUP reply is missing event port` and aborts the session.
2. For PTP only, `timingPeerInfo.Addresses`. It walks the array, takes the first address of the address family it is using, and hands it to `ptpd_slave_add`. If `timingPeerInfo` is missing, or `Addresses` is missing, or no address of the right family is in it, it aborts ([airplay.c:3122-3178](https://github.com/owntone/owntone-server/blob/a038de21065bbbfec721c9c974e3bbd30b22fd59/src/outputs/airplay.c#L3122-L3178)).

OwnTone reads no `ClockID`, no `DeviceType`, no `SupportsClockPortMatchingOverride` and no `timingPort` from the reply.

Doubletake, the other open sender, disagrees. Its media clock is configured from the SETUP response and it treats `timingPeerInfo.ClockID` as mandatory, failing with `SETUP response omitted timingPeerInfo.ClockID` when it is absent or zero ([mirror.go:47-52](https://github.com/omarroth/doubletake/blob/ae067228d76df011375164814b729932ed55ca2f/internal/airplay/mirror.go#L47-L52)) **[impl]**. Its own comment explains why it will not work around it: "A ClockID remains mandatory: inventing one would describe a timeline the receiver has never advertised and would make both audio and video invalid" ([mirror.go:75-91](https://github.com/omarroth/doubletake/blob/ae067228d76df011375164814b729932ed55ca2f/internal/airplay/mirror.go#L75-L91)). Its test receiver returns all five keys: `ClockID`, `ID`, `DeviceType`, `Addresses` and `SupportsClockPortMatchingOverride` ([receiver_server.go:981-989](https://github.com/omarroth/doubletake/blob/ae067228d76df011375164814b729932ed55ca2f/internal/airplay/receiver_server.go#L981-L989)).

**Sources disagree, and the disagreement is real.** Shairport Sync ships a reply without `ClockID` and works against Apple senders. Doubletake refuses a reply without `ClockID`. Both are third-party code, and each is right about itself. What follows is that `ClockID` is not needed by *every* sender, and nothing read here establishes whether Apple's sender needs it. Doubletake is a mirroring sender that deliberately runs no PTP stack of its own and derives its timeline from the receiver's identity instead ([mirror.go:37-45](https://github.com/omarroth/doubletake/blob/ae067228d76df011375164814b729932ed55ca2f/internal/airplay/mirror.go#L37-L45)), which is a design choice that makes `ClockID` load-bearing for it and for nobody else. **[inference]**

### Does the reply need to mirror what the sender sent?

The sender's own `timingPeerInfo` describes the sender, not the receiver. OwnTone builds the outgoing one from its own PTP clock: `ID` as a UUID it generated at startup, `DeviceType: 0`, `ClockID` as its own PTP clock identity cast to a signed 64-bit integer, `SupportsClockPortMatchingOverride: false`, and `Addresses` as its own addresses ([airplay.c:2719-2760](https://github.com/owntone/owntone-server/blob/a038de21065bbbfec721c9c974e3bbd30b22fd59/src/outputs/airplay.c#L2719-L2760)) **[impl]**. Two of its inline comments are honest about the gaps: `iOS sends a UUID, but where does it come from?` on `ID`, and `iOS says true, no idea what it means` on `SupportsClockPortMatchingOverride`.

So the reply is not a mirror. It is the receiver's own answer to the same questions, with the same key names. No source read here shows a receiver echoing the sender's `ClockID` or its `SupportsClockPortMatchingOverride` back. **[inference]**

### `timingPort` under PTP

Two independent implementations put `0` in it under PTP and both comment that it is vestigial: Shairport Sync writes `// dummy` ([rtsp.c:2654](https://github.com/mikebrady/shairport-sync/blob/01078ad15d4da06dffba0c5f15ffeaf9146a2a2a/rtsp.c#L2654)) and the Python receiver writes `Seems like legacy, non PTP setting` ([ap2-receiver.py:220](https://github.com/openairplay/airplay2-receiver/blob/6c343d3679ddb561c61566985acaaf587d0a3bd3/ap2-receiver.py#L220)) **[impl]**. Doubletake's test receiver only emits `timingPort` at all when the timing protocol is NTP ([receiver_server.go:990-992](https://github.com/omarroth/doubletake/blob/ae067228d76df011375164814b729932ed55ca2f/internal/airplay/receiver_server.go#L990-L992)), and its sender-side test asserts that a PTP control SETUP must **not** contain `timingPort` ([mirror_setup_test.go:146-151](https://github.com/omarroth/doubletake/blob/ae067228d76df011375164814b729932ed55ca2f/internal/airplay/mirror_setup_test.go#L146-L151)) **[impl]**. The write-up at emanuelecozzi.net is quoted as saying the time channel "is used only with NTP synchronization and stays down when using PTP" ([search index quotation, page unreachable](https://emanuelecozzi.net/docs/airplay2/rtsp/)) **[docs, second hand]**.

PTP itself is on UDP 319 for event messages and 320 for general messages. NQPTP's README states it "monitors timing data from PTP clocks it sees on ports 319 and 320" and that it "requires exclusive access to ports 319 and 320" ([nqptp README:2 and 111](https://github.com/mikebrady/nqptp/blob/c925f27c1fd12e4033ac477e5a405969b0b0260b/README.md)) **[docs]**. Its maintainer adds on the issue tracker that "It seems to be a pretty strict requirement that the ports used are 319/320 and that they match" ([nqptp issue 44](https://github.com/mikebrady/nqptp/issues/44)) **[report]**.

**Answer to the question as posed.** `timingPort` is not meaningless in general, because it names the NTP timing port under `timingProtocol: NTP`. Under PTP it carries no information, because PTP is on the fixed ports, and every implementation read here either sends zero or omits it. **[inference from four implementations]**

## 2. `asyncPTPClockConfig: True`

This is new in OS 27. `AsyncPTPClockConfig` appears as an added key in `Domain/AirPlay.plist` in the iOS 26.5 to 27.0 diff, alongside `CombinedGetInfoWithControlSetup`, `CombinedGetInfoWithPairing` and `SkipRecord`, each with `DevelopmentPhase: FeatureComplete` ([AirPlay.plist.md](https://github.com/blacktop/ipsw-diffs/blob/61157ab6a859ee24ae8c2e9a2ba08b9a5f47c991/26_5_23F77_vs_27_0_24A5355q/FEATURES/filesystem/Domain/AirPlay.plist.md)) **[apple]**. None of these four keys existed in iOS 26.5.

It appears in neither Shairport Sync nor the Python receiver. A grep for `asyncPTPClockConfig` across both repositories returns nothing **[impl]**.

### What Apple's receiver does with it

The macOS 27.2 `AirPlayReceiver` framework contains these format strings, in this order in the string table, around `_TimingInit` and `_TimingSetupAsync` **[apple]**:

```
[%{ptr}] PTP clock was not enabled per receiver setting (enablePTPClock: %s)
_TimingInit
[%{ptr}] timingProtocol = %@ | shouldRunTimingSetupAsync = %s
void _TimingSetupAsync(AirPlayReceiverSessionRef, CFDictionaryRef)_block_invoke
[%{ptr}] Processing %@ clock setup asynchronously
[%{ptr}] Failed to set up %@ clock asynchronously in %llu ms (err %#m)
[%{ptr}] %@ clock setup completed asynchronously in %llu ms
[%{ptr}] Failed to send timingPeerInfo over event connection (err %#m)
[%{ptr}] Clock init task completed (err: %#m)
OSStatus _TimingSetup(AirPlayReceiverSessionRef, CFDictionaryRef, CFMutableDictionaryRef)
[%{ptr}] Starting networkClock %@ [%{ptr}]
```

and, a few entries earlier, the function that pushes the result to the sender **[apple]**:

```
OSStatus _SendTimingPeerInfoAsyncIfNeeded(AirPlayReceiverSessionRef)
[%{ptr}] Network Clock not set up
_SendTimingPeerInfoAsyncIfNeeded
updateTimingPeerInfo
[%{ptr}] Sending timingPeerInfo to event connection
OSStatus _SendTimingPeerInfoAsyncIfNeeded(AirPlayReceiverSessionRef)_block_invoke
[%{ptr}] timingPeerInfo%s sent to event connection (err %#m)
```

The literal `asyncPTPClockConfig` sits in the receiver's SETUP request parsing block, next to `timingProtocol`, `isPersistentConnection` and `surviveAudioInterruption`, immediately before the symbol `airplayReqProcessor_finishSetupPlist` **[apple]**. The same symbols are present as additions in the iOS 27.0 diff, including `__SendTimingPeerInfoAsyncIfNeeded` and the strings `"Starting PTP clock"` and `"Start PTP clock failed (err: %#m)"` ([AirPlayReceiver.md](https://github.com/blacktop/ipsw-diffs/blob/61157ab6a859ee24ae8c2e9a2ba08b9a5f47c991/26_5_23F77_vs_27_0_24A5355q/DYLIBS/System/Library/PrivateFrameworks/AirPlayReceiver.framework/AirPlayReceiver.md)) **[apple]**.

Reading those together: when the sender sets `asyncPTPClockConfig`, the receiver sets `shouldRunTimingSetupAsync`, does its clock setup on a background task instead of inside the SETUP response, and when that task completes it sends `updateTimingPeerInfo` over the event connection rather than returning `timingPeerInfo` in the SETUP body. **[inference from Apple strings, high confidence on the shape, no direct evidence of the branch condition]**

Apple's receiver also makes the same call from inside control setup itself. `_ControlSetup` carries `[%{ptr}] Listening to port %d for event connection`, `[%{ptr}] Failed to establish the event connection (err: %#m)`, `[%{ptr}] Failed to send the timingPeerinfo over the event connection (err: %#m)` and `[%{ptr}] Events set up on port %d` **[apple]**. So the event connection is established during control setup and the timing peer info goes out over it at that point.

### What Apple's sender does with it

The macOS 27.2 `AirPlaySender` framework contains, inside the block for `apsession_upgradeSession` **[apple]**:

```
[%{ptr}] Ensuring network clock started.
[%{ptr}] Requesting upgrade control setup.
asyncPTPClockConfig
[%{ptr}] Expecting Timing Peer Info async: %s
timingPeerInfo
[%{ptr}] Received UPGRADE response with timing peer info: %@
```

and, on the event-channel side **[apple]**:

```
OSStatus endpoint_handleTimingPeerInfo(FigEndpointRef, CFDictionaryRef)
[%{ptr}] eventStream didn't provide timingPeerInfo
[%{ptr}] Ignoring timing peer info - no sender session
[%{ptr}] Received senderSession [%{ptr}] timing peer info: %@
```

`updateTimingPeerInfo` appears in the sender's list of event-channel commands it dispatches, alongside `forceKeyFrame`, `setScreenRecordingState`, `updateDisplayInfo`, `sendMediaRemoteCommand`, `updateInfo` and `handleSessionDowngrade`, under `OSStatus endpoint_processCommandCreatingResponse(FigEndpointRef, CFDictionaryRef, CFDictionaryRef *)` **[apple]**. The sender also has `apsession_updatePTPTimingPeerInfoIfNeeded` and `apsession_addPeerToNetworkClock` with `[%{ptr}] Added peer %@ to sender network clock` **[apple]**.

Doubletake, written independently, describes the same mechanism in prose: "AirPlayReceiver sends this as a binary plist containing `{type: "updateTimingPeerInfo", value: <timingPeerInfo>}` after asynchronous PTP setup or a timing-peer change" ([event_channel.go:268-294](https://github.com/omarroth/doubletake/blob/ae067228d76df011375164814b729932ed55ca2f/internal/airplay/event_channel.go#L268-L294)) **[impl]**. Its handler accepts `POST /command` on the event channel with content type `application/x-apple-binary-plist`, reads `type` and `value`, and replies `RTSP/1.0 200 OK`.

### Answer

Yes, `asyncPTPClockConfig: True` changes what the receiver must do. It asks the receiver to defer its clock setup and, once the clock is up, to push its `timingPeerInfo` to the sender over the event channel as a `POST /command` binary plist with `type: "updateTimingPeerInfo"` and `value` holding the peer dictionary. **[inference from Apple strings plus doubletake implementation, two independent sources agreeing]**

Whether the sender *waits* for it, and for how long, is not established. The string `[%{ptr}] Expecting Timing Peer Info async: %s` shows the sender tracks the expectation, and `[%{ptr}] eventStream didn't provide timingPeerInfo` shows it has a code path for the absence, but neither says what it does next, and no timeout constant for this appeared in the extract. The only clock-related timeout name found on the sender side is `networkClockLockTimeoutMs`, which sits inside the buffered audio engine string block next to `startWatermarkPercent` and `burstIntervalSecs`, so it governs playback rather than session setup **[apple, inference]**.

**Relevance to the failing session.** The Python receiver's event channel cannot send this. `EventGeneric.serve` binds a socket, accepts one connection, reads one byte at a time into a debug file until the peer closes, and writes nothing back, ever ([event.py:23-66](https://github.com/openairplay/airplay2-receiver/blob/6c343d3679ddb561c61566985acaaf587d0a3bd3/ap2/connections/event.py#L23-L66)) **[impl]**. A sender that expects `updateTimingPeerInfo` on that channel will never receive it. That makes this the strongest candidate explanation for the eight-second stall, and it is a candidate rather than a finding, because the sender's behaviour on the missing message was not observed. **[inference]**

## 3. `combinedGetInfoWithControlSetup: True`

Also new in OS 27, from the same feature plist diff ([AirPlay.plist.md](https://github.com/blacktop/ipsw-diffs/blob/61157ab6a859ee24ae8c2e9a2ba08b9a5f47c991/26_5_23F77_vs_27_0_24A5355q/FEATURES/filesystem/Domain/AirPlay.plist.md)) **[apple]**.

### What it asks for

Apple's receiver has a function whose name says it plainly, `airplayReqProcessor_appendReceiverInfoIfNeeded`, with the literal `combinedGetInfoWithControlSetup` and the strings `[%{ptr}] Client requested CombinedGetInfoWithControlSetup`, `[%{ptr}] Adding Info to Setup response` and `GetInfo: %@` **[apple]**. Both the sender and the receiver carry the new symbol `_kAPSSetupResponseKey_Info`, and alongside it `_kAPSSetupResponseKey_SkipRecord` with the receiver string `[%{ptr}] Adding SkipRecord` ([AirPlaySender.md](https://github.com/blacktop/ipsw-diffs/blob/61157ab6a859ee24ae8c2e9a2ba08b9a5f47c991/26_5_23F77_vs_27_0_24A5355q/DYLIBS/System/Library/PrivateFrameworks/AirPlaySender.framework/AirPlaySender.md), [AirPlayReceiver.md](https://github.com/blacktop/ipsw-diffs/blob/61157ab6a859ee24ae8c2e9a2ba08b9a5f47c991/26_5_23F77_vs_27_0_24A5355q/DYLIBS/System/Library/PrivateFrameworks/AirPlayReceiver.framework/AirPlayReceiver.md)) **[apple]**.

So the key asks the receiver to fold what a `GET /info` would have returned into the SETUP response under an `Info` key, saving a round trip. Doubletake's test receiver implements exactly that, using the lower-case key `info` ([receiver_server.go:976-980](https://github.com/omarroth/doubletake/blob/ae067228d76df011375164814b729932ed55ca2f/internal/airplay/receiver_server.go#L976-L980)) **[impl]**. The exact spelling of Apple's key is not established, because the constant's *value* is not visible in a string extract, only its symbol name.

### What the sender does when the receiver ignores it

Apple's sender side, in `apsession_requestControlSetupWithResponse` **[apple]**:

```
[%{ptr}] Setup request to %''@: %@
[%{ptr}] Setup response from %''@: %@
[%{ptr}] Info found from Setup response
%?{end}GetInfo: %@
[%{ptr}] Failed to process GetInfo (err: %#m)
[%{ptr}] Receiver responded with SkipRecord. Will skip record command during stage 2.
```

`[%{ptr}] Info found from Setup response` is a conditional log, which implies a branch for "not found". A few entries later comes `apsession_createGetInfoQualifier` with the literals `txtAirPlay` and `displayCapabilities` **[apple]**. Doubletake's sender describes the same fallback in prose: "Control SETUP then requests ordinary receiver info with `combinedGetInfoWithControlSetup` (without a `qualifier`), and a returned `info` dictionary takes precedence over the pre-session snapshot. If it is omitted, doubletake makes one bounded `/info` refresh after the accepted control SETUP" ([README](https://github.com/omarroth/doubletake/blob/ae067228d76df011375164814b729932ed55ca2f/README.md)) **[impl]**.

### Does ignoring it break a macOS sender?

The only public field evidence says no, on iOS. UxPlay does not reference the key anywhere in its source, and the reporter of [UxPlay issue 535](https://github.com/FDH2/UxPlay/issues/535) suspected it was the cause of an iOS 27 mirroring session that negotiated and then never opened its data connection **[report]**. The maintainer answered "combinedGetInfoWithControlSetup is not a known mode" and later, on 2026-08-29, tested an iPadOS 27 beta 5 client against UxPlay and reported "client seems to work fine", posting a SETUP plist that contains `combinedGetInfoWithControlSetup: true` **[report]**. A second reporter on the same issue, with iOS 27.0 beta on an iPhone 15 Pro, also got a working mirror connection and traced the original failure to a codec issue instead **[report]**.

So a receiver that silently ignores `combinedGetInfoWithControlSetup` gets a normal separate `GET /info` instead, which is what the sender's fallback path is for. That is the observed behaviour with iOS 27 clients against UxPlay, and it matches the fallback in doubletake. **[inference from one implementation plus one issue thread, medium confidence, and untested for macOS senders and for audio rather than mirroring]**

This also matches the trace in question. A sender that got no `Info` in the SETUP response making exactly one `GET /info` afterwards is the fallback working, not the fallback failing. **[inference]**

## 4. Must the receiver join the PTP domain before the sender will send the stream-level SETUP?

### Who speaks on the wire

NQPTP is the reference answer here, and its README is blunt about what it is: "`nqptp` uses just a part of the IEEE 1588-2008 protocol. It is not a PTP clock" ([README:154-155](https://github.com/mikebrady/nqptp/blob/c925f27c1fd12e4033ac477e5a405969b0b0260b/README.md)) **[docs]**.

Read as code, it is close to a pure listener. Its receive loop handles exactly three PTP message types, `Announce`, `Follow_Up` and `Sync`, and logs anything else as unusual ([nqptp.c:405-423](https://github.com/mikebrady/nqptp/blob/c925f27c1fd12e4033ac477e5a405969b0b0260b/nqptp.c#L405-L423)) **[impl]**. There is no `Delay_Req` handler and no `Delay_Req` sender, even though the message type is defined in its headers ([nqptp-ptp-definitions.h:81](https://github.com/mikebrady/nqptp/blob/c925f27c1fd12e4033ac477e5a405969b0b0260b/nqptp-ptp-definitions.h#L81)) **[impl]**. The whole daemon contains two `sendto` calls, both inside `send_awakening_announcement_sequence`, which fires only from `broadcasting_task` when a clock has been seen announcing three times without ever sending a `Follow_Up`, and then only once per clock ([nqptp.c:447-578](https://github.com/mikebrady/nqptp/blob/c925f27c1fd12e4033ac477e5a405969b0b0260b/nqptp.c#L447-L578)) **[impl]**. In a healthy session it transmits nothing at all.

The direction is therefore sender to receiver. The Apple device is the grandmaster, sending `Announce`, `Sync` and `Follow_Up` to the receiver's ports 319 and 320, and the receiver derives an offset from them without answering. This is confirmed by the tcpdump in [nqptp issue 44](https://github.com/mikebrady/nqptp/issues/44), which shows a Mac at `192.168.0.1` sending `sync msg` to `192.168.0.186.319` and `follow up msg` to `192.168.0.186.320` **[report]**. Shairport Sync's code agrees: it calls `set_client_as_ptp_clock(conn)`, that is, it nominates the *sender* as the clock ([rtsp.c:2756](https://github.com/mikebrady/shairport-sync/blob/01078ad15d4da06dffba0c5f15ffeaf9146a2a2a/rtsp.c#L2756)) **[impl]**.

OwnTone as a sender does the mirror image, adding the receiver's address from the SETUP reply via `ptpd_slave_add` so its own PTP daemon starts sending to it ([airplay.c:3168](https://github.com/owntone/owntone-server/blob/a038de21065bbbfec721c9c974e3bbd30b22fd59/src/outputs/airplay.c#L3168)) **[impl]**. Apple's sender has the equivalent, `apsession_addPeerToNetworkClock` with `[%{ptr}] Added peer %@ to sender network clock` **[apple]**.

### When PTP is needed

Shairport Sync only tells NQPTP about the peer list at stream setup, not at session setup. In the session SETUP handler the peer-list message is built into a buffer and then deliberately not sent, with the comment `// deferring this until play is about to start` ([rtsp.c:2615-2620](https://github.com/mikebrady/shairport-sync/blob/01078ad15d4da06dffba0c5f15ffeaf9146a2a2a/rtsp.c#L2615-L2620)) **[impl]**. `set_client_as_ptp_clock` and the "clock dependability period is beginning" message are sent from the second SETUP, the one carrying `streams` ([rtsp.c:2756-2758](https://github.com/mikebrady/shairport-sync/blob/01078ad15d4da06dffba0c5f15ffeaf9146a2a2a/rtsp.c#L2756-L2758)) **[impl]**. So a receiver known to work with Apple senders does nothing PTP-related between the session SETUP and the stream SETUP, and the sender proceeds anyway. **[inference from implementation, high confidence]**

What PTP is needed for is playing audio. [nqptp issue 44](https://github.com/mikebrady/nqptp/issues/44) is exactly this case measured end to end: an iPhone's PTP packets were being dropped by a source-port check, "the shared memory is never populated with clock data, and shairport-sync reports 'No NQPTP master clock' and cannot play audio" **[report]**. The session had reached playback. Only the audio was missing.

The Python receiver corroborates from the other direction. It implements no PTP on 319 or 320 at all, taking its timeline from the `TIME_ANNOUNCE_PTP` RTCP packets on the control channel instead ([control.py:44 and 64-83](https://github.com/openairplay/airplay2-receiver/blob/6c343d3679ddb561c61566985acaaf587d0a3bd3/ap2/connections/control.py#L44), [session_properties.py:81-102](https://github.com/openairplay/airplay2-receiver/blob/6c343d3679ddb561c61566985acaaf587d0a3bd3/ap2/connections/session_properties.py#L81-L102)) **[impl]**. Its README lists "Accurate audio sync (with help of PTP and/or NTP)" under what it does not implement and "PTP (Precision Time Protocol)" under next steps, whilst stating that it receives both realtime and buffered AirPlay 2 audio streams ([README](https://github.com/openairplay/airplay2-receiver/blob/6c343d3679ddb561c61566985acaaf587d0a3bd3/README.md)) **[docs]**. An iPhone completing a full session against it, as measured locally, is consistent with that.

### Answer

A receiver that never appears on the PTP domain can still get audio. It gets audio that is not accurately synchronised with other AirPlay 2 devices, which is a different problem. Nothing in any source read here shows a sender withholding the stream-level SETUP because the receiver is silent on 319 and 320, and the strongest evidence against it is that NQPTP, the helper of the receiver that Apple senders demonstrably work with, is silent on those ports too. **[inference across four sources, high confidence]**

One caveat that was not tested and cannot be settled from code. NQPTP *binds* 319 and 320 even though it does not transmit. A host with nothing bound to those ports answers an incoming unicast PTP packet with an ICMP port-unreachable. Whether a macOS sender treats that as a reachability failure is unknown, and it is the one mechanism by which "no PTP at all" could differ from "NQPTP" as seen from the sender. **[inference, untested, flagged as an open question]**

## 5. Evidence that macOS senders are stricter than iOS senders

### What is actually recorded

One measured difference exists and it is not at the SETUP stage. [nqptp issue 44](https://github.com/mikebrady/nqptp/issues/44) reports, with tcpdump output on both sides, that "iPhones (and possibly other Apple devices) send PTP packets from a non-standard source port (e.g. 461) instead of the expected 319/320", whilst "Macs send PTP from standard ports (319→319, 320→320) and work fine" **[report]**. The reporter ran shairport-sync 5.0.2 with nqptp 1.2.6 against an iPhone running `AirPlay/940.23.1`. The issue is open and unreproduced by the maintainer, who noted that the source-port check exists "because other PTP-using programs include it" **[report]**. In this one case iOS was the *looser* side and it was the receiver that was strict.

Beyond that, no source read here records a macOS sender rejecting a session that an iOS sender accepts at the session-level SETUP. Searches of the Shairport Sync and airplay2-receiver issue trackers for macOS-specific connection failures turned up reports that resolved to other causes, such as [shairport-sync 2085](https://github.com/mikebrady/shairport-sync/issues/2085), where "Could not connect" after upgrading a Mac to macOS 26 was investigated by the maintainer against the same OS version without reproducing it **[report]**.

### What the comparison in the failing case actually compares

The iPhone in the local test runs iOS 18.7. `AsyncPTPClockConfig` and `CombinedGetInfoWithControlSetup` were both added between iOS 26.5 and iOS 27.0 ([AirPlay.plist.md](https://github.com/blacktop/ipsw-diffs/blob/61157ab6a859ee24ae8c2e9a2ba08b9a5f47c991/26_5_23F77_vs_27_0_24A5355q/FEATURES/filesystem/Domain/AirPlay.plist.md)) **[apple]**. An iOS 18.7 sender therefore cannot request either of them, and its SETUP will not carry `asyncPTPClockConfig`, `combinedGetInfoWithControlSetup`, `sessionCorrelationUUID` handling of this generation, or `updateSessionRequest`.

So the observed difference is between an OS 27 sender and an OS 18 sender, not between macOS and iOS. Testing the same receiver against an iPhone on iOS 27 would separate the two, and until that is done the platform hypothesis is unsupported. **[inference, and the single most load-bearing caveat in this note]**

## Open questions

These could not be settled from the sources read, and none of them should be filled in with a plausible value.

1. The exact key name Apple uses for the combined info in the SETUP response. Only the symbol `_kAPSSetupResponseKey_Info` is visible; doubletake guesses `info`.
2. Whether Apple's sender requires `timingPeerInfo.ClockID` in the SETUP reply. Shairport Sync omits it and works; doubletake requires it and is not Apple.
3. What Apple's sender does, and for how long, when `updateTimingPeerInfo` never arrives on the event channel after it requested `asyncPTPClockConfig`. The string `[%{ptr}] eventStream didn't provide timingPeerInfo` proves the case is handled, not what the handling is.
4. Whether a host with nothing bound to UDP 319 and 320, and therefore returning ICMP port-unreachable, is treated differently by a sender from a host running NQPTP, which binds them and stays silent.
5. Whether `SkipRecord` in the SETUP response is expected of a modern receiver, or is purely an optimisation the sender takes up when offered. The sender string reads `Receiver responded with SkipRecord. Will skip record command during stage 2.`, which suggests the latter.
6. Whether any of this differs for audio sessions against mirroring sessions. UxPlay issue 535 and doubletake are both about mirroring; Shairport Sync and OwnTone are both about audio.

## Verified facts

Every reference above was checked against the artefact named, on 2026-09-22.

| Reference | How it was checked |
| --- | --- |
| shairport-sync `handle_setup_2` line numbers | full read of `rtsp.c` lines 2380 to 2780 at commit `01078ad` |
| shairport-sync `AIRPLAY2.md` claims | full read of the file at `01078ad` |
| nqptp `sendto` count and message handlers | grep over every `.c` in the repository at `c925f27`, plus full read of `nqptp.c` lines 360 to 588 |
| nqptp README quotations | full read of `README.md` at `c925f27` |
| airplay2-receiver `device_setup` and event channel | read of `ap2-receiver.py` lines 180 to 260 and 1130 to 1190, and full read of `ap2/connections/event.py` at `6c343d3` |
| owntone SETUP request and response handling | read of `src/outputs/airplay.c` lines 3118 to 3268 at `a038de2`, grep for `ptp` over the whole file |
| doubletake clock, event channel and test receiver | read of `internal/airplay/mirror.go` lines 30 to 210, `internal/airplay/event_channel.go` lines 230 to 336, `internal/airplay/receiver_server.go` lines 930 to 1010 at `ae06722` |
| Apple iOS 26.5 to 27.0 additions | downloaded `AirPlay.plist.md`, `AirPlaySender.md` and `AirPlayReceiver.md` from `blacktop/ipsw-diffs` at `61157ab` and read them |
| Apple macOS 27.2 strings | `strings -a -n 8` over `dyld_shared_cache_arm64e.19` and `.38` on this machine, build 26B5086k, cache files dated 2026-09-14 |
| UxPlay issue 535 | full issue body and all comments read via `gh issue view` |
| nqptp issue 44 | full issue body and all comments read via `gh issue view` |
| emanuelecozzi.net | host did not resolve; quoted second hand from a search index and marked as such |
