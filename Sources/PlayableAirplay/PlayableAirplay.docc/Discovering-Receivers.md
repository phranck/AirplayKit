# Discovering receivers

Find the speakers on the network and keep the list current.

## Overview

``AirPlayDiscovery`` browses for the `_raop._tcp` service, which is what AirPlay audio receivers advertise. It finds every one of them, whether or not something is currently connected to it, which is the part Apple's route picker does not do.

Browsing starts when the instance is created and stops when it is released, so holding on to it is what keeps it running.

```swift
final class SpeakerList {
    private var discovery: AirPlayDiscovery?

    func start() {
        discovery = AirPlayDiscovery { [weak self] receivers in
            self?.show(receivers)
        }
    }

    func stop() {
        discovery = nil
    }

    private func show(_ receivers: [AirPlayReceiver]) {
        // Runs on the main queue, so this may touch the interface.
    }
}
```

### What arrives, and where

The handler is called with the whole set each time it changes, sorted by name, rather than with what moved. Comparing it against what you already had is your business, and most lists want the whole set anyway.

Changes arrive on the main queue unless another one is named:

```swift
let queue = DispatchQueue(label: "at.example.speakers")
let discovery = AirPlayDiscovery(deliveringOn: queue) { receivers in
    // Runs on `queue`.
}
```

``AirPlayDiscovery/receivers`` holds the same set, and it is written on that queue, so read it there.

### When browsing cannot start

Browsing needs an mDNS responder on the machine. macOS always has one. A Linux machine needs Avahi, and a container often has neither, so ``AirPlayDiscovery/isBrowsing`` says whether it got going at all.

```swift
guard discovery.isBrowsing else {
    // No responder. Nothing will ever arrive.
    return
}
```

### AirPlay 1 and AirPlay 2

``AirPlayReceiver/supportsAirPlay2`` is true where the receiver announced a pairing key, which every receiver seen so far has. A receiver without one speaks the older protocol, and this library does not pair with it.
