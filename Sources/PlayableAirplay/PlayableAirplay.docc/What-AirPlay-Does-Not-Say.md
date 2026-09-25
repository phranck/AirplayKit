# What AirPlay does not say

The questions a receiver will not answer over AirPlay, and the limits on what this library can report.

## Overview

AirPlay carries audio, the volume of the receiver a sender is talking to, and a service record naming what the thing is. It does not carry the rest of what a speaker knows about itself, and for receivers that are not Apple's it carries less than it appears to.

Measured on one network on 2026-09-24, with five Sonos, a HomePod mini, an Apple TV and two Macs.

## What a Sonos withholds

**Its state.** It advertises the same status value whatever it is doing, so ``AirPlayReceiver/hasSender`` and ``AirPlayReceiver/isPlaying`` are false for it whether it is silent or at full volume. Only Apple's own receivers move those bits. Read them as a receiver saying it is busy, never as one saying it is free.

**Its volume, outside a session.** `GET_PARAMETER` returns the level of the receiver a session is with, and there is no request outside one. A list of speakers therefore cannot show what each is set to without opening a session with each, which is not a thing a list should do.

**What it actually is.** Its model is a product label such as `One` or `Bookshelf`, and two different products arrive under one word: `Bookshelf` is IKEA's SYMFONISK, and `One` covers both a Sonos One and a Sonos One paired into a stereo set.

## What the group field does not mean

``AirPlayReceiver/groupID`` looks as though it says which speakers play together. It does not.

Three Sonos playing together as one group, measured at that moment, each published a different value, and each was the speaker's own. On the same network, eight receivers published eight different values: Apple's devices published something other than their own identifier, and a HomePod mini published two identifiers joined by `+`.

So a shared value is a hint worth checking rather than a fact about what will play together, and for a Sonos it is known not to be one.

## A bonded set is one receiver, not several

Two arrangements look alike from outside and are not. A soundbar with two surrounds is **one** receiver with two speakers bonded into it, playing as one room by itself. Three speakers in three rooms that somebody grouped are **three** receivers.

The satellites publish no AirPlay service of their own and nothing can be sent to them. Only the coordinator of a bonded set advertises `_raop._tcp` at all: of eight speakers on the measured network, five published the service and three were reachable only through the others.

So a list of AirPlay receivers is already a list of things that can be played to, and a bonded set appears in it once, correctly.

## Product descriptions from another standard

With explicit permission for model names, ``AirPlayReceiver/resolveProductName()`` now looks for the receiver's standard UPnP root device description by SSDP and reads its `modelName`. This is a read-only metadata request. It can distinguish a SYMFONISK Bookshelf from the short AirPlay label `Bookshelf` on the tested receiver. Other manufacturers can use the same path if they publish a compatible description; support for every AirPlay receiver has not been established. When no UPnP description is available, it uses AirPlay `/info` and then the published model. It does not hide a short model while waiting.

## Why playback state is not fetched from elsewhere

The other questions can be answered by some manufacturers' own services. A Sonos publishes them on port 1400 over plain HTTP and without authentication, and this package spoke those services until 2026-09-24.

Control through those services was removed deliberately. The UPnP metadata exception above reads a standard device description for its product name only. Playback, volume, grouping and group events still use the AirPlay API rather than manufacturer control services.

What this library does instead is say plainly what it does not know. ``AirPlayReceiver/isFullyDescribed`` is that principle in one property.

## Topics

### Reading a receiver

- ``AirPlayReceiver``
- ``AirPlayReceiver/isFullyDescribed``
- ``AirPlayReceiver/groupID``
