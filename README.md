# PlayableAirplay

Sends audio to an AirPlay 2 receiver from macOS and from Linux, from Swift.

Apple's own route picker only moves the whole system's output, and the private entitlements that would let an app pick a receiver for itself are not in the public SDK. This library takes the other road: it speaks RAOP to the receiver directly, so one application streams to a speaker whilst everything else on the machine keeps playing through the built-in output.

## What it does

Discovery finds every `_raop._tcp` receiver on the network, whether or not anything is currently connected to it, and says which of them speak AirPlay 2. A session pairs with one of them, takes 16 bit stereo frames at 44100 Hz, and carries the volume.

One session reaches one receiver. Several sessions at once would each start their own RTP timeline against their own clock, so the receivers would drift apart, and holding them together needs a single timeline shared between them. That is the multi-room work the sender underneath has not done yet, so this library does not offer it and does not pretend to.

The library itself is C, and that is what makes it portable: Swift imports it as a module on macOS and on Linux alike, with no bridging header and no C++ interoperability. Nothing about the C++ underneath reaches a caller, and nothing in it touches AVFoundation, CoreAudio or AppKit.

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

What comes out is `build/libPlayableAirplay.a` and the `include` directory. That archive holds the sender, the crypto, ed25519 and Mbed TLS as members, so linking it is the whole of it.

```bash
# macOS
swiftc -I include YourFile.swift -Xlinker build/libPlayableAirplay.a -lc++ -framework CoreFoundation

# Linux
swiftc -I include YourFile.swift -Xlinker build/libPlayableAirplay.a -lstdc++ -lpthread -ldns_sd
```

In Xcode, put `include` on the import paths, add the archive to the link phase, and run the two CMake commands above from a build phase so the library is always current.

## Using it

The names and host names arrive in fixed C buffers, which Swift sees as tuples. This turns them back into strings, and every example below uses it:

```swift
import PlayableAirplay

extension PAReceiver {
    var displayName: String { Self.string(from: name, capacity: Int(PA_MAX_NAME)) }
    var hostName: String { Self.string(from: host, capacity: Int(PA_MAX_HOST)) }

    private static func string<Buffer>(from buffer: Buffer, capacity: Int) -> String {
        withUnsafePointer(to: buffer) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { String(cString: $0) }
        }
    }
}
```

Discovery reports the full list, sorted by name, each time it changes. The handler is a C function pointer, so it captures nothing and anything it needs travels through the context argument. It runs on the library's own thread, and the list it carries lives only for the duration of the call, so copy what you want to keep and hop to your own queue before touching an interface.

```swift
let discovery = pa_discovery_start({ _, receivers, count in
    guard let receivers else { return }
    let found = (0..<count).map { receivers[$0] }
    DispatchQueue.main.async { show(found) }
}, nil)

// ...

pa_discovery_stop(discovery)
```

Opening a session pairs with the receiver and blocks until it is playing or has refused, which takes a couple of seconds on a cold receiver. After that, write frames as they arrive:

```swift
var result = PAResultOK
guard let session = pa_session_open(receiver.hostName, receiver.port, "My App", &result) else {
    print(String(cString: pa_result_description(result)))
    return
}

pa_session_set_volume(session, 0.7)

// 16 bit, stereo, interleaved, 44100 Hz.
if !pa_session_write(session, &frames, frameCount) {
    // The frames were not taken. See below for what that means.
}

pa_session_close(session)
```

`pa_session_write` never waits, because the thread producing live audio must not. A `false` result therefore means one of two things. Either the session has ended, and the next call will say so as well, or the buffer is full because the sender is still working through the four seconds it holds. The second is back pressure rather than a failure, and what to do about it depends on where the audio comes from: a live source drops those frames and carries on, whilst a source reading a file faster than real time waits and offers them again.

## The example

`example/Demo.swift` is the whole interface exercised from a terminal.

```bash
swiftc -O -I include example/Demo.swift -o build/Demo \
    -Xlinker build/libPlayableAirplay.a -lc++ -framework CoreFoundation

./build/Demo list
./build/Demo play Sonos-48A6B8F7CA56.local 7000 5
```

`list` browses for five seconds and prints what it found. `play` opens a session and sends a quiet 440 Hz tone at a tenth of full volume.

## Tests

```bash
ctest --test-dir build --output-on-failure
```

They cover what can be checked without a receiver on the network: the parsing of a Bonjour instance name into an address and a name, the result descriptions, and what the session and discovery entry points do when they are handed nothing usable. Whether a particular speaker accepts a pairing is not something a test can settle, and the example is how that gets answered.

## What it rests on

The RAOP and pairing work is [airplay2-sender-cpp](https://github.com/akustikrausch/airplay2-sender-cpp), built from source as a submodule. `NOTICE` carries its attribution and the licenses of everything it in turn depends on.

## License

This repository has been published under the [MIT](https://layered.mit-license.org) license.
