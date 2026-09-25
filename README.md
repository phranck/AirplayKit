<div align="center">

[![CI](https://img.shields.io/github/actions/workflow/status/phranck/PlayableAirplay/ci.yml?branch=main&style=flat&label=CI&labelColor=1c1c1c&color=e53935)](https://github.com/phranck/PlayableAirplay/actions/workflows/ci.yml)
[![Last commit](https://img.shields.io/github/last-commit/phranck/PlayableAirplay?style=flat&label=Commit&labelColor=1c1c1c&color=fb8c00)](https://github.com/phranck/PlayableAirplay/commits/main)
[![Platforms](https://img.shields.io/badge/Platforms-macOS%20%7C%20Linux-fdd835?style=flat&labelColor=1c1c1c)](https://github.com/phranck/PlayableAirplay/actions/workflows/ci.yml)
[![Language](https://img.shields.io/badge/Written%20in-Swift-43a047?style=flat&labelColor=1c1c1c)](https://swift.org)
[![Documentation](https://img.shields.io/badge/Reference-DocC-1e88e5?style=flat&labelColor=1c1c1c)](https://playable-airplay.layered.work/docs/)
[![License](https://img.shields.io/github/license/phranck/PlayableAirplay?style=flat&label=License&labelColor=1c1c1c&color=8e24aa)](https://layered.mit-license.org)

</div>

# PlayableAirplay

Targets AirPlay 2 audio output from macOS and Linux through Swift. Playback against receivers is recorded for macOS. Linux builds in CI; receiver playback on Linux has not yet been recorded.

Apple's own route picker only moves the whole system's output, and the private entitlements that would let an app pick a receiver for itself are not in the public SDK. This library takes the other road: it speaks RAOP to the receiver directly, so one application streams to a speaker whilst everything else on the machine keeps playing through the built-in output.

## What it does

Discovery browses `_raop._tcp` and `_airplay._tcp` without moving the system output, reports the receivers it sees, says which of them speak AirPlay 2, and carries each published name and model. The `model` field is the advertised value and may be abbreviated, such as `Bookshelf`. For a speaker list, `productName` formats the published fields and `await receiver.resolveProductName()` can read a fuller name from a standard device description. Apple's receivers also publish whether they are in use; other receivers may not update those flags. A session pairs with one receiver, takes 16 bit stereo frames at 44100 Hz, reads its current volume where the receiver reports one, and can change that volume. Receiver-pushed requests are available through Swift and C event callbacks.

One session reaches one receiver. `AirPlayGroup` can start with one receiver and add others under one PTP clock and media timeline. It can add or remove receivers while audio continues, dissolve the group, and set individual or all member volumes. Two and three Sonos receivers played together in local tests. A mixed Sonos and HomePod mini group also played for 30 seconds after Home speaker access was temporarily set to "Anyone On the Same Network". The listener reported simultaneous playback in each test; exact inter-speaker offset has not been measured. Under the restored "Only People Sharing This Home" rule, the HomePod refused this library's fresh transient pairing. Authorized pairing under that rule is not yet supported. Typed `AirPlayEvent` callbacks report discovery changes, volume changes during an open connection, and membership changes made through this sender. Other controllers' group topology is not reliably observable from the tested Bonjour records.

Per-receiver volume memory is opt-in. An application supplies its own storage path to `AirPlayVolumeMemory` (Swift) or `pa_volume_memory_open` (C), enables the feature, and passes that object to a session or group. Confirmed levels are stored by stable receiver ID and restored before playback on reconnect or group join. Turning the feature off keeps the saved file but stops restores and writes. Changes made while a speaker is disconnected may be overwritten on reconnect.

## Documentation

The site is at [playable-airplay.layered.work](https://playable-airplay.layered.work/), and the reference under [/docs](https://playable-airplay.layered.work/docs/). Both are built from the source by CI on every push to `main`.

To read them locally, run `./Scripts/build-site.sh` and serve `build/site`, which the reference needs because it is served from `/docs`. CI uses the same script to build both from one commit. The file-streaming snippets on the home page come from the compiled Demo; the other page text and examples are maintained separately and must still be checked against the API.

## How it is put together

The sender, public Swift interface and device metadata are Swift. Bonjour discovery and its name and state parsing are C, using the same DNS-SD interface on both platforms.

`Sources/PlayableAirplay` is the Swift library: `AirPlayDiscovery`, `AirPlayReceiver`, `AirPlaySession`, `AirPlayGroup`, `AirPlayEvent` and `AirPlayError`. Protocol types remain underneath; no opaque pointer, C buffer or `pa_` function reaches this interface.

`Sources/PlayableAirplaySender` is the sender itself: the pairing, the encrypted channels, the session and the audio. It takes its cryptography from swift-crypto and its arbitrary-precision arithmetic from BigInt, and implements nothing either of them offers. The library does not depend on AVFoundation, CoreAudio or AppKit. The macOS Demo uses AVFoundation to convert file formats before handing PCM to the library.

`CPlayableAirplay` is offered as a product of its own for one case: an Objective-C application, which has no Swift to import the library from. Calling a C header is what Objective-C does with a C library, so it takes `CPlayableAirplay`, imports `PlayableAirplay.h`, and gets the same thing a step lower down. The discovery entry points are implemented in C; session, group and device-naming entry points are implemented in Swift and exported with C linkage.

## Using it in a project

### macOS

Add the package to your project. In Xcode that is **File > Add Package Dependencies**, with `https://github.com/phranck/PlayableAirplay.git`, and then `import PlayableAirplay`. Swift Package Manager resolves swift-crypto and BigInt automatically.

In a package of your own:

```swift
dependencies: [
    .package(url: "https://github.com/phranck/PlayableAirplay.git", exact: "0.1.0"),
],
targets: [
    .target(name: "YourTarget", dependencies: ["PlayableAirplay"]),
]
```

### Linux

The same dependency line, and one system package first, because Bonjour on Linux is Avahi's compatibility library:

```bash
sudo apt install libavahi-compat-libdnssd-dev
```

Then `swift build` as usual. Browsing needs `avahi-daemon` running at the time, which is a runtime matter rather than a build one.

### What comes with it

Two Swift packages, swift-crypto and BigInt, which the package manager fetches. Nothing is vendored and nothing is built from a checkout beside the sources, so a change to one file rebuilds one file.

## Writing against it

Discovery reports the whole set each time it changes, sorted by name, on a queue you name. Browsing runs for as long as you hold on to the instance.

```swift
let discovery = AirPlayDiscovery { receivers in
    for receiver in receivers {
        print("\(receiver.name) at \(receiver.host):\(receiver.port): \(receiver.productName)")
    }
}

// ...

discovery.stop()
```

Opening a session pairs with the receiver and blocks until it is ready for audio or has refused, which takes a couple of seconds on one that was asleep. After that, write frames as they arrive:

```swift
let session = try AirPlaySession(receiver: receiver, senderName: "My App")
print(session.volume as Any) // nil if the receiver did not report a usable level.
session.volume = 0.7

// 16 bit, stereo, interleaved, 44100 Hz.
switch session.write(frames) {
case .taken:
    break

case .bufferFull:
    // The sender has not caught up. A live source drops these frames and
    // carries on; one that can pause offers them again.
    break

case .ended:
    // Schedule session.close() outside the audio callback.
    break
}
```

Writing never waits, because the thread producing live audio must not. `.bufferFull` is therefore back pressure rather than a failure, and it says the four seconds the sender holds are not yet spent. `.ended` is the receiver having hung up, and the answer to it is to close the session.

Call `session.observeEvents { event in ... }` to receive requests pushed by the receiver, including binary property list commands. `session.observeChanges` reports typed volume changes while connected, and `discovery.observeChanges` reports advertised device changes. A group has `observeChanges`, `observeMembership` and `observeVolume` for its own members. Reading a speaker's volume currently requires an open session or group membership.

```swift
let group = try AirPlayGroup(receivers: [office, diningRoom], senderName: "My App")
group.observeChanges { event in print(event) }
try group.add(bathroom)
try group.setVolume(0.6, for: office.id)
try group.setVolume(0.5) // Every current member.
try group.remove(diningRoom.id)
group.dissolve()
```

Write the same 16 bit stereo frames to `group.write` that a single session accepts. `setVolume(_:)` sets every member to the same level. `averageVolume` and `setAverageVolume(_:)` provide a group fader that preserves differences while members remain inside their 0 to 1 range. The latter requires a known level for every member.

In an audio callback the samples usually arrive as a pointer already, and there is a `write` for that. It copies them once, from where they are into the session's buffer, and allocates nothing on the way.

## The example

`Sources/Demo` is the whole interface exercised from a terminal.

```bash
swift run Demo list
swift run Demo play speaker.local 7000 5
swift run Demo wave ~/Music/track.wav speaker.local
swift run Demo file ~/Music/track.m4a speaker.local # macOS only
```

`list` browses for five seconds and prints what it found. `play` opens a session and sends a quiet 440 Hz tone. `wave` plays a WAVE file that is already 16 bit stereo at 44100, using nothing but Foundation, so it runs wherever the library does. `file` takes any format macOS can read and converts it with AVFoundation.

## The toolchain

The package is built and tested with Swift 6.2.4, and `.swift-version` is where that version is written down. Both CI runners are pinned to it: the macOS one builds with Xcode 26.3, whose compiler reports 6.2.4 on that runner, and the Linux one runs in the `swift:6.2.4` image, which `Scripts/check-linux.sh` builds from as well.

The pin is there because compilers disagree about what they accept. In a Swift test target that imports the C header, a direct call into a Swift `@_cdecl` group function made Linux Swift 6.2.4 abort while linking SIL: the header declared an opaque pointer where the Swift export used a raw pointer. That test was removed; the C and Objective-C boundary is checked through the caller build. A gate run on another compiler can therefore promise less than it looks like it promises.

A local run means what a CI run means when it uses the same compiler, which is the toolchain of that version from [swift.org](https://www.swift.org/install/) or an Xcode carrying it. [swiftly](https://github.com/swiftlang/swiftly) picks it from `.swift-version` without being told. Where the two differ, `Scripts/build-and-test.sh` says which compiler it ran on and which one CI will use.

## Tests

```bash
swift test
```

They cover discovery parsing and state, protocol messages, cryptography, audio buffering and loopback control exchanges, including reading a receiver's volume. Whether a particular speaker accepts pairing and plays audio requires a device test.

`Scripts/build-and-test.sh` is the whole gate, and `Scripts/check-linux.sh` compiles the package inside the same Swift image CI uses, so Linux is checked here before anything is pushed. That check compiles rather than tests, because the test process deadlocks inside the container on this machine, which is #25. CI runs the tests on Linux.

`Scripts/check-callers.sh` builds the known Objective-C caller when its checkout is available. A local package reference checks this working tree; Podlive's tagged SPM reference checks the released package instead. The script states which one it tested. It cannot run in CI because that runner has no Podlive checkout.

## What it rests on

The protocol, which is written down in the reference under `Sources/PlayableAirplay/PlayableAirplay.docc` from published descriptions and from measurements taken here. Every statement there says where it came from and whether it was measured or reported.

The cryptography comes from [swift-crypto](https://github.com/apple/swift-crypto) and the arbitrary-precision arithmetic from [BigInt](https://github.com/attaswift/BigInt). Neither is reimplemented. `NOTICE` carries both licences.

## License

This repository has been published under the [MIT](https://layered.mit-license.org) license.
