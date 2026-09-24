//
//  SessionReportTests.swift
//  What a session did, handed over at the moment it ends.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

import CPlayableAirplay
import XCTest

/**
 The report `pa_session_close` writes.

 Its layout lives in two places and cannot live in one. The header declares
 `PASessionReport` for C to read, and the Swift side writes it from
 `PlayableAirplaySender`, which is below `CPlayableAirplay` in the package and
 therefore cannot import the header that declares it.

 So the two are held together here instead. C reads these fields by offset, so
 one added on one side and not the other is read as the wrong bytes: the
 seconds come back as a packet count and nothing anywhere reports it.
 */
final class SessionReportTests: XCTestCase {

    /// Exactly what the Swift side writes: two words, two doubles, two words.
    private typealias WrittenLayout = (Int, Double, Double, Int)

    func testTheReportTheHeaderDeclaresIsTheOneTheLibraryWrites() {
        XCTAssertEqual(MemoryLayout<PASessionReport>.size, MemoryLayout<WrittenLayout>.size)
        XCTAssertEqual(MemoryLayout<PASessionReport>.stride, MemoryLayout<WrittenLayout>.stride)

        XCTAssertEqual(MemoryLayout<PASessionReport>.offset(of: \.inventedPackets), 0)
        XCTAssertEqual(MemoryLayout<PASessionReport>.offset(of: \.inventedSeconds),
                       MemoryLayout<Int>.stride)
        XCTAssertEqual(MemoryLayout<PASessionReport>.offset(of: \.waitedSeconds),
                       MemoryLayout<Int>.stride + MemoryLayout<Double>.stride)
        XCTAssertEqual(MemoryLayout<PASessionReport>.offset(of: \.fellBehind),
                       MemoryLayout<Int>.stride + MemoryLayout<Double>.stride * 2)
    }

    func testClosingNothingWritesNothing() {
        // A caller that hands over a session it has already closed, or never
        // opened, gets its report left exactly as it was rather than zeroed,
        // because there is nothing to say about a session that is not there.
        var report = PASessionReport(inventedPackets: 7,
                                     inventedSeconds: 1.5,
                                     waitedSeconds: 2.5,
                                     fellBehind: 3)

        pa_session_close(nil, &report)

        XCTAssertEqual(report.inventedPackets, 7)
        XCTAssertEqual(report.fellBehind, 3)
    }

    func testClosingWithNowhereToPutTheReportIsAllowed() {
        // The report is optional, because a caller that does not care about the
        // figures should not have to make room for them.
        pa_session_close(nil, nil)
    }
}
