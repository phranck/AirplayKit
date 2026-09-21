//
//  Demo.swift
//  Finds receivers, sends a tone to one of them, and shows what this library
//  looks like at the use site.
//
//  Copyright © 2026 cocoa:naut. All rights reserved.
//

import Dispatch
import Foundation

// MARK: - Listing what is on the network

/// Browses for a while and prints the set each time it changes.
func listReceivers(forSeconds seconds: Int) -> Int32 {
    let printing = DispatchQueue(label: "at.playable.airplay.demo")

    let discovery = AirPlayDiscovery(deliveringOn: printing) { receivers in
        print("\(receivers.count) receiver(s):")
        for receiver in receivers {
            let generation = receiver.supportsAirPlay2 ? "AirPlay 2" : "AirPlay 1"
            let name = receiver.name.padding(toLength: 24, withPad: " ", startingAt: 0)
            print("  \(name) \(receiver.host):\(receiver.port)  \(generation)")
        }
    }

    guard discovery.isBrowsing else {
        print("could not start looking, is there an mDNS responder running?")
        return 1
    }

    print("looking for receivers, \(seconds) seconds")
    Thread.sleep(forTimeInterval: TimeInterval(seconds))
    discovery.stop()

    return 0
}

// MARK: - Sending a tone

/// Opens a session and plays a quiet 440 Hz tone for a while.
func playTone(on host: String, port: UInt16, forSeconds seconds: Int) -> Int32 {
    let session: AirPlaySession

    do {
        session = try AirPlaySession(host: host, port: port, senderName: "PlayableAirplay demo")
    } catch {
        FileHandle.standardError.write(Data("could not open: \(error)\n".utf8))
        return 1
    }

    print("connected to \(host):\(port), \(seconds) seconds at a tenth of full volume")
    session.volume = 0.1

    let framesPerChunk = 1024
    let chunkDuration = Double(framesPerChunk) / Double(AirPlaySession.sampleRate)
    var chunk = [Int16](repeating: 0, count: framesPerChunk * AirPlaySession.channelCount)
    var frame = 0.0
    var written = 0

    while written < seconds * AirPlaySession.sampleRate {
        for index in 0..<framesPerChunk {
            let value = Int16(3000.0 * sin(2.0 * .pi * 440.0 * frame / Double(AirPlaySession.sampleRate)))
            chunk[index * 2] = value
            chunk[index * 2 + 1] = value
            frame += 1
        }

        switch session.write(chunk) {
        case .taken:
            written += framesPerChunk
            Thread.sleep(forTimeInterval: chunkDuration)

        case .bufferFull:
            // This tone is generated as fast as the loop runs, so a full buffer
            // means the sender has not caught up. A live source would drop the
            // frames here; this one can pause, so it offers them again.
            Thread.sleep(forTimeInterval: 0.01)

        case .ended:
            print("the receiver ended the session")
            session.close()
            return 1
        }
    }

    session.close()
    print("done")

    return 0
}

// MARK: - What the command does

@main
struct Demo {
    static func main() {
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
            exit(listReceivers(forSeconds: 5))

        case "play" where arguments.count > 2:
            let port = UInt16(arguments.count > 3 ? arguments[3] : "7000") ?? 7000
            let seconds = Int(arguments.count > 4 ? arguments[4] : "5") ?? 5
            exit(playTone(on: arguments[2], port: port, forSeconds: seconds))

        default:
            print("usage: Demo play <host> [port] [seconds]")
            exit(2)
        }
    }
}
