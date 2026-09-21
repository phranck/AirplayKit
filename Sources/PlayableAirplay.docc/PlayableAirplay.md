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

Underneath sits a C module and, below that, a C++ RAOP sender. C is what Swift imports directly on macOS and on Linux alike, with no bridging header and no C++ interoperability, which is why that layer exists. Nothing in it reaches this interface, and nothing anywhere touches AVFoundation, CoreAudio or AppKit.

### One receiver at a time

One session reaches one receiver. Several sessions at once would each start their own RTP timeline against their own clock, so the receivers would drift apart. Holding them together needs a single timeline shared between them, which is the multi-room work the sender underneath has not done yet.

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
