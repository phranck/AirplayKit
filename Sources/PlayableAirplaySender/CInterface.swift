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
private enum CResult: Int32 {
    case ok = 0
    case unreachable = 1
    case pairingRefused = 2
    case sessionEnded = 3
    case invalidArgument = 4
    case internalFailure = 5
}

/// Which of those an error from the Swift side is. Named apart from the out parameter it fills.
private func outcome(for error: Error) -> CResult {
    switch SenderFailureKind(error) {
    case .unreachable: return .unreachable
    case .sessionEnded: return .sessionEnded
    case .pairingRefused: return .pairingRefused
    case .invalidRequest: return .invalidArgument
    case .senderFailed: return .internalFailure
    }
}

@_cdecl("pa_session_open")
public func pa_session_open(_ host: UnsafePointer<CChar>?,
                            _ port: UInt16,
                            _ senderName: UnsafePointer<CChar>?,
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

    let name = senderName.map { String(cString: $0) } ?? ""

    do {
        let sender = try AirPlaySender(host: address,
                                       port: port,
                                       senderName: name.isEmpty ? "Playable" : name)
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
public func pa_session_write(_ session: UnsafeMutableRawPointer?,
                             _ frames: UnsafePointer<Int16>?,
                             _ frameCount: Int) -> Bool {
    guard let session, let frames, frameCount > 0 else { return false }

    let held = Unmanaged<CSession>.fromOpaque(session).takeUnretainedValue()
    let samples = Array(UnsafeBufferPointer(start: frames, count: frameCount * ALACFrame.channelCount))

    return held.sender.write(samples) == .taken
}

@_cdecl("pa_session_discard_held_audio")
public func pa_session_discard_held_audio(_ session: UnsafeMutableRawPointer?) -> Int {
    guard let session else { return 0 }

    return Unmanaged<CSession>.fromOpaque(session).takeUnretainedValue().sender.discardHeldAudio()
}

@_cdecl("pa_session_held_frames")
public func pa_session_held_frames(_ session: UnsafeMutableRawPointer?) -> Int {
    guard let session else { return 0 }

    return Unmanaged<CSession>.fromOpaque(session).takeUnretainedValue().sender.heldFrames
}

@_cdecl("pa_session_invented_packets")
public func pa_session_invented_packets(_ session: UnsafeMutableRawPointer?) -> Int {
    guard let session else { return 0 }

    return Unmanaged<CSession>.fromOpaque(session).takeUnretainedValue().sender.underruns.packets
}

@_cdecl("pa_session_invented_seconds")
public func pa_session_invented_seconds(_ session: UnsafeMutableRawPointer?) -> Double {
    guard let session else { return 0 }

    return Unmanaged<CSession>.fromOpaque(session).takeUnretainedValue().sender.underruns.duration
}

@_cdecl("pa_session_waited_seconds")
public func pa_session_waited_seconds(_ session: UnsafeMutableRawPointer?) -> Double {
    guard let session else { return 0 }

    return Unmanaged<CSession>.fromOpaque(session).takeUnretainedValue().sender.underruns.waited
}

@_cdecl("pa_session_is_running")
public func pa_session_is_running(_ session: UnsafeMutableRawPointer?) -> Bool {
    guard let session else { return false }

    return Unmanaged<CSession>.fromOpaque(session).takeUnretainedValue().sender.isRunning
}

@_cdecl("pa_session_set_volume")
public func pa_session_set_volume(_ session: UnsafeMutableRawPointer?, _ volume: Float) {
    guard let session else { return }

    // Swallowed rather than reported, because the C interface has no way to say
    // so and a volume that did not arrive is not worth ending a session over.
    try? Unmanaged<CSession>.fromOpaque(session).takeUnretainedValue().sender.setVolume(volume)
}

@_cdecl("pa_session_close")
public func pa_session_close(_ session: UnsafeMutableRawPointer?) {
    guard let session else { return }

    let held = Unmanaged<CSession>.fromOpaque(session).takeRetainedValue()
    held.sender.close()
}

@_cdecl("pa_result_description")
public func pa_result_description(_ value: Int32) -> UnsafePointer<CChar>? {
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
private let descriptionOfRefused = literal("the receiver refused the pairing")
private let descriptionOfEnded = literal("the receiver ended the session")
private let descriptionOfUnusable = literal("the caller passed something unusable")
private let descriptionOfFailed = literal("the sender failed for a reason the caller cannot act on")

/// A sentence that outlives the call, since C reads the pointer after returning.
private func literal(_ text: String) -> UnsafePointer<CChar> {
    UnsafePointer(strdup(text)!)
}
