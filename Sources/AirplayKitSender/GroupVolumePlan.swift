//
//  GroupVolumePlan.swift
//  Move a group's average level while keeping member differences where possible.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

package enum GroupVolumePlan {
    package static func levels(for current: [Float], average requested: Float) -> [Float]? {
        guard !current.isEmpty, requested.isFinite,
              current.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { return nil }

        let target = Double(min(max(requested, 0), 1))
        let originals = current.map(Double.init)
        var lower = -1.0
        var upper = 1.0

        // The mean of clamped levels grows monotonically with the common
        // offset. Saturated members stop moving while the others take over.
        for _ in 0..<40 {
            let offset = (lower + upper) / 2
            let mean = originals.reduce(0) { $0 + min(max($1 + offset, 0), 1) }
                / Double(originals.count)
            if mean < target { lower = offset } else { upper = offset }
        }

        let offset = (lower + upper) / 2
        return originals.map { Float(min(max($0 + offset, 0), 1)) }
    }
}
