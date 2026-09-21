# PlayableAirplay

Sends audio to an AirPlay 2 receiver from macOS and from Linux, behind one C header.

Apple's own route picker only moves the whole system's output, and the private entitlements that would let an app pick a receiver for itself are not in the public SDK. This library takes the other road: it speaks RAOP to the receiver directly, so one application streams to a speaker whilst everything else on the machine keeps playing through the built-in output.

## What it does

Discovery finds every `_raop._tcp` receiver on the network, whether or not anything is currently connected to it, and says which of them speak AirPlay 2. A session pairs with one of them, takes 16 bit stereo frames at 44100 Hz, and carries the volume.

The interface is C, and that is deliberate. Swift imports it without a bridging layer, the Objective-C side of an existing app calls it as it stands, and nothing about the C++ underneath reaches a caller.

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

The configure step fetches Mbed TLS, so the first build needs a network connection. Everything else is in the repository or in the submodule, and what comes out is `libPlayableAirplay.a` plus `include/PlayableAirplay.h`.

## Using it

Discovery runs in the background and calls back with the full list, sorted by name, each time it changes. That call comes on the library's own thread, and the list it carries lives only for the duration of the call, so copy what you want to keep and hop to your own thread before touching an interface.

```c
#include "PlayableAirplay.h"

static void onReceivers(void *context, const PAReceiver *receivers, size_t count) {
    for (size_t index = 0; index < count; index++) {
        printf("%s at %s:%u\n", receivers[index].name, receivers[index].host, receivers[index].port);
    }
}

PADiscovery *discovery = pa_discovery_start(onReceivers, NULL);
// ...
pa_discovery_stop(discovery);
```

Opening a session pairs with the receiver and blocks until it is playing or has refused, which takes a couple of seconds on a cold receiver. After that, write frames as they arrive:

```c
PAResult result = PAResultOK;
PASession *session = pa_session_open("sonos-2.local", 7000, "My App", &result);
if (!session) {
    fprintf(stderr, "%s\n", pa_result_description(result));
    return 1;
}

pa_session_set_volume(session, 0.7f);

// 16 bit, stereo, interleaved, 44100 Hz.
if (!pa_session_write(session, frames, frameCount)) {
    // The frames were not taken. See below for what that means.
}

pa_session_close(session);
```

`pa_session_write` never waits, because the thread producing live audio must not. A `false` result therefore means one of two things. Either the session has ended, and the next call will say so as well, or the buffer is full because the sender is still working through the four seconds it holds. The second is back pressure rather than a failure, and what to do about it depends on where the audio comes from: a live source drops those frames and carries on, whilst a source reading a file faster than real time waits and offers them again.

## The example

`pa_demo` is the whole interface exercised from a terminal.

```bash
./build/pa_demo list
./build/pa_demo play sonos-2.local 7000 5
```

`list` browses for five seconds and prints what it found. `play` opens a session and sends a quiet 440 Hz tone at a tenth of full volume.

## Tests

```bash
ctest --test-dir build --output-on-failure
```

They cover what can be checked without a receiver on the network: the parsing of a Bonjour instance name into an address and a name, the result descriptions, and what the session and discovery entry points do when they are handed nothing usable. Whether a particular speaker accepts a pairing is not something a test can settle, and `pa_demo` is how that gets answered.

## What it rests on

The RAOP and pairing work is [airplay2-sender-cpp](https://github.com/akustikrausch/airplay2-sender-cpp), built from source as a submodule. `NOTICE` carries its attribution and the licenses of everything it in turn depends on.

## License

This repository has been published under the [MIT](https://layered.mit-license.org) license.
