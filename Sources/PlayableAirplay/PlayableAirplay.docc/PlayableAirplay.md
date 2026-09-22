# ``PlayableAirplay``

Send audio to an AirPlay 2 receiver from macOS and from Linux.

## Overview

Apple's own route picker only moves the whole system's output, and the private entitlements that would let an app pick a receiver for itself are not in the public SDK. This library takes the other road: it speaks RAOP to the receiver directly, so one application streams to a speaker whilst everything else on the machine keeps playing through the built-in output.

Two types carry the whole of it. ``AirPlayDiscovery`` watches the network and reports the receivers it finds. ``AirPlaySession`` pairs with one of them and takes the audio.

```swift
let discovery = AirPlayDiscovery { receivers in
    for receiver in receivers {
        print("\(receiver.name) at \(receiver.host):\(receiver.port)")
    }
}
```

### Why this exists at all

macOS does know how to talk to an AirPlay speaker, and an app can ask the system to move its output there. What it cannot do is move only its own. Connecting a receiver through Control Centre takes the machine's default output with it, so the podcast in one window and the video call in another both follow.

Three ways of asking the public API for less than that were measured and none of them reaches it. `AVRoutePickerView` presents the receivers and changes nothing without a player it owns. The device list CoreAudio reports holds a receiver only once the system has already connected it, which is almost none of them. The entitlements that would open either door are not in the public SDK.

Speaking the protocol is what is left, and it turns out to be the better answer anyway: what this sends is this application's audio and nothing else's, and the machine's own output never moves.

### How the pieces fit together

A receiver announces itself on the network over Bonjour, which is mDNS and DNS-SD under another name. ``AirPlayDiscovery`` browses for the service AirPlay audio receivers advertise and hands back an ``AirPlayReceiver`` for each one it hears from, carrying the host name and port to reach it on.

Opening an ``AirPlaySession`` with one of those takes several round trips. The two sides agree a shared secret, verify each other and settle on a key, and only then does the receiver accept audio. That is why opening blocks, and why it can take a couple of seconds against a speaker that was asleep.

Once it is open the session holds a buffer of a few seconds. Writing into it never waits, because the thread that produces live audio must not be blocked; the sender drains that buffer against its own clock and paces packets onto the network. So a write that is refused is usually the buffer being full rather than anything being wrong, and ``AirPlaySession/WriteOutcome`` says which of the two it is.

### What it carries, and what it does not

The audio goes in as interleaved signed 16 bit stereo at 44100 samples a second, and that is the only thing that goes over the wire. Anything else is converted before it arrives here. There is no resampling in this library, on purpose: the platform's own converter is better at it than a second implementation would be, and on Apple's platforms that is `AVAudioConverter`.

One session reaches one receiver. Two sessions would each start their own timeline against their own clock, so two speakers in the same room drift apart within a minute. Holding them together needs a single timeline shared between them, which is the multi-room work the sender underneath has not done yet.

### Where the threads are

Discovery reports on a thread of its own and hands every change to a queue you name, which defaults to the main one, so a list on screen never updates from the wrong place.

A session runs its sender on a thread of its own as well. ``AirPlaySession/write(_:)-([Int16])`` is meant to be called from whatever thread produces the audio, including an audio callback, and it copies what it needs and returns.

Opening and closing a session are the two calls that wait, so neither belongs on the main queue.

## Topics

### Finding receivers

- ``AirPlayDiscovery``
- ``AirPlayReceiver``

### Playing audio

- ``AirPlaySession``
- ``AirPlaySession/WriteOutcome``

### Failures

- ``AirPlayError``

### Articles

- <doc:Discovering-Receivers>
- <doc:Playing-Audio>

### The protocol

- <doc:AirPlay-2-Protocol>
- <doc:Protocol-Finding-Receivers>
- <doc:Protocol-Pairing>
- <doc:Protocol-Session>
- <doc:Protocol-Timing>
- <doc:Protocol-Audio>
- <doc:Protocol-Control>
- <doc:Protocol-Open-Questions>
- <doc:Protocol-Sources>
