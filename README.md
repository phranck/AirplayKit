<div align="center">

[![CI](https://img.shields.io/github/actions/workflow/status/phranck/PlayableAirplay/ci.yml?branch=main&style=for-the-badge&label=CI&labelColor=1c1c1c&color=e53935)](https://github.com/phranck/PlayableAirplay/actions/workflows/ci.yml)
[![Last commit](https://img.shields.io/github/last-commit/phranck/PlayableAirplay?style=for-the-badge&label=Commit&labelColor=1c1c1c&color=fb8c00)](https://github.com/phranck/PlayableAirplay/commits/main)
[![Platforms](https://img.shields.io/badge/Platforms-macOS%20%7C%20Linux-fdd835?style=for-the-badge&labelColor=1c1c1c)](https://github.com/phranck/PlayableAirplay/actions/workflows/ci.yml)
[![Language](https://img.shields.io/badge/Written%20in-Swift-43a047?style=for-the-badge&labelColor=1c1c1c)](https://swift.org)
[![Documentation](https://img.shields.io/badge/Reference-DocC-1e88e5?style=for-the-badge&labelColor=1c1c1c)](https://playable-airplay.layered.work/docs/)
[![License](https://img.shields.io/github/license/phranck/PlayableAirplay?style=for-the-badge&label=License&labelColor=1c1c1c&color=8e24aa)](https://layered.mit-license.org)

</div>

# PlayableAirplay

Sends audio to an AirPlay 2 receiver from macOS and from Linux, from Swift.

Apple's own route picker only moves the whole system's output, and the private entitlements that would let an app pick a receiver for itself are not in the public SDK. This library takes the other road: it speaks RAOP to the receiver directly, so one application streams to a speaker whilst everything else on the machine keeps playing through the built-in output.

## What it does

Discovery finds every `_raop._tcp` receiver on the network, whether or not anything is currently connected to it, and says which of them speak AirPlay 2. A session pairs with one of them, takes 16 bit stereo frames at 44100 Hz, and carries the volume.

One session reaches one receiver. Several sessions at once would each start their own RTP timeline against their own clock, so the receivers would drift apart, and holding them together needs a single timeline shared between them. That is the multi-room work the sender underneath has not done yet, so this library does not offer it and does not pretend to.

## Documentation

The site is at [playable-airplay.layered.work](https://playable-airplay.layered.work/), and the reference under [/docs](https://playable-airplay.layered.work/docs/). Both are built from the source by CI on every push to `main`.

To read them locally, run `./Scripts/build-site.sh` and open `build/site`. That script is also what CI runs, so the two cannot drift apart.

## How it is put together

There are two layers, and only the upper one is meant to be called.

`Sources/PlayableAirplay.swift` is the library: `AirPlayDiscovery`, `AirPlaySession`, `AirPlayReceiver` and `AirPlayError`. That is the whole interface.

Underneath it sits a C module, `CPlayableAirplay`, and further down the C++ sender. C is what Swift imports directly on macOS and on Linux alike, with no bridging header and no C++ interoperability, which is why that layer exists at all. Nothing in it reaches the Swift interface: no opaque pointer, no C buffer, no `pa_` function. Nothing anywhere touches AVFoundation, CoreAudio or AppKit.

## Building

```bash
git clone --recurse-submodules https://github.com/phranck/PlayableAirplay.git
cd PlayableAirplay
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j8
```

On Linux, `dns_sd.h` comes from Avahi's compatibility package:

```bash
sudo apt install libavahi-compat-libdnssd-dev
```

The configure step fetches Mbed TLS, so the first build needs a network connection. Everything else is in the repository or in the submodule.

What comes out is `build/libPlayableAirplay.a`, and that archive holds the sender, the crypto, ed25519 and Mbed TLS as members, so linking it is the whole of it.

To use the library, add `Sources/PlayableAirplay.swift` to your own target, put `include` on the import paths, and link the archive:

```bash
# macOS
swiftc -I include Sources/PlayableAirplay.swift YourFile.swift \
    -Xlinker build/libPlayableAirplay.a -lc++ -framework CoreFoundation

# Linux
swiftc -I include Sources/PlayableAirplay.swift YourFile.swift \
    -Xlinker build/libPlayableAirplay.a -lstdc++ -lpthread -ldns_sd
```

In Xcode, add the Swift file to the target, put `include` on the header search paths, add the archive to the link phase, and run the two CMake commands above from a build phase so the library is always current.

## Using it

Discovery reports the whole set each time it changes, sorted by name, on a queue you name. Browsing runs for as long as you hold on to the instance.

```swift
let discovery = AirPlayDiscovery { receivers in
    for receiver in receivers {
        print("\(receiver.name) at \(receiver.host):\(receiver.port)")
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

In an audio callback the samples usually arrive as a pointer already, and there is a `write` for that which copies nothing on the way in.

## The example

`example/Demo.swift` is the whole interface exercised from a terminal.

```bash
swiftc -O -I include Sources/PlayableAirplay.swift example/Demo.swift -o build/Demo \
    -Xlinker build/libPlayableAirplay.a -lc++ -framework CoreFoundation

./build/Demo list
./build/Demo play Sonos-48A6B8F7CA56.local 7000 5
./build/Demo file ~/Music/track.m4a Sonos-48A6B8F7CA56.local
```

`list` browses for five seconds and prints what it found. `play` opens a session and sends a quiet 440 Hz tone. `file` plays an audio file, converting it to what AirPlay carries on the way, and its `stream` function is the complete example the site shows.

## Tests

```bash
ctest --test-dir build --output-on-failure
```

They cover what can be checked without a receiver on the network: the parsing of a Bonjour instance name into an address and a name, the result descriptions, and what the session and discovery entry points do when they are handed nothing usable. Whether a particular speaker accepts a pairing is not something a test can settle, and the example is how that gets answered.

## What it rests on

The RAOP and pairing work is [airplay2-sender-cpp](https://github.com/akustikrausch/airplay2-sender-cpp), built from source as a submodule. `NOTICE` carries its attribution and the licenses of everything it in turn depends on.

## License

This repository has been published under the [MIT](https://layered.mit-license.org) license.
