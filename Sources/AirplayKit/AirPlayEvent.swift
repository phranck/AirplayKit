//
//  AirPlayEvent.swift
//  Typed changes for applications that manage their own speaker UI.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

import Foundation

/// A change AirplayKit can establish from discovery or a session it owns.
///
/// A receiver's advertised group identifier is deliberately not interpreted
/// as playback membership. On some receivers it stays equal to the receiver's
/// own identifier while an AirPlay group is playing.
public enum AirPlayEvent: Sendable {
    /// A receiver appeared on the network.
    case receiverAppeared(AirPlayReceiver)
    /// A receiver disappeared from the current discovery set.
    case receiverDisappeared(id: String)
    /// The name its owner assigned changed.
    case receiverNameChanged(id: String, name: String)
    /// The advertised model or manufacturer changed.
    case receiverModelChanged(id: String, model: String, manufacturer: String)
    /// The receiver's advertised sender or playback state changed.
    case receiverStateChanged(id: String, hasSender: Bool, isPlaying: Bool)
    /// A group's receiver reported a different volume over AirPlay.
    case volumeChanged(id: String, level: Float)
    /// This sender created a group with the listed receiver identifiers.
    case groupCreated(id: String, members: [String])
    /// This sender added a receiver to its group.
    case memberJoined(groupID: String, receiverID: String)
    /// This sender removed a receiver from its group.
    case memberLeft(groupID: String, receiverID: String)
    /// One member's connection failed while the group kept playing on the others.
    case memberLost(groupID: String, receiverID: String, reason: String)
    /// This sender dissolved its group.
    case groupDissolved(id: String)
    /// A receiver or connection ended this sender's group.
    case groupEnded(id: String, reason: String?)
}

/// Produces changes from two consecutive complete Bonjour snapshots.
enum ReceiverEventDiff {
    static func changes(from old: [AirPlayReceiver], to new: [AirPlayReceiver]) -> [AirPlayEvent] {
        let previous = Dictionary(uniqueKeysWithValues: old.map { ($0.id, $0) })
        let current = Dictionary(uniqueKeysWithValues: new.map { ($0.id, $0) })
        var changes: [AirPlayEvent] = []

        for receiver in new {
            guard let before = previous[receiver.id] else {
                changes.append(.receiverAppeared(receiver))
                continue
            }
            if before.name != receiver.name {
                changes.append(.receiverNameChanged(id: receiver.id, name: receiver.name))
            }
            if before.model != receiver.model || before.manufacturer != receiver.manufacturer {
                changes.append(.receiverModelChanged(id: receiver.id,
                                                     model: receiver.model,
                                                     manufacturer: receiver.manufacturer))
            }
            if before.hasSender != receiver.hasSender || before.isPlaying != receiver.isPlaying {
                changes.append(.receiverStateChanged(id: receiver.id,
                                                     hasSender: receiver.hasSender,
                                                     isPlaying: receiver.isPlaying))
            }
        }
        for receiver in old where current[receiver.id] == nil {
            changes.append(.receiverDisappeared(id: receiver.id))
        }
        return changes
    }
}
