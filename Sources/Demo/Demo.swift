//
//  Demo.swift
//  Finds receivers, sends a tone to one of them, and shows what this library
//  looks like at the use site.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

import Dispatch
import Foundation
import PlayableAirplay
import PlayableAirplaySender
import PlayableAirplayUPnP

// The library runs on Linux as well, and AVFoundation does not. Everything that
// reads any format and resamples it is Apple's framework doing the work, so
// that half of this example is built only where the framework exists.
#if canImport(AVFoundation)
import AVFoundation
#endif

// MARK: - Listing what is on the network

/// Says what stopped a browse, in the words somebody could act on.
func describe(_ problem: AirPlayDiscovery.Problem) -> String {
    switch problem {
    case .refused(let code):
        return "this program is not allowed to look at the local network, "
             + "which is granted in the system's privacy settings (\(code))"
    case .noResponder(let code):
        return "no mDNS responder this program can reach, which is either a machine "
             + "without one or a sandbox that will not let this program reach it (\(code))"
    case .failed(let code):
        return "the responder answered with error \(code)"
    }
}

/// Browses for a while and prints the set each time it changes.
func listReceivers(forSeconds seconds: Int) -> Int32 {
    let printing = DispatchQueue(label: "at.playable.airplay.demo")

    var discovery: AirPlayDiscovery?
    discovery = AirPlayDiscovery(deliveringOn: printing) { receivers in
        // An empty list has more than one cause, and they want different
        // answers, so the reason is read before the list is believed.
        if receivers.isEmpty, let problem = discovery?.problem {
            print("nothing found: \(describe(problem))")
            return
        }

        print("\(receivers.count) receiver(s):")

        // Receivers that name the same group as each other. Nothing measured
        // says what that means, so this prints what was seen and claims nothing.
        let shared = Dictionary(grouping: receivers.filter { !$0.groupID.isEmpty }, by: \.groupID)
            .filter { $0.value.count > 1 }

        for receiver in receivers {
            let generation = receiver.supportsAirPlay2 ? "AirPlay 2" : "AirPlay 1"
            let name = receiver.name.padding(toLength: 24, withPad: " ", startingAt: 0)
            let model = receiver.model.isEmpty ? "unknown model" : receiver.model
            let state = receiver.isPlaying ? "playing" : (receiver.hasSender ? "in use" : "free")
            let group = shared[receiver.groupID].map { " same group as \($0.count - 1) other(s)" } ?? ""
            print("  \(name) \(receiver.host):\(receiver.port)  \(generation)  \(model)  \(state)\(group)")
        }
    }

    guard let discovery, discovery.isBrowsing else {
        let reason = discovery?.problem.map(describe) ?? "no reason was given"
        print("could not start looking: \(reason)")
        return 1
    }

    print("looking for receivers, \(seconds) seconds")
    Thread.sleep(forTimeInterval: TimeInterval(seconds))
    discovery.stop()

    return 0
}

// MARK: - Asking a Sonos directly

/// Asks one speaker what AirPlay will not tell, and prints it.
func describeSonos(at host: String) async -> Int32 {
    let speaker = SonosClient(host: host)

    do {
        let device = try await speaker.device()
        let playing = try await speaker.playback()

        print("\(device.roomName): \(device.modelName) (\(device.modelNumber)), \(device.identifier)")
        if let icon = speaker.iconURL(for: device) { print("  picture   \(icon)") }

        let following = playing.followingIdentifier.map { ", following \($0)" } ?? ""
        print("  playing   \(playing.state.rawValue)\(following)")
        print("  volume    \(playing.volume) of 100\(playing.isMuted ? ", muted" : "")")

        print("groups on this network:")
        for group in try await speaker.zoneGroups() {
            let rooms = group.members.map { member in
                member.isBonded ? "\(member.roomName) with \(member.satellites.count) bonded"
                                : member.roomName
            }
            let together = group.joinsSeveralMembers ? "" : " (on its own)"
            print("  \(group.coordinatorIdentifier) leads \(rooms.joined(separator: ", "))\(together)")
        }
    } catch {
        FileHandle.standardError.write(Data("could not ask \(host): \(error)\n".utf8))
        return 1
    }

    return 0
}

// MARK: - The Swift sender

/**
 Pairs with a receiver using the Swift sender, and says what came out.

 This exercises the path being built beside the C++ one. It stops at the keys,
 because that is as far as that path goes so far.

 @param host The receiver's host name or address.
 @param port Its RTSP port.
 @returns Nought where it paired, and one where it did not.
 */
func playThroughSwiftSender(at host: String, port: UInt16, seconds: Int) -> Int32 {
    do {
        print("connecting to \(host):\(port)")
        let sender = try AirPlaySender(host: host, port: port, senderName: "PlayableAirplay")
        try sender.setVolume(0.3)
        print("session up, sending \(seconds) seconds of 440 Hz at a third of full volume")

        // Handed over from outside, a packet's worth at a time, exactly as a
        // live source arrives. The sender paces what leaves; this only fills.
        var frame = 0.0
        let packets = seconds * 44100 / ALACFrame.framesPerPacket
        var dropped = 0
        var due = Date()

        for _ in 0..<packets {
            var samples = [Int16](repeating: 0, count: ALACFrame.framesPerPacket * ALACFrame.channelCount)
            for index in 0..<ALACFrame.framesPerPacket {
                let value = Int16(3000.0 * sin(2.0 * .pi * 440.0 * frame / 44100.0))
                samples[index * 2] = value
                samples[index * 2 + 1] = value
                frame += 1
            }

            switch sender.write(samples) {
            case .taken:
                break
            case .bufferFull:
                dropped += 1
            case .ended:
                print("the receiver ended the session")
                sender.close()
                return 1
            }

            // Against a fixed schedule rather than by sleeping a packet's worth
            // each time. Sleep always overshoots a little, and a producer that
            // accumulates that drift falls behind real time, empties the ring,
            // and is heard as crackle towards the end of a long tone.
            due = due.addingTimeInterval(Double(ALACFrame.framesPerPacket) / 44100.0)
            let wait = due.timeIntervalSinceNow
            if wait > 0 { Thread.sleep(forTimeInterval: wait) }
        }

        // Let the ring drain before closing, or the tail is never sent.
        Thread.sleep(forTimeInterval: AirPlaySender.anchorLead + 1)
        sender.close()

        print("done, \(dropped) packet(s) refused for want of room")

        return 0
    }
    catch {
        FileHandle.standardError.write(Data("could not play: \(error)\n".utf8))
        return 1
    }
}

/// Pairs and reports what came out, without sending any audio.
func pairWithReceiver(at host: String, port: UInt16, seconds: Int = 0) -> Int32 {
    do {
        print("connecting to \(host):\(port)")
        let connection = try ReceiverConnection(host: host, port: port, senderName: "PlayableAirplay")

        try connection.pair()

        guard let keys = connection.keys else { return 1 }

        print("paired, and the connection is encrypted from here")

        var session = Session(connection: connection)

        // Asked before the session SETUP, which a receiver rejects without it.
        let info = try session.askWhatItIs()
        if let name = info["name"] as? String {
            print("  it says it is \(name), a \(info["model"] as? String ?? "receiver")")
        }

        // Everything it says about time and about what it can carry, which is
        // what decides which path can actually be driven.
        for key in info.keys.sorted() where key.lowercased().contains("timing")
            || key.lowercased().contains("clock")
            || key.lowercased().contains("ptp")
            || key.lowercased().contains("feature")
            || key.lowercased().contains("status") {
            print("  \(key) = \(info[key] ?? "")")
        }

        let eventPort = try session.open(senderName: "PlayableAirplay")
        print("  session open, event channel wanted on \(eventPort)")

        // Before RECORD, because a receiver answers RECORD with 500 until this
        // connection exists and then never renders anything.
        let events = try EventChannel(host: host, port: eventPort, keys: keys)
        session.record()

        let stream = try session.openStream(.buffered, audioKey: keys.audio)
        let buffered = stream.audioBufferSize.map { ", buffer \($0)" } ?? ""
        print("  buffered stream: data \(stream.dataPort), control \(stream.controlPort)\(buffered)")

        try session.setVolume(0.3)

        // An anchor on a timeline of our own, which is the open question here:
        // the session declared no timing protocol, so there is no shared clock,
        // and whether a receiver plays against one it was simply handed is what
        // this finds out.
        // Opened before SETPEERS, because the receiver starts announcing as
        // soon as it is told where to announce to.
        let clock = try PTPClock()

        do {
            try session.setPeers([connection.localAddress])
            print("  peers accepted")
        }
        catch {
            print("  peers refused: \(error)")
        }

        // The receiver keeps the clock and announces it, so the anchor is
        // expressed on its timeline rather than on one of ours.
        guard let reading = clock.read(timeout: 12) else {
            print("  the receiver announced no clock, so there is no timeline to anchor to")
            return 1
        }

        // Two seconds ahead, because the anchor says when frame zero sounds and
        // the first block cannot arrive before it is sent. Anchored on the
        // instant of sending, everything arrives after its own moment and a
        // receiver drops audio that is already late.
        let lead = 2.0
        let time = PTPClock.now(from: reading, ahead: lead)
        print(String(format: "  its clock is %016llx, reading %lld s", reading.identity, time.seconds))

        do {
            try session.setAnchor(rtpTime: 0,
                                  seconds: time.seconds,
                                  fraction: time.fraction,
                                  timelineIdentifier: Int64(bitPattern: reading.identity))
            print("  anchor accepted, frame zero sounds in \(lead) s")
        }
        catch {
            print("  anchor refused: \(error)")
        }

        let audio = try BufferedAudioStream(host: host, port: stream.dataPort, audioKey: keys.audio)
        print("  sending \(seconds) seconds of 440 Hz at a third of full volume")

        // Paced against the clock, because a live source cannot be sent ahead
        // and this is the case the product needs.
        var frame = 0.0
        let packets = seconds * 44100 / ALACFrame.framesPerPacket
        for _ in 0..<packets {
            var samples = [Int16](repeating: 0, count: ALACFrame.framesPerPacket * 2)
            for index in 0..<ALACFrame.framesPerPacket {
                let value = Int16(3000.0 * sin(2.0 * .pi * 440.0 * frame / 44100.0))
                samples[index * 2] = value
                samples[index * 2 + 1] = value
                frame += 1
            }

            try audio.write(samples)
            Thread.sleep(forTimeInterval: Double(ALACFrame.framesPerPacket) / 44100.0)
        }

        print("  done")

        audio.close()
        events.close()
        connection.close()

        return 0
    }
    catch {
        FileHandle.standardError.write(Data("could not pair: \(error)\n".utf8))
        return 1
    }
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

#if canImport(AVFoundation)

// MARK: - Sending a file

/// Plays a file to a speaker, converting it to what AirPlay carries on the way.
func stream(_ file: AVAudioFile, to host: String, port: UInt16) throws {
    // Interleaved 16 bit stereo at 44100 is the only thing that goes over the wire.
    let audioFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                    sampleRate: Double(AirPlaySession.sampleRate),
                                    channels: AVAudioChannelCount(AirPlaySession.channelCount),
                                    interleaved: true)!
    let converter = AVAudioConverter(from: file.processingFormat, to: audioFormat)!

    let session = try AirPlaySession(host: host, port: port, senderName: "My App")
    session.volume = 0.2

    let framesPerChunk: AVAudioFrameCount = 4096
    let ratio = audioFormat.sampleRate / file.processingFormat.sampleRate
    let readBuffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: framesPerChunk)!
    let convertedCapacity = AVAudioFrameCount(Double(framesPerChunk) * ratio) + 1
    let convertedBuffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: convertedCapacity)!

    // Read against the file's own length rather than until it complains: asking
    // for one frame past the end throws rather than coming back empty.
    while file.framePosition < file.length {
        let remaining = file.length - file.framePosition
        try file.read(into: readBuffer, frameCount: AVAudioFrameCount(min(Int64(framesPerChunk), remaining)))

        var handedOver = false
        converter.convert(to: convertedBuffer, error: nil) { _, status in
            defer { handedOver = true }
            status.pointee = handedOver ? .noDataNow : .haveData

            return handedOver ? nil : readBuffer
        }

        let samples = convertedBuffer.int16ChannelData![0]
        let count = Int(convertedBuffer.frameLength) * AirPlaySession.channelCount

        // A file can wait, so it offers the same frames again. A live source would drop them.
        var outcome = session.write(UnsafeBufferPointer(start: samples, count: count))
        while outcome == .bufferFull {
            Thread.sleep(forTimeInterval: 0.01)
            outcome = session.write(UnsafeBufferPointer(start: samples, count: count))
        }

        if outcome == .ended { break }
    }

    // The sender still holds what has not gone out, so closing now would cut the end off.
    Thread.sleep(forTimeInterval: 4)
    session.close()
}

/// Reads the file named on the command line and hands it to the function above.
func playFile(at path: String, on host: String, port: UInt16) -> Int32 {
    do {
        let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
        print("playing \(path) on \(host):\(port)")
        try stream(file, to: host, port: port)
        print("done")
    } catch {
        FileHandle.standardError.write(Data("\(error)\n".utf8))
        return 1
    }

    return 0
}

#endif

// MARK: - Sending a file anywhere

/// What a WAVE file says about the audio in it, and where that audio starts.
struct WaveFile {
    let sampleRate: Int
    let channelCount: Int
    let bitsPerSample: Int
    let frames: Data
}

/// Reads the two chunks of a WAVE file that matter: what the audio is, and the audio.
func readWave(at path: String) throws -> WaveFile {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))

    func number(at offset: Int, bytes: Int) -> Int {
        (0..<bytes).reduce(0) { $0 | Int(data[offset + $1]) << (8 * $1) }
    }

    var sampleRate = 0, channelCount = 0, bitsPerSample = 0
    var offset = 12   // past "RIFF", the size, and "WAVE"

    while offset + 8 <= data.count {
        let identifier = String(decoding: data[offset..<offset + 4], as: UTF8.self)
        let size = number(at: offset + 4, bytes: 4)
        let body = offset + 8

        switch identifier {
        case "fmt ":
            channelCount = number(at: body + 2, bytes: 2)
            sampleRate = number(at: body + 4, bytes: 4)
            bitsPerSample = number(at: body + 14, bytes: 2)

        case "data":
            // Copied out of the slice, because a slice keeps the indices it had
            // in the file and everything below counts from zero.
            return WaveFile(sampleRate: sampleRate,
                            channelCount: channelCount,
                            bitsPerSample: bitsPerSample,
                            frames: Data(data[body..<min(body + size, data.count)]))

        default:
            break
        }

        offset = body + size + (size % 2)   // chunks are padded to an even length
    }

    throw POSIXError(.EINVAL)
}

/// Plays a WAVE file to a speaker. Nothing here is Apple's, so it runs on Linux too.
func streamWave(at path: String, to host: String, port: UInt16) throws {
    let wave = try readWave(at: path)

    // No resampling here: what the file holds has to be what AirPlay carries.
    guard wave.sampleRate == AirPlaySession.sampleRate,
          wave.channelCount == AirPlaySession.channelCount,
          wave.bitsPerSample == 16 else {
        print("this wants 16 bit stereo at \(AirPlaySession.sampleRate), and that file is "
              + "\(wave.bitsPerSample) bit, \(wave.channelCount) channel, at \(wave.sampleRate)")
        throw POSIXError(.EINVAL)
    }

    let session = try AirPlaySession(host: host, port: port, senderName: "My App")
    session.volume = 0.2

    let samplesPerChunk = 4096 * AirPlaySession.channelCount
    let bytesPerChunk = samplesPerChunk * MemoryLayout<Int16>.size

    for start in stride(from: 0, to: wave.frames.count, by: bytesPerChunk) {
        let chunk = wave.frames[start..<min(start + bytesPerChunk, wave.frames.count)]
        var samples = [Int16](repeating: 0, count: chunk.count / MemoryLayout<Int16>.size)
        _ = samples.withUnsafeMutableBytes { chunk.copyBytes(to: $0) }

        // A file can wait, so it offers the same frames again. A live source would drop them.
        var outcome = session.write(samples)
        while outcome == .bufferFull {
            Thread.sleep(forTimeInterval: 0.01)
            outcome = session.write(samples)
        }

        if outcome == .ended { break }
    }

    // The sender still holds what has not gone out, so closing now would cut the end off.
    Thread.sleep(forTimeInterval: 4)
    session.close()
}

// MARK: - What the command does

@main
struct Demo {
    // Asynchronous because asking a Sonos is, and because holding the process
    // open with a semaphore whilst waiting for it deadlocked instead.
    static func main() async {
        let arguments = CommandLine.arguments

        guard arguments.count > 1 else {
            var usage = """
                        usage: Demo list
                               Demo sonos <host>                what AirPlay will not say
                               Demo pair <host> [port]          pair only, and say what came out
                               Demo swift <host> [port] [secs]  play through the Swift sender
                               Demo play <host> [port] [seconds]
                               Demo wave <path> <host> [port]   16 bit stereo at 44100
                        """

            // Only where AVFoundation is, because it does the conversion.
            #if canImport(AVFoundation)
            usage += "\n       Demo file <path> <host> [port]   any format the system reads"
            #endif

            print(usage)
            exit(2)
        }

        switch arguments[1] {
        case "list":
            exit(listReceivers(forSeconds: 5))

        case "sonos" where arguments.count > 2:
            exit(await describeSonos(at: arguments[2]))

        case "pair" where arguments.count > 2:
            let port = UInt16(arguments.count > 3 ? arguments[3] : "7000") ?? 7000
            exit(pairWithReceiver(at: arguments[2], port: port))

        case "swift" where arguments.count > 2:
            let port = UInt16(arguments.count > 3 ? arguments[3] : "7000") ?? 7000
            let seconds = Int(arguments.count > 4 ? arguments[4] : "10") ?? 10
            exit(playThroughSwiftSender(at: arguments[2], port: port, seconds: seconds))

        case "play" where arguments.count > 2:
            let port = UInt16(arguments.count > 3 ? arguments[3] : "7000") ?? 7000
            let seconds = Int(arguments.count > 4 ? arguments[4] : "5") ?? 5
            exit(playTone(on: arguments[2], port: port, forSeconds: seconds))

        case "wave" where arguments.count > 3:
            let port = UInt16(arguments.count > 4 ? arguments[4] : "7000") ?? 7000
            do {
                print("playing \(arguments[2]) on \(arguments[3]):\(port)")
                try streamWave(at: arguments[2], to: arguments[3], port: port)
                print("done")
            } catch {
                FileHandle.standardError.write(Data("\(error)\n".utf8))
                exit(1)
            }
            exit(0)

        #if canImport(AVFoundation)
        case "file" where arguments.count > 3:
            let port = UInt16(arguments.count > 4 ? arguments[4] : "7000") ?? 7000
            exit(playFile(at: arguments[2], on: arguments[3], port: port))
        #endif

        default:
            print("usage: Demo play <host> [port] [seconds]")
            exit(2)
        }
    }
}
