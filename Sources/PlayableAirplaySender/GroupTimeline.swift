//
//  GroupTimeline.swift
//  One media-to-clock mapping for every stream in a group.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

import Foundation

struct GroupTimeline {
    struct Anchor {
        let rtpTime: UInt32
        let seconds: Int64
        let fraction: Int64
    }

    let baseSeconds: Double
    let sampleRate: Int

    init(reading: PTPClock.Reading, ahead: TimeInterval, sampleRate: Int) {
        baseSeconds = Double(reading.seconds) + Double(reading.nanoseconds) / 1_000_000_000
            + ProcessInfo.processInfo.systemUptime - reading.heardAt + ahead
        self.sampleRate = sampleRate
    }

    init(baseSeconds: Double, sampleRate: Int) {
        self.baseSeconds = baseSeconds
        self.sampleRate = sampleRate
    }

    func anchor(forFrame frame: UInt64) -> Anchor? {
        guard sampleRate > 0 else { return nil }
        let time = baseSeconds + Double(frame) / Double(sampleRate)
        guard time.isFinite, time >= 0, time < Double(Int64.max) else { return nil }
        let seconds = Int64(time)
        let fractional = time - Double(seconds)
        let scale = 18_446_744_073_709_551_616.0
        let bits = UInt64(min((fractional * scale).rounded(.down), scale.nextDown))
        return Anchor(rtpTime: UInt32(truncatingIfNeeded: frame),
                      seconds: seconds, fraction: Int64(bitPattern: bits))
    }
}
