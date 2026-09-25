# Observing speaker changes

Use typed ``AirPlayEvent`` values to keep an application's own speaker UI current.

## Discovery

```swift
let discovery = AirPlayDiscovery { receivers in
    // This is the complete current set.
}
discovery.observeChanges { change in
    switch change {
    case .receiverAppeared(let receiver): print(receiver.name, receiver.model)
    case .receiverNameChanged(let id, let name): print(id, name)
    case .receiverDisappeared(let id): print(id)
    default: break
    }
}
```

Discovery sends appearances for the receivers already known when the observer is installed. Later events report advertised name, model and playback-state changes as well as appearances and disappearances. These are Bonjour observations; a receiver that does not publish a change cannot generate one.

## Open playback

```swift
session.observeChanges { change in
    if case .volumeChanged(let id, let level) = change {
        print(id, level)
    }
}

group.observeChanges { change in
    switch change {
    case .groupCreated(let id, let members): print(id, members)
    case .memberJoined(let id, let receiver): print(id, receiver)
    case .memberLeft(let id, let receiver): print(id, receiver)
    case .memberLost(let id, let receiver, let reason): print(id, receiver, reason)
    case .volumeChanged(let id, let level): print(id, level)
    default: break
    }
}
```

An open session or group reads receiver volume over the AirPlay control connection and reports changes on the delivery queue. A physical volume-button test on a Sonos receiver produced rising and falling `volumeChanged` values. Group membership events describe operations made through this ``AirPlayGroup`` instance and report a member connection lost while the others continue. The latter recovery path has not yet been physically disconnected in a device test. The library does not infer another controller's group topology from Bonjour's advertised group ID: on tested Sonos receivers that ID stayed equal to each receiver's own ID during playback as a group.

``AirPlaySession/observeEvents(deliveringOn:_:)`` and ``AirPlayGroup/observeEvents(deliveringOn:_:)`` also expose complete receiver-pushed requests for applications that need to inspect commands the library has not typed. Their bodies may be binary property lists. Observers only receive changes while their discovery, session or group is alive.
