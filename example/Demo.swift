//
//  Demo.swift
//  Finds receivers, sends a tone to one of them, and shows what calling this
//  library from Swift looks like.
//
//  Copyright © 2026 cocoa:naut. All rights reserved.
//

import Foundation
import PlayableAirplay

// MARK: - Reading the C buffers

extension PAReceiver {
    /// The fixed C buffers arrive in Swift as tuples of CChar, and this is where they stop being that.
    var displayName: String { Self.string(from: name, capacity: Int(PA_MAX_NAME)) }
    var hostName: String { Self.string(from: host, capacity: Int(PA_MAX_HOST)) }

    private static func string<Buffer>(from buffer: Buffer, capacity: Int) -> String {
        withUnsafePointer(to: buffer) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { String(cString: $0) }
        }
    }
}

// MARK: - Listing what is on the network

/// Browses for receivers and prints the set each time it changes.
final class ReceiverList {
    private var discovery: OpaquePointer?

    func browse(forSeconds seconds: Int) {
        // The handler is a C function pointer, so it captures nothing. Anything
        // it needs would travel through the context argument.
        discovery = pa_discovery_start({ _, receivers, count in
            guard let receivers else { return }
            print("\(count) receiver(s):")
            for index in 0..<count {
                let receiver = receivers[index]
                let generation = receiver.supportsAirPlay2 ? "AirPlay 2" : "AirPlay 1"
                print("  \(receiver.displayName.padding(toLength: 24, withPad: " ", startingAt: 0))"
                      + " \(receiver.hostName):\(receiver.port)  \(generation)")
            }
        }, nil)

        guard discovery != nil else {
            print("could not start looking, is there an mDNS daemon running?")
            return
        }

        print("looking for receivers, \(seconds) seconds")
        Thread.sleep(forTimeInterval: TimeInterval(seconds))
        pa_discovery_stop(discovery)
        discovery = nil
    }
}

// MARK: - Sending a tone

/// Opens a session and plays a quiet 440 Hz tone for a while.
func play(host: String, port: UInt16, seconds: Int) -> Int32 {
    var result = PAResultOK
    guard let session = pa_session_open(host, port, "PlayableAirplay demo", &result) else {
        FileHandle.standardError.write(Data("could not open: \(String(cString: pa_result_description(result)))\n".utf8))
        return 1
    }

    print("connected to \(host):\(port), \(seconds) seconds at a tenth of full volume")
    pa_session_set_volume(session, 0.1)

    let framesPerChunk = 1024
    var chunk = [Int16](repeating: 0, count: framesPerChunk * Int(PA_CHANNELS))
    var frame = 0.0
    var written = 0

    while written < seconds * Int(PA_SAMPLE_RATE) {
        for index in 0..<framesPerChunk {
            let value = Int16(3000.0 * sin(2.0 * .pi * 440.0 * frame / Double(PA_SAMPLE_RATE)))
            chunk[index * 2] = value
            chunk[index * 2 + 1] = value
            frame += 1
        }

        if !pa_session_write(session, &chunk, framesPerChunk) {
            // This tone is generated as fast as the loop runs, so a full buffer
            // means the sender has not caught up. A live source would drop the
            // frames here; one that can pause offers them again.
            Thread.sleep(forTimeInterval: 0.01)
            continue
        }

        written += framesPerChunk
        Thread.sleep(forTimeInterval: Double(framesPerChunk) / Double(PA_SAMPLE_RATE))
    }

    pa_session_close(session)
    print("done")

    return 0
}

// MARK: - What the command does

let arguments = CommandLine.arguments

guard arguments.count > 1 else {
    print("""
          usage: Demo list
                 Demo play <host> [port] [seconds]
          """)
    exit(2)
}

switch arguments[1] {
case "list":
    ReceiverList().browse(forSeconds: 5)
    exit(0)

case "play" where arguments.count > 2:
    let host = arguments[2]
    let port = UInt16(arguments.count > 3 ? arguments[3] : "7000") ?? 7000
    let seconds = Int(arguments.count > 4 ? arguments[4] : "5") ?? 5
    exit(play(host: host, port: port, seconds: seconds))

default:
    print("usage: Demo play <host> [port] [seconds]")
    exit(2)
}
