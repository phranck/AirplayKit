# Asking a Sonos directly

What a Sonos withholds over AirPlay, and where it says the same things instead.

## Overview

A Sonos tells an AirPlay sender almost nothing about itself. It advertises the same status value whatever it is doing, so ``AirPlayReceiver/hasSender`` and ``AirPlayReceiver/isPlaying`` are false for it whether it is silent or at full volume. Its `/info` carries no volume and no state. Its model is a product label such as `One` or `Bookshelf`, and two different products share one word.

It publishes all of it over its own services instead, on port 1400, over plain HTTP and without authentication.

`PlayableAirplayUPnP` is a separate product in this package for exactly that. It does not depend on the AirPlay library and the AirPlay library does not depend on it, because the two answer the same questions by different means and neither needs the other. A caller that wants both takes both.

```swift
import PlayableAirplayUPnP

let speaker = SonosClient(host: "Sonos-38420B60C6CE.local")

let device = try await speaker.device()
print(device.roomName, device.modelName, device.modelNumber)

let playing = try await speaker.playback()
print(playing.state, playing.volume, playing.isMuted)
```

The host is the one an ordinary browse already found. A Sonos publishes its AirPlay service under a name of that shape, and the same host answers on 1400.

**Only Sonos.** That port and those services are theirs. A receiver from anybody else answers nothing there, and the failure looks like a speaker that is switched off.

## What it says about itself

`device()` fetches the speaker's own description. It carries the room its owner put it in, the product and the model code, the identifier the other speakers know it by, and a path to a picture the speaker serves of itself.

The picture is the part worth knowing about. It is one plain request to the same host, so no application has to ship a picture of every model, and a model that did not exist when the application was written still draws correctly.

The description nests the speaker and the two services it offers, repeating the same element names inside each, so what is read is the outermost of them. A reader that took the last of each would describe a service rather than a speaker.

## What it is doing

`playback()` answers the two questions AirPlay withholds, and one more.

The transport state is `PLAYING`, `PAUSED_PLAYBACK`, `STOPPED`, `TRANSITIONING` or `NO_MEDIA_PRESENT`, and anything else a speaker reports is kept rather than refused. The volume is a whole number from 0 to 100, which is the speaker's own scale. The mute is separate from a volume of zero, because they are separate settings.

It also says which speaker this one is following, where it is following one. A speaker in a group has no stream of its own: it plays what the group's coordinator plays and names the coordinator in place of a track. So a member of a group reports playing with nothing of its own to report about what.

## Which speakers play together

`zoneGroups()` answers for the whole network, so it is asked of whichever speaker is to hand rather than of each in turn.

Every speaker is always in a group, so being in one says nothing. What says something is a group with more than one member, which is somebody having put two rooms together, and `joinsSeveralMembers` is that question.

Two things that look alike are not. A soundbar with two surrounds is **one** member with two satellites bonded into it, and it is one room playing by itself. Three speakers in three rooms that somebody grouped are **three** members. Satellites are inside the member they belong to rather than beside it, they publish no AirPlay service of their own, and nothing can be sent to them.

```swift
for group in try await speaker.zoneGroups() {
    let rooms = group.members.map(\.roomName).joined(separator: ", ")
    print(group.joinsSeveralMembers ? "grouped: \(rooms)" : "on its own: \(rooms)")
}
```

### This is the only place the grouping is true

``AirPlayReceiver/groupID`` looks as though it should answer the same question and does not. Measured on one network: three Sonos playing together as one group, at that moment, each published a different AirPlay group identity, and each identity was the speaker's own. So for a Sonos the AirPlay field says nothing about what is playing together, and the topology here says it exactly.

## The two volume scales

A speaker counts from 0 to 100 and ``AirPlaySession/volume`` takes a fraction from 0 to 1. `SonosVolume` converts between them, linearly, which is what one slider showing both wants.

It is not a conversion between either of those and the decibel value AirPlay carries on the wire, and nothing here says the two scales sound the same at the same number.

## What happens when a speaker cannot be asked

`SonosError` has three cases and they divide by what somebody can do. A speaker that cannot be reached is asleep or gone. A speaker that answered with something other than success said no, and the status says how. A speaker that answered without what was asked for has changed in a way this has not caught up with, and that one names the field that was missing, so the next person knows where to look.
