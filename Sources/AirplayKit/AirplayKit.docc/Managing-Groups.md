# Managing speaker groups

Play one PCM source through several AirPlay 2 receivers with a shared timeline.

## Open and feed a group

``AirPlayGroup`` needs one or more distinct receivers reported by discovery as AirPlay 2 capable. Start with one when another receiver may be added later without interrupting playback. Opening pairs with each receiver and waits for the sender's shared PTP clock to settle. Call it away from an audio callback or the main queue.

```swift
let group = try AirPlayGroup(receivers: [office, diningRoom], senderName: "My App")

switch group.write(frames) {
case .taken: break
case .bufferFull: break // Retry later or drop live audio.
case .ended: group.dissolve()
}
```

Frames are interleaved signed 16 bit stereo PCM at 44100 Hz. All members receive the same samples at positions on one media timeline. The group has one bounded input buffer; ``AirPlayGroup/heldFrames`` reports what remains in it.

When changing audio sources, ``AirPlayGroup/discardHeldAudio()`` drops frames still buffered for the old source. Audio already sent to receivers cannot be recalled.

## Change membership

```swift
try group.add(bathroom)
try group.remove(diningRoom.id)
let current = group.memberIDs
group.dissolve()
```

Adding or removing a receiver keeps the remaining members connected and playing. Removing the last member ends the group. A failed member's event connection is retired while the remaining members continue; `.lost` distinguishes that from an explicit `.left`. If peer-list cleanup fails, the group ends and reports the failure. ``AirPlayGroup/observeMembership(deliveringOn:_:)`` reports creation, joins, departures, loss, dissolution and unexpected ends for this sender's group. ``AirPlayGroup/observeChanges(deliveringOn:_:)`` reports the same operations as ``AirPlayEvent`` values. Single-member failure handling still needs a physical disconnection test.

## Control volume

```swift
let officeLevel = try group.volume(of: office.id)
try group.setVolume(0.6, for: office.id)
try group.setVolume(0.5) // Set each current member to the same level.
if let mean = group.averageVolume {
    try group.setAverageVolume(mean + 0.1) // Keep relative levels where possible.
}
```

Both group-wide setters change each receiver's own volume; AirPlay has no separate group volume command. ``AirPlayGroup/setVolume(_:)`` makes all members equal. ``AirPlayGroup/setAverageVolume(_:)`` shifts the group mean and keeps level differences until a receiver reaches 0 or 1. It requires a known level for every current member, which ``AirPlayGroup/averageVolume`` indicates. A network failure partway through either setter can leave some receivers changed. ``AirPlayGroup/observeVolume(deliveringOn:_:)`` reports changed member levels, including changes made at a receiver while the group is connected.

The shared-clock sender was heard on two and three Sonos receivers and on a mixed Sonos and HomePod mini pair in one local network. The listener reported simultaneous playback, but exact inter-speaker delay has not been instrumented. The HomePod test required temporarily changing Home speaker access to "Anyone On the Same Network"; with the original home-members-only rule restored, the HomePod again rejected fresh transient pairing. Authorized pairing under that rule and Linux group playback still need validation. Single-receiver WAVE playback from Ubuntu 26.04 to a Sonos receiver was heard separately.

## Remember a receiver's volume

``AirPlayVolumeMemory`` is optional and starts disabled. The application chooses a file path and retains the object. When enabled, a group records confirmed volume changes by stable receiver ID. On reconnect or group join, it restores a saved level before audio starts. Without a saved level, it leaves the receiver's current level alone. Changes made while a receiver is disconnected may be overwritten when it reconnects.

```swift
let memory = try AirPlayVolumeMemory(fileURL: applicationSupportURL.appendingPathComponent("airplay-volumes.json"))
memory.isEnabled = userPreference
let group = try AirPlayGroup(receivers: [office, diningRoom], senderName: "My App",
                             volumeMemory: memory)
```

Turning memory off stops restores and writes but retains the saved file. A corrupt or unreadable file makes initialization throw without replacing it. Check ``AirPlayVolumeMemory/lastStorageError`` for later write failures. The same object can be passed to ``AirPlaySession``.
