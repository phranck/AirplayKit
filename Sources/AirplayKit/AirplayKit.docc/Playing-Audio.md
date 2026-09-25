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
let session = try AirPlaySession(host: "sonos-2.local", senderName: "My App")
```

### What opening a session actually does

The two sides have to agree on a key before any audio moves. This library uses transient pair-setup: an SRP password-authenticated exchange establishes a shared secret without sending it, and the sender checks the receiver's proof. There is no separate elliptic-curve pair-verify step on this path. The control connection is encrypted with keys derived from that secret. See <doc:Protocol-Pairing>.

None of that is visible here. What it costs is time: several round trips, plus however long the receiver takes to wake up and answer. That is why opening a session blocks rather than handing back something that becomes usable later, and why it gives up rather than waiting for ever.

If the receiver refuses pairing, ``AirPlayError/pairingRefused`` provides an English message that an application can show. It conditionally points HomePod users to **Home Settings > Speakers & TV** in the Home app. A refusal alone does not prove which receiver rule caused it, and AirplayKit does not change that setting.

Once the pairing is through, the sender announces the format, the receiver allocates its buffers, and the two agree where the timeline starts. From there the sender paces packets onto the network against its own clock, and the receiver plays them a fixed distance behind.

### Linux PTP port permission

The sender binds UDP ports 319 and 320 for PTP timing. Ubuntu reserves these ports for privileged processes. Give the final executable `CAP_NET_BIND_SERVICE` after building it, for example:

```bash
sudo setcap cap_net_bind_service=+ep "$(swift build --show-bin-path)/Demo"
```

`setcap` is supplied by `libcap2-bin`. A rebuild may remove the capability, so apply it to the executable that will actually run. The receiver also has to be able to send PTP packets back to the sender; successful pairing over TCP does not verify this return path.

### The audio it takes

Interleaved, signed 16 bit, two channels, at ``AirPlaySession/sampleRate`` samples a second. Anything else has to be converted before it gets here.

The sender encodes ALAC at that rate, so audio at any other rate must be resampled first. On macOS, the Demo uses `AVAudioConverter` for this step. On Linux, the portable WAVE example expects audio in the required format.

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

Opening a session reads the receiver's current level first. The property is `nil` if a complete reply does not contain a usable level; without optional memory, the library does not change the speaker's level while opening. A transport failure still fails the session. Assigning `nil` leaves the level alone.

An application can opt into ``AirPlayVolumeMemory`` and pass it when opening the session. An enabled store restores a level saved for the receiver's stable ID before audio starts, and records confirmed changes during playback. Without a saved level, opening leaves the receiver's level alone. The host-only initializer has no volume store unless one is explicitly supplied with a receiver ID.

The range here is 0 to 1 and the protocol's is an attenuation in decibels, so the two are not the same curve. Half way up this control is half way up the receiver's range, which sounds louder than half volume: decibels are how the ear hears, not how a linear fader is spaced. Somebody wanting a fader that sounds linear should shape the value before setting it.

### Receiver events

The receiver can push requests over the encrypted event connection. Register a handler to receive each complete request after the library has answered it:

```swift
session.observeEvents { event in
    print(event.path, event.commandType as Any)
}
```

``AirPlaySession/Event`` preserves the original body so an application can inspect commands the library does not yet interpret. A command sent before registration cannot be replayed. The callback defaults to the main queue; pass another queue when processing belongs elsewhere. ``AirPlaySession/observeChanges(deliveringOn:_:)`` delivers typed volume changes while the session is open. Discovery separately reports published receiver names, models and flags. AirPlay 2 receivers do not all publish every state change, so an absent event is not proof that a value stayed unchanged. See <doc:Observing-Changes>.

### Finishing

``AirPlaySession/close()`` ends the session, and releasing the session does it anyway. Calling it twice is allowed.

Closing does not wait for what is still in the buffer. A caller that has just written the end of a file and closes at once cuts off however much the sender had not sent yet, so give it that long before closing.

### Feeding it from an audio callback

In a callback the samples usually arrive as a pointer, and there is a `write` that takes one. They are copied once, from where they already are into the session's buffer, and nothing on that path allocates.

```swift
func render(_ samples: UnsafeBufferPointer<Int16>) {
    if session.write(samples) == .ended {
        session.close()
    }
}
```

This is the shape the library was built for. An engine's tap hands over the samples it just played, they go straight in, and the callback returns without having waited for anything.
