# Playing audio

Open a session and keep it fed.

## Overview

``AirPlaySession`` pairs with one receiver and carries audio to it. Opening blocks until the receiver has accepted or refused, which takes a couple of seconds on one that was asleep, so do it off the main queue.

```swift
let session = try AirPlaySession(receiver: receiver, senderName: "My App")
session.volume = 0.7
```

A receiver you already know can be named directly, without browsing for it:

```swift
let session = try AirPlaySession(host: "Sonos-48A6B8F7CA56.local", senderName: "My App")
```

### What opening a session actually does

The two sides have to agree on a key before any audio moves, and neither trusts the network in between. The exchange is the transient form of the pairing Apple uses across its own accessories: a password-authenticated agreement that establishes a shared secret without ever sending it, an elliptic-curve exchange on top of that, and from then on a stream encrypted with the key both sides derived.

None of that is visible here. What it costs is time: several round trips, plus however long the receiver takes to wake up and answer. That is the whole reason ``AirPlaySession/init(receiver:senderName:)`` blocks rather than handing back something that becomes usable later, and why it gives up rather than waiting for ever.

Once the pairing is through, the sender announces the format, the receiver allocates its buffers, and the two agree where the timeline starts. From there the sender paces packets onto the network against its own clock, and the receiver plays them a fixed distance behind.

### The audio it takes

Interleaved, signed 16 bit, two channels, at ``AirPlaySession/sampleRate`` samples a second. Anything else has to be converted before it gets here.

That is not a simplification for the sake of a small interface. The realtime AirPlay stream carries ALAC at that rate, and the sender encodes into it, so audio at any other rate would have to be resampled first. Doing that here would mean a second resampler competing with the one the platform already has, and on Apple's platforms `AVAudioConverter` is both better at it and already in the process.

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

Writing never waits, because the thread producing live audio is one that must not block. Between the caller and the sender sits a buffer holding a few seconds, and the sender drains it in real time. A caller that produces audio faster than real time fills it and is then told so.

So a write that does not take the frames says why, and the two reasons want opposite answers.

``AirPlaySession/WriteOutcome/bufferFull`` means the sender has not worked through what it holds. Where the audio is live, drop those frames and carry on, because a late packet is worse than a missing one and there is nowhere to put them anyway. Where it is read from a file or generated, wait a moment and offer the same frames again, which is what turns the buffer into the thing that paces the read.

``AirPlaySession/WriteOutcome/ended`` means the receiver hung up. Close the session; further writes will say the same thing.

### Volume is the speaker's, not the samples'

``AirPlaySession/volume`` moves the receiver's own control rather than scaling what is sent. Setting it sends a parameter to the receiver, which is why it survives a track change, why the speaker's own display follows it, and why it costs nothing in the audio path.

The range here is 0 to 1 and the protocol's is an attenuation in decibels, so the two are not the same curve. Half way up this control is half way up the receiver's range, which sounds louder than half volume: decibels are how the ear hears, not how a linear fader is spaced. Somebody wanting a fader that sounds linear should shape the value before setting it.

### Finishing

``AirPlaySession/close()`` ends the session, and releasing the session does it anyway. Calling it twice is allowed.

Closing does not wait for what is still in the buffer. A caller that has just written the end of a file and closes at once cuts off however much the sender had not sent yet, so give it that long before closing.

### Feeding it from an audio callback

In a callback the samples usually arrive as a pointer, and there is a `write` that takes one, so nothing is copied on the way in.

```swift
func render(_ samples: UnsafeBufferPointer<Int16>) {
    if session.write(samples) == .ended {
        session.close()
    }
}
```

This is the shape the library was built for. An engine's tap hands over the samples it just played, they go straight in, and the callback returns without having waited for anything.
