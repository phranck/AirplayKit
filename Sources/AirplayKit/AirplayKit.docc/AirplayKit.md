# ``AirplayKit``

Discover AirPlay 2 receivers and send audio from macOS and Linux.

## Overview

Apple's own route picker only moves the whole system's output, and the private entitlements that would let an app pick a receiver for itself are not in the public SDK. This library takes the other road: it speaks RAOP to the receiver directly, so one application streams to a speaker whilst everything else on the machine keeps playing through the built-in output.

``AirPlayDiscovery`` watches the network and reports ``AirPlayReceiver`` values and typed ``AirPlayEvent`` changes. ``AirPlaySession`` pairs with one receiver. ``AirPlayGroup`` gives multiple receivers one PTP clock and media timeline. ``AirPlayError`` describes failures a caller can handle.

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

Opening an ``AirPlaySession`` with one of those takes several round trips. The sender uses transient pair-setup to agree a shared secret and check the receiver's proof; keys derived from that secret protect the control connection. Only then does the receiver accept audio. That is why opening blocks, and why it can take a couple of seconds against a speaker that was asleep.

Once it is open the session holds a buffer of a few seconds. Writing into it never waits, because the thread that produces live audio must not be blocked; the sender drains that buffer against its own clock and paces packets onto the network. So a write that is refused is usually the buffer being full rather than anything being wrong, and ``AirPlaySession/WriteOutcome`` says which of the two it is.

### What it carries, and what it does not

The audio goes in as interleaved signed 16 bit stereo at 44100 samples a second. The sender encodes those frames as ALAC before transmission. Any other input format is converted before it arrives here. There is no resampling in this library; the macOS Demo uses `AVAudioConverter`, while the Linux WAVE example expects the required PCM format.

One session reaches one receiver. An ``AirPlayGroup`` opens separate receiver sessions under a shared PTP clock and media timeline. Its members can be added and removed while audio continues. A three-receiver Sonos test and a mixed Sonos and HomePod mini test were audible at all members and judged simultaneous by the listener; exact inter-speaker offset has not been measured. The HomePod accepted fresh pairing only while the Home speaker access rule was temporarily opened. See <doc:Managing-Groups>.

### Where the threads are

Discovery reports on a thread of its own and hands every change to a queue you name, which defaults to the main one, so a list on screen never updates from the wrong place.

A session runs its sender on a thread of its own as well. ``AirPlaySession/write(_:)-([Int16])`` is meant to be called from whatever thread produces the audio, including an audio callback, and it copies what it needs and returns.

Opening and closing a session are the two calls that wait, so neither belongs on the main queue.

## Topics

### Articles

- <doc:Discovering-Receivers>
- <doc:Playing-Audio>
- <doc:Managing-Groups>
- <doc:Observing-Changes>
- <doc:What-AirPlay-Does-Not-Say>

- <doc:AirPlay-2-Protocol>
- <doc:Protocol-Finding-Receivers>
- <doc:Protocol-Pairing>
- <doc:Protocol-Session>
- <doc:Protocol-Timing>
- <doc:Protocol-Audio>
- <doc:Protocol-Control>
- <doc:Protocol-Open-Questions>
- <doc:Protocol-Sources>

### AirplayKit API

- ``AirPlayDiscovery``
- ``AirPlayDiscovery/Problem``
- ``AirPlayReceiver``
- ``AirPlayReceiver/Kind``
- ``AirPlaySession``
- ``AirPlaySession/WriteOutcome``
- ``AirPlaySession/Underruns``
- ``AirPlaySession/Event``
- ``AirPlayGroup``
- ``AirPlayGroup/MembershipChange``
- ``AirPlayVolumeMemory``
- ``AirPlayEvent``
- ``AirPlayError``
- <doc:C-API>
