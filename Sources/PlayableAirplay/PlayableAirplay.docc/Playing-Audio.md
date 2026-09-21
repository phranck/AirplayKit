# Playing audio

Open a session and keep it fed.

## Overview

``AirPlaySession`` pairs with one receiver and carries audio to it. Opening blocks until the receiver has accepted or refused, which takes a couple of seconds on one that was asleep, so do it off the main queue.

```swift
let session = try AirPlaySession(receiver: receiver, senderName: "My App")
session.volume = 0.7
```

``AirPlaySession/volume`` is the receiver's own control rather than a gain on the samples, so it moves the speaker's volume and survives a track change.

A receiver you already know can be named directly, without browsing for it:

```swift
let session = try AirPlaySession(host: "Sonos-48A6B8F7CA56.local", senderName: "My App")
```

### The audio it takes

Interleaved, signed 16 bit, two channels, at ``AirPlaySession/sampleRate`` samples a second. Anything else has to be converted before it gets here.

```swift
switch session.write(frames) {
case .taken:
    break

case .bufferFull:
    break

case .ended:
    session.close()
}
```

### Back pressure is not a failure

Writing never waits, because the thread producing live audio is one that must not block. So a write that does not take the frames says why, and the two reasons want opposite answers.

``AirPlaySession/WriteOutcome/bufferFull`` means the sender has not worked through the four seconds it holds. Where the audio is live, drop those frames and carry on, because a late packet is worse than a missing one. Where it is read from a file or generated, wait a moment and offer the same frames again.

``AirPlaySession/WriteOutcome/ended`` means the receiver hung up. Close the session; further writes will say the same thing.

### Finishing

``AirPlaySession/close()`` ends the session, and releasing the session does it anyway. Calling it twice is allowed.

### Feeding it from an audio callback

In a callback the samples usually arrive as a pointer, and there is a `write` that takes one, so nothing is copied on the way in.

```swift
func render(_ samples: UnsafeBufferPointer<Int16>) {
    if session.write(samples) == .ended {
        session.close()
    }
}
```
