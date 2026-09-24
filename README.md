<div align="center">

[![CI](https://img.shields.io/github/actions/workflow/status/phranck/PlayableAirplay/ci.yml?branch=main&style=flat&label=CI&labelColor=1c1c1c&color=e53935)](https://github.com/phranck/PlayableAirplay/actions/workflows/ci.yml)
[![Last commit](https://img.shields.io/github/last-commit/phranck/PlayableAirplay?style=flat&label=Commit&labelColor=1c1c1c&color=fb8c00)](https://github.com/phranck/PlayableAirplay/commits/main)
[![Platforms](https://img.shields.io/badge/Platforms-macOS%20%7C%20Linux-fdd835?style=flat&labelColor=1c1c1c)](https://github.com/phranck/PlayableAirplay/actions/workflows/ci.yml)
[![Language](https://img.shields.io/badge/Written%20in-Swift-43a047?style=flat&labelColor=1c1c1c)](https://swift.org)
[![Documentation](https://img.shields.io/badge/Reference-DocC-1e88e5?style=flat&labelColor=1c1c1c)](https://playable-airplay.layered.work/docs/)
[![License](https://img.shields.io/github/license/phranck/PlayableAirplay?style=flat&label=License&labelColor=1c1c1c&color=8e24aa)](https://layered.mit-license.org)

</div>

# PlayableAirplay

Sends audio to an AirPlay 2 receiver from macOS and from Linux, from Swift.

Apple's own route picker only moves the whole system's output, and the private entitlements that would let an app pick a receiver for itself are not in the public SDK. This library takes the other road: it speaks RAOP to the receiver directly, so one application streams to a speaker whilst everything else on the machine keeps playing through the built-in output.

## What it does

Discovery finds every `_raop._tcp` receiver on the network, whether or not anything is currently connected to it, says which of them speak AirPlay 2, reports what each one says it is, and says which of them are already in use. A session pairs with one of them, takes 16 bit stereo frames at 44100 Hz, and carries the volume.

One session reaches one receiver. Several sessions at once would each start their own RTP timeline against their own clock, so the receivers would drift apart, and holding them together needs a single timeline shared between them. That is the multi-room work the sender underneath has not done yet, so this library does not offer it and does not pretend to.

## Documentation

The site is at [playable-airplay.layered.work](https://playable-airplay.layered.work/), and the reference under [/docs](https://playable-airplay.layered.work/docs/). Both are built from the source by CI on every push to `main`.

To read them locally, run `./Scripts/build-site.sh` and serve `build/site`, which the reference needs because it is served from `/docs`. That script is also what CI runs, so the two cannot drift apart.

## How it is put together

All of it is Swift, apart from the discovery, which is C because Bonjour is a C library on both platforms.

`Sources/PlayableAirplay` is the library: `AirPlayDiscovery`, `AirPlaySession`, `AirPlayReceiver` and `AirPlayError`. That is the whole interface, and nothing from underneath reaches it: no opaque pointer, no C buffer, no `pa_` function.

`Sources/PlayableAirplaySender` is the sender itself: the pairing, the encrypted channels, the session and the audio. It takes its cryptography from swift-crypto and its arbitrary-precision arithmetic from BigInt, and implements nothing either of them offers. Nothing anywhere touches AVFoundation, CoreAudio or AppKit.

`CPlayableAirplay` is offered as a product of its own for one case: an Objective-C application, which has no Swift to import the library from. Calling a C header is what Objective-C does with a C library, so it takes `CPlayableAirplay`, imports `PlayableAirplay.h`, and gets the same thing a step lower down. The functions behind that header are Swift, exported with C linkage.

## Using it in a project

### macOS and iOS

Add the package to your project and that is the whole of it. In Xcode that is **File > Add Package Dependencies**, with `https://github.com/phranck/PlayableAirplay.git`, and then `import PlayableAirplay`. Nothing else is fetched at build time and there is nothing to configure.

In a package of your own:

```swift
dependencies: [
    .package(url: "https://github.com/phranck/PlayableAirplay.git", branch: "main"),
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
        print("\(receiver.name) at \(receiver.host):\(receiver.port), a \(receiver.model)")
    }
}

// ...

discovery.stop()
```

Opening a session pairs with the receiver and blocks until it is playing or has refused, which takes a couple of seconds on one that was asleep. After that, write frames as they arrive:

```swift
let session = try AirPlaySession(receiver: receiver, senderName: "My App")
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
    session.close()
}
```

Writing never waits, because the thread producing live audio must not. `.bufferFull` is therefore back pressure rather than a failure, and it says the four seconds the sender holds are not yet spent. `.ended` is the receiver having hung up, and the answer to it is to close the session.

In an audio callback the samples usually arrive as a pointer already, and there is a `write` for that. It copies them once, from where they are into the session's buffer, and allocates nothing on the way.

## The example

`Sources/Demo` is the whole interface exercised from a terminal.

```bash
swift run Demo list
swift run Demo play speaker.local 7000 5
swift run Demo wave ~/Music/track.wav speaker.local
swift run Demo file ~/Music/track.m4a speaker.local
```

`list` browses for five seconds and prints what it found. `play` opens a session and sends a quiet 440 Hz tone. `wave` plays a WAVE file that is already 16 bit stereo at 44100, using nothing but Foundation, so it runs wherever the library does. `file` takes any format the system can read and converts it, which is AVFoundation's work and therefore Apple's platforms only.

## The toolchain

The package is built and tested with Swift 6.2.3, and `.swift-version` is where that version is written down. Both CI runners are pinned to it: the macOS one builds with Xcode 26.3, which [carries that compiler](https://developer.apple.com/documentation/xcode-release-notes/xcode-26_3-release-notes), and the Linux one runs in the `swift:6.2.3` image, which `Scripts/check-linux.sh` builds from as well.

The pin is there because the compilers disagree about what they accept. Swift 6.1.2 aborts on a call into an `@_cdecl` function from a test target that also imports the C header, and later versions compile it without a word, so a gate run on another compiler promises less than it looks like it promises.

A local run means what a CI run means when it uses the same compiler, which is Xcode 26.3 or the toolchain of that version from [swift.org](https://www.swift.org/install/). [swiftly](https://github.com/swiftlang/swiftly) picks it from `.swift-version` without being told. Where the two differ, `Scripts/build-and-test.sh` says which compiler it ran on and which one CI will use.

## Tests

```bash
swift test
```

They cover what can be checked without a receiver on the network: the parsing of a Bonjour instance name into an address and a name, what the session and the discovery do when they are handed nothing usable, and that every failure says what it means. Whether a particular speaker accepts a pairing is not something a test can settle, and the example is how that gets answered.

`Scripts/build-and-test.sh` is the whole gate, and `Scripts/check-linux.sh` compiles the package inside the same Swift image CI uses, so Linux is checked here before anything is pushed. That check compiles rather than tests, because the test process deadlocks inside the container on this machine, which is #25. CI runs the tests on Linux.

## What it rests on

The protocol, which is written down in the reference under `Sources/PlayableAirplay/PlayableAirplay.docc` from published descriptions and from measurements taken here. Every statement there says where it came from and whether it was measured or reported.

The cryptography comes from [swift-crypto](https://github.com/apple/swift-crypto) and the arbitrary-precision arithmetic from [BigInt](https://github.com/attaswift/BigInt). Neither is reimplemented. `NOTICE` carries both licences.

## License

This repository has been published under the [MIT](https://layered.mit-license.org) license.
