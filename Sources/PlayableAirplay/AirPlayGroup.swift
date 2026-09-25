//
//  AirPlayGroup.swift
//  A public AirPlay 2 group driven by one media timeline.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

import Dispatch
import Foundation
import PlayableAirplaySender

/// Plays one audio source on multiple AirPlay 2 receivers in synchrony.
///
/// Opening the group pairs separately with every receiver. The sender keeps one
/// PTP clock and maps every member's RTP stream to the same media timeline.
/// ``add(_:)`` and ``remove(_:)`` change membership while the stream continues.
/// ``dissolve()`` stops the group and releases its network connections.
public final class AirPlayGroup {
    /// A change in this sender's group membership or lifetime.
    public enum MembershipChange: Sendable {
        /// The group exists with these stable receiver identifiers.
        case created([String])
        /// A receiver joined the running group.
        case joined(String)
        /// A receiver left while other members kept playing.
        case left(String)
        /// A receiver's connection failed while other members kept playing.
        case lost(String, String)
        /// The caller dissolved the group.
        case dissolved
        /// A connection or receiver ended the group unexpectedly.
        case ended(String?)
    }

    private let state = NSLock()
    private var sender: AirPlayGroupSender?
    private let groupIdentifier: String
    private let observers = NSLock()
    private var membershipObserver: (queue: DispatchQueue,
                                     handler: (MembershipChange) -> Void)?
    private var volumeObserver: (queue: DispatchQueue, handler: (String, Float) -> Void)?
    private var changeObserver: (queue: DispatchQueue, handler: (AirPlayEvent) -> Void)?

    /// Opens a group with one or more distinct AirPlay 2 receivers.
    public init(receivers: [AirPlayReceiver], senderName: String,
                volumeMemory: AirPlayVolumeMemory? = nil) throws {
        guard !receivers.isEmpty,
              receivers.allSatisfy({ $0.supportsAirPlay2 && !$0.host.isEmpty && $0.port != 0 }),
              Set(receivers.map(\.id)).count == receivers.count else {
            throw AirPlayError.invalidRequest
        }
        do {
            let active = try AirPlayGroupSender(receivers: receivers.map {
                .init(id: $0.id, host: $0.host, port: $0.port)
            }, senderName: senderName, volumeMemory: volumeMemory?.storage)
            sender = active
            groupIdentifier = active.groupID
            active.stoppedHandler = { [weak self] reason in
                self?.deliver(.ended(reason))
            }
            active.observeVolume { [weak self] id, level in
                self?.deliverVolume(id: id, level: level)
            }
            active.observeMemberLoss { [weak self] id, reason in
                self?.deliver(.lost(id, reason))
            }
        } catch {
            throw Self.publicError(error)
        }
    }

    deinit { dissolve() }

    /// Stable identity of the group created by this sender.
    public var id: String { groupIdentifier }

    /// The stable identifiers of the receivers currently in the group.
    public var memberIDs: [String] { heldSender()?.memberIDs ?? [] }

    /// Whether the group is still carrying audio.
    public var isRunning: Bool { heldSender()?.isRunning ?? false }

    /// How many frames have been accepted but not yet sent.
    public var heldFrames: Int { heldSender()?.heldFrames ?? 0 }

    /// Discards audio not yet sent to group members, such as the end of a replaced programme.
    @discardableResult
    public func discardHeldAudio() -> Int { heldSender()?.discardHeldAudio() ?? 0 }

    /// A transport or receiver failure that ended the group, if one was observed.
    public var endedBecause: String? { heldSender()?.endedBecause }

    /// Adds another AirPlay 2 receiver without restarting existing members.
    public func add(_ receiver: AirPlayReceiver) throws {
        guard receiver.supportsAirPlay2, !receiver.host.isEmpty, receiver.port != 0 else {
            throw AirPlayError.invalidRequest
        }
        guard let sender = heldSender() else { throw AirPlayError.sessionEnded }
        do {
            try sender.add(.init(id: receiver.id, host: receiver.host, port: receiver.port))
            deliver(.joined(receiver.id))
        } catch { throw Self.publicError(error) }
    }

    /// Removes one receiver. Other members keep playing.
    public func remove(_ receiverID: String) throws {
        guard let sender = heldSender() else { throw AirPlayError.sessionEnded }
        do {
            try sender.remove(receiverID)
            deliver(.left(receiverID))
        }
        catch { throw Self.publicError(error) }
    }

    /// Returns the last level read or set for one member, if known.
    public func volume(of receiverID: String) throws -> Float? {
        guard let sender = heldSender() else { throw AirPlayError.sessionEnded }
        do { return try sender.volume(of: receiverID) }
        catch { throw Self.publicError(error) }
    }

    /// Sets one receiver's own volume from 0 to 1.
    public func setVolume(_ level: Float, for receiverID: String) throws {
        guard level.isFinite, let sender = heldSender() else { throw AirPlayError.invalidRequest }
        do { try sender.setVolume(level, of: receiverID) }
        catch { throw Self.publicError(error) }
    }

    /// Sets every current member's own volume from 0 to 1.
    public func setVolume(_ level: Float) throws {
        guard level.isFinite, let sender = heldSender() else { throw AirPlayError.invalidRequest }
        do { try sender.setVolume(level) }
        catch { throw Self.publicError(error) }
    }

    /// The mean of all known member levels, or nil if any member has no level.
    public var averageVolume: Float? { heldSender()?.averageVolume }

    /// Moves the group's mean level while preserving member differences where possible.
    /// All member levels must be known. A member at 0 or 1 may limit its balance.
    public func setAverageVolume(_ level: Float) throws {
        guard level.isFinite, let sender = heldSender() else { throw AirPlayError.invalidRequest }
        do { try sender.setAverageVolume(level) }
        catch { throw Self.publicError(error) }
    }

    /// Delivers receiver-pushed requests with the stable identifier of their source.
    public func observeEvents(deliveringOn queue: DispatchQueue = .main,
                              _ handler: @escaping (String, AirPlaySession.Event) -> Void) {
        heldSender()?.observeEvents { id, request in
            let event = AirPlaySession.Event(request)
            queue.async { handler(id, event) }
        }
    }

    /// Stops delivering receiver-pushed requests.
    public func stopObservingEvents() { heldSender()?.observeEvents(nil) }

    /// Delivers per-receiver volume changes, including changes made elsewhere.
    /// The current level can be read with ``volume(of:)`` before observing.
    public func observeVolume(deliveringOn queue: DispatchQueue = .main,
                              _ handler: @escaping (String, Float) -> Void) {
        observers.lock()
        volumeObserver = (queue, handler)
        observers.unlock()
    }

    /// Stops delivering volume changes.
    public func stopObservingVolume() {
        observers.lock()
        volumeObserver = nil
        observers.unlock()
    }

    /// Delivers typed PlayableAirplay events for this group.
    /// Installation immediately sends `.groupCreated` with current members.
    public func observeChanges(deliveringOn queue: DispatchQueue = .main,
                               _ handler: @escaping (AirPlayEvent) -> Void) {
        observers.lock()
        changeObserver = (queue, handler)
        observers.unlock()
        let groupID = id
        let current = memberIDs
        queue.async { handler(.groupCreated(id: groupID, members: current)) }
    }

    /// Stops delivering typed group changes.
    public func stopObservingChanges() {
        observers.lock()
        changeObserver = nil
        observers.unlock()
    }

    /// Delivers group creation, joins, departures, connection loss, dissolution and unexpected ends.
    /// Installation immediately sends the current membership as `.created`.
    public func observeMembership(deliveringOn queue: DispatchQueue = .main,
                                  _ handler: @escaping (MembershipChange) -> Void) {
        observers.lock()
        membershipObserver = (queue, handler)
        observers.unlock()
        let current = memberIDs
        queue.async { handler(.created(current)) }
    }

    /// Stops delivering group membership changes.
    public func stopObservingMembership() {
        observers.lock()
        membershipObserver = nil
        observers.unlock()
    }

    /// Copies interleaved 16-bit stereo PCM into the group's shared buffer.
    @discardableResult
    public func write(_ frames: [Int16]) -> AirPlaySession.WriteOutcome {
        frames.withUnsafeBufferPointer { write($0) }
    }

    /// Writes directly from an audio callback without an intermediate allocation.
    @discardableResult
    public func write(_ samples: UnsafeBufferPointer<Int16>) -> AirPlaySession.WriteOutcome {
        let wholeCount = samples.count / AirPlaySession.channelCount * AirPlaySession.channelCount
        guard wholeCount > 0 else { return .taken }
        guard let sender = heldSender() else { return .ended }
        switch sender.write(UnsafeBufferPointer(rebasing: samples.prefix(wholeCount))) {
        case .taken: return .taken
        case .bufferFull: return .bufferFull
        case .ended: return .ended
        }
    }

    /// Stops playback for all members and releases the shared PTP clock.
    public func dissolve() {
        state.lock()
        let held = sender
        sender = nil
        state.unlock()
        held?.stoppedHandler = nil
        held?.close()
        if held != nil { deliver(.dissolved) }
    }

    private func heldSender() -> AirPlayGroupSender? {
        state.lock()
        defer { state.unlock() }
        return sender
    }

    private func deliver(_ change: MembershipChange) {
        observers.lock()
        let observer = membershipObserver
        let changes = changeObserver
        observers.unlock()
        observer?.queue.async { observer?.handler(change) }
        let event: AirPlayEvent
        switch change {
        case .created(let members): event = .groupCreated(id: id, members: members)
        case .joined(let receiver): event = .memberJoined(groupID: id, receiverID: receiver)
        case .left(let receiver): event = .memberLeft(groupID: id, receiverID: receiver)
        case .lost(let receiver, let reason):
            event = .memberLost(groupID: id, receiverID: receiver, reason: reason)
        case .dissolved: event = .groupDissolved(id: id)
        case .ended(let reason): event = .groupEnded(id: id, reason: reason)
        }
        changes?.queue.async { changes?.handler(event) }
    }

    private func deliverVolume(id: String, level: Float) {
        observers.lock()
        let volume = volumeObserver
        let changes = changeObserver
        observers.unlock()
        volume?.queue.async { volume?.handler(id, level) }
        changes?.queue.async { changes?.handler(.volumeChanged(id: id, level: level)) }
    }

    private static func publicError(_ error: Error) -> AirPlayError {
        switch SenderFailureKind(error) {
        case .unreachable: return .unreachable
        case .pairingRefused: return .pairingRefused
        case .sessionEnded: return .sessionEnded
        case .invalidRequest: return .invalidRequest
        case .senderFailed: return .senderFailed
        }
    }
}
