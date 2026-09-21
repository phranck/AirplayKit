//
//  Demo.swift
//  Finds receivers, sends a tone to one of them, and shows what this library
//  looks like at the use site.
//
//  Copyright © 2026 cocoa:naut. All rights reserved.
//

import Dispatch
import Foundation
import PlayableAirplay

// The library runs on Linux as well, and AVFoundation does not. Everything that
// reads any format and resamples it is Apple's framework doing the work, so
// that half of this example is built only where the framework exists.
#if canImport(AVFoundation)
import AVFoundation
#endif

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
    static func main() {
        let arguments = CommandLine.arguments

        guard arguments.count > 1 else {
            var usage = """
                        usage: Demo list
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
