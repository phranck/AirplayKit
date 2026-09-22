# Discovering receivers

Find the speakers on the network and keep the list current.

## Overview

``AirPlayDiscovery`` browses for the `_raop._tcp` service, which is what AirPlay audio receivers advertise. It finds every one of them, whether or not the system has connected it, which is the part Apple's route picker does not do.

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

### What is actually being browsed

Bonjour is Apple's name for two standards used together. mDNS answers "what is at this name" without a DNS server, by asking the local network and letting whoever owns the name reply. DNS-SD answers "who here does this kind of thing", by publishing records under a service type that anybody can browse for.

`_raop._tcp` is the service type for AirPlay audio. RAOP stands for Remote Audio Output Protocol, which is what AirPlay's audio half has been called since it was AirTunes. A receiver publishes an instance under that type, and browsing for the type is how every receiver on the network turns up at once, including the ones nothing is talking to.

On macOS this goes through the system's own responder, which is always running. On Linux it goes through Avahi's Bonjour compatibility library, which speaks the same API to the same standards, and that is why one implementation covers both.

### Why this is not the list of output devices

CoreAudio has a list of output devices, and an AirPlay receiver does appear in it. Measured on one network, connecting a receiver through Control Centre took the device count from four to five and moved the default output to it, and disconnecting took both back.

The catch is the word connected. CoreAudio knows a receiver only once macOS has joined it, and joining it is the thing that moves the whole machine's output. On the same network, browsing found nine receivers whilst CoreAudio knew none of them. So the device list is the right list for a different question.

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

The handler can be called several times in the first second or two as receivers answer one after another, and a receiver that goes quiet drops out of the set a little after it actually went. That is mDNS: there is no central register to ask, only answers that arrive and records that expire.

### When browsing cannot start

Browsing needs an mDNS responder on the machine. macOS always has one. A Linux machine needs `avahi-daemon`, and a container usually has neither, so ``AirPlayDiscovery/isBrowsing`` says whether it got going at all.

```swift
guard discovery.isBrowsing else {
    // No responder. Nothing will ever arrive.
    return
}
```

This is worth checking rather than assuming, because a machine with no responder looks exactly like a network with no speakers.

### AirPlay 1 and AirPlay 2

``AirPlayReceiver/supportsAirPlay2`` is true where the receiver announced a pairing key in its service record. That key is what the pairing this library performs is built on, so a receiver without one speaks the older protocol, which used an RSA challenge instead and which this library does not implement.

In practice the distinction rarely bites. On the network this was written against, all nine receivers announced the key and none announced the older scheme.

### What a receiver's name and address are for

``AirPlayReceiver/name`` is what its owner called it, such as "Dining Room", and it is what belongs on screen. ``AirPlayReceiver/host`` is a host name rather than an address, because an address on a home network is a lease and can change between one sighting and the next, whilst the name keeps resolving.

``AirPlayReceiver/id`` is taken from the part of the service instance name that identifies the hardware. It stays the same across sightings, which is what lets a selection survive a receiver going away and coming back.

### What a receiver says it is

``AirPlayReceiver/model`` carries whatever the receiver announced about itself, and the useful thing about it is that Apple's receivers announce the identifier their hardware is known by everywhere else. Measured on one network: `AppleTV11,1` for an Apple TV, `AudioAccessory5,1` for a HomePod mini, and `Mac16,11` and `Macmini9,1` for two Macs.

That is the code macOS files a picture of the machine under, so a list can draw a receiver as the thing it actually is rather than as a generic speaker.

```swift
import UniformTypeIdentifiers

func picture(of receiver: AirPlayReceiver) -> NSImage? {
    guard let type = UTType(tag: receiver.model,
                            tagClass: UTTagClass(rawValue: "com.apple.device-model-code"),
                            conformingTo: nil),
          type.isDeclared
    else {
        return nil
    }

    return NSWorkspace.shared.icon(for: type)
}
```

Everybody else announces whatever they like, and there is no register to check it against. The Sonos speakers on that same network announced `Arc`, `One` and `Bookshelf`, which are product names rather than model codes, and macOS has never heard of them. So treat this as a hint that is worth using where it is recognised and worth ignoring where it is not. A receiver that announced nothing leaves it empty.
