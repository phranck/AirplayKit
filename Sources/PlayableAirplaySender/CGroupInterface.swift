//
//  CGroupInterface.swift
//  The C group interface over the shared Swift sender.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

import Foundation

private final class CGroup {
    let sender: AirPlayGroupSender
    private let callbacks = NSLock()
    private var membershipHandler: (@convention(c) (UnsafeMutableRawPointer?, Int32,
                                                   UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> Void)?
    private var membershipContext: UnsafeMutableRawPointer?
    private var volumeHandler: (@convention(c) (UnsafeMutableRawPointer?,
                                               UnsafePointer<CChar>?, Float) -> Void)?
    private var volumeContext: UnsafeMutableRawPointer?
    private var dissolved = false

    init(_ sender: AirPlayGroupSender) {
        self.sender = sender
        sender.stoppedHandler = { [weak self] reason in
            self?.notifyMembership(4, identifier: nil)
            _ = reason
        }
        sender.observeVolume { [weak self] id, level in
            self?.notifyVolume(id: id, level: level)
        }
        sender.observeMemberLoss { [weak self] id, _ in
            self?.notifyMembership(5, identifier: id)
        }
    }

    func setMembershipHandler(
        _ handler: (@convention(c) (UnsafeMutableRawPointer?, Int32,
                                   UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> Void)?,
        context: UnsafeMutableRawPointer?
    ) {
        callbacks.lock()
        membershipHandler = handler
        membershipContext = context
        callbacks.unlock()
        if handler != nil { notifyMembership(sender.isRunning ? 0 : 4, identifier: nil) }
    }

    func setVolumeHandler(
        _ handler: (@convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?, Float) -> Void)?,
        context: UnsafeMutableRawPointer?
    ) {
        callbacks.lock()
        volumeHandler = handler
        volumeContext = context
        callbacks.unlock()
    }

    func notifyMembership(_ change: Int32, identifier: String?) {
        callbacks.lock()
        let handler = membershipHandler
        let context = membershipContext
        callbacks.unlock()
        guard let handler else { return }
        sender.groupID.withCString { groupID in
            if let identifier {
                identifier.withCString { memberID in
                    handler(context, change, groupID, memberID)
                }
            } else {
                handler(context, change, groupID, nil)
            }
        }
    }

    private func notifyVolume(id: String, level: Float) {
        callbacks.lock()
        let handler = volumeHandler
        let context = volumeContext
        callbacks.unlock()
        guard let handler else { return }
        id.withCString { handler(context, $0, level) }
    }

    func dissolve() {
        callbacks.lock()
        guard !dissolved else { callbacks.unlock(); return }
        dissolved = true
        callbacks.unlock()
        sender.stoppedHandler = nil
        sender.close()
        notifyMembership(3, identifier: nil)
    }
}

private func heldGroup(_ pointer: UnsafeMutableRawPointer?) -> CGroup? {
    guard let pointer else { return nil }
    return Unmanaged<CGroup>.fromOpaque(pointer).takeUnretainedValue()
}

@_cdecl("pa_group_open")
package func pa_group_open(
    _ identifiers: UnsafePointer<UnsafePointer<CChar>?>?,
    _ hosts: UnsafePointer<UnsafePointer<CChar>?>?,
    _ ports: UnsafePointer<UInt16>?,
    _ count: Int,
    _ senderName: UnsafePointer<CChar>?,
    _ result: UnsafeMutablePointer<Int32>?
) -> UnsafeMutableRawPointer? {
    openGroup(identifiers, hosts, ports, count, senderName, nil, result)
}

@_cdecl("pa_group_open_with_volume_memory")
package func pa_group_open_with_volume_memory(
    _ identifiers: UnsafePointer<UnsafePointer<CChar>?>?,
    _ hosts: UnsafePointer<UnsafePointer<CChar>?>?,
    _ ports: UnsafePointer<UInt16>?,
    _ count: Int,
    _ senderName: UnsafePointer<CChar>?,
    _ memory: UnsafeMutableRawPointer?,
    _ result: UnsafeMutablePointer<Int32>?
) -> UnsafeMutableRawPointer? {
    guard memory != nil else {
        result?.pointee = CResult.invalidArgument.rawValue
        return nil
    }
    return openGroup(identifiers, hosts, ports, count, senderName, heldVolumeMemory(memory), result)
}

private func openGroup(
    _ identifiers: UnsafePointer<UnsafePointer<CChar>?>?,
    _ hosts: UnsafePointer<UnsafePointer<CChar>?>?,
    _ ports: UnsafePointer<UInt16>?,
    _ count: Int,
    _ senderName: UnsafePointer<CChar>?,
    _ volumeMemory: ReceiverVolumeMemory?,
    _ result: UnsafeMutablePointer<Int32>?
) -> UnsafeMutableRawPointer? {
    guard let identifiers, let hosts, let ports, (1...32).contains(count) else {
        result?.pointee = CResult.invalidArgument.rawValue
        return nil
    }

    var endpoints: [AirPlayGroupSender.Endpoint] = []
    endpoints.reserveCapacity(count)
    for index in 0..<count {
        guard let identifier = identifiers[index], let host = hosts[index], ports[index] != 0 else {
            result?.pointee = CResult.invalidArgument.rawValue
            return nil
        }
        let id = String(cString: identifier)
        let address = String(cString: host)
        guard !id.isEmpty, !address.isEmpty else {
            result?.pointee = CResult.invalidArgument.rawValue
            return nil
        }
        endpoints.append(.init(id: id, host: address, port: ports[index]))
    }
    guard Set(endpoints.map(\.id)).count == count else {
        result?.pointee = CResult.invalidArgument.rawValue
        return nil
    }

    let name = senderName.map { String(cString: $0) } ?? ""
    do {
        let sender = try AirPlayGroupSender(receivers: endpoints,
                                            senderName: name.isEmpty ? "Playable" : name,
                                            volumeMemory: volumeMemory)
        result?.pointee = CResult.ok.rawValue
        return Unmanaged.passRetained(CGroup(sender)).toOpaque()
    } catch {
        result?.pointee = outcome(for: error).rawValue
        return nil
    }
}

@_cdecl("pa_group_add")
package func pa_group_add(_ pointer: UnsafeMutableRawPointer?,
                          _ identifier: UnsafePointer<CChar>?,
                          _ host: UnsafePointer<CChar>?,
                          _ port: UInt16) -> Int32 {
    guard let group = heldGroup(pointer), let identifier, let host, port != 0 else {
        return CResult.invalidArgument.rawValue
    }
    let id = String(cString: identifier)
    let address = String(cString: host)
    guard !id.isEmpty, !address.isEmpty else { return CResult.invalidArgument.rawValue }
    do {
        try group.sender.add(.init(id: id, host: address, port: port))
        group.notifyMembership(1, identifier: id)
        return CResult.ok.rawValue
    } catch { return outcome(for: error).rawValue }
}

@_cdecl("pa_group_remove")
package func pa_group_remove(_ pointer: UnsafeMutableRawPointer?,
                             _ identifier: UnsafePointer<CChar>?) -> Int32 {
    guard let group = heldGroup(pointer), let identifier else {
        return CResult.invalidArgument.rawValue
    }
    do {
        let id = String(cString: identifier)
        try group.sender.remove(id)
        group.notifyMembership(2, identifier: id)
        return CResult.ok.rawValue
    } catch { return outcome(for: error).rawValue }
}

@_cdecl("pa_group_member_count")
package func pa_group_member_count(_ pointer: UnsafeMutableRawPointer?) -> Int {
    heldGroup(pointer)?.sender.memberIDs.count ?? 0
}

@_cdecl("pa_group_member_id")
package func pa_group_member_id(_ pointer: UnsafeMutableRawPointer?,
                                _ index: Int,
                                _ out: UnsafeMutablePointer<CChar>?,
                                _ capacity: Int) -> Int {
    let ids = heldGroup(pointer)?.sender.memberIDs ?? []
    guard index >= 0, index < ids.count else {
        if let out, capacity > 0 { out.pointee = 0 }
        return 0
    }
    let bytes = Array(ids[index].utf8)
    if let out, capacity > 0 {
        let count = min(bytes.count, capacity - 1)
        for offset in 0..<count { out[offset] = CChar(bitPattern: bytes[offset]) }
        out[count] = 0
    }
    return bytes.count
}

@_cdecl("pa_group_write")
package func pa_group_write(_ pointer: UnsafeMutableRawPointer?,
                            _ frames: UnsafePointer<Int16>?,
                            _ frameCount: Int) -> Bool {
    guard let group = heldGroup(pointer), let frames,
          frameCount > 0, frameCount <= Int.max / ALACFrame.channelCount else { return false }
    let samples = UnsafeBufferPointer(start: frames,
                                      count: frameCount * ALACFrame.channelCount)
    return group.sender.write(samples) == .taken
}

@_cdecl("pa_group_is_running")
package func pa_group_is_running(_ pointer: UnsafeMutableRawPointer?) -> Bool {
    heldGroup(pointer)?.sender.isRunning ?? false
}

@_cdecl("pa_group_held_frames")
package func pa_group_held_frames(_ pointer: UnsafeMutableRawPointer?) -> Int {
    heldGroup(pointer)?.sender.heldFrames ?? 0
}

@_cdecl("pa_group_discard_held_audio")
package func pa_group_discard_held_audio(_ pointer: OpaquePointer?) -> Int {
    guard let pointer else { return 0 }
    return heldGroup(UnsafeMutableRawPointer(pointer))?.sender.discardHeldAudio() ?? 0
}

@_cdecl("pa_group_get_volume")
package func pa_group_get_volume(_ pointer: UnsafeMutableRawPointer?,
                                 _ identifier: UnsafePointer<CChar>?,
                                 _ volume: UnsafeMutablePointer<Float>?) -> Bool {
    guard let group = heldGroup(pointer), let identifier, let volume,
          let level = try? group.sender.volume(of: String(cString: identifier)) else { return false }
    volume.pointee = level
    return true
}

@_cdecl("pa_group_set_volume")
package func pa_group_set_volume(_ pointer: UnsafeMutableRawPointer?,
                                 _ identifier: UnsafePointer<CChar>?,
                                 _ level: Float) -> Int32 {
    guard let group = heldGroup(pointer), let identifier, level.isFinite else {
        return CResult.invalidArgument.rawValue
    }
    do {
        try group.sender.setVolume(level, of: String(cString: identifier))
        return CResult.ok.rawValue
    } catch { return outcome(for: error).rawValue }
}

@_cdecl("pa_group_set_membership_handler")
package func pa_group_set_membership_handler(
    _ pointer: UnsafeMutableRawPointer?,
    _ handler: (@convention(c) (UnsafeMutableRawPointer?, Int32,
                               UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> Void)?,
    _ context: UnsafeMutableRawPointer?
) {
    heldGroup(pointer)?.setMembershipHandler(handler, context: context)
}

@_cdecl("pa_group_set_volume_handler")
package func pa_group_set_volume_handler(
    _ pointer: UnsafeMutableRawPointer?,
    _ handler: (@convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?, Float) -> Void)?,
    _ context: UnsafeMutableRawPointer?
) {
    heldGroup(pointer)?.setVolumeHandler(handler, context: context)
}

@_cdecl("pa_group_set_volume_all")
package func pa_group_set_volume_all(_ pointer: UnsafeMutableRawPointer?,
                                     _ level: Float) -> Int32 {
    guard let group = heldGroup(pointer), level.isFinite else {
        return CResult.invalidArgument.rawValue
    }
    do {
        try group.sender.setVolume(level)
        return CResult.ok.rawValue
    } catch { return outcome(for: error).rawValue }
}

@_cdecl("pa_group_get_average_volume")
package func pa_group_get_average_volume(_ pointer: UnsafeMutableRawPointer?,
                                         _ volume: UnsafeMutablePointer<Float>?) -> Bool {
    guard let level = heldGroup(pointer)?.sender.averageVolume, let volume else { return false }
    volume.pointee = level
    return true
}

@_cdecl("pa_group_set_average_volume")
package func pa_group_set_average_volume(_ pointer: UnsafeMutableRawPointer?,
                                         _ level: Float) -> Int32 {
    guard let group = heldGroup(pointer), level.isFinite else {
        return CResult.invalidArgument.rawValue
    }
    do {
        try group.sender.setAverageVolume(level)
        return CResult.ok.rawValue
    } catch { return outcome(for: error).rawValue }
}

@_cdecl("pa_group_set_event_handler")
package func pa_group_set_event_handler(
    _ pointer: UnsafeMutableRawPointer?,
    _ handler: (@convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?,
                               UnsafePointer<CChar>?, UnsafePointer<CChar>?,
                               UnsafePointer<UInt8>?, Int) -> Void)?,
    _ context: UnsafeMutableRawPointer?
) {
    guard let group = heldGroup(pointer) else { return }
    guard let handler else { group.sender.observeEvents(nil); return }
    group.sender.observeEvents { id, request in
        id.withCString { identifier in
            request.method.withCString { method in
                request.path.withCString { path in
                    request.body.withUnsafeBytes { bytes in
                        handler(context, identifier, method, path,
                                bytes.baseAddress?.assumingMemoryBound(to: UInt8.self), bytes.count)
                    }
                }
            }
        }
    }
}

@_cdecl("pa_group_close")
package func pa_group_close(_ pointer: UnsafeMutableRawPointer?) {
    guard let pointer else { return }
    let group = Unmanaged<CGroup>.fromOpaque(pointer).takeRetainedValue()
    group.sender.stoppedHandler = nil
    group.sender.close()
}

@_cdecl("pa_group_dissolve")
package func pa_group_dissolve(_ pointer: UnsafeMutableRawPointer?) {
    heldGroup(pointer)?.dissolve()
}
