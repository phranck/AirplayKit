//
//  Demo.swift
//  Finds receivers, sends a tone to one of them, and shows what this library
//  looks like at the use site.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

import Dispatch
import Foundation
import AirplayKit
import AirplayKitSender

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
    let printing = DispatchQueue(label: "work.layered.airplaykit.demo")

    var discovery: AirPlayDiscovery?
    discovery = AirPlayDiscovery(deliveringOn: printing) { receivers in
        // An empty list has more than one cause, and they want different
        // answers, so the reason is read before the list is believed.
        if receivers.isEmpty, let problem = discovery?.problem {
            print("nothing found: \(describe(problem))")
            return
        }

        print("\(receivers.count) receiver(s):")

        // A matching advertised identifier is not proof of playback grouping:
        // two copies of one test receiver publish the same pi before selection.
        let shared = Dictionary(grouping: receivers.filter { !$0.groupID.isEmpty }, by: \.groupID)
            .filter { $0.value.count > 1 }

        for receiver in receivers {
            let generation = receiver.supportsAirPlay2 ? "AirPlay 2" : "AirPlay 1"
            let name = receiver.name.padding(toLength: 22, withPad: " ", startingAt: 0)
            let state = receiver.isPlaying ? "playing" : (receiver.hasSender ? "in use" : "free")
            let group = shared[receiver.groupID].map { " same advertised gid as \($0.count - 1) other(s)" } ?? ""

            // What a list would put under the name, and the symbol it would draw
            // beside it. Printed here so both can be read against real hardware.
            let product = (receiver.productName.isEmpty ? "unknown" : receiver.productName)
                .padding(toLength: 22, withPad: " ", startingAt: 0)
            let symbol = receiver.symbolName.padding(toLength: 16, withPad: " ", startingAt: 0)

            // A receiver the AirPlay record has not arrived for is described
            // from half of what it publishes, so its name can still change. That
            // is worth seeing here, because this is where the two answers for
            // one speaker were first noticed.
            let known = receiver.isFullyDescribed ? "" : "  half known"

            print("  \(name) \(product) \(symbol) \(generation)  \(state)\(group)\(known)")
            print("  \(String(repeating: " ", count: 22)) \(receiver.host):\(receiver.port)")
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

/// Exercises the public group API with one live join and one live departure.
func testGroupAPI(names: [String], seconds: Int) -> Int32 {
    let queue = DispatchQueue(label: "work.layered.airplaykit.demo.groupDiscovery")
    var latest: [AirPlayReceiver] = []
    let discovery = AirPlayDiscovery(deliveringOn: queue) { latest = $0 }
    Thread.sleep(forTimeInterval: 6)
    discovery.stop()
    let found = queue.sync { latest }
    let receivers = names.compactMap { name in found.first { $0.name == name } }
    guard receivers.count == 3 else {
        print("found \(receivers.map(\.name)); wanted \(names)")
        return 1
    }

    var opened: AirPlayGroup?
    do {
        let group = try AirPlayGroup(receivers: Array(receivers.prefix(1)),
                                     senderName: "AirplayKit group test")
        opened = group
        defer { group.dissolve() }
        print("group opened: \(group.memberIDs)")

        let finished = DispatchSemaphore(value: 0)
        let producer = Thread {
            defer { finished.signal() }
            let packets = seconds * AirPlaySession.sampleRate / ALACFrame.framesPerPacket
            var frame = 0
            var due = ProcessInfo.processInfo.systemUptime
            for _ in 0..<packets {
                var samples = [Int16](repeating: 0,
                                      count: ALACFrame.framesPerPacket * AirPlaySession.channelCount)
                for index in 0..<ALACFrame.framesPerPacket {
                    let angle = 2 * Double.pi * 440 * Double(frame) / Double(AirPlaySession.sampleRate)
                    let value = Int16(3000 * sin(angle))
                    samples[index * 2] = value
                    samples[index * 2 + 1] = value
                    frame += 1
                }
                if case .ended = group.write(samples) { return }
                due += ALACFrame.packetDuration
                let wait = due - ProcessInfo.processInfo.systemUptime
                if wait > 0 { Thread.sleep(forTimeInterval: wait) }
            }
        }
        producer.start()

        Thread.sleep(forTimeInterval: 5)
        try group.add(receivers[1])
        print("joined \(names[1]): \(group.memberIDs)")
        Thread.sleep(forTimeInterval: 5)
        try group.add(receivers[2])
        print("joined \(names[2]): \(group.memberIDs)")
        Thread.sleep(forTimeInterval: 5)
        try group.remove(receivers[1].id)
        print("removed \(names[1]): \(group.memberIDs)")
        finished.wait()
        Thread.sleep(forTimeInterval: 2.5)
        print("group test complete")
        if !group.isRunning { print("group ended: \(group.endedBecause ?? "no reason recorded")") }
        return group.isRunning ? 0 : 1
    } catch {
        let detail = opened?.endedBecause ?? "no group failure recorded"
        FileHandle.standardError.write(Data("group API failed: \(error); \(detail)\n".utf8))
        return 1
    }
}

/// Keeps one AirPlay session open while device-side volume changes arrive.
func watchVolume(on host: String, seconds: Int) -> Int32 {
    do {
        let session = try AirPlaySession(host: host, senderName: "AirplayKit volume watch")
        defer { session.close() }
        print("initial volume: \(session.volume.map(String.init(describing:)) ?? "unknown")")
        let queue = DispatchQueue(label: "work.layered.airplaykit.demo.volume")
        session.observeChanges(deliveringOn: queue) { event in
            if case .volumeChanged(let id, let level) = event {
                print("volumeChanged \(id): \(level)")
            }
        }
        Thread.sleep(forTimeInterval: TimeInterval(seconds))
        print("final volume: \(session.volume.map(String.init(describing:)) ?? "unknown")")
        return 0
    } catch {
        FileHandle.standardError.write(Data("volume watch failed: \(error)\n".utf8))
        return 1
    }
}

// MARK: - The Swift sender

/**
 Pairs with a receiver using the Swift sender, and says what came out.

 This exercises the Swift buffered sender through a complete audio session.

 @param host The receiver's host name or address.
 @param port Its RTSP port.
 @returns Nought where it paired, and one where it did not.
 */
func playThroughSwiftSender(at host: String, port: UInt16, seconds: Int) -> Int32 {
    do {
        print("connecting to \(host):\(port)")
        let sender = try AirPlaySender(host: host, port: port, senderName: "AirplayKit")
        try sender.setVolume(0.3)
        print("session up, sending \(seconds) seconds of 440 Hz at a third of full volume")

        // Handed over from outside, a packet's worth at a time, exactly as a
        // live source arrives. The sender paces what leaves; this only fills.
        var frame = 0.0
        let packets = seconds * ALACFrame.sampleRate / ALACFrame.framesPerPacket
        var dropped = 0
        var due = Date()

        for _ in 0..<packets {
            var samples = [Int16](repeating: 0, count: ALACFrame.framesPerPacket * ALACFrame.channelCount)
            for index in 0..<ALACFrame.framesPerPacket {
                let value = Int16(3000.0 * sin(2.0 * .pi * 440.0 * frame / Double(ALACFrame.sampleRate)))
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
            due = due.addingTimeInterval(ALACFrame.packetDuration)
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
        let connection = try ReceiverConnection(host: host, port: port, senderName: "AirplayKit")

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

        let eventPort = try session.open(senderName: "AirplayKit")
        print("  session open, event channel wanted on \(eventPort)")

        // Before RECORD, because a receiver answers RECORD with 500 until this
        // connection exists and then never renders anything.
        let events = try EventChannel(host: host, port: eventPort, keys: keys)
        session.record()

        let stream = try session.openStream(.buffered, audioKey: keys.audio)
        let buffered = stream.audioBufferSize.map { ", buffer \($0)" } ?? ""
        print("  buffered stream: data \(stream.dataPort), control \(stream.controlPort)\(buffered)")

        try session.setVolume(0.3)

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
        guard let reading = clock.read(from: connection.peerAddress, timeout: 12) else {
            print("  the receiver announced no clock, so there is no timeline to anchor to")
            return 1
        }

        // Two seconds ahead, because the anchor says when frame zero sounds and
        // the first block cannot arrive before it is sent. Anchored on the
        // instant of sending, everything arrives after its own moment and a
        // receiver drops audio that is already late.
        let lead = 2.0
        guard let time = PTPClock.now(from: reading, ahead: lead) else {
            print("  its clock reads a time no anchor can carry, so there is nothing to anchor to")
            return 1
        }

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
        let packets = seconds * ALACFrame.sampleRate / ALACFrame.framesPerPacket
        for _ in 0..<packets {
            var samples = [Int16](repeating: 0, count: ALACFrame.framesPerPacket * 2)
            for index in 0..<ALACFrame.framesPerPacket {
                let value = Int16(3000.0 * sin(2.0 * .pi * 440.0 * frame / Double(ALACFrame.sampleRate)))
                samples[index * 2] = value
                samples[index * 2 + 1] = value
                frame += 1
            }

            try audio.write(samples)
            Thread.sleep(forTimeInterval: ALACFrame.packetDuration)
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
        session = try AirPlaySession(host: host, port: port, senderName: "AirplayKit demo")
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
    var due = Date()

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

            // Against a fixed schedule rather than by sleeping a chunk's worth
            // each time. Sleep always overshoots a little, and a producer that
            // accumulates that drift falls behind real time, empties the
            // sender's ring, and is heard as a scratch towards the end.
            due = due.addingTimeInterval(chunkDuration)
            let wait = due.timeIntervalSinceNow
            if wait > 0 { Thread.sleep(forTimeInterval: wait) }

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

    // The anchor places the first frame a little ahead of the clock, so at any
    // moment that much audio is written and not yet played. Closing at once
    // takes it with you, which is heard as the tone stopping short.
    Thread.sleep(forTimeInterval: 3)

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
func streamWave(at path: String, to host: String, port: UInt16, volume: Float = 0.2) throws {
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
    session.volume = volume
    let reportedLevel = session.volume.map { String(describing: $0) } ?? "unknown"
    print("  volume set to \(reportedLevel), told to the receiver as "
          + String(format: "%.1f dB", volume <= 0 ? -144 : Double(volume) * 30 - 30))

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
    // Asynchronous because the work below is, and because holding the process
    // open with a semaphore whilst waiting for it deadlocked instead.
    static func main() async {
        let arguments = CommandLine.arguments

        guard arguments.count > 1 else {
            var usage = """
                        usage: Demo list
                               Demo pair <host> [port]          pair only, and say what came out
                               Demo group-clock <host1> <host2> [port]
                               Demo group-tone <host1> <host2> [seconds]
                               Demo group-tone3 <host1> <host2> <host3> [seconds]
                               Demo group-api <name1> <name2> <name3> [seconds]
                               Demo volume-watch <host> [seconds]
                               Demo swift <host> [port] [secs]  play through the Swift sender
                               Demo play <host> [port] [seconds]
                               Demo wave <path> <host> [port] [volume]   16 bit stereo at 44100
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

        case "pair" where arguments.count > 2:
            let port = UInt16(arguments.count > 3 ? arguments[3] : "7000") ?? 7000
            exit(pairWithReceiver(at: arguments[2], port: port))

        case "group-clock" where arguments.count > 3:
            let port = UInt16(arguments.count > 4 ? arguments[4] : "7000") ?? 7000
            do {
                let results = try GroupClockProbe.run(first: arguments[2], second: arguments[3], port: port)
                for result in results {
                    let clock = result.announcedClock.map { String(format: "%016llx", $0) } ?? "none"
                    print("\(result.address): announced=\(clock), count=\(result.announcements), "
                          + "delay=\(result.delayRequests), peer-delay=\(result.peerDelayRequests), "
                          + "anchor=\(result.anchorAccepted)")
                }
                exit(results.allSatisfy(\.anchorAccepted) ? 0 : 1)
            } catch {
                FileHandle.standardError.write(Data("group clock failed: \(error)\n".utf8))
                exit(1)
            }

        case "group-tone" where arguments.count > 3:
            let seconds = Int(arguments.count > 4 ? arguments[4] : "4") ?? 4
            guard seconds > 0, seconds <= 30 else { exit(2) }
            do {
                let results = try GroupClockProbe.run(first: arguments[2], second: arguments[3],
                                                       toneSeconds: seconds)
                for result in results {
                    print("\(result.address): delay=\(result.delayRequests), "
                          + "peer-delay=\(result.peerDelayRequests), anchor=\(result.anchorAccepted)")
                }
                exit(results.allSatisfy(\.anchorAccepted) ? 0 : 1)
            } catch {
                FileHandle.standardError.write(Data("group tone failed: \(error)\n".utf8))
                exit(1)
            }

        case "group-tone3" where arguments.count > 4:
            let seconds = Int(arguments.count > 5 ? arguments[5] : "10") ?? 10
            guard seconds > 0, seconds <= 30 else { exit(2) }
            do {
                let results = try GroupClockProbe.run(hosts: Array(arguments[2...4]),
                                                       toneSeconds: seconds)
                for result in results {
                    print("\(result.address): delay=\(result.delayRequests), "
                          + "anchor=\(result.anchorAccepted)")
                }
                exit(results.allSatisfy(\.anchorAccepted) ? 0 : 1)
            } catch {
                FileHandle.standardError.write(Data("group tone failed: \(error)\n".utf8))
                exit(1)
            }

        case "group-api" where arguments.count > 4:
            let seconds = Int(arguments.count > 5 ? arguments[5] : "20") ?? 20
            guard seconds > 0, seconds <= 30 else { exit(2) }
            exit(testGroupAPI(names: Array(arguments[2...4]), seconds: seconds))

        case "volume-watch" where arguments.count > 2:
            let seconds = Int(arguments.count > 3 ? arguments[3] : "30") ?? 30
            guard seconds > 0, seconds <= 60 else { exit(2) }
            exit(watchVolume(on: arguments[2], seconds: seconds))

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
            let volume = Float(arguments.count > 5 ? arguments[5] : "0.2") ?? 0.2
            do {
                print("playing \(arguments[2]) on \(arguments[3]):\(port)")
                try streamWave(at: arguments[2], to: arguments[3], port: port, volume: volume)
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
