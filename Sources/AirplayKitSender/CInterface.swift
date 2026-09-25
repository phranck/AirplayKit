//
//  CInterface.swift
//  The C session interface, over the Swift sender.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

import Foundation

/**
 What a caller holds, seen from C.

 A class rather than the sender itself, so the pointer handed out stays valid
 whatever the sender does internally, and so closing can be told apart from
 deallocating.
 */
private final class CSession {
    let sender: AirPlaySender

    init(sender: AirPlaySender) {
        self.sender = sender
    }
}

/// The numbers `PAResult` gives, repeated here because C sees the enumeration and Swift does not.
enum CResult: Int32 {
    case ok = 0
    case unreachable = 1
    case pairingRefused = 2
    case sessionEnded = 3
    case invalidArgument = 4
    case internalFailure = 5
}

/**
 What the receiver shows as the source.

 - Parameter offered: What the caller passed, which from C may be NULL.
 - Returns: That name, or this library's where there is none.

 Something has to stand on the speaker, and the library is what is sending, so
 that is what an unnamed caller is shown as. Here rather than at each entry point
 that needs it, because the session and the group boundary both do and two
 answers to it would part company.
 */
func sourceName(from offered: UnsafePointer<CChar>?) -> String {
    let given = offered.map { String(cString: $0) } ?? ""
    return given.isEmpty ? "AirplayKit" : given
}

/// Which of those an error from the Swift side is. Named apart from the out parameter it fills.
func outcome(for error: Error) -> CResult {
    switch SenderFailureKind(error) {
    case .unreachable: return .unreachable
    case .sessionEnded: return .sessionEnded
    case .pairingRefused: return .pairingRefused
    case .invalidRequest: return .invalidArgument
    case .senderFailed: return .internalFailure
    }
}

@_cdecl("pa_session_open")
package func pa_session_open(_ host: UnsafePointer<CChar>?,
                            _ port: UInt16,
                            _ senderName: UnsafePointer<CChar>?,
                            _ result: UnsafeMutablePointer<Int32>?) -> UnsafeMutableRawPointer? {
    openSession(host, port, senderName, nil, nil, result)
}

@_cdecl("pa_session_open_with_volume_memory")
package func pa_session_open_with_volume_memory(_ identifier: UnsafePointer<CChar>?,
                                                _ host: UnsafePointer<CChar>?,
                                                _ port: UInt16,
                                                _ senderName: UnsafePointer<CChar>?,
                                                _ memory: UnsafeMutableRawPointer?,
                                                _ result: UnsafeMutablePointer<Int32>?) -> UnsafeMutableRawPointer? {
    guard let identifier, !String(cString: identifier).isEmpty, memory != nil else {
        result?.pointee = CResult.invalidArgument.rawValue
        return nil
    }
    return openSession(host, port, senderName, String(cString: identifier),
                       heldVolumeMemory(memory), result)
}

private func openSession(_ host: UnsafePointer<CChar>?,
                         _ port: UInt16,
                         _ senderName: UnsafePointer<CChar>?,
                         _ receiverID: String?,
                         _ volumeMemory: ReceiverVolumeMemory?,
                         _ result: UnsafeMutablePointer<Int32>?) -> UnsafeMutableRawPointer? {
    func report(_ value: CResult) { result?.pointee = value.rawValue }

    guard let host, port != 0 else {
        report(.invalidArgument)
        return nil
    }

    let address = String(cString: host)
    guard !address.isEmpty else {
        report(.invalidArgument)
        return nil
    }

    do {
        let sender = try AirPlaySender(host: address,
                                       port: port,
                                       senderName: sourceName(from: senderName),
                                       receiverID: receiverID, volumeMemory: volumeMemory)
        report(.ok)

        // Handed to C, which now owns it. The matching release is in close.
        return Unmanaged.passRetained(CSession(sender: sender)).toOpaque()
    }
    catch {
        report(outcome(for: error))
        return nil
    }
}

@_cdecl("pa_session_write")
package func pa_session_write(_ session: UnsafeMutableRawPointer?,
                             _ frames: UnsafePointer<Int16>?,
                             _ frameCount: Int) -> Bool {
    guard let session, let frames, frameCount > 0 else { return false }

    let held = Unmanaged<CSession>.fromOpaque(session).takeUnretainedValue()

    // The caller's own memory, handed on as it is. C hands audio over from
    // whatever produced it, which is as likely to be a callback with a deadline
    // as anything in Swift, and an array made here would be a heap allocation
    // on that thread.
    let samples = UnsafeBufferPointer(start: frames, count: frameCount * ALACFrame.channelCount)

    return held.sender.write(samples) == .taken
}

@_cdecl("pa_session_discard_held_audio")
package func pa_session_discard_held_audio(_ session: UnsafeMutableRawPointer?) -> Int {
    guard let session else { return 0 }

    return Unmanaged<CSession>.fromOpaque(session).takeUnretainedValue().sender.discardHeldAudio()
}

@_cdecl("pa_session_held_frames")
package func pa_session_held_frames(_ session: UnsafeMutableRawPointer?) -> Int {
    guard let session else { return 0 }

    return Unmanaged<CSession>.fromOpaque(session).takeUnretainedValue().sender.heldFrames
}

@_cdecl("pa_session_invented_packets")
package func pa_session_invented_packets(_ session: UnsafeMutableRawPointer?) -> Int {
    guard let session else { return 0 }

    return Unmanaged<CSession>.fromOpaque(session).takeUnretainedValue().sender.underruns.packets
}

@_cdecl("pa_session_invented_seconds")
package func pa_session_invented_seconds(_ session: UnsafeMutableRawPointer?) -> Double {
    guard let session else { return 0 }

    return Unmanaged<CSession>.fromOpaque(session).takeUnretainedValue().sender.underruns.duration
}

@_cdecl("pa_session_fell_behind")
package func pa_session_fell_behind(_ session: UnsafeMutableRawPointer?) -> Int {
    guard let session else { return 0 }

    return Unmanaged<CSession>.fromOpaque(session).takeUnretainedValue().sender.underruns.fellBehind
}

@_cdecl("pa_session_waited_seconds")
package func pa_session_waited_seconds(_ session: UnsafeMutableRawPointer?) -> Double {
    guard let session else { return 0 }

    return Unmanaged<CSession>.fromOpaque(session).takeUnretainedValue().sender.underruns.waited
}

@_cdecl("pa_session_is_running")
package func pa_session_is_running(_ session: UnsafeMutableRawPointer?) -> Bool {
    guard let session else { return false }

    return Unmanaged<CSession>.fromOpaque(session).takeUnretainedValue().sender.isRunning
}

@_cdecl("pa_session_set_volume")
package func pa_session_set_volume(_ session: UnsafeMutableRawPointer?, _ volume: Float) {
    guard let session else { return }

    // Swallowed rather than reported, because the C interface has no way to say
    // so and a volume that did not arrive is not worth ending a session over.
    try? Unmanaged<CSession>.fromOpaque(session).takeUnretainedValue().sender.setVolume(volume)
}

@_cdecl("pa_session_get_volume")
package func pa_session_get_volume(_ session: OpaquePointer?,
                                  _ volume: UnsafeMutablePointer<Float>?) -> Bool {
    guard let session, let volume,
          let known = Unmanaged<CSession>.fromOpaque(UnsafeMutableRawPointer(session))
              .takeUnretainedValue().sender.volume
    else { return false }

    volume.pointee = known
    return true
}

@_cdecl("pa_session_set_volume_handler")
package func pa_session_set_volume_handler(
    _ session: OpaquePointer?,
    _ handler: (@convention(c) (UnsafeMutableRawPointer?, Float) -> Void)?,
    _ context: UnsafeMutableRawPointer?
) {
    guard let session else { return }
    let sender = Unmanaged<CSession>.fromOpaque(UnsafeMutableRawPointer(session))
        .takeUnretainedValue().sender
    sender.volumeHandler = handler.map { callback in
        { level in callback(context, level) }
    }
}

@_cdecl("pa_session_set_event_handler")
package func pa_session_set_event_handler(
    _ session: OpaquePointer?,
    _ handler: (@convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?,
                               UnsafePointer<CChar>?, UnsafePointer<UInt8>?, Int) -> Void)?,
    _ context: UnsafeMutableRawPointer?
) {
    guard let session else { return }
    let sender = Unmanaged<CSession>.fromOpaque(UnsafeMutableRawPointer(session))
        .takeUnretainedValue().sender
    guard let handler else {
        sender.eventHandler = nil
        return
    }

    sender.eventHandler = { request in
        request.method.withCString { method in
            request.path.withCString { path in
                request.body.withUnsafeBytes { bytes in
                    handler(context, method, path,
                            bytes.baseAddress?.assumingMemoryBound(to: UInt8.self), bytes.count)
                }
            }
        }
    }
}

/**
 What a session did, laid out as `PASessionReport` in the header.

 The order and the types are the header's, because C reads these by offset. The
 layout is checked against the header by `SessionReportTests`, since a field
 added to one and not the other is read as the wrong bytes rather than reported.
 */
private struct CSessionReport {
    var inventedPackets: Int
    var inventedSeconds: Double
    var waitedSeconds: Double
    var fellBehind: Int
}

@_cdecl("pa_session_close")
package func pa_session_close(_ session: UnsafeMutableRawPointer?,
                             _ report: UnsafeMutableRawPointer?) {
    guard let session else { return }

    let held = Unmanaged<CSession>.fromOpaque(session).takeRetainedValue()
    held.sender.close()

    // Written after closing, so it carries whatever the pump padded whilst it
    // was being waited for, and written here because this is the last moment
    // the figures exist. The pointer C holds is released as this returns, so
    // asking afterwards is a read of memory that has gone, which is why the
    // answer is handed over rather than left to be fetched.
    guard let report else { return }

    let tally = held.sender.underruns
    report.assumingMemoryBound(to: CSessionReport.self).pointee =
        CSessionReport(inventedPackets: tally.packets,
                       inventedSeconds: tally.duration,
                       waitedSeconds: tally.waited,
                       fellBehind: tally.fellBehind)
}

@_cdecl("pa_result_description")
package func pa_result_description(_ value: Int32) -> UnsafePointer<CChar>? {
    // Static storage, because C is handed the pointer and reads it afterwards.
    // One sentence per value, so nothing has to be freed.
    switch CResult(rawValue: value) {
    case .ok: return descriptionOfAccepted
    case .unreachable: return descriptionOfUnreachable
    case .pairingRefused: return descriptionOfRefused
    case .sessionEnded: return descriptionOfEnded
    case .invalidArgument: return descriptionOfUnusable
    case .internalFailure, .none: return descriptionOfFailed
    }
}

private let descriptionOfAccepted = literal("the receiver accepted")
private let descriptionOfUnreachable = literal("the receiver could not be reached")
private let descriptionOfRefused = literal("the receiver refused the pairing. If this is a HomePod, "
                                         + "check Home Settings > Speakers & TV in the Home app.")
private let descriptionOfEnded = literal("the receiver ended the session")
private let descriptionOfUnusable = literal("the caller passed something unusable")
private let descriptionOfFailed = literal("the sender failed for a reason the caller cannot act on")

/// A sentence that outlives the call, since C reads the pointer after returning.
private func literal(_ text: String) -> UnsafePointer<CChar> {
    UnsafePointer(strdup(text)!)
}
