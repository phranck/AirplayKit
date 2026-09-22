//
//  SonosSpeaker.swift
//  What a Sonos will say about itself, asked directly rather than through AirPlay.
//
//  Copyright © 2026 cocoa:naut. All rights reserved.
//

import Foundation

// MARK: - What a speaker is

/// What a speaker says it is, out of its own device description.
///
/// AirPlay gives none of this. A Sonos announces a product label in the `am`
/// field of its service record, such as `One` or `Bookshelf`, and two different
/// products share one word: `Bookshelf` is IKEA's SYMFONISK, and `One` covers
/// both a Sonos One and a Sonos One SL. The description separates them.
public struct SonosDevice: Sendable, Equatable {
    /// The room its owner put it in, such as "Kitchen".
    ///
    /// Several speakers in one room carry the same value, which is the point of
    /// it. This is not a unique name and is not what identifies a speaker.
    public let roomName: String

    /// The short label the service record also carries, such as `One`.
    public let displayName: String

    /// The product, such as `Sonos One` or `SYMFONISK Bookshelf`.
    public let modelName: String

    /// The model code, such as `S18`. Two products can share a `modelName` and never a `modelNumber`.
    public let modelNumber: String

    /// What identifies this speaker to the others, such as `RINCON_38420B60C6CE01400`.
    ///
    /// It is what a zone group names its members by, and what a speaker
    /// following another one names in the address it is playing.
    public let identifier: String

    /// Where the speaker serves a picture of itself, relative to its own address.
    ///
    /// Present on every speaker measured. Fetching it is one plain HTTP request
    /// to the same host and port, and it is the only picture of a speaker that
    /// does not have to be shipped with an application.
    public let iconPath: String?
}

// MARK: - What a speaker is doing

/// What the transport is doing, which is the answer AirPlay's status field withholds.
public enum SonosTransportState: String, Sendable, Equatable {
    case playing = "PLAYING"
    case pausedPlayback = "PAUSED_PLAYBACK"
    case stopped = "STOPPED"
    case transitioning = "TRANSITIONING"
    case noMediaPresent = "NO_MEDIA_PRESENT"

    /// Anything the speaker reported that is not one of the above, kept as it arrived.
    case other

    init(reported: String) {
        self = SonosTransportState(rawValue: reported) ?? .other
    }
}

/// What a speaker is doing at this moment.
public struct SonosPlayback: Sendable, Equatable {
    /// Playing, paused, stopped, or between two of those.
    public let state: SonosTransportState

    /// Its own volume, from 0 to 100.
    ///
    /// This is the speaker's scale. ``SonosVolume`` converts between it and the
    /// one this package's AirPlay sender uses.
    public let volume: Int

    /// Whether it is muted, which is separate from a volume of zero.
    public let isMuted: Bool

    /// The speaker this one is following, or `nil` when it is playing its own audio.
    ///
    /// A speaker in a group does not have its own stream. It plays what the
    /// group's coordinator plays, and says so by naming the coordinator in the
    /// address it reports rather than a track. So a member of a group reports
    /// playing, with nothing of its own to report about what.
    public let followingIdentifier: String?
}

// MARK: - Which speakers play together

/// One group of speakers playing the same thing.
public struct SonosZoneGroup: Sendable, Equatable {
    /// One speaker bonded into another, such as a surround behind a soundbar.
    ///
    /// A satellite is not a member in its own right. It has no AirPlay service,
    /// does not appear in a picker, and cannot be sent to. It exists here so an
    /// application can say that a room holds five speakers rather than one.
    public struct Satellite: Sendable, Equatable {
        /// Its ``SonosDevice/identifier``.
        public let identifier: String

        /// The room it is in, which is its member's room.
        public let roomName: String
    }

    /// One speaker in a group, with whatever is bonded into it.
    public struct Member: Sendable, Equatable {
        /// Its ``SonosDevice/identifier``.
        public let identifier: String

        /// The room it is in, as the topology reports it.
        public let roomName: String

        /// The speakers bonded into this one, which is empty for most speakers.
        ///
        /// A stereo pair and a soundbar with surrounds both appear as one
        /// member with the rest as satellites. Measured: a soundbar reported two,
        /// one for each rear channel, and the member itself held the front pair.
        public let satellites: [Satellite]

        /// Whether other speakers are bonded into this one.
        public var isBonded: Bool { !satellites.isEmpty }
    }

    /// The speaker holding the stream that the others follow.
    public let coordinatorIdentifier: String

    /// Every speaker in the group that appears in its own right, the coordinator among them.
    ///
    /// Satellites are not here. They are inside the member they are bonded to.
    public let members: [Member]

    /// Whether this group joins more than one room's worth of speakers.
    ///
    /// Every speaker is always in a group, so being in one says nothing. What
    /// says something is a group with more than one member, which is somebody
    /// having put two rooms together.
    ///
    /// A soundbar with two surrounds is one member with two satellites, so this
    /// is false for it, which is right: it is one room playing on its own.
    public var joinsSeveralMembers: Bool { members.count > 1 }
}

// MARK: - The two volume scales

/// Converting between a speaker's own volume and the one the AirPlay sender takes.
///
/// The two scales are different and the difference is easy to miss, because
/// both look like a number that goes up. A speaker counts from 0 to 100, and
/// ``AirPlaySession`` in the sibling library takes a fraction from 0 to 1.
///
/// The conversion here is linear between those two, which is what a caller
/// showing one slider for both wants. It is not a conversion between either of
/// them and the decibel value AirPlay carries on the wire, and nothing here
/// claims the two scales sound the same at the same number.
public enum SonosVolume {
    /// A speaker's own volume, from a fraction between 0 and 1.
    public static func fromFraction(_ level: Float) -> Int {
        Int((min(max(level, 0), 1) * 100).rounded())
    }

    /// A fraction between 0 and 1, from a speaker's own volume.
    public static func fraction(from volume: Int) -> Float {
        Float(min(max(volume, 0), 100)) / 100
    }
}

// MARK: - Failures

/// Why a speaker could not be asked, or could not be understood.
public enum SonosError: Error, Sendable, Equatable {
    /// The speaker could not be reached, or did not answer in time.
    case unreachable

    /// It answered with something other than success.
    case refused(status: Int)

    /// It answered, and the answer did not carry what was asked for.
    ///
    /// This is the one that means something changed rather than something
    /// broke, so it names the field that was missing.
    case unexpectedAnswer(missing: String)
}
