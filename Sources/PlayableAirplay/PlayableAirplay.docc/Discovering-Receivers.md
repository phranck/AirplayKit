# Discovering receivers

Find the speakers on the network and keep the list current.

## Overview

``AirPlayDiscovery`` browses for both services an AirPlay receiver advertises and reports one set of receivers. It finds every one of them, whether or not the system has connected it, which is the part Apple's route picker does not do.

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

There are two service types and both are browsed. `_raop._tcp` is the audio one, where RAOP stands for Remote Audio Output Protocol, which is what AirPlay's audio half has been called since it was AirTunes. `_airplay._tcp` is the general one.

Browsing both matters, because a receiver can publish the second and not the first, and macOS offers such a receiver as a sound output. Every shipping device on the network this was written against published both, so the case is shown by an implementation rather than found in the wild, and a browse of one type would still miss it. The second service also carries ``AirPlayReceiver/groupID``, which the first publishes nothing like.

A receiver seen on both is reported once. The two services name it differently, so the join is made on the hardware address: the audio service puts it in front of the display name, and the other publishes it as a field in its record.

On macOS this goes through the system's own responder, which is always running. On Linux it goes through Avahi's Bonjour compatibility library, which speaks the same API to the same standards, and that is why one implementation covers both.

One service failing does not stop the other. Browsing starts when either one starts, so a machine whose responder offers only one type still finds receivers.

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

### Why the list is empty

A network with nothing on it and a machine that will not let this application look produce the same empty list, and they want opposite answers. ``AirPlayDiscovery/problem`` says which it is, and ``AirPlayDiscovery/isBrowsing`` says whether either service got going at all.

```swift
guard discovery.isBrowsing else {
    // Nothing will ever arrive. problem says why.
    return
}
```

The reason is also worth reading on every change rather than once at the start, because a browse can be refused after it has started.

```swift
let discovery = AirPlayDiscovery { [weak self] receivers in
    guard receivers.isEmpty, let problem = self?.discovery?.problem else {
        self?.show(receivers)
        return
    }

    switch problem {
    case .refused, .noResponder: self?.askForLocalNetworkAccess()
    case .failed(let code):      self?.log("browsing failed with \(code)")
    }
}
```

There are three reasons and two of them mean the same thing to a person.

``AirPlayDiscovery/Problem/refused(code:)`` is the responder saying in as many words that this application may not look. Nothing the application does clears it; somebody has to allow it in the system's privacy settings.

``AirPlayDiscovery/Problem/noResponder(code:)`` is no responder this application can reach, and it covers two situations that the responder does not separate. There may be none at all, which is the ordinary Linux case without `avahi-daemon` and the ordinary container case. Or there is one and this application is not allowed to reach it: an application built into a sandbox without network access was measured getting exactly this, with the same error number a machine running nothing gives. On macOS read it as the second, because macOS always runs a responder.

``AirPlayDiscovery/Problem/failed(code:)`` is anything else, and the number is what the responder called it. That belongs in a log rather than on screen.

So the honest reading is that a refusal and an absent responder arrive together, and the platform decides which sentence to put on screen. That is still far better than an empty list with no explanation, which is what an application shows when it cannot ask.

### AirPlay 1 and AirPlay 2

``AirPlayReceiver/supportsAirPlay2`` is true where the receiver announced a pairing key in its service record. That key is what the pairing this library performs is built on, so a receiver without one speaks the older protocol, which used an RSA challenge instead and which this library does not implement.

In practice the distinction rarely bites. On the network this was written against, all nine receivers announced the key and none announced the older scheme.

### What a receiver's name and address are for

``AirPlayReceiver/name`` is what its owner called it, such as "Dining Room", and it is what belongs on screen. ``AirPlayReceiver/host`` is a host name rather than an address, because an address on a home network is a lease and can change between one sighting and the next, whilst the name keeps resolving.

``AirPlayReceiver/id`` is the receiver's hardware address, written the way the audio service writes it. It stays the same across sightings, which is what lets a selection survive a receiver going away and coming back, and it is also what joins a receiver's two service records into one entry.

The two services can disagree about the name. Bonjour settles a clash inside one service by putting a number after the name, and it settles each service separately, so an Apple TV in a room where a speaker already holds the name appears as "Living Room" on one and "Living Room (2)" on the other. The audio service carries what its owner typed, so that is the one reported.

### Which receivers belong together

``AirPlayReceiver/groupID`` is what a receiver says about the group it is in, and it comes from the general service, so it is empty for a receiver found only through the audio one.

What it is worth is honestly limited, and its own documentation says so. On the network this was written against, eight receivers published eight different values whilst none of them was grouped, so what two receivers sharing a value means was never seen.

For a Sonos it is worse than unproven. Three Sonos playing together as one group, measured at that moment, each published a different value, and each was the speaker's own. So the AirPlay field says nothing about which Sonos are playing together, and the answer has to come from the speaker itself, which <doc:Asking-A-Sonos> covers.

### Which speakers are already in use

``AirPlayReceiver/hasSender`` says that somebody holds a session with a receiver, and ``AirPlayReceiver/isPlaying`` says that audio is reaching it right now. The two are separate because a sender that has stopped keeps its session, so a receiver can be held by somebody and silent.

Both come out of the same record the name comes out of, and a receiver rewrites that record as its state changes. So a list learns that a speaker has become busy through an ordinary browse update, without asking anything and without polling.

```swift
let discovery = AirPlayDiscovery { receivers in
    for receiver in receivers {
        let state = receiver.isPlaying ? "playing" : (receiver.hasSender ? "in use" : "free")
        print("\(receiver.name) is \(state)")
    }
}
```

Only Apple's receivers report this. Everything else publishes a value that never moves, so both answers are false for them whatever they are doing. Read a false as a receiver not saying it is busy rather than as one saying it is free, and do not refuse to send to a receiver on the strength of it: taking a speaker from somebody else is allowed, and this is what lets you warn them first.

The bits behind it were measured rather than taken from a table, because the published tables disagree and none of them was checked against a device. <doc:Protocol-Finding-Receivers> carries the four readings they come from.

### What a receiver says it is

``AirPlayReceiver/model`` carries whatever the receiver announced about itself, under `am` on the audio service and `model` on the other, which were measured carrying the same value at the same minute. The useful thing about it is that Apple's receivers announce the identifier their hardware is known by everywhere else. Measured on one network: `AppleTV11,1` for an Apple TV, `AudioAccessory5,1` for a HomePod mini, and `Mac16,11` and `Macmini9,1` for two Macs.

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
